#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM="sas-recovery"
VERSION="0.1.0"
QR_LIMIT_DEFAULT=240

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

usage() {
  cat <<'USAGE'
SysAdminSuite SystemRescue recovery harness

Usage:
  sas-recovery.sh inventory
  sas-recovery.sh protect-source --source DEV [--expect-model TEXT] [--expect-serial TEXT]
  sas-recovery.sh mount-destination --partition DEV --mount DIR [--expect-label LABEL]
  sas-recovery.sh verify-workdir --workdir DIR --image NAME --map NAME
  sas-recovery.sh start-image --source DEV --workdir DIR --image NAME --map NAME --confirm-new-image
  sas-recovery.sh resume-image --source DEV --workdir DIR --image NAME --map NAME
  sas-recovery.sh image-status --workdir DIR --image NAME --map NAME
  sas-recovery.sh capture-checkpoint --workdir DIR --map NAME --tag TEXT
  sas-recovery.sh attach-image --image FILE --state-file FILE
  sas-recovery.sh open-bitlocker --partition DEV --name NAME
  sas-recovery.sh mount-ntfs --mapper DEV --mount DIR
  sas-recovery.sh audit-user-data --source-root DIR --report FILE [--include-appdata]
  sas-recovery.sh copy-user-data --source-root DIR --destination-root DIR --log FILE [--include-appdata]
  sas-recovery.sh cleanup --mount DIR --mapper-name NAME --loop-state-file FILE --image FILE
  sas-recovery.sh qr-catalog --repo-mount DIR [--max-chars N]

Safety contract:
  * Never repairs or mounts the failing source read-write.
  * Resumes only with an existing image and mapfile.
  * Image, BitLocker mapper, and NTFS filesystem are attached read-only.
  * User-data copy writes only to the explicit destination root.
USAGE
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
  if findmnt -rn --target "$mountpoint" >/dev/null 2>&1; then
    local mounted_source
    mounted_source=$(findmnt -n -o SOURCE --target "$mountpoint")
    [ "$mounted_source" = "$partition" ] || die "$mountpoint already mounted from $mounted_source"
  else
    mount -t exfat -o rw "$partition" "$mountpoint"
  fi
  require_mount_option "$mountpoint" rw
  log "destination mounted read-write: $partition -> $mountpoint"
  findmnt "$mountpoint"
  df -h "$mountpoint"
}

cmd_verify_workdir() {
  local workdir='' image='' map=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --workdir) workdir=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      *) die "unknown verify-workdir argument: $1";;
    esac
  done
  [ -n "$workdir" ] && [ -n "$image" ] && [ -n "$map" ] || die "--workdir, --image, and --map are required"
  require_basename "$image"; require_basename "$map"
  require_dir "$workdir"; require_file "$workdir/$image"; require_file "$workdir/$map"
  log "existing recovery artifacts verified"
  ls -lh -- "$workdir/$image" "$workdir/$map"
  if command -v ddrescuelog >/dev/null 2>&1; then ddrescuelog -t "$workdir/$map"; fi
}

cmd_start_image() {
  require_root; need ddrescue; need blockdev; need findmnt; need df
  local source='' workdir='' image='' map='' confirm=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --source) source=${2:-}; shift 2;;
      --workdir) workdir=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      --confirm-new-image) confirm=1; shift;;
      *) die "unknown start-image argument: $1";;
    esac
  done
  [ -n "$source" ] && [ -n "$workdir" ] && [ -n "$image" ] && [ -n "$map" ] || die "--source, --workdir, --image, and --map are required"
  require_basename "$image"; require_basename "$map"
  [ "$confirm" -eq 1 ] || die "new imaging requires --confirm-new-image"
  require_block "$source"; require_ro_block "$source"; require_source_not_mounted "$source"
  assert_safe_path "$workdir"; mkdir -p "$workdir"; require_mount_option "$workdir" rw
  [ ! -e "$workdir/$image" ] || die "image already exists; use resume-image: $workdir/$image"
  [ ! -e "$workdir/$map" ] || die "mapfile already exists; use resume-image: $workdir/$map"
  local source_bytes available_bytes
  source_bytes=$(blockdev --getsize64 "$source")
  available_bytes=$(df -B1 --output=avail "$workdir" | tail -n 1 | tr -d '[:space:]')
  [ "$available_bytes" -ge "$source_bytes" ] || die "insufficient destination space: need $source_bytes bytes, have $available_bytes"
  log "starting new ddrescue image"
  log "source=$source image=$workdir/$image map=$workdir/$map"
  ddrescue --no-scrape --verbose "$source" "$workdir/$image" "$workdir/$map"
}

