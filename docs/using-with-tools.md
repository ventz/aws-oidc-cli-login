# Using Profiles with Other Tools

Anything built on a current AWS SDK reads `~/.aws/config` and understands `sso-session` profiles. Log in once with `aws sso login --sso-session huit`, then point the tool at a profile.

## SDKs and IaC

| Tool | How to pick the profile |
|---|---|
| AWS CLI | `--profile X` or `export AWS_PROFILE=X` |
| boto3 (Python) | `boto3.Session(profile_name="X")` or `AWS_PROFILE=X` |
| AWS SDK for JavaScript v3 | `fromSSO({ profile: "X" })` or `AWS_PROFILE=X` |
| Terraform (AWS provider) | `provider "aws" { profile = "X" }` or `AWS_PROFILE=X` |
| AWS CDK | `cdk deploy --profile X` |
| AWS SAM | `sam deploy --profile X` |

Old SDK releases predate the `sso-session` format. If a tool says it can't find credentials for a profile that works in the CLI, upgrade the tool, or use one of the fallbacks below.

## Tools that only accept keys

Export temporary keys for one profile into your shell:

```bash
eval "$(aws configure export-credentials --profile X --format env)"
```

Other formats: `env-no-export`, `powershell`, `windows-cmd`, and `process` (JSON for `credential_process`). The keys expire like any role credentials, so re-run it when they do.

For a tool that reads `~/.aws/credentials` but not SSO config, give it a `credential_process` profile that asks the CLI:

```ini
[profile X-keys]
credential_process = aws configure export-credentials --profile X --format process
```

## Docker

Mount your AWS directory read-only and pass the profile:

```bash
docker run --rm -v ~/.aws:/root/.aws:ro -e AWS_PROFILE=X amazon/aws-cli sts get-caller-identity
```

The container reads the cached token directly, so log in on the host first. If the token needs refreshing, the container can't write the refreshed token back to a read-only mount. For long jobs, pass exported keys (`--format env-no-export` into an `--env-file`) instead.

## Shell prompt and switching helpers

A small shell function makes switching quick:

```bash
awsp() { export AWS_PROFILE="$1"; aws sts get-caller-identity --query Arn --output text; }
```

To tab-complete profile names, `aws configure list-profiles` prints them all.
