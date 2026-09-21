# How It Works

## Pieces

| Piece | Where | What it is |
|---|---|---|
| `[sso-session huit]` | `~/.aws/config` | How to log in: portal URL, Identity Center region, scopes |
| `[profile <name>]` | `~/.aws/config` | What to assume: `sso_session`, `sso_account_id`, `sso_role_name` |
| Session token | `~/.aws/sso/cache/<sha1 of session name>.json` | OIDC access token plus refresh token from your login |
| Role credentials | `~/.aws/cli/cache/` | Short-lived keys for one account and role, fetched on demand |

Identity Center calls a role a **permission set**. In each account it shows up as an IAM role named `AWSReservedSSO_<PermissionSet>_<suffix>`. That's what you'll see in `sts get-caller-identity` and in CloudTrail.

## The login flow

1. `aws sso login --sso-session huit` registers the CLI as an OIDC client with Identity Center in `us-east-1`.
2. It opens your browser to the portal using the OAuth 2.0 **authorization code flow with PKCE**. With `--use-device-code`, it uses the **device authorization flow** instead: you enter a short code on any device.
3. You sign in as usual (HarvardKey through Okta, with your passkey). The CLI receives an access token and a refresh token and caches them.
4. When you run a command with `--profile X`, the CLI swaps the access token for role credentials for X's account and role (`sso:GetRoleCredentials`), caches them, and signs the request.

Because the login is OAuth/OIDC rather than SAML, no tool ever sees your sign-in credentials, and nothing scrapes an HTML login page.

## Lifetimes

| Thing | Typical lifetime | Renewal |
|---|---|---|
| Access token | ~1 hour | Refreshed automatically with the refresh token |
| Portal session | Set by the portal admins (commonly 8–12 hours) | `aws sso login` again |
| Role credentials | Set by the permission set (commonly 1–12 hours) | Re-fetched automatically while the session lasts |

Automatic refresh needs the `sso-session` format with the `sso:account:access` scope. Older profiles that put `sso_start_url` directly on the profile can't refresh and make you log in again each time the token expires.

## Security model

- **Nothing long-lived is written.** Everything in the caches expires. `aws sso logout` revokes the session and clears the caches.
- **The token cache is a bearer secret.** Until it expires, anyone who can read `~/.aws/sso/cache/` can act as you in every account you have. The CLI creates those files as mode `600`. Don't sync `~/.aws/` to cloud storage or commit it to a dotfiles repo without excluding `sso/` and `cli/`.
- **Everything is attributed to you.** CloudTrail records each call against `AWSReservedSSO_<PermissionSet>` with your identity as the session name.
- **Least privilege is a choice.** By default the script picks the highest role you have in each account. To default to read-only, use `ROLE_PREFERENCE=HUITReadOnly aws-oidc-login`, or `--all-roles` to get a profile for each role and choose per command.

## What `aws-oidc-login setup` does

1. Adds `[sso-session huit]` if it's missing (after backing up the config).
2. Reuses a valid token, refreshes an expired one through an existing profile, or opens the browser to log in.
3. Lists every account and role (`sso:ListAccounts`, `sso:ListAccountRoles`).
4. Plans one profile per account. Each is marked **add**, **merge** (add `sso_*` keys to an existing plain section), **exists** (already set up, under any name), or renamed with a `-sso` suffix (the name belongs to a long-lived key, an assume-role profile or another account).
5. Shows the plan, backs up `~/.aws/config`, and applies the plan once you confirm.
6. Runs `sts get-caller-identity` against every profile in the session.

It only calls read-only Identity Center APIs and STS, and the only file it edits is `~/.aws/config` (or `$AWS_CONFIG_FILE`).
