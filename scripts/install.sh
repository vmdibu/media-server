#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

log "Running preflight checks"
"$REPO_ROOT/scripts/preflight.sh"

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
  "$CONFIG_ROOT/nginx/html" \
  "$CONFIG_ROOT/ombi" \
  "$CONFIG_ROOT/plex" \
  "$CONFIG_ROOT/portainer" \
  "$CONFIG_ROOT/qBittorrent" \
  "$CONFIG_ROOT/radarr" \
  "$CONFIG_ROOT/sonarr"

if [ -d "$CONFIG_ROOT/nginx/certs" ] && [ -z "$(ls -A "$CONFIG_ROOT/nginx/certs" 2>/dev/null)" ]; then
  log "INFO: $CONFIG_ROOT/nginx/certs is empty. HTTPS is optional; see README."
fi

log "Ensuring media subfolders exist"
mkdir -p "$MOVIES_DIR" "$TV_DIR" "$DOWNLOADS_DIR"

TEMPLATE_ROOT="$REPO_ROOT/configs/_templates"
if [ -d "$TEMPLATE_ROOT" ]; then
  if [ -d "$CONFIG_ROOT/nginx/conf.d" ] && [ -z "$(ls -A "$CONFIG_ROOT/nginx/conf.d" 2>/dev/null)" ]; then
    log "Copying nginx template configs"
    mkdir -p "$CONFIG_ROOT/nginx/conf.d"
    cp -a "$TEMPLATE_ROOT/nginx/conf.d/." "$CONFIG_ROOT/nginx/conf.d/"
  else
    log "Skipping nginx template copy (target not empty)"
  fi

  if [ -d "$CONFIG_ROOT/nginx/html" ] && [ -z "$(ls -A "$CONFIG_ROOT/nginx/html" 2>/dev/null)" ]; then
    log "Copying nginx template html"
    mkdir -p "$CONFIG_ROOT/nginx/html"
    cp -a "$TEMPLATE_ROOT/nginx/html/." "$CONFIG_ROOT/nginx/html/"
  else
    log "Skipping nginx html template copy (target not empty)"
  fi
fi

log "Starting containers"
cd "$REPO_ROOT"
docker compose up -d

log "Done"
