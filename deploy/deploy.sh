#!/usr/bin/env bash
# Zero-downtime static deploy: build output -> new release on the server -> atomic symlink swap
# -> caddy reload -> health check against /version.txt.
#
# Usage:   deploy/deploy.sh [ssh-target]
# Example: SITE_URL=https://example.com deploy/deploy.sh deploy@your-server
#
# Settings (environment variables):
#   SITE_DIR     local directory with the built site            (default: dist)
#   REMOTE_DIR   directory on the server that holds the site    (default: /srv/sites/example)
#   SITE_URL     public URL used for the health check           (default: https://example.com)
#   BRANCH       only deploy when HEAD equals origin/$BRANCH    (default: main; empty disables the check)
#   KEEP_RELEASES  how many releases to keep on the server      (default: 3)
set -euo pipefail

TARGET="${1:-deploy@your-server}"
SITE_DIR="${SITE_DIR:-dist}"
REMOTE_DIR="${REMOTE_DIR:-/srv/sites/example}"
SITE_URL="${SITE_URL:-https://example.com}"
BRANCH="${BRANCH-main}"
KEEP_RELEASES="${KEEP_RELEASES:-3}"

fail() { echo "deploy stopped: $*" >&2; exit 1; }
cd "$(dirname "$0")/.."

# 1) Only deploy a clean, known commit. The commit hash becomes the release name and version.txt.
[ -z "$(git status --porcelain)" ] || fail "uncommitted changes"
SHA="$(git rev-parse HEAD)"
if [ -n "$BRANCH" ]; then
  git fetch --quiet origin "$BRANCH"
  [ "$SHA" = "$(git rev-parse "origin/$BRANCH")" ] || fail "HEAD is not origin/$BRANCH"
fi
[ -d "$SITE_DIR" ] || fail "$SITE_DIR not found (build the site first)"

# 2) Stage: the site, the Caddy config, the compose file and the remote script.
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/new"
cp -R "$SITE_DIR" "$STAGE/new/site"
printf '%s\n' "$SHA" > "$STAGE/new/site/version.txt"
cp deploy/Caddyfile deploy/docker-compose.yml deploy/remote.sh deploy/rollback.sh "$STAGE/new/"

# 3) Upload into new/ and let remote.sh do the swap. Nothing live changes before remote.sh validates.
tar -czf - -C "$STAGE" new \
  | ssh "$TARGET" "set -e; mkdir -p '$REMOTE_DIR'; cd '$REMOTE_DIR'; rm -rf new
tar --no-same-owner -xzf -
install -m 755 new/remote.sh remote.sh
install -m 755 new/rollback.sh rollback.sh
KEEP_RELEASES='$KEEP_RELEASES' ./remote.sh '$SHA'"

# 4) Health check: the new release is live when /version.txt returns this commit.
for _ in $(seq 1 20); do
  if curl -fsS "$SITE_URL/version.txt" 2>/dev/null | grep -q "$SHA"; then
    echo "deploy ready: $SHA -> $SITE_URL"; exit 0
  fi
  sleep 3
done
fail "$SITE_URL/version.txt did not return $SHA. Roll back with: ssh $TARGET 'cd $REMOTE_DIR && ./rollback.sh'"
