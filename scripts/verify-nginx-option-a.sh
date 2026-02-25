#!/usr/bin/env bash
set -euo pipefail

if [ -t 1 ]; then
  GREEN="$(printf '\033[32m')"
  RED="$(printf '\033[31m')"
  CYAN="$(printf '\033[36m')"
  DIM="$(printf '\033[2m')"
  RESET="$(printf '\033[0m')"
else
  GREEN=""
  RED=""
  CYAN=""
  DIM=""
  RESET=""
fi

step() { printf '\n%s[%s]%s %s\n' "$CYAN" "STEP" "$RESET" "$*"; }
pass() { printf '%s✔%s %s\n' "$GREEN" "$RESET" "$*"; }
info() { printf '%s•%s %s\n' "$DIM" "$RESET" "$*"; }

fail() {
  printf '%s✘%s %s\n' "$RED" "$RESET" "$*" >&2
  exit 1
}

check_http_code() {
  local url="$1"
  local allowed_csv="$2"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$url" || true)"
  case ",$allowed_csv," in
    *",$code,"*) return 0 ;;
  esac
  fail "GET $url returned $code (allowed: $allowed_csv)"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
CONF_BASENAME="media-server.conf"

step "Checking prerequisites"
[ -f "$ENV_FILE" ] || fail "Missing .env at $ENV_FILE"
command -v docker >/dev/null 2>&1 || fail "docker is not installed or not in PATH"
command -v grep >/dev/null 2>&1 || fail "grep is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"
pass "Prerequisites found"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

[ -n "${CONFIG_ROOT:-}" ] || fail "CONFIG_ROOT is not set in .env"
pass "Loaded .env (CONFIG_ROOT=$CONFIG_ROOT)"

COMPOSE=(docker compose --project-directory "$ROOT_DIR" -f "$ROOT_DIR/compose.yml")
LIVE_CONF="$CONFIG_ROOT/nginx/conf.d/$CONF_BASENAME"

step "Checking live nginx config file"
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
pass "Live conf uses host.docker.internal for media app upstreams"

step "Checking disk-usage host port mapping"
PORT_OUTPUT="$("${COMPOSE[@]}" port disk-usage 3000 2>/dev/null || true)"
[ -n "$PORT_OUTPUT" ] || fail "disk-usage does not expose port 3000"
printf '%s\n' "$PORT_OUTPUT" | grep -Eq '(:|^)3000$' || fail "Unexpected disk-usage port mapping: $PORT_OUTPUT"
pass "disk-usage port mapping is $PORT_OUTPUT"

step "Checking nginx can reach disk-usage via host.docker.internal"
"${COMPOSE[@]}" exec -T nginx sh -lc 'wget -qO- http://host.docker.internal:3000/disk >/tmp/disk.json && test -s /tmp/disk.json'
pass "nginx can reach host.docker.internal:3000/disk"

step "Validating nginx syntax"
"${COMPOSE[@]}" exec -T nginx nginx -t >/dev/null
pass "nginx -t passed"

step "Checking loaded nginx config references host.docker.internal"
"${COMPOSE[@]}" exec -T nginx nginx -T 2>/dev/null | grep -q "host.docker.internal" || fail "Loaded nginx config does not contain host.docker.internal upstreams"
pass "Loaded nginx config includes host.docker.internal upstreams"

step "Running end-to-end HTTP checks through nginx"
curl -fsS http://localhost/api/disk >/dev/null || fail "GET /api/disk failed"
check_http_code "http://localhost/radarr/" "200,301,302,307,308,401,403"
check_http_code "http://localhost/ombi/" "200,301,302,307,308,401,403"
pass "nginx endpoint checks passed"

info "Verification complete"