cmd_resume_image() {
  require_root; need ddrescue; need blockdev; need findmnt
  local source='' workdir='' image='' map=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --source) source=${2:-}; shift 2;;
      --workdir) workdir=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      *) die "unknown resume-image argument: $1";;
    esac
  done
  [ -n "$source" ] && [ -n "$workdir" ] && [ -n "$image" ] && [ -n "$map" ] || die "--source, --workdir, --image, and --map are required"
  require_basename "$image"; require_basename "$map"
  require_block "$source"; require_ro_block "$source"; require_source_not_mounted "$source"
  require_dir "$workdir"; require_file "$workdir/$image"; require_file "$workdir/$map"
  require_mount_option "$workdir" rw
  log "resuming ddrescue with existing image and mapfile"
  log "source=$source image=$workdir/$image map=$workdir/$map"
  ddrescue --no-scrape --verbose "$source" "$workdir/$image" "$workdir/$map"
}

cmd_image_status() {
  need ddrescuelog
  local workdir='' image='' map=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --workdir) workdir=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      *) die "unknown image-status argument: $1";;
    esac
  done
  [ -n "$workdir" ] && [ -n "$image" ] && [ -n "$map" ] || die "--workdir, --image, and --map are required"
  require_basename "$image"; require_basename "$map"
  require_file "$workdir/$image"; require_file "$workdir/$map"
  ls -lh -- "$workdir/$image" "$workdir/$map"
  ddrescuelog -t "$workdir/$map"
}

cmd_capture_checkpoint() {
  need dmesg; need ddrescuelog
  local workdir='' map='' tag=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --workdir) workdir=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      --tag) tag=${2:-}; shift 2;;
      *) die "unknown capture-checkpoint argument: $1";;
    esac
  done
  [ -n "$workdir" ] && [ -n "$map" ] && [ -n "$tag" ] || die "--workdir, --map, and --tag are required"
  require_basename "$map"
  require_dir "$workdir"; require_file "$workdir/$map"; require_mount_option "$workdir" rw
  [[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || die "unsafe checkpoint tag: $tag"
  dmesg > "$workdir/dmesg-$tag.txt"
  ddrescuelog -t "$workdir/$map" > "$workdir/ddrescuelog-$tag.txt"
  ls -lah "$workdir" > "$workdir/artifacts-$tag.txt"
  sync
  log "checkpoint captured and synced: $tag"
  ls -lh -- "$workdir/dmesg-$tag.txt" "$workdir/ddrescuelog-$tag.txt" "$workdir/artifacts-$tag.txt"
}

cmd_attach_image() {
  require_root; need losetup; need lsblk; need readlink
  local image='' state_file=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --image) image=${2:-}; shift 2;;
      --state-file) state_file=${2:-}; shift 2;;
      *) die "unknown attach-image argument: $1";;
    esac
  done
  [ -n "$image" ] && [ -n "$state_file" ] || die "--image and --state-file are required"
  require_file "$image"; assert_safe_path "$state_file"
  local state_parent image_real loopdev
  state_parent=$(dirname "$state_file")
  require_absolute_no_symlink_components "$state_parent"
  require_dir "$state_parent"; require_mount_option "$state_parent" rw
  [ ! -e "$state_file" ] && [ ! -L "$state_file" ] || die "state file already exists or is a symlink: $state_file"
  image_real=$(canonical_path "$image")
  case "$image_real" in *$'\n'*) die "newline in image path is unsupported";; esac
  loopdev=$(losetup --find --show --read-only --partscan "$image_real")
  [ "$(blockdev --getro "$loopdev")" = "1" ] || { losetup -d "$loopdev"; die "loop device did not become read-only"; }
  if ! (umask 077; set -o noclobber; printf 'LOOP=%s\nIMAGE=%s\n' "$loopdev" "$image_real" > "$state_file") 2>/dev/null; then
    losetup -d "$loopdev"
    die "could not create state file atomically without clobbering: $state_file"
  fi
  [ -f "$state_file" ] && [ ! -L "$state_file" ] || { losetup -d "$loopdev"; die "state file validation failed: $state_file"; }
  log "image attached read-only: $image_real -> $loopdev"
  lsblk -rpn -o NAME,SIZE,FSTYPE,LABEL,TYPE,RO,MOUNTPOINTS "$loopdev"
}

