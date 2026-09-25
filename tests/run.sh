#!/usr/bin/env bash
# Offline tests for bin/aws-oidc-login. A fake `aws` on PATH stands in for the
# real CLI, and each test gets its own throwaway HOME, so nothing real is read
# or written. Run: tests/run.sh   (optionally TEST_BASH=/bin/bash tests/run.sh)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
test_bash="${TEST_BASH:-bash}"
pass=0
fail=0

fixture=$(mktemp)
cat > "$fixture" <<'EOF'
[
  {"id": "111111111111", "name": "Alpha Dev",        "roles": ["ReadOnly"]},
  {"id": "222222222222", "name": "beta-prod",        "roles": ["ReadOnly", "PowerUser", "DevOpsAdmin"]},
  {"id": "333333333333", "name": "Legacy Key",       "roles": ["ReadOnly"]},
  {"id": "444444444444", "name": "Temp Key",         "roles": ["ReadOnly"]},
  {"id": "555555555555", "name": "Plain Section",    "roles": ["ReadOnly"]},
  {"id": "666666666666", "name": "Assume Role",      "roles": ["ReadOnly"]},
  {"id": "777777777777", "name": "alpha dev",        "roles": ["ReadOnly"]}
]
EOF

new_env() {
  home=$(mktemp -d)
  mkdir -p "$home/.aws" "$home/bin"
  ln -s "$root/tests/fake-aws" "$home/bin/aws"
  export HOME="$home"
  export PATH="$home/bin:$PATH"
  export AWS_CONFIG_FILE="$home/.aws/config"
  export AWS_SHARED_CREDENTIALS_FILE="$home/.aws/credentials"
  export FAKE_AWS_FIXTURE="$fixture"
  export ROLE_PREFERENCE="DevOpsAdmin,PowerUser,ReadOnly"
}

tool() { "$test_bash" "$root/bin/aws-oidc-login" "$@"; }

check() {  # description, command...
  local d="$1"; shift
  if "$@"; then pass=$((pass+1)); echo "  ok    $d"
  else fail=$((fail+1)); echo "  FAIL  $d"; fi
}

