# Security policy

## Supported versions

deploy-kit is a template: you copy `deploy/` into your own repository. Fixes go to `main`; there are no
older versions to patch. If you copied an earlier version, compare it with `main` and the
[CHANGELOG](CHANGELOG.md).

## Reporting a vulnerability

Please **do not** open a public issue, pull request or discussion for a vulnerability.

1. Preferred: GitHub private vulnerability reporting, in this repository's **Security** tab,
   then **Report a vulnerability**: <https://github.com/wonmortech/deploy-kit/security/advisories/new>.
2. If you cannot use GitHub: a private message on Telegram to <https://t.me/xnosir>. A short first message such as
   "Security report for deploy-kit" is enough; we will agree on a safe way to share the details.

Include the affected file, the steps to reproduce, and what an attacker could gain. Never send live
credentials, keys or server addresses, even as proof.

## What happens next

| Step | What we do | Within |
|---|---|---|
| Acknowledge | Confirm we received your report | 7 days |
| Assess | Reproduce it and rate its severity (CVSS) | 14 days |
| Fix | Fix high and critical issues on `main`, sooner where possible | 60 days |
| Disclose | Publish a GitHub security advisory with the fix | With the fix |

We credit reporters in the advisory if they wish. Good-faith research that follows the
[organization security policy](https://github.com/wonmortech/.github/blob/main/SECURITY.md) is welcome and
covered by its safe-harbour section. There is no paid bug bounty.

## Security notes for users

- `deploy.sh` sends the site over SSH; pin the server's host key (`DEPLOY_KNOWN_HOSTS` in the example
  workflow) instead of accepting it on first use.
- The deploy user only needs to run `docker` and write to the site directory. Do not deploy as root.
- The example workflow runs on manual dispatch only and checks out without persisting credentials.
