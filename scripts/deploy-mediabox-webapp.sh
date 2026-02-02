#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

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

TEMPLATE_ROOT="$REPO_ROOT/configs/_templates"
SRC_FILE="$TEMPLATE_ROOT/nginx/html/index.html"
DEST_DIR="$CONFIG_ROOT/nginx/html"
DEST_FILE="$DEST_DIR/index.html"

if [ ! -f "$SRC_FILE" ]; then
  log "Template not found: $SRC_FILE"
  exit 1
fi

mkdir -p "$DEST_DIR"
cp -a "$SRC_FILE" "$DEST_FILE"
log "Copied $SRC_FILE -> $DEST_FILE"