cmd_open_bitlocker() {
  require_root; need cryptsetup; need blockdev
  local partition='' name=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --partition) partition=${2:-}; shift 2;;
      --name) name=${2:-}; shift 2;;
      *) die "unknown open-bitlocker argument: $1";;
    esac
  done
  [ -n "$partition" ] && [ -n "$name" ] || die "--partition and --name are required"
  require_block "$partition"; require_ro_block "$partition"
  [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || die "unsafe mapper name: $name"
  cryptsetup open --type bitlk --readonly "$partition" "$name"
  local status
  status=$(cryptsetup status "$name")
  printf '%s\n' "$status"
  grep -q 'mode:[[:space:]]*readonly' <<<"$status" || { cryptsetup close "$name" || true; die "BitLocker mapper is not read-only"; }
  log "BitLocker mapper opened read-only: /dev/mapper/$name"
}

cmd_mount_ntfs() {
  require_root; need mount; need findmnt
  local mapper='' mountpoint=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --mapper) mapper=${2:-}; shift 2;;
      --mount) mountpoint=${2:-}; shift 2;;
      *) die "unknown mount-ntfs argument: $1";;
    esac
  done
  [ -n "$mapper" ] && [ -n "$mountpoint" ] || die "--mapper and --mount are required"
  require_block "$mapper"; require_ro_block "$mapper"; assert_safe_path "$mountpoint"
  mkdir -p "$mountpoint"
  mount -t ntfs-3g -o ro "$mapper" "$mountpoint"
  require_mount_option "$mountpoint" ro
  log "NTFS mounted read-only: $mapper -> $mountpoint"
  findmnt "$mountpoint"
}

is_system_profile() {
  case "$1" in 'All Users'|'Default'|'Default User'|'desktop.ini') return 0;; *) return 1;; esac
}

build_rsync_excludes() {
  local include_appdata=$1
  printf '%s\n' '--exclude=/NTUSER.DAT*' '--exclude=/ntuser.dat*' '--exclude=/Application Data' '--exclude=/Cookies' '--exclude=/Local Settings' '--exclude=/My Documents' '--exclude=/NetHood' '--exclude=/PrintHood' '--exclude=/Recent' '--exclude=/SendTo' '--exclude=/Start Menu' '--exclude=/Templates'
  [ "$include_appdata" = "1" ] || printf '%s\n' '--exclude=/AppData/***'
}

