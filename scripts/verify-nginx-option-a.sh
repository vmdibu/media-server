#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
CONF_BASENAME="media-server.conf"

log "Checking prerequisites"
[ -f "$ENV_FILE" ] || fail "Missing .env at $ENV_FILE"
command -v docker >/dev/null 2>&1 || fail "docker is not installed or not in PATH"
command -v grep >/dev/null 2>&1 || fail "grep is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

[ -n "${CONFIG_ROOT:-}" ] || fail "CONFIG_ROOT is not set in .env"

COMPOSE=(docker compose --project-directory "$ROOT_DIR" -f "$ROOT_DIR/compose.yml")
LIVE_CONF="$CONFIG_ROOT/nginx/conf.d/$CONF_BASENAME"

log "Checking live nginx config file"
[ -f "$LIVE_CONF" ] || fail "Live nginx config not found: $LIVE_CONF"

for target in \
  "host.docker.internal:3000" \
  "host.docker.internal:8080" \
  "host.docker.internal:9117" \
  "host.docker.internal:7878" \
  "host.docker.internal:8989" \
  "host.docker.internal:6767" \
  "host.docker.internal:3579" \
  "host.docker.internal:9000"
do
  grep -q "$target" "$LIVE_CONF" || fail "Missing upstream in live conf: $target"
done
log "OK: live conf uses host.docker.internal for media app upstreams"

log "Checking disk-usage host port mapping"
PORT_OUTPUT="$("${COMPOSE[@]}" port disk-usage 3000 2>/dev/null || true)"
[ -n "$PORT_OUTPUT" ] || fail "disk-usage does not expose port 3000"
printf '%s\n' "$PORT_OUTPUT" | grep -Eq '(:|^)3000$' || fail "Unexpected disk-usage port mapping: $PORT_OUTPUT"
log "OK: disk-usage port mapping is $PORT_OUTPUT"

log "Checking nginx can reach disk-usage via host.docker.internal"
"${COMPOSE[@]}" exec -T nginx sh -lc 'wget -qO- http://host.docker.internal:3000/disk >/tmp/disk.json && test -s /tmp/disk.json'
log "OK: nginx can reach host.docker.internal:3000/disk"

log "Validating nginx syntax"
"${COMPOSE[@]}" exec -T nginx nginx -t >/dev/null
log "OK: nginx -t passed"

log "Checking loaded nginx config references host.docker.internal"
"${COMPOSE[@]}" exec -T nginx nginx -T 2>/dev/null | grep -q "host.docker.internal" || fail "Loaded nginx config does not contain host.docker.internal upstreams"
log "OK: loaded nginx config includes host.docker.internal upstreams"

log "Running end-to-end HTTP checks through nginx"
curl -fsS http://localhost/api/disk >/dev/null || fail "GET /api/disk failed"
curl -fsSI http://localhost/radarr/ >/dev/null || fail "HEAD /radarr/ failed"
curl -fsSI http://localhost/ombi/ >/dev/null || fail "HEAD /ombi/ failed"
log "OK: nginx endpoint checks passed"

log "Verification complete"
