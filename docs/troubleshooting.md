# Troubleshooting

Start with these two commands. They answer most questions:

```bash
aws configure list --profile X            # where credentials come from (TYPE column)
aws sts get-caller-identity --profile X   # who you actually are
```

| Symptom | Cause | Fix |
|---|---|---|
| `Error loading SSO Token: Token for huit does not exist` | Not logged in | `aws sso login --sso-session huit` |
| `The SSO session associated with this profile has expired or is otherwise invalid` | The portal session ended | `aws sso login --sso-session huit` |
| `ForbiddenException: No access` from `GetRoleCredentials` | Wrong `sso_role_name` for that account, or the assignment was removed | `aws-oidc-login list` shows the real roles; fix the profile or re-run setup |
| `InvalidRequestException` or an invalid-client error during login | Wrong `sso_region` (it must be the Identity Center region, `us-east-1`, not your workload region) | Fix `sso_region` in `[sso-session huit]` |
| Login opens a browser on the wrong machine (SSH) | Browser flow runs locally | `aws sso login --sso-session huit --use-device-code` |
| `--profile` works but `export AWS_PROFILE=X` is ignored | `AWS_ACCESS_KEY_ID` is still exported in your shell and beats `AWS_PROFILE` | `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN` |
| A profile still uses old SAML keys | Its `config` section has no `sso_*` keys (typo in the name, or `[name]` instead of `[profile name]`) | `aws configure list --profile X` should show TYPE `sso` |
| An account you expected is missing | Not assigned to you in the portal | Ask the account owner; SAML-only accounts stay on your old tool |
| A tool can't find credentials but the CLI can | The tool's SDK predates `sso-session` | Upgrade the tool, or see [using-with-tools.md](using-with-tools.md) |
| `aws-oidc-login: could not list the roles for every account` | A `ListAccountRoles` call failed; the AWS error is printed above it (for example `ThrottlingException` if other tools are calling Identity Center at the same time) | Run the command again |
| `aws-oidc-login: not logged in` right after using the CLI | The cached access token expired (~1 h) and there's no SSO profile yet to refresh it through | `aws-oidc-login login` |

## Undo

Every write by `aws-oidc-login` first saves `~/.aws/config.bak.<timestamp>`. To roll back:

```bash
ls -t ~/.aws/config.bak.* | head -1                     # newest backup
cp "$(ls -t ~/.aws/config.bak.* | head -1)" ~/.aws/config
```

Profiles the script added sit below a `# --- aws-oidc-login: sso-session huit (date) ---` comment, so you can also delete them by hand.

## Start over

```bash
aws sso logout                                          # revoke the session and clear token caches
# then remove the [sso-session huit] and generated [profile ...] blocks from ~/.aws/config
```

## Debugging the CLI itself

`aws sso login --sso-session huit --debug` shows the OIDC endpoints and responses. Add `--debug` to any command to see which credential provider was used.
