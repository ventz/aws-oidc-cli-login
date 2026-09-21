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

The script only reuses a name automatically when it matches the account's name after conversion (`Campus Services Dev` → `campus-services-dev`). If your SAML tool used different names (say `entarch` for `entarch-prod-standard`), you have two options:
- Edit `~/.aws/config` by hand and add the `sso_*` keys under your old name.
- Run the script first, then rename the section it created.

Either way, later runs recognize that profile by its account and role and won't add a duplicate.

## Precedence cheat sheet

From highest to lowest, for a given command:

1. `--profile X` on the command line (it overrides environment keys)
2. `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in the environment
3. `AWS_PROFILE=X`
4. Inside profile X: assume-role settings (`role_arn`), then SSO settings, then keys in `~/.aws/credentials`, then `credential_process`

The common trap is item 2 beating item 3. If you `export AWS_PROFILE=...` but a SAML tool left `AWS_ACCESS_KEY_ID` exported in your shell, the environment keys win. Run `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN`.

## Accounts that aren't in the portal

`aws-oidc-login list` shows exactly what Identity Center assigns you. An account you reach through SAML but that isn't listed isn't federated through this portal. Keep using your old tool for it, or ask the account owner to assign you a permission set.
