# Contributing to deploy-kit

Thank you for helping. deploy-kit is a small template for zero-downtime static deploys with Caddy: three shell
scripts in [deploy/](deploy/), a Caddyfile and a compose file.

## Ways to contribute

| You want to | Do this |
|---|---|
| Report a bug | Open an issue with the steps, what you expected and what happened |
| Suggest a change | Open an issue first if it changes how a deploy works, so we can agree on it |
| Fix a typo or a small bug | Open a pull request |
| Report a vulnerability | Not a public issue: see [SECURITY.md](SECURITY.md) |

## Development

Requirements: `bash`, `git` and [ShellCheck](https://www.shellcheck.net/). The tests need no server, Docker
or network: `docker`, `ssh`, `curl` and `date` are replaced by stubs.

```sh
shellcheck --severity=style deploy/*.sh tests/*.sh   # static analysis, no findings allowed
bash tests/run.sh                                    # the test suite; prints one line per check
```

The server side uses `mv -T` (GNU coreutils), so run the tests on Linux or in WSL.

## Requirements for a change

- **Tests.** New behaviour and every bug fix come with a check in [tests/run.sh](tests/run.sh). CI runs
  ShellCheck and the tests on every pull request.
- **Nothing live changes before validation.** `remote.sh` must stop before the swap when the upload is
  incomplete or the Caddyfile is invalid; keep it that way and keep the swaps atomic (`mv -T`).
- **Placeholders only.** No real hosts, paths, keys or names: use `example.com`, `deploy@your-server`,
  `/srv/sites/example`.
- **Coding standard.** Bash with `set -euo pipefail`, quoted expansions, and a comment for each step that
  says why it is there.
- **One topic per pull request**, Conventional Commits style (`feat:`, `fix:`, `docs:`, `test:`).

## Developer Certificate of Origin (DCO)

Every commit must be signed off, which certifies that you wrote it or have the right to submit it under the
project licence ([developercertificate.org](https://developercertificate.org/)):

```sh
git commit -s -m "fix: ..."
```

The `dco` check fails a pull request that has an unsigned commit; fix it with
`git rebase --signoff origin/main` and push again.

## Review and merge

Every change goes through a pull request with green CI (`build`, `dco`) and an approving review from a
maintainer other than the author. We squash-merge and delete the branch.

## Licence

Contributions are released under the [MIT License](LICENSE). No CLA is required.
