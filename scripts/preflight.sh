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

log "Checking .env"
if [ ! -f "$ENV_FILE" ]; then
  log "Missing .env in repo root."
  log "Create it with:"
  log "  cp .env.example .env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

log "Validating required variables"
required_vars=(
  TZ
  PUID
  PGID
  CONFIG_ROOT
  MEDIA_ROOT
  MOVIES_DIR
  TV_DIR
  DOWNLOADS_DIR
)

for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name:-}" ]; then
    fail "$var_name is not set in .env"
  fi
done

case "$PUID" in
  ''|*[!0-9]*) fail "PUID must be numeric";;
esac
case "$PGID" in
  ''|*[!0-9]*) fail "PGID must be numeric";;
esac

log "Checking Docker"
command -v docker >/dev/null 2>&1 || fail "docker is not installed or not in PATH"
docker ps >/dev/null 2>&1 || fail "docker is installed but not usable by this user (docker ps failed)"
docker compose version >/dev/null 2>&1 || fail "docker compose is not available"

log "Ensuring CONFIG_ROOT exists"
mkdir -p "$CONFIG_ROOT"

log "Ensuring media subfolders exist"
mkdir -p "$MOVIES_DIR" "$TV_DIR" "$DOWNLOADS_DIR"

log "Validating MEDIA_ROOT mount"
[ -d "$MEDIA_ROOT" ] || fail "MEDIA_ROOT does not exist: $MEDIA_ROOT"
if command -v findmnt >/dev/null 2>&1; then
  findmnt -T "$MEDIA_ROOT" >/dev/null 2>&1 || fail "MEDIA_ROOT is not a mounted filesystem: $MEDIA_ROOT"
else
  mount | awk '{print $3}' | grep -Fx "$MEDIA_ROOT" >/dev/null 2>&1 || \
    fail "MEDIA_ROOT is not a mounted filesystem: $MEDIA_ROOT"
fi

log "Checking required ports"
required_ports=(80 443 7878 8989 6767 9117 8080 3579 9000)

published_ports="$(
  docker ps --format '{{.Ports}}' | tr ',' '\n' | \
  sed -n 's/.*:\([0-9][0-9]*\)->.*/\1/p' | sort -u
)"

has_ss=false
has_netstat=false
if command -v ss >/dev/null 2>&1; then
  has_ss=true
elif command -v netstat >/dev/null 2>&1; then
  has_netstat=true
fi

if ! $has_ss && ! $has_netstat; then
  fail "Neither ss nor netstat is available to check ports"
fi

conflicts=()
conflict_details=()

for port in "${required_ports[@]}"; do
  in_use=false
  details=""
  if $has_ss; then
    if ss -ltnH "( sport = :$port )" | grep -q .; then
      in_use=true
      details="$(ss -ltnp "( sport = :$port )" | tail -n +2)"
    fi
  else
    if netstat -ltnp 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
      in_use=true
      details="$(netstat -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p {print}')"
    fi
  fi

  if $in_use; then
    if ! printf '%s\n' "$published_ports" | grep -qx "$port"; then
      conflicts+=("$port")
      conflict_details+=("Port $port is in use:\n$details")
    fi
  fi
done

if [ "${#conflicts[@]}" -gt 0 ]; then
  printf 'ERROR: Port conflicts found (non-Docker processes): %s\n' "${conflicts[*]}" >&2
  for item in "${conflict_details[@]}"; do
    printf '%s\n' "$item" >&2
  done
  exit 1
fi

log "Preflight OK"
log "CONFIG_ROOT=$CONFIG_ROOT"
log "MEDIA_ROOT=$MEDIA_ROOT"
log "MOVIES_DIR=$MOVIES_DIR"
log "TV_DIR=$TV_DIR"
log "DOWNLOADS_DIR=$DOWNLOADS_DIR"