cmd_audit_user_data() {
  need find; need du
  local source_root='' report='' include_appdata=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-root) source_root=${2:-}; shift 2;;
      --report) report=${2:-}; shift 2;;
      --include-appdata) include_appdata=1; shift;;
      *) die "unknown audit-user-data argument: $1";;
    esac
  done
  [ -n "$source_root" ] && [ -n "$report" ] || die "--source-root and --report are required"
  require_dir "$source_root"; assert_safe_path "$report"
  require_mount_option "$source_root" ro
  mkdir -p "$(dirname "$report")"
  {
    printf 'AUDIT_STARTED=%s\nSOURCE_ROOT=%s\nINCLUDE_APPDATA=%s\n' "$(date -Is)" "$source_root" "$include_appdata"
    local profile name
    for profile in "$source_root"/*; do
      [ -d "$profile" ] || continue
      name=$(basename "$profile")
      is_system_profile "$name" && continue
      printf '\nPROFILE=%s\n' "$name"
      find "$profile" -xdev -mindepth 1 -maxdepth 1 -printf '%y\t%f\n' | sort
      printf 'PROFILE_BYTES=%s\n' "$(du -sb "$profile" 2>/dev/null | awk '{print $1}')"
    done
    printf '\nNONREGULAR_ENTRIES\n'
    find "$source_root" -xdev ! -type d ! -type f -printf '%y\t%p\t%l\n' 2>/dev/null || true
    printf 'AUDIT_FINISHED=%s\n' "$(date -Is)"
  } | tee "$report"
}

cmd_copy_user_data() {
  need rsync; need find; need findmnt; need du
  local source_root='' destination_root='' logfile='' include_appdata=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-root) source_root=${2:-}; shift 2;;
      --destination-root) destination_root=${2:-}; shift 2;;
      --log) logfile=${2:-}; shift 2;;
      --include-appdata) include_appdata=1; shift;;
      *) die "unknown copy-user-data argument: $1";;
    esac
  done
  [ -n "$source_root" ] && [ -n "$destination_root" ] && [ -n "$logfile" ] || die "--source-root, --destination-root, and --log are required"
  require_dir "$source_root"; require_mount_option "$source_root" ro
  assert_safe_path "$destination_root"; assert_safe_path "$logfile"
  mkdir -p "$destination_root" "$(dirname "$logfile")"
  require_mount_option "$destination_root" rw
  local -a excludes=()
  mapfile -t excludes < <(build_rsync_excludes "$include_appdata")
  : > "$logfile"
  log "copy start source=$source_root destination=$destination_root include_appdata=$include_appdata" | tee -a "$logfile"
  local profile name rc=0
  for profile in "$source_root"/*; do
    [ -d "$profile" ] || continue
    name=$(basename "$profile")
    is_system_profile "$name" && continue
    log "copy profile: $name" | tee -a "$logfile"
    mkdir -p "$destination_root/$name"
    set +e
    rsync -rlt --omit-dir-times --no-perms --no-owner --no-group --partial --ignore-errors --human-readable --info=progress2 --safe-links "${excludes[@]}" --log-file="$logfile" -- "$profile/" "$destination_root/$name/"
    local one_rc=$?
    set -e
    [ "$one_rc" -eq 0 ] || rc=$one_rc
  done
  sync
  local files bytes pending
  files=$(find "$destination_root" -type f | wc -l)
  bytes=$(du -sb "$destination_root" | awk '{print $1}')
  pending=0
  local verify_rc=0 verify_one=0 verify_count=0
  for profile in "$source_root"/*; do
    [ -d "$profile" ] || continue
    name=$(basename "$profile")
    is_system_profile "$name" && continue
    local verify_output
    verify_output=$(mktemp)
    set +e
    rsync -rltni --omit-dir-times --no-perms --no-owner --no-group --safe-links "${excludes[@]}" -- "$profile/" "$destination_root/$name/" >"$verify_output" 2>>"$logfile"
    verify_one=$?
    set -e
    verify_count=$(wc -l < "$verify_output")
    rm -f "$verify_output"
    pending=$((pending + verify_count))
    [ "$verify_one" -eq 0 ] || verify_rc=$verify_one
  done
  printf 'COPY_FINISHED=%s\nFILES=%s\nBYTES=%s\nPENDING_ITEMS=%s\nCOPY_RC=%s\nVERIFY_RC=%s\n' "$(date -Is)" "$files" "$bytes" "$pending" "$rc" "$verify_rc" | tee -a "$logfile"
  sync
  if [ "$rc" -eq 0 ] && [ "$verify_rc" -eq 0 ] && [ "$pending" -eq 0 ]; then
    printf 'RESULT: RECOVERED USER DATA COPY VERIFIED BY RSYNC DRY RUN\n'
  else
    printf 'RESULT: COPY COMPLETED WITH LOGGED ITEMS REQUIRING REVIEW\n'
    return 2
  fi
}

cmd_cleanup() {
  require_root; need findmnt; need cryptsetup; need losetup; need readlink
  local mountpoint='' mapper_name='' loop_state_file='' image=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --mount) mountpoint=${2:-}; shift 2;;
      --mapper-name) mapper_name=${2:-}; shift 2;;
      --loop-state-file) loop_state_file=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      *) die "unknown cleanup argument: $1";;
    esac
  done
  [ -n "$mountpoint" ] && [ -n "$mapper_name" ] && [ -n "$loop_state_file" ] && [ -n "$image" ] || die "--mount, --mapper-name, --loop-state-file, and --image are required"
  require_file "$image"; require_file "$loop_state_file"
  require_absolute_no_symlink_components "$(dirname "$loop_state_file")"
  [ ! -L "$loop_state_file" ] || die "loop state file must not be a symlink: $loop_state_file"
  local expected_image state_image loopdev backing_file
  expected_image=$(canonical_path "$image")
  loopdev=$(sed -n 's/^LOOP=//p' "$loop_state_file")
  state_image=$(sed -n 's/^IMAGE=//p' "$loop_state_file")
  [[ "$loopdev" =~ ^/dev/loop[0-9]+$ ]] || die "invalid loop device in state file: ${loopdev:-missing}"
  [ "$state_image" = "$expected_image" ] || die "state image mismatch: expected $expected_image, got ${state_image:-missing}"
  require_block "$loopdev"; require_ro_block "$loopdev"
  backing_file=$(losetup --noheadings --raw --output BACK-FILE "$loopdev" | sed 's/[[:space:]]*$//')
  backing_file=$(canonical_path "$backing_file")
  [ "$backing_file" = "$expected_image" ] || die "loop backing-file mismatch: expected $expected_image, got $backing_file"
  if findmnt -rn --target "$mountpoint" >/dev/null 2>&1; then
    local mounted_source
    mounted_source=$(findmnt -n -o SOURCE --target "$mountpoint")
    [ "$mounted_source" = "/dev/mapper/$mapper_name" ] || die "cleanup mount source mismatch: $mounted_source"
    umount "$mountpoint"
  fi
  if cryptsetup status "$mapper_name" >/dev/null 2>&1; then cryptsetup close "$mapper_name"; fi
  losetup -d "$loopdev"
  rm -f "$loop_state_file"
  log "read-only image stack cleaned up"
}

emit_qr() {
  local index=$1 command=$2 max=$3
  local length=${#command}
  [ "$length" -le "$max" ] || die "QR command $index is $length characters; limit is $max"
  printf 'QR_%s_CHARS=%s\n%s\n\n' "$index" "$length" "$command"
}

cmd_qr_catalog() {
  local repo_mount='' source='' expect_model='' expect_serial='' destination='' destination_label='' dest_mount='/mnt/expansion' workdir='' image='' map='' bitlocker_partition='' mode='resume' max=$QR_LIMIT_DEFAULT
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo-mount) repo_mount=${2:-}; shift 2;;
      --source) source=${2:-}; shift 2;;
      --expect-model) expect_model=${2:-}; shift 2;;
      --expect-serial) expect_serial=${2:-}; shift 2;;
      --destination) destination=${2:-}; shift 2;;
      --destination-label) destination_label=${2:-}; shift 2;;
      --destination-mount) dest_mount=${2:-}; shift 2;;
      --workdir) workdir=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      --bitlocker-partition-number) bitlocker_partition=${2:-}; shift 2;;
      --mode) mode=${2:-}; shift 2;;
      --max-chars) max=${2:-}; shift 2;;
      *) die "unknown qr-catalog argument: $1";;
    esac
  done
  [ -n "$repo_mount" ] && [ -n "$source" ] && [ -n "$expect_model" ] && [ -n "$expect_serial" ] && [ -n "$destination" ] && [ -n "$destination_label" ] && [ -n "$workdir" ] && [ -n "$image" ] && [ -n "$map" ] && [ -n "$bitlocker_partition" ] || die "qr-catalog requires confirmed source model/serial, destination label, paths, filenames, and BitLocker partition number"
  require_basename "$image"; require_basename "$map"
  [[ "$bitlocker_partition" =~ ^[1-9][0-9]*$ ]] || die "--bitlocker-partition-number must be a positive integer"
  case "$mode" in start|resume) ;; *) die "--mode must be start or resume";; esac
  [[ "$max" =~ ^[0-9]+$ ]] || die "--max-chars must be numeric"
  local runner="$repo_mount/recovery/systemrescue/sas-recovery.sh"
  local state
  state="export R=$(shell_quote "$runner") SRC=$(shell_quote "$source") MODEL=$(shell_quote "$expect_model") SERIAL=$(shell_quote "$expect_serial") DST=$(shell_quote "$destination") DL=$(shell_quote "$destination_label") M=$(shell_quote "$dest_mount") W=$(shell_quote "$workdir") IMG=$(shell_quote "$image") MAP=$(shell_quote "$map") BP=$(shell_quote "$bitlocker_partition")"
  emit_qr 1 "$state" "$max"
  emit_qr 2 'bash "$R" protect-source --source "$SRC" --expect-model "$MODEL" --expect-serial "$SERIAL"' "$max"
  emit_qr 3 'bash "$R" mount-destination --partition "$DST" --mount "$M" --expect-label "$DL"' "$max"
  if [ "$mode" = "start" ]; then
    emit_qr 4 'bash "$R" start-image --source "$SRC" --workdir "$W" --image "$IMG" --map "$MAP" --confirm-new-image' "$max"
  else
    emit_qr 4 'bash "$R" resume-image --source "$SRC" --workdir "$W" --image "$IMG" --map "$MAP"' "$max"
  fi
  emit_qr 5 'bash "$R" capture-checkpoint --workdir "$W" --map "$MAP" --tag post-image' "$max"
  emit_qr 6 'bash "$R" attach-image --image "$W/$IMG" --state-file "$W/loop.state"' "$max"
  emit_qr 7 'bash "$R" open-bitlocker --partition "$(sed -n s/^LOOP=//p "$W/loop.state")p$BP" --name sas_image_bitlk' "$max"
  emit_qr 8 'bash "$R" mount-ntfs --mapper /dev/mapper/sas_image_bitlk --mount /mnt/recovery-image' "$max"
  emit_qr 9 'bash "$R" audit-user-data --source-root /mnt/recovery-image/Users --report "$W/user-audit.txt"' "$max"
  emit_qr 10 'bash "$R" copy-user-data --source-root /mnt/recovery-image/Users --destination-root "$W/RECOVERED_USER_DATA" --log "$W/user-copy.log"' "$max"
}

main() {
  local command=${1:-help}
  [ $# -eq 0 ] || shift
  case "$command" in
    inventory) cmd_inventory "$@";;
    protect-source) cmd_protect_source "$@";;
    mount-destination) cmd_mount_destination "$@";;
    verify-workdir) cmd_verify_workdir "$@";;
    start-image) cmd_start_image "$@";;
    resume-image) cmd_resume_image "$@";;
    image-status) cmd_image_status "$@";;
    capture-checkpoint) cmd_capture_checkpoint "$@";;
    attach-image) cmd_attach_image "$@";;
    open-bitlocker) cmd_open_bitlocker "$@";;
    mount-ntfs) cmd_mount_ntfs "$@";;
    audit-user-data) cmd_audit_user_data "$@";;
    copy-user-data) cmd_copy_user_data "$@";;
    cleanup) cmd_cleanup "$@";;
    qr-catalog) cmd_qr_catalog "$@";;
    help|-h|--help) usage;;
    version|--version) printf '%s %s\n' "$PROGRAM" "$VERSION";;
    *) die "unknown command: $command";;
  esac
}

main "$@"
