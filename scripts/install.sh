#!/usr/bin/env bash
set -euo pipefail

RECREATE_MEDIA_CONFIG=0

log() {
  printf '%s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: ./scripts/install.sh [--recreate-media-config]

Options:
  --recreate-media-config   Force-copy nginx/conf.d/media-server.conf from templates.
  -h, --help                Show this help.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --recreate-media-config)
      RECREATE_MEDIA_CONFIG=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "ERROR: Unknown argument: $arg"
      usage
      exit 1
      ;;
  esac
done

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

CERT_DIR="$CONFIG_ROOT/nginx/certs"
CERT_FILE="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/privkey.pem"
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  log "TLS cert files not found. Generating self-signed cert for nginx."
  command -v openssl >/dev/null 2>&1 || {
    log "ERROR: openssl is required to generate TLS certs."
    log "Provide certs manually at:"
    log "  $CERT_FILE"
    log "  $KEY_FILE"
    exit 1
  }
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=localhost" \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" >/dev/null 2>&1
  log "Generated self-signed TLS certs in $CERT_DIR"
fi

log "Ensuring media subfolders exist"
mkdir -p "$MOVIES_DIR" "$TV_DIR" "$DOWNLOADS_DIR"

TEMPLATE_ROOT="$REPO_ROOT/configs/_templates"
if [ -d "$TEMPLATE_ROOT" ]; then
  mkdir -p "$CONFIG_ROOT/nginx/conf.d"

  if [ -d "$CONFIG_ROOT/nginx/conf.d" ] && [ -z "$(ls -A "$CONFIG_ROOT/nginx/conf.d" 2>/dev/null)" ]; then
    log "Copying nginx template configs"
    cp -a "$TEMPLATE_ROOT/nginx/conf.d/." "$CONFIG_ROOT/nginx/conf.d/"
  else
    log "Skipping nginx template copy (target not empty)"
  fi

  if [ "$RECREATE_MEDIA_CONFIG" -eq 1 ]; then
    log "Recreating nginx media config (media-server.conf)"
    cp -f "$TEMPLATE_ROOT/nginx/conf.d/media-server.conf" \
      "$CONFIG_ROOT/nginx/conf.d/media-server.conf"
  fi

  log "Copying nginx template html"
  mkdir -p "$CONFIG_ROOT/nginx/html"
  cp -a "$TEMPLATE_ROOT/nginx/html/." "$CONFIG_ROOT/nginx/html/"
fi

log "Starting containers"
cd "$REPO_ROOT"
docker compose up -d

log "Done"
