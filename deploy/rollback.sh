#!/usr/bin/env bash
# Runs on the server inside REMOTE_DIR. Points www/current at an earlier release and reloads Caddy.
#
# Usage:
#   ./rollback.sh            # switch to the release before the live one (from www/history)
#   ./rollback.sh <release>  # switch to a named directory under www/releases/
#   ./rollback.sh --list     # show the kept releases, live one marked with *
set -euo pipefail
cd "$(dirname "$0")"

live="$(basename "$(readlink www/current)")"
if [ "${1:-}" = "--list" ]; then
  while read -r r; do [ "$r" = "$live" ] && echo "* $r" || echo "  $r"; done < www/history
  exit 0
fi

target="${1:-}"
if [ -z "$target" ]; then
  target="$(grep -vx "$live" www/history | tail -n 1 || true)"
  [ -n "$target" ] || { echo "no earlier release kept" >&2; exit 1; }
fi
[ -d "www/releases/$target" ] || { echo "www/releases/$target not found" >&2; exit 1; }

ln -sfn "releases/$target" www/current.next
mv -T www/current.next www/current
docker compose exec -T site caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
echo "rolled back: $live -> $target"
