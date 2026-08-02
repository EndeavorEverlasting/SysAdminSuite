#!/usr/bin/env bash
# User-data audit and evacuation commands.

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
  local source_root='' destination_partition='' destination_mount='' report='' include_appdata=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-root) source_root=${2:-}; shift 2;;
      --destination-partition) destination_partition=${2:-}; shift 2;;
      --destination-mount) destination_mount=${2:-}; shift 2;;
      --report) report=${2:-}; shift 2;;
      --include-appdata) include_appdata=1; shift;;
      *) die "unknown audit-user-data argument: $1";;
    esac
  done
  [ -n "$source_root" ] && [ -n "$destination_partition" ] && [ -n "$destination_mount" ] && [ -n "$report" ] || die "--source-root, --destination-partition, --destination-mount, and --report are required"
  require_dir "$source_root"; assert_safe_path "$report"
  require_mount_option "$source_root" ro
  mkdir -p "$(dirname "$report")"
  require_destination_binding "$destination_partition" "$destination_mount" "$(dirname "$report")"
  {
    printf 'AUDIT_STARTED=%s\nSOURCE_ROOT=%s\nINCLUDE_APPDATA=%s\n' "$(date -Is)" "$source_root" "$include_appdata"
    local profile name
    for profile in "$source_root"/*; do
      [ -d "$profile" ] || continue
      name=$(basename "$profile")
      is_system_profile "$name" && continue
      printf '\nPROFILE=%s\n' "$name"
      find "$profile" -xdev -mindepth 1 -maxdepth 1 -printf '%y\t%f\n' 2>/dev/null | sort || true
      local profile_bytes
      profile_bytes=$(du -sb "$profile" 2>/dev/null | awk '{print $1}' || true)
      printf 'PROFILE_BYTES=%s\n' "${profile_bytes:-UNKNOWN}"
    done
    printf '\nNONREGULAR_ENTRIES\n'
    find "$source_root" -xdev ! -type d ! -type f -printf '%y\t%p\t%l\n' 2>/dev/null || true
    printf 'AUDIT_FINISHED=%s\n' "$(date -Is)"
  } | tee "$report"
}

cmd_copy_user_data() {
  need rsync; need find; need findmnt; need du
  local source_root='' destination_partition='' destination_mount='' destination_root='' logfile='' include_appdata=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --source-root) source_root=${2:-}; shift 2;;
      --destination-partition) destination_partition=${2:-}; shift 2;;
      --destination-mount) destination_mount=${2:-}; shift 2;;
      --destination-root) destination_root=${2:-}; shift 2;;
      --log) logfile=${2:-}; shift 2;;
      --include-appdata) include_appdata=1; shift;;
      *) die "unknown copy-user-data argument: $1";;
    esac
  done
  [ -n "$source_root" ] && [ -n "$destination_partition" ] && [ -n "$destination_mount" ] && [ -n "$destination_root" ] && [ -n "$logfile" ] || die "--source-root, --destination-partition, --destination-mount, --destination-root, and --log are required"
  require_dir "$source_root"; require_mount_option "$source_root" ro
  assert_safe_path "$destination_root"; assert_safe_path "$logfile"
  mkdir -p "$destination_root" "$(dirname "$logfile")"
  require_destination_binding "$destination_partition" "$destination_mount" "$destination_root"
  require_destination_binding "$destination_partition" "$destination_mount" "$(dirname "$logfile")"
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
