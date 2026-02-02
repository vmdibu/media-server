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
is_mounted=false
if command -v findmnt >/dev/null 2>&1; then
  if findmnt -T "$MEDIA_ROOT" >/dev/null 2>&1; then
    is_mounted=true
  elif findmnt -M "$MEDIA_ROOT" >/dev/null 2>&1; then
    is_mounted=true
  fi
elif [ -r /proc/self/mountinfo ]; then
  if awk '{print $5}' /proc/self/mountinfo | grep -Fx "$MEDIA_ROOT" >/dev/null 2>&1; then
    is_mounted=true
  fi
else
  if mount | awk '{print $3}' | grep -Fx "$MEDIA_ROOT" >/dev/null 2>&1; then
    is_mounted=true
  fi
fi

if [ "$is_mounted" != "true" ]; then
  fail "MEDIA_ROOT does not appear to be a mountpoint (including bind mounts): $MEDIA_ROOT"
fi

log "Checking required ports"
required_ports=(80 443 7878 8989 6767 9117 8080 3579 9000)

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

project_ports=()
compose_ids=()
compose_args=(docker compose --project-directory "$ROOT_DIR" -f "$ROOT_DIR/compose.yml")

if "${compose_args[@]}" ps -q >/dev/null 2>&1; then
  mapfile -t compose_ids < <("${compose_args[@]}" ps -q 2>/dev/null)
fi

if [ "${#compose_ids[@]}" -gt 0 ]; then
  ports_raw="$(
    docker inspect -f '{{range $p,$conf := .NetworkSettings.Ports}}{{if $conf}}{{(index $conf 0).HostPort}}{{"\n"}}{{end}}{{end}}' \
      "${compose_ids[@]}" 2>/dev/null || true
  )"
  while IFS= read -r port; do
    if [ -n "$port" ]; then
      project_ports+=("$port")
    fi
  done <<< "$ports_raw"
fi

is_project_port() {
  local target="$1"
  for item in "${project_ports[@]}"; do
    if [ "$item" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

conflicts=()
conflict_details=()
in_use_ports=()

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
    in_use_ports+=("$port")
    if ! is_project_port "$port"; then
      conflicts+=("$port")
      conflict_details+=("Port $port is in use:\n$details")
    fi
  fi
done

if [ "${#conflicts[@]}" -gt 0 ]; then
  printf 'ERROR: Port conflicts found (not owned by this compose project): %s\n' "${conflicts[*]}" >&2
  for item in "${conflict_details[@]}"; do
    printf '%s\n' "$item" >&2
  done
  exit 1
fi

if [ "${#in_use_ports[@]}" -eq "${#required_ports[@]}" ] && [ "${#project_ports[@]}" -gt 0 ]; then
  printf 'WARN: All required ports are already bound by the current compose project. Continuing.\n' >&2
fi

log "Preflight OK"
log "CONFIG_ROOT=$CONFIG_ROOT"
log "MEDIA_ROOT=$MEDIA_ROOT"
log "MOVIES_DIR=$MOVIES_DIR"
