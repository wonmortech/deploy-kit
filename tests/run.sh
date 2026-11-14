#!/usr/bin/env bash
# Tests for deploy/deploy.sh, deploy/remote.sh and deploy/rollback.sh. No server, Docker or network
# is needed: docker, ssh, curl and date are replaced by small stubs on PATH, and every test case
# runs in its own temporary directory. Run with: bash tests/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL_DATE="$(command -v date)"
export REAL_DATE
PASS=0
FAIL=0
WORK=""

# Call right after a test command: records its exit status under the given name.
check() {
  local rc=$?
  if [ "$rc" -eq 0 ]; then PASS=$((PASS + 1)); echo "ok   - $1"; else FAIL=$((FAIL + 1)); echo "FAIL - $1"; fi
}
# Passes when the command fails.
fails() { ! "$@" >/dev/null 2>&1; }

stub() { cat > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }

# A fresh server directory with the scripts installed, and stubs on PATH.
setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/bin" "$WORK/srv"
  cp "$ROOT/deploy/remote.sh" "$ROOT/deploy/rollback.sh" "$WORK/srv/"
  # docker records every call; `docker run` (the Caddyfile validation) fails when DOCKER_VALIDATE=fail.
  stub docker <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
if [ "$1" = run ] && [ "${DOCKER_VALIDATE:-ok}" = fail ]; then echo "invalid Caddyfile" >&2; exit 1; fi
exit 0
EOF
  # date returns FAKE_DATE when it is set, so two deploys can land in the same second on purpose.
  stub date <<'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_DATE:-}" ]; then echo "$FAKE_DATE"; else exec "$REAL_DATE" "$@"; fi
EOF
  export STUB_LOG="$WORK/calls.log"
  : > "$STUB_LOG"
  export PATH="$WORK/bin:$PATH"
}
teardown() { rm -rf "$WORK"; WORK=""; unset FAKE_DATE DOCKER_VALIDATE; }

# What deploy.sh uploads: new/ with the site, the Caddyfile and the compose file.
stage() {
  mkdir -p "$WORK/srv/new/site"
  echo "<h1>$1</h1>" > "$WORK/srv/new/site/index.html"
  echo "$1" > "$WORK/srv/new/site/version.txt"
  cp "$ROOT/deploy/Caddyfile" "$ROOT/deploy/docker-compose.yml" "$WORK/srv/new/"
}
remote() { (cd "$WORK/srv" && ./remote.sh "$@"); }
rollback() { (cd "$WORK/srv" && ./rollback.sh "$@"); }
deploy_remote() { stage "$1"; remote "$1" >/dev/null; }
live() { readlink "$WORK/srv/www/current"; }
live_version() { cat "$WORK/srv/www/current/version.txt"; }
line_of() { grep -n -m1 "$1" "$STUB_LOG" | cut -d: -f1; }

# ---------------------------------------------------------------- remote.sh
setup
deploy_remote aaaaaaaaaaaa1111
[ "$(live_version)" = aaaaaaaaaaaa1111 ]; check "remote.sh: first deploy makes current point at the new release"
[[ "$(live)" == releases/aaaaaaaaaaaa-* ]]; check "remote.sh: current is a relative symlink into releases/"
cmp -s "$WORK/srv/conf/Caddyfile" "$ROOT/deploy/Caddyfile"; check "remote.sh: the Caddyfile is installed under conf/"
[ "$(cat "$WORK/srv/www/history")" = "$(basename "$(live)")" ]; check "remote.sh: history holds the live release"
[ "$(cat "$WORK/srv/REVISION")" = aaaaaaaaaaaa1111 ]; check "remote.sh: REVISION holds the commit"
[ ! -e "$WORK/srv/new" ]; check "remote.sh: new/ is removed after the swap"
grep -q "caddy validate" "$STUB_LOG" && [ "$(line_of "caddy validate")" -lt "$(line_of "caddy reload")" ]
check "remote.sh: the Caddyfile is validated before Caddy is reloaded"
grep -q "docker compose exec -T site caddy reload" "$STUB_LOG"; check "remote.sh: Caddy is reloaded in place"
teardown

setup
for s in 1111111111110001 2222222222220002 3333333333330003 4444444444440004; do deploy_remote "$s"; done
[ "$(find "$WORK/srv/www/releases" -mindepth 1 -maxdepth 1 | wc -l)" -eq 3 ]; check "remote.sh: KEEP_RELEASES=3 keeps three releases"
! compgen -G "$WORK/srv/www/releases/111111111111-*" >/dev/null; check "remote.sh: the oldest release is pruned"
[ "$(live_version)" = 4444444444440004 ]; check "remote.sh: the latest deploy is live"
[ "$(wc -l < "$WORK/srv/www/history")" -eq 3 ] && [ "$(tail -n 1 "$WORK/srv/www/history")" = "$(basename "$(live)")" ]
check "remote.sh: history lists the kept releases, live one last"
teardown

