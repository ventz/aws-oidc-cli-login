# Migrating from SAML Tools

SAML command-line tools (`saml2aws`, `aws-google-auth`, homegrown `aws-login` scripts, and so on) usually log in by automating the web login. They write **temporary keys** into `~/.aws/credentials` under a profile name you chose. Identity Center profiles replace all of that. Here's how to move over without breaking the names your scripts already use.

## You can keep your profile names

To give an old name SSO credentials, add the `sso_*` keys to a `[profile <name>]` block in `~/.aws/config`:

```ini
# ~/.aws/config
[profile cloudhacks]
sso_session = huit
sso_account_id = 111122223333
sso_role_name = HUITDevOpsAdmin
region = us-east-1
```

This works even if the old SAML keys are still in `~/.aws/credentials`. The CLI and SDKs look for SSO settings **before** the shared credentials file, so the SSO keys win.

To see which one a profile is using:

```bash
aws configure list --profile cloudhacks
#   access_key : ****************X572 : sso              ← SSO
#   access_key : ****************ABCD : shared-credentials-file  ← old keys
```

You can delete the stale sections from `~/.aws/credentials` whenever you like, but you don't have to. If your old tool keeps rewriting them, that's harmless too.

## When not to reuse a name

| The existing name holds | Why not reuse it | The script does |
|---|---|---|
| A **long-lived IAM user key** (`aws_access_key_id = AKIA…`) | Adding SSO keys would quietly switch the name to a different identity with different permissions, and anything that relied on that IAM user would change behavior | Creates `<name>-sso` |
| An **assume-role** profile (`role_arn`, `source_profile`, `credential_process`, …) | That's a different way to authenticate, so mixing them in one section is ambiguous | Creates `<name>-sso` |
| An SSO profile for a **different** account or role | It's already in use | Creates `<name>-sso` |
| Temporary SAML keys (`ASIA…`) | Nothing: this is the case that's safe to reuse | Reuses the name |
| A plain section (`region`, `output` only) | Nothing | Adds the `sso_*` keys to it |

## Keeping your own aliases

SAML tools usually keep a separate role-mapping file (for example, the `profile_map` in `~/.huit_aws/config`). With Identity Center there is no separate mapping: **the profile name is the alias**. Name a profile anything you like, as long as it points at the same `sso_session`:

```ini
[profile my-alias]            # any name you want
sso_session = huit
sso_account_id = 111122223333
sso_role_name = HUITReadOnly
region = us-east-1
```

You can give one account and role several aliases (say `prod` and `fas-prod`). They all share the same login.

**What changes: role names.** SAML mappings point at IAM role ARNs such as `arn:aws:iam::111122223333:role/myapp-prod-standard-saml-admin-iam-role`. Identity Center uses permission-set names like `HUITReadOnly`, `HUITPowerUser` or `HUITDevOpsAdmin` instead. Keep the account ID, but look up the new role name for each account:

```bash
aws-oidc-login list        # every account and the roles you have in it
```

**Convert an existing `profile_map`.** This prints one profile block per alias, with the alias, account ID and region carried over. You fill in each `sso_role_name` from `aws-oidc-login list`, check the output, and append it to `~/.aws/config`:

```bash
jq -r '.profile_map | to_entries[] |
  (.key | capture("iam::(?<acct>[0-9]+):role/(?<role>[^@]+)@(?<region>.+)")) as $m |
  "# was SAML role \($m.role)\n[profile \(.value)]\nsso_session = huit\nsso_account_id = \($m.acct)\nsso_role_name = CHANGE-ME\nregion = \($m.region)\n"' \
  ~/.huit_aws/config
```

**Aliases and the script work together:**
- Running `aws-oidc-login setup` after you've set up your aliases is safe. It recognizes a profile by its account and role, whatever it's named, and only adds profiles for accounts you haven't set up yet.
- If you only want your own aliases, skip `setup`. `aws-oidc-login verify` still checks every profile that uses the session.
- The script only reuses a name on its own when it matches the account's name after conversion (`Campus Services Dev` → `campus-services-dev`). For any other alias, add the `sso_*` keys by hand, or run `setup` and rename the section it created.
- The rule from the table above still applies: if an alias holds a long-lived `AKIA…` key in `~/.aws/credentials`, give the SSO version a different name.

## Precedence cheat sheet

From highest to lowest, for a given command:

1. `--profile X` on the command line (it overrides environment keys)
2. `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in the environment
3. `AWS_PROFILE=X`
4. Inside profile X: assume-role settings (`role_arn`), then SSO settings, then keys in `~/.aws/credentials`, then `credential_process`

The common trap is item 2 beating item 3. If you `export AWS_PROFILE=...` but a SAML tool left `AWS_ACCESS_KEY_ID` exported in your shell, the environment keys win. Run `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN`.

## Accounts that aren't in the portal

`aws-oidc-login list` shows exactly what Identity Center assigns you. An account you reach through SAML but that isn't listed isn't federated through this portal. Keep using your old tool for it, or ask the account owner to assign you a permission set.
