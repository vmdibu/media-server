#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$*"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

log "Running preflight checks"
"$ROOT_DIR/scripts/preflight.sh"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

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

log "Ensuring media subfolders exist"
mkdir -p "$MOVIES_DIR" "$TV_DIR" "$DOWNLOADS_DIR"

TEMPLATE_ROOT="$ROOT_DIR/configs/_templates"
if [ -d "$TEMPLATE_ROOT" ]; then
  if [ -d "$CONFIG_ROOT/nginx/conf.d" ] && [ -z "$(ls -A "$CONFIG_ROOT/nginx/conf.d" 2>/dev/null)" ]; then
    log "Copying nginx template configs"
    mkdir -p "$CONFIG_ROOT/nginx/conf.d"
    cp -a "$TEMPLATE_ROOT/nginx/conf.d/." "$CONFIG_ROOT/nginx/conf.d/"
  else
    log "Skipping nginx template copy (target not empty)"
  fi
fi

log "Starting containers"
cd "$ROOT_DIR"
docker compose up -d

log "Done"
