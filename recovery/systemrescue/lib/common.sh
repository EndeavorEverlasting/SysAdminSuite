#!/usr/bin/env bash
# Shared guards, identity checks, and destination binding.

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
require_root() { [ "$(id -u)" -eq 0 ] || die "run as root in SystemRescue"; }
require_block() { [ -b "$1" ] || die "not a block device: $1"; }
require_file() { [ -f "$1" ] || die "required file missing: $1"; }
require_dir() { [ -d "$1" ] || die "required directory missing: $1"; }
require_basename() { [ -n "$1" ] && [ "${1##*/}" = "$1" ] && [ "$1" != "." ] && [ "$1" != ".." ] || die "expected a filename without path separators: $1"; }
shell_quote() { printf '%q' "$1"; }
canonical_path() { readlink -f -- "$1"; }
require_absolute_no_symlink_components() {
  local path=$1 current='' part
  local -a parts=()
  [[ "$path" = /* ]] || die "absolute path required: $path"
  case "/$path/" in *'/../'*|*'/./'*) die "dot path components rejected: $path";; esac
  IFS='/' read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || continue
    current="$current/$part"
    [ ! -L "$current" ] || die "symlink path component rejected: $current"
  done
}
require_ro_block() { [ "$(blockdev --getro "$1")" = "1" ] || die "block device is not read-only: $1"; }
require_mount_option() {
  local target=$1 option=$2 opts
  opts=$(findmnt -n -o OPTIONS --target "$target" 2>/dev/null || true)
  case ",$opts," in *",$option,"*) return 0;; esac
  die "mount $target does not include option $option (actual: ${opts:-unmounted})"
}
exact_mount_source() {
  findmnt -ern -o SOURCE --mountpoint "$1" 2>/dev/null || true
}
require_destination_binding() {
  local partition=$1 mountpoint=$2 path=$3
  require_block "$partition"
  require_dir "$mountpoint"
  local mounted_source mounted_target path_target partition_real source_real mount_real target_real
  mounted_source=$(exact_mount_source "$mountpoint")
  [ -n "$mounted_source" ] || die "destination mount is not an exact mountpoint: $mountpoint"
  partition_real=$(canonical_path "$partition")
  source_real=$(canonical_path "$mounted_source")
  [ "$source_real" = "$partition_real" ] || die "destination mount source mismatch: expected $partition_real, got $source_real"
  require_mount_option "$mountpoint" rw
  mounted_target=$(findmnt -rn -o TARGET --mountpoint "$mountpoint")
  path_target=$(findmnt -rn -o TARGET --target "$path" 2>/dev/null || true)
  [ -n "$path_target" ] || die "path is not on a mounted filesystem: $path"
  mount_real=$(canonical_path "$mounted_target")
  target_real=$(canonical_path "$path_target")
  [ "$target_real" = "$mount_real" ] || die "path is not bound to destination mount $mount_real: $path resolves on $target_real"
}
require_source_not_mounted() {
  local source=$1
  if lsblk -nrpo MOUNTPOINTS "$source" | grep -q '[^[:space:]]'; then
    die "source or a child partition is mounted: $source"
  fi
}
assert_safe_path() {
  local path=$1
  [ -n "$path" ] || die "empty path rejected"
  case "$path" in /|/mnt|/tmp|/run|/dev|/sys|/proc) die "unsafe path rejected: $path";; esac
}
cmd_inventory() {
  need lsblk
  log "whole-device inventory"
  lsblk -dpno NAME,SIZE,MODEL,SERIAL,TRAN
  printf '\n'
  log "partition and mount inventory"
  lsblk -rpno NAME,SIZE,FSTYPE,LABEL,TYPE,RO,MOUNTPOINTS
}
cmd_protect_source() {
  require_root; need blockdev; need lsblk
  local source='' expect_model='' expect_serial=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --source) source=${2:-}; shift 2;;
      --expect-model) expect_model=${2:-}; shift 2;;
      --expect-serial) expect_serial=${2:-}; shift 2;;
      *) die "unknown protect-source argument: $1";;
    esac
  done
  [ -n "$source" ] || die "--source is required"
  require_block "$source"
  require_source_not_mounted "$source"
  local model serial
  model=$(lsblk -dn -o MODEL "$source" | sed 's/[[:space:]]*$//')
  serial=$(lsblk -dn -o SERIAL "$source" | sed 's/[[:space:]]*$//')
  [ -z "$expect_model" ] || [ "$model" = "$expect_model" ] || die "model mismatch: expected '$expect_model', got '$model'"
  [ -z "$expect_serial" ] || [ "$serial" = "$expect_serial" ] || die "serial mismatch: expected '$expect_serial', got '$serial'"
  blockdev --setro "$source"
  require_ro_block "$source"
  log "source protected read-only: $source model='$model' serial='$serial'"
  lsblk -rpn -o NAME,SIZE,FSTYPE,LABEL,TYPE,RO,MOUNTPOINTS "$source"
}
cmd_mount_destination() {
  require_root; need mount; need findmnt; need lsblk
  local partition='' mountpoint='' expect_label=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --partition) partition=${2:-}; shift 2;;
      --mount) mountpoint=${2:-}; shift 2;;
      --expect-label) expect_label=${2:-}; shift 2;;
      *) die "unknown mount-destination argument: $1";;
    esac
  done
  [ -n "$partition" ] || die "--partition is required"
  [ -n "$mountpoint" ] || die "--mount is required"
  require_block "$partition"; assert_safe_path "$mountpoint"
  local fstype label
  fstype=$(lsblk -dn -o FSTYPE "$partition" | tr -d '[:space:]')
  label=$(lsblk -dn -o LABEL "$partition" | sed 's/[[:space:]]*$//')
  [ "$fstype" = "exfat" ] || die "destination must be exFAT; got '${fstype:-unknown}'"
  [ -z "$expect_label" ] || [ "$label" = "$expect_label" ] || die "destination label mismatch: expected '$expect_label', got '$label'"
  mkdir -p "$mountpoint"
  local mounted_source
  mounted_source=$(exact_mount_source "$mountpoint")
  if [ -n "$mounted_source" ]; then
    [ "$(canonical_path "$mounted_source")" = "$(canonical_path "$partition")" ] || die "$mountpoint already mounted from $mounted_source"
  else
    mount -t exfat -o rw "$partition" "$mountpoint"
  fi
  require_destination_binding "$partition" "$mountpoint" "$mountpoint"
  log "destination mounted read-write: $partition -> $mountpoint"
  findmnt "$mountpoint"
  df -h "$mountpoint"
}