section_has() {  # profile key value
  awk -v s="[profile $1]" -v k="$2" -v v="$3" '
    $0==s {f=1; next} /^\[/ {f=0}
    f && $1==k && $3==v {found=1} END {exit !found}' "$AWS_CONFIG_FILE"
}
count() { grep -c "$1" "$AWS_CONFIG_FILE" || true; }

# shellcheck disable=SC2016  # expands in the child bash
echo "bash under test: $("$test_bash" -c 'echo $BASH_VERSION')"

echo "fresh setup"
new_env
tool setup --yes > "$HOME/out" 2>&1
check "creates sso-session"         grep -qx '\[sso-session huit\]' "$AWS_CONFIG_FILE"
check "uses the default portal"     grep -q 'huitprodpayer.awsapps.com/start' "$AWS_CONFIG_FILE"
check "adds one profile per account" test "$(count '^\[profile ')" -eq 7
check "picks preferred role"        section_has beta-prod sso_role_name DevOpsAdmin
check "slugs account names"         section_has alpha-dev sso_account_id 111111111111
check "de-duplicates slug clashes"  section_has alpha-dev-777777777777 sso_account_id 777777777777
check "verification passes"         grep -q '7 ok, 0 failed' "$HOME/out"

echo "re-run is idempotent"
cp "$AWS_CONFIG_FILE" "$HOME/before"
tool setup --yes > "$HOME/out" 2>&1
check "reports nothing to change"   grep -q 'Nothing to change' "$HOME/out"
check "config unchanged"            cmp -s "$AWS_CONFIG_FILE" "$HOME/before"

echo "existing profiles"
new_env
cat > "$AWS_CONFIG_FILE" <<'EOF'
[profile plain-section]
region = us-west-2

[profile assume-role]
role_arn = arn:aws:iam::666666666666:role/Admin
source_profile = legacy-key
EOF
cat > "$AWS_SHARED_CREDENTIALS_FILE" <<'EOF'
[legacy-key]
aws_access_key_id = AKIAEXAMPLEEXAMPLE00
aws_secret_access_key = x

[temp-key]
aws_access_key_id = ASIAEXAMPLEEXAMPLE00
aws_secret_access_key = x
aws_session_token = x
EOF
cp "$AWS_SHARED_CREDENTIALS_FILE" "$HOME/creds-before"
tool setup --yes --no-verify > "$HOME/out" 2>&1
check "long-lived key name is renamed"   section_has legacy-key-sso sso_account_id 333333333333
check "long-lived key name left alone"   test -z "$(awk '$0=="[profile legacy-key]"' "$AWS_CONFIG_FILE")"
check "temporary key name is reused"     section_has temp-key sso_account_id 444444444444
check "plain section gets sso keys"      section_has plain-section sso_account_id 555555555555
check "plain section keeps its region"   section_has plain-section region us-west-2
check "plain section not duplicated"     test "$(count '^\[profile plain-section\]')" -eq 1
check "assume-role profile is renamed"   section_has assume-role-sso sso_account_id 666666666666
check "assume-role profile untouched"    section_has assume-role role_arn arn:aws:iam::666666666666:role/Admin
check "credentials file untouched"       cmp -s "$AWS_SHARED_CREDENTIALS_FILE" "$HOME/creds-before"
check "config was backed up"             test -n "$(ls "$HOME"/.aws/config.bak.* 2>/dev/null)"

echo "existing SSO profile under another name"
new_env
printf '[sso-session huit]\nsso_start_url = https://huitprodpayer.awsapps.com/start\nsso_region = us-east-1\n\n[profile my-beta]\nsso_session = huit\nsso_account_id = 222222222222\nsso_role_name = DevOpsAdmin\n' > "$AWS_CONFIG_FILE"
tool login > /dev/null 2>&1
tool setup --yes --no-verify > "$HOME/out" 2>&1
check "recognized under its own name"     grep -q 'exists  my-beta' "$HOME/out"
check "no duplicate for that account"     test -z "$(awk '$0=="[profile beta-prod]"' "$AWS_CONFIG_FILE")"
check "other accounts still added"        test "$(count '^\[profile ')" -eq 7

echo "options"
new_env
tool setup --dry-run > "$HOME/out" 2>&1
check "dry run without session writes nothing" test ! -e "$AWS_CONFIG_FILE"
printf '[sso-session huit]\nsso_start_url = https://huitprodpayer.awsapps.com/start\nsso_region = us-east-1\n' > "$AWS_CONFIG_FILE"
cp "$AWS_CONFIG_FILE" "$HOME/before"
tool setup --dry-run > "$HOME/out" 2>&1
check "dry run shows the plan"           grep -q '7 add, 0 merge' "$HOME/out"
check "dry run writes nothing"           cmp -s "$AWS_CONFIG_FILE" "$HOME/before"
tool setup --yes --no-verify --all-roles --prefix sso- > /dev/null 2>&1
check "--all-roles adds every role"      test "$(count '^\[profile ')" -eq 9
check "--prefix is applied"              section_has sso-beta-prod-poweruser sso_role_name PowerUser
tool generate > "$HOME/gen" 2>/dev/null
check "generate prints profiles"         test "$(grep -c '^\[profile ' "$HOME/gen")" -eq 7
tool list > "$HOME/list" 2>/dev/null
check "list shows every role"            test "$(wc -l < "$HOME/list" | tr -d ' ')" -eq 9
check "conflicting start URL refused"    bash -c "! $test_bash '$root/bin/aws-oidc-login' setup --yes -u https://other.awsapps.com/start 2>/dev/null"
new_env
check "generate without login fails"     bash -c "! $test_bash '$root/bin/aws-oidc-login' generate 2>/dev/null"

echo "versioning"
latest=$(awk '/^## [0-9]/ {print $2; exit}' "$root/CHANGELOG.md")
check "--version matches CHANGELOG"      test "$(tool --version)" = "aws-oidc-login $latest"

rm -f "$fixture"
echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
