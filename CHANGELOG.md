# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/). Releases are git tags `vX.Y.Z` with the same notes on the
[releases page](https://github.com/wonmortech/deploy-kit/releases).

## [Unreleased]

## [0.1.0] - 2026-11-14

First tagged version: the zero-downtime static deploy template (release directories, atomic symlink swap,
validated Caddy config, graceful reload, health check against `/version.txt`, rollback), plus:

### Added

- Test suite (`tests/run.sh`) for `deploy.sh`, `remote.sh` and `rollback.sh`, with `docker`, `ssh`, `curl`
  and `date` stubbed, so it needs no server.
- CI: ShellCheck and the tests on every pull request; DCO sign-off check.
- `CONTRIBUTING.md`, `SECURITY.md` and this changelog.
- OpenSSF Scorecard workflow, CODEOWNERS and Dependabot for GitHub Actions.

### Fixed

- `remote.sh`: deploying the same commit twice within one second produced the same release name, and the new
  site was moved *inside* the existing release directory. It now stops before anything changes.

### Security

- The example deploy workflow pins `actions/checkout` to a commit and does not persist credentials.
