#!/usr/bin/env bash
# GNU ddrescue, image attachment, BitLocker, NTFS, and cleanup commands.

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
  local source='' destination_partition='' destination_mount='' workdir='' image='' map='' confirm=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --source) source=${2:-}; shift 2;;
      --destination-partition) destination_partition=${2:-}; shift 2;;
      --destination-mount) destination_mount=${2:-}; shift 2;;
      --workdir) workdir=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      --confirm-new-image) confirm=1; shift;;
      *) die "unknown start-image argument: $1";;
    esac
  done
  [ -n "$source" ] && [ -n "$destination_partition" ] && [ -n "$destination_mount" ] && [ -n "$workdir" ] && [ -n "$image" ] && [ -n "$map" ] || die "--source, --destination-partition, --destination-mount, --workdir, --image, and --map are required"
  require_basename "$image"; require_basename "$map"
  [ "$confirm" -eq 1 ] || die "new imaging requires --confirm-new-image"
  require_block "$source"; require_ro_block "$source"; require_source_not_mounted "$source"
  assert_safe_path "$workdir"; mkdir -p "$workdir"; require_destination_binding "$destination_partition" "$destination_mount" "$workdir"
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
  local source='' destination_partition='' destination_mount='' workdir='' image='' map=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --source) source=${2:-}; shift 2;;
      --destination-partition) destination_partition=${2:-}; shift 2;;
      --destination-mount) destination_mount=${2:-}; shift 2;;
      --workdir) workdir=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      *) die "unknown resume-image argument: $1";;
    esac
  done
  [ -n "$source" ] && [ -n "$destination_partition" ] && [ -n "$destination_mount" ] && [ -n "$workdir" ] && [ -n "$image" ] && [ -n "$map" ] || die "--source, --destination-partition, --destination-mount, --workdir, --image, and --map are required"
  require_basename "$image"; require_basename "$map"
  require_block "$source"; require_ro_block "$source"; require_source_not_mounted "$source"
  require_dir "$workdir"; require_file "$workdir/$image"; require_file "$workdir/$map"
  require_destination_binding "$destination_partition" "$destination_mount" "$workdir"
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
  local destination_partition='' destination_mount='' workdir='' map='' tag=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --destination-partition) destination_partition=${2:-}; shift 2;;
      --destination-mount) destination_mount=${2:-}; shift 2;;
      --workdir) workdir=${2:-}; shift 2;;
      --map) map=${2:-}; shift 2;;
      --tag) tag=${2:-}; shift 2;;
      *) die "unknown capture-checkpoint argument: $1";;
    esac
  done
  [ -n "$destination_partition" ] && [ -n "$destination_mount" ] && [ -n "$workdir" ] && [ -n "$map" ] && [ -n "$tag" ] || die "--destination-partition, --destination-mount, --workdir, --map, and --tag are required"
  require_basename "$map"
  require_dir "$workdir"; require_file "$workdir/$map"; require_destination_binding "$destination_partition" "$destination_mount" "$workdir"
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
  local destination_partition='' destination_mount='' image='' state_file=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --destination-partition) destination_partition=${2:-}; shift 2;;
      --destination-mount) destination_mount=${2:-}; shift 2;;
      --image) image=${2:-}; shift 2;;
      --state-file) state_file=${2:-}; shift 2;;
      *) die "unknown attach-image argument: $1";;
    esac
  done
  [ -n "$destination_partition" ] && [ -n "$destination_mount" ] && [ -n "$image" ] && [ -n "$state_file" ] || die "--destination-partition, --destination-mount, --image, and --state-file are required"
  require_file "$image"; assert_safe_path "$state_file"
  local state_parent image_real loopdev
  state_parent=$(dirname "$state_file")
  require_absolute_no_symlink_components "$state_parent"
  require_dir "$state_parent"; require_destination_binding "$destination_partition" "$destination_mount" "$state_parent"
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
  local mounted_source
  mounted_source=$(exact_mount_source "$mountpoint")
  if [ -n "$mounted_source" ]; then
    [ "$mounted_source" = "/dev/mapper/$mapper_name" ] || die "cleanup mount source mismatch: $mounted_source"
    umount "$mountpoint"
  fi
  if cryptsetup status "$mapper_name" >/dev/null 2>&1; then cryptsetup close "$mapper_name"; fi
  losetup -d "$loopdev"
  rm -f "$loop_state_file"
  log "read-only image stack cleaned up"
}
