#!/usr/bin/env bash
# QR-safe pointer-command catalog.

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
    emit_qr 4 'bash "$R" start-image --source "$SRC" --destination-partition "$DST" --destination-mount "$M" --workdir "$W" --image "$IMG" --map "$MAP" --confirm-new-image' "$max"
  else
    emit_qr 4 'bash "$R" resume-image --source "$SRC" --destination-partition "$DST" --destination-mount "$M" --workdir "$W" --image "$IMG" --map "$MAP"' "$max"
  fi
  emit_qr 5 'bash "$R" capture-checkpoint --destination-partition "$DST" --destination-mount "$M" --workdir "$W" --map "$MAP" --tag post-image' "$max"
  emit_qr 6 'bash "$R" attach-image --destination-partition "$DST" --destination-mount "$M" --image "$W/$IMG" --state-file "$W/loop.state"' "$max"
  emit_qr 7 'bash "$R" open-bitlocker --partition "$(head -n1 "$W/loop.state"|cut -d= -f2-)p$BP" --name sas_image_bitlk' "$max"
  emit_qr 8 'bash "$R" mount-ntfs --mapper /dev/mapper/sas_image_bitlk --mount /mnt/recovery-image' "$max"
  emit_qr 9 'bash "$R" audit-user-data --source-root /mnt/recovery-image/Users --destination-partition "$DST" --destination-mount "$M" --report "$W/user-audit.txt"' "$max"
  emit_qr 10 'bash "$R" copy-user-data --source-root /mnt/recovery-image/Users --destination-partition "$DST" --destination-mount "$M" --destination-root "$W/RECOVERED_USER_DATA" --log "$W/user-copy.log"' "$max"
}
