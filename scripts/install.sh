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
CERT_HOST="mediabox.home.arpa"
CA_CERT_FILE="$CERT_DIR/local-ca.crt"
CA_KEY_FILE="$CERT_DIR/local-ca.key"
LEAF_CERT_FILE="$CERT_DIR/server.crt"
LEAF_CSR_FILE="$CERT_DIR/server.csr"
needs_new_cert=false
needs_new_ca=false
manage_local_ca=false

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  needs_new_cert=true
  manage_local_ca=true
  log "TLS cert files not found. Generating local-CA-signed cert for nginx."
fi

if [ ! -f "$CA_CERT_FILE" ] || [ ! -f "$CA_KEY_FILE" ]; then
  if [ "$manage_local_ca" = "true" ]; then
    needs_new_ca=true
    needs_new_cert=true
    log "Local CA files not found. Generating local CA and server cert for nginx."
  fi
elif command -v openssl >/dev/null 2>&1; then
  cert_issuer="$(openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null | sed 's/^issuer= *//')"
  ca_subject="$(openssl x509 -in "$CA_CERT_FILE" -noout -subject 2>/dev/null | sed 's/^subject= *//')"

  if [ -n "$cert_issuer" ] && [ -n "$ca_subject" ] && [ "$cert_issuer" = "$ca_subject" ]; then
    manage_local_ca=true
    if ! openssl x509 -in "$CERT_FILE" -noout -ext subjectAltName 2>/dev/null | grep -Fq "DNS:$CERT_HOST"; then
      needs_new_cert=true
      log "Local-CA cert does not include $CERT_HOST SAN. Regenerating server cert."
    fi
  else
    log "Detected custom TLS cert/key. Preserving existing files."
  fi
fi

if [ "$needs_new_ca" = "true" ] || [ "$needs_new_cert" = "true" ]; then
  command -v openssl >/dev/null 2>&1 || {
    log "ERROR: openssl is required to generate TLS certs."
    log "Provide certs manually at:"
    log "  $CERT_FILE"
    log "  $KEY_FILE"
    exit 1
  }
fi

if [ "$needs_new_ca" = "true" ]; then
  openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -subj "/CN=MediaBox Local Root CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash" \
    -keyout "$CA_KEY_FILE" \
    -out "$CA_CERT_FILE" >/dev/null 2>&1
  chmod 600 "$CA_KEY_FILE"
  log "Generated local CA cert: $CA_CERT_FILE"
fi

if [ "$needs_new_cert" = "true" ]; then
  CERT_CONF="$(mktemp)"
  cat >"$CERT_CONF" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $CERT_HOST

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CERT_HOST
DNS.2 = localhost
EOF

  openssl req -new -nodes -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$LEAF_CSR_FILE" \
    -config "$CERT_CONF" >/dev/null 2>&1
  chmod 600 "$KEY_FILE"

  openssl x509 -req -days 825 -sha256 \
    -in "$LEAF_CSR_FILE" \
    -CA "$CA_CERT_FILE" \
    -CAkey "$CA_KEY_FILE" \
    -CAcreateserial \
    -out "$LEAF_CERT_FILE" \
    -extfile "$CERT_CONF" \
    -extensions v3_req >/dev/null 2>&1

  cat "$LEAF_CERT_FILE" "$CA_CERT_FILE" > "$CERT_FILE"

  rm -f "$CERT_CONF"
  rm -f "$LEAF_CSR_FILE"
  log "Generated local-CA-signed TLS certs for $CERT_HOST in $CERT_DIR"
  log "Import CA into browsers/devices for trust: $CA_CERT_FILE"
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

log "Restarting nginx to apply updated config/certs from bind mounts"
docker compose restart nginx

log "Done"
