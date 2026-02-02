#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  SUDO="sudo"
fi

default_mount="/mnt/plexdrive/NetworkDrive"
default_src=""
default_fs_type="ext4"
default_options="defaults,nofail"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  if [ -n "${MEDIA_ROOT:-}" ]; then
    default_mount="$MEDIA_ROOT"
  fi
fi

if command -v findmnt >/dev/null 2>&1; then
  mount_source="$(findmnt -n -o SOURCE "$default_mount" 2>/dev/null || true)"
  mount_fstype="$(findmnt -n -o FSTYPE "$default_mount" 2>/dev/null || true)"
  mount_options="$(findmnt -n -o OPTIONS "$default_mount" 2>/dev/null || true)"
  if [ -n "$mount_fstype" ]; then
    default_fs_type="$mount_fstype"
  fi
  if [ -n "$mount_options" ]; then
    default_options="$mount_options"
  fi
  if [ -n "$mount_source" ]; then
    if command -v blkid >/dev/null 2>&1; then
      uuid_value="$($SUDO blkid -s UUID -o value "$mount_source" 2>/dev/null || true)"
      if [ -n "$uuid_value" ]; then
        default_src="UUID=$uuid_value"
      else
        default_src="$mount_source"
      fi
    else
      default_src="$mount_source"
    fi
  fi
fi

log "Available disks (lsblk -f):"
if command -v lsblk >/dev/null 2>&1; then
  lsblk -f
else
  log "lsblk not found."
fi

log ""
log "Available UUIDs (blkid):"
if command -v blkid >/dev/null 2>&1; then
  $SUDO blkid || true
else
  log "blkid not found."
fi

log ""
read -r -p "Mountpoint [$default_mount]: " mountpoint
mountpoint="${mountpoint:-$default_mount}"
if [ -z "$mountpoint" ]; then
  fail "Mountpoint is required."
fi

read -r -p "Device path or UUID (e.g. /dev/sdb1 or UUID=xxxx)${default_src:+ [$default_src]}: " src
src="${src:-$default_src}"
if [ -z "$src" ]; then
  fail "Device or UUID is required."
fi

if [[ "$src" =~ ^[A-Fa-f0-9-]+$ ]]; then
  src="UUID=$src"
fi

read -r -p "Filesystem type [$default_fs_type]: " fs_type
fs_type="${fs_type:-$default_fs_type}"

read -r -p "Mount options [$default_options]: " options
options="${options:-$default_options}"

log ""
log "Creating mountpoint: $mountpoint"
$SUDO mkdir -p "$mountpoint"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_path="/etc/fstab.bak.$timestamp"
log "Backing up /etc/fstab to $backup_path"
$SUDO cp -a /etc/fstab "$backup_path"

existing_lines="$($SUDO grep -nE "^[^#].*[[:space:]]$mountpoint[[:space:]]" /etc/fstab || true)"
if [ -n "$existing_lines" ]; then
  log "Existing fstab entries for $mountpoint:"
  log "$existing_lines"
  read -r -p "Replace existing entries? [y/N]: " replace
  if [ "$replace" = "y" ] || [ "$replace" = "Y" ]; then
    $SUDO sed -i "\|[[:space:]]$mountpoint[[:space:]]|d" /etc/fstab
  else
    fail "Aborted. No changes made."
  fi
fi

line="$src $mountpoint $fs_type $options 0 2"
log "Adding to /etc/fstab:"
log "  $line"
printf '%s\n' "$line" | $SUDO tee -a /etc/fstab >/dev/null

log "Mounting all entries..."
$SUDO mount -a

log "Verifying mount:"
if command -v findmnt >/dev/null 2>&1; then
  findmnt "$mountpoint"
else
  mount | grep -F " $mountpoint " || true
fi

log "Done."
