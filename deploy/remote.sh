#!/usr/bin/env bash
# Runs on the server inside REMOTE_DIR. deploy.sh unpacks the upload into new/ and calls
# `./remote.sh <sha>`.
#
# Layout after the first deploy:
#   conf/Caddyfile       Caddy config, mounted as a directory (conf/ -> /etc/caddy)
#   www/releases/<rel>/  one directory per deploy, never modified after it is created
#   www/current          symlink to the live release; Caddy serves /www/current
#   www/history          release names, oldest first, last line = live
#   docker-compose.yml   the web container definition
set -euo pipefail

SHA="${1:?usage: remote.sh <sha>}"
KEEP="${KEEP_RELEASES:-3}"
cd "$(dirname "$0")"
[ -d new/site ] && [ -f new/Caddyfile ] && [ -f new/docker-compose.yml ] || { echo "new/ is incomplete" >&2; exit 1; }

# 1) Validate the new Caddyfile in a throwaway container with no network, before anything live changes.
docker run --rm --network none --tmpfs /var/log/caddy -v "$PWD/new:/c:ro" caddy:2-alpine \
  caddy validate --config /c/Caddyfile --adapter caddyfile >/dev/null

mkdir -p conf www/releases

# 2) Unpack into a directory no request has seen. The name includes the time, so redeploying the
#    same commit never overwrites the release that is being served.
REL="${SHA:0:12}-$(date -u +%Y%m%dT%H%M%SZ)"
mv new/site "www/releases/$REL"

# 3) Swap. `ln -sfn` alone is not atomic (unlink + create). Creating a second link and renaming it
#    over the first is a single rename(2): every request sees the old release or the new one.
prev="$(readlink www/current 2>/dev/null || true)"
ln -sfn "releases/$REL" www/current.next
mv -T www/current.next www/current

# 4) Config, replaced the same way. conf/ is mounted as a directory: a single-file bind mount would
#    keep pointing at the old inode after the rename.
mv new/Caddyfile conf/Caddyfile.next
mv -T conf/Caddyfile.next conf/Caddyfile
mv new/docker-compose.yml docker-compose.yml
rm -rf new

# 5) The container is recreated only if docker-compose.yml changed. Otherwise reload in place:
#    open connections keep their files, new requests get the new release.
docker compose up -d --remove-orphans
docker compose exec -T site caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

# 6) History and pruning: keep the last KEEP releases; the live one is always among them.
echo "$REL" >> www/history
tail -n "$KEEP" www/history > www/history.keep
mv www/history.keep www/history
for d in www/releases/*/; do
  n="$(basename "$d")"
  grep -qx "$n" www/history || rm -rf "www/releases/$n"
done
echo "$SHA" > REVISION
echo "release: $REL (previous: ${prev#releases/})"
