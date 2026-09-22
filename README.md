# aws-oidc-cli-login

Log in to every AWS account you have in the **Harvard AWS access portal** from the terminal, using only the official AWS CLI v2. One browser login gives you a named CLI profile for every account and role you can reach, and the credentials refresh on their own.

There are no SAML scrapers, no passwords in scripts and no long-lived access keys. The CLI does all the authentication with [AWS IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html) (formerly AWS SSO) over OAuth 2.0 / OIDC. This repo adds a small script that writes the profiles for you, and docs on how it all fits together.

Defaults are set for the HUIT portal (`https://huitprodpayer.awsapps.com/start`), and it works with any Identity Center portal via `--start-url`.

## Table of Contents

- [Quick Install](#quick-install)
- [Overview](#overview)
- [Features](#features)
- [Usage](#usage)
- [Doing It By Hand](#doing-it-by-hand)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Quick Install

Prereqs: [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and `jq` (`brew install awscli jq`).

```bash
git clone https://github.com/ventz/aws-oidc-cli-login.git
cd aws-oidc-cli-login
./bin/aws-oidc-login                        # sign in through Okta (passkey), review, confirm
aws sts get-caller-identity --profile <account-name>
```

After that, each day starts with `aws sso login --sso-session huit`.

## Overview

When you open the access portal in a browser, you pick an account and a role, and AWS hands you short-lived credentials. The AWS CLI can do the same thing without the browser clicking:

```
aws sso login ──► browser: Okta + passkey ──► token cached in ~/.aws/sso/cache/
                                                   │
aws s3 ls --profile fas-dev-standard ──────────────┘──► temporary role credentials
```

- **One login, every account.** The `[sso-session huit]` block holds the login. Every profile that points at it shares the same token.
- **Nothing long-lived on disk.** Tokens and role credentials expire. The CLI refreshes them quietly until your session ends (typically 8–12 hours), and then you log in again.
- **Works with everything that reads `~/.aws/config`.** That includes boto3, the other AWS SDKs, Terraform, CDK, SAM, and IDE plugins.

The one tedious part is writing a `[profile]` block for each of the dozens of accounts you may have. That's what `bin/aws-oidc-login` does.

## Features

- **Profiles for every account.** Each is named after the account (`Campus Services Dev` → `campus-services-dev`), with your highest role by default.
- **Safe with an existing config.** It shows a plan, backs up `~/.aws/config`, and asks before writing. It never touches `~/.aws/credentials`.
- **Migration-aware.** It reuses profile names left behind by SAML tools, but never takes over a name that holds a long-lived IAM key (`AKIA…`) or an assume-role profile. Those get a `-sso` suffix instead.
- **Idempotent.** It recognizes profiles that are already set up, under any name, so re-running only adds new accounts.
- **Built-in checks.** `verify` confirms every profile really works, and `list` shows every account and role you have.
- **Portable.** It's plain bash (including the bash 3.2 that ships with macOS) plus `jq`, and has an offline test suite.

## Usage

```bash
aws-oidc-login                  # setup: session + login + profiles + verify
aws-oidc-login --dry-run        # show what setup would change
aws-oidc-login list             # every account and role you can access
aws-oidc-login verify           # sts get-caller-identity on every profile
aws-oidc-login generate         # print profile blocks, change nothing
aws-oidc-login --help
```

| Option | Effect |
|---|---|
| `--all-roles` | One profile per account **and** role (`fas-dev-standard-huitreadonly`) |
| `--prefix sso-` | Prefix every new profile name |
| `-u URL`, `-r REGION`, `-s NAME` | Another portal, its Identity Center region, and a session name for it |
| `--region REGION` | Default region written into profiles (the default is the SSO region, `us-east-1`) |
| `ROLE_PREFERENCE=HUITReadOnly,...` | Which role to pick when an account offers several (most preferred first) |

Day to day:

```bash
aws sso login --sso-session huit            # once per session
export AWS_PROFILE=fas-dev-standard         # or pass --profile each time
aws sso logout                              # end the session and clear cached tokens
```

Working over SSH or on a machine without a browser? Use `aws sso login --sso-session huit --use-device-code` and open the printed URL on any device.

Optionally, put the script on your `PATH`: `ln -s "$PWD/bin/aws-oidc-login" /usr/local/bin/`.

## Doing It By Hand

The script only writes standard AWS CLI config. To set it up yourself:

```bash
aws configure sso-session
#   SSO session name:        huit
#   SSO start URL:           https://huitprodpayer.awsapps.com/start
#   SSO region:              us-east-1
#   SSO registration scopes: sso:account:access

aws sso login --sso-session huit
aws configure sso --profile fas-dev-standard    # choose the account and role from the list
```

Resulting `~/.aws/config`:

```ini
[sso-session huit]
sso_start_url = https://huitprodpayer.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile fas-dev-standard]
sso_session = huit
sso_account_id = 111122223333
sso_role_name = HUITReadOnly
region = us-east-1
```

## Documentation

- [How it works](docs/how-it-works.md): the login flow, what's cached where, lifetimes, and the security model
- [Migrating from SAML tools](docs/migrating-from-saml.md): keeping profile names, custom aliases (converting a SAML role map), credential precedence, and what the script renames and why
- [Using profiles with other tools](docs/using-with-tools.md): boto3, Terraform, CDK, Docker, and tools that only take environment variables
- [Troubleshooting](docs/troubleshooting.md): common errors and fixes

## Contributing

Issues and pull requests are welcome. Run the offline tests before sending changes. They use a fake `aws` and a throwaway `HOME`, so they never touch your real config:

```bash
tests/run.sh                    # your default bash
TEST_BASH=/bin/bash tests/run.sh   # macOS system bash 3.2
shellcheck bin/aws-oidc-login tests/*.sh tests/fake-aws
```

This is a community tool, not an official HUIT service. For access to an account or role, ask that account's owner or HUIT Cloud Operations.

## License

[MIT](LICENSE) © Ventz Petkov