setup
export KEEP_RELEASES=1
deploy_remote 1111111111110001; deploy_remote 2222222222220002
[ "$(find "$WORK/srv/www/releases" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ] && [ "$(live_version)" = 2222222222220002 ]
check "remote.sh: KEEP_RELEASES=1 keeps only the live release"
unset KEEP_RELEASES
teardown

setup
deploy_remote aaaaaaaaaaaa1111
before="$(live)"
mkdir -p "$WORK/srv/new/site"   # no Caddyfile, no compose file
fails remote bbbbbbbbbbbb2222; check "remote.sh: refuses an incomplete upload"
[ "$(live)" = "$before" ]; check "remote.sh: an incomplete upload leaves the live release alone"
rm -rf "$WORK/srv/new"
stage bbbbbbbbbbbb2222
export DOCKER_VALIDATE=fail
fails remote bbbbbbbbbbbb2222; check "remote.sh: stops on an invalid Caddyfile"
unset DOCKER_VALIDATE
[ "$(live)" = "$before" ] && cmp -s "$WORK/srv/conf/Caddyfile" "$ROOT/deploy/Caddyfile"
check "remote.sh: an invalid Caddyfile leaves the live release and the config alone"
teardown

setup
export FAKE_DATE=20260101T000000Z
deploy_remote cccccccccccc3333
rel="$(basename "$(live)")"
stage cccccccccccc3333
fails remote cccccccccccc3333; check "remote.sh: refuses a release name that already exists (same commit, same second)"
[ ! -e "$WORK/srv/www/releases/$rel/site" ] && [ "$(live)" = "releases/$rel" ]
check "remote.sh: the existing release is not modified"
teardown

# ---------------------------------------------------------------- rollback.sh
setup
for s in 1111111111110001 2222222222220002 3333333333330003; do deploy_remote "$s"; done
rollback >/dev/null
[ "$(live_version)" = 2222222222220002 ]; check "rollback.sh: with no argument goes back to the previous release"
grep -q "caddy reload" <(tail -n 1 "$STUB_LOG"); check "rollback.sh: reloads Caddy"
list="$(rollback --list)"
grep -q "^\* 222222222222-" <<<"$list"; check "rollback.sh: --list marks the live release with *"
rollback "$(head -n 1 "$WORK/srv/www/history")" >/dev/null
[ "$(live_version)" = 1111111111110001 ]; check "rollback.sh: a named release can be made live"
fails rollback does-not-exist; check "rollback.sh: rejects an unknown release"
[ "$(live_version)" = 1111111111110001 ]; check "rollback.sh: a rejected rollback leaves the live release alone"
teardown

setup
deploy_remote 1111111111110001
fails rollback; check "rollback.sh: fails when no earlier release is kept"
teardown

# ---------------------------------------------------------------- deploy.sh, end to end
# A git checkout of the kit with a built dist/. ssh runs the remote command locally; curl reads
# version.txt from the live release on disk.
e2e_setup() {
  setup
  REPO="$WORK/repo"
  mkdir -p "$REPO"
  cp -R "$ROOT/deploy" "$REPO/"
  printf 'dist/\n' > "$REPO/.gitignore"
  git -C "$REPO" init -q
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=test -c user.email=test@example.com commit -q -m init
  mkdir -p "$REPO/dist"
  echo "<h1>site</h1>" > "$REPO/dist/index.html"
  stub ssh <<'EOF'
#!/usr/bin/env bash
shift   # the ssh target
exec bash -c "$*"
EOF
  stub curl <<'EOF'
#!/usr/bin/env bash
cat "$REMOTE_DIR/www/current/version.txt"
EOF
  export REMOTE_DIR="$WORK/server" BRANCH="" SITE_URL=http://site.test
}
e2e_teardown() { unset REMOTE_DIR BRANCH SITE_URL; teardown; }

e2e_setup
out="$("$REPO/deploy/deploy.sh" deploy@site.test 2>&1)"; rc=$?
sha="$(git -C "$REPO" rev-parse HEAD)"
[ "$rc" -eq 0 ] && grep -q "deploy ready: $sha" <<<"$out"; check "deploy.sh: a clean checkout deploys and passes the health check"
[ "$(cat "$REMOTE_DIR/www/current/version.txt")" = "$sha" ]; check "deploy.sh: version.txt of the live release is the commit"
[ -f "$REMOTE_DIR/www/current/index.html" ]; check "deploy.sh: the built site is live"
[ -x "$REMOTE_DIR/remote.sh" ] && [ -x "$REMOTE_DIR/rollback.sh" ]; check "deploy.sh: remote.sh and rollback.sh are installed on the server"
e2e_teardown

e2e_setup
echo "# local edit" >> "$REPO/deploy/Caddyfile"
out="$("$REPO/deploy/deploy.sh" deploy@site.test 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q "uncommitted changes" <<<"$out"; check "deploy.sh: refuses a working tree with uncommitted changes"
[ ! -e "$REMOTE_DIR" ]; check "deploy.sh: nothing is uploaded from a dirty tree"
e2e_teardown

e2e_setup
rm -rf "$REPO/dist"
out="$("$REPO/deploy/deploy.sh" deploy@site.test 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q "dist not found" <<<"$out"; check "deploy.sh: refuses when the build output is missing"
e2e_teardown

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
