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

log "Loading environment from .env"
[ -f "$ENV_FILE" ] || fail ".env not found at $ENV_FILE"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

log "Validating prerequisites"
command -v docker >/dev/null 2>&1 || fail "docker is not installed or not in PATH"
docker compose version >/dev/null 2>&1 || fail "docker compose is not available"

: "${CONFIG_ROOT:?CONFIG_ROOT is not set}"
: "${MEDIA_ROOT:?MEDIA_ROOT is not set}"
: "${MOVIES_DIR:?MOVIES_DIR is not set}"
: "${TV_DIR:?TV_DIR is not set}"
: "${DOWNLOADS_DIR:?DOWNLOADS_DIR is not set}"

log "Ensuring CONFIG_ROOT exists"
mkdir -p "$CONFIG_ROOT"

log "Ensuring CONFIG_ROOT subfolders exist"
mkdir -p \
  "$CONFIG_ROOT/bazarr" \
  "$CONFIG_ROOT/jackett" \
  "$CONFIG_ROOT/nginx/certs" \
  "$CONFIG_ROOT/nginx/conf.d" \
  "$CONFIG_ROOT/ombi" \
  "$CONFIG_ROOT/plex" \
  "$CONFIG_ROOT/portainer" \
  "$CONFIG_ROOT/qBittorrent" \
  "$CONFIG_ROOT/radarr" \
  "$CONFIG_ROOT/sonarr"

log "Validating MEDIA_ROOT mount"
[ -d "$MEDIA_ROOT" ] || fail "MEDIA_ROOT does not exist: $MEDIA_ROOT"
if [ -z "$(ls -A "$MEDIA_ROOT" 2>/dev/null)" ]; then
  fail "MEDIA_ROOT appears empty; ensure it is mounted: $MEDIA_ROOT"
fi

log "Ensuring media subfolders exist"
mkdir -p "$MOVIES_DIR" "$TV_DIR" "$DOWNLOADS_DIR"

log "Starting containers"
cd "$ROOT_DIR"
docker compose up -d

log "Done"
