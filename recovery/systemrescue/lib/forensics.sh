#!/usr/bin/env bash
# Read-only NVMe diagnostics and unattended reproduction/postmortem helpers.

FORENSIC_VIEWPORT_LINES=20
FORENSIC_VIEWPORT_COLUMNS=100

forensic_assert_no_symlink_components() {
  local path=$1 current='/' part
  local -a parts=()
  IFS='/' read -r -a parts <<< "${path#/}"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || continue
    current="${current%/}/$part"
    [ ! -L "$current" ] || die "forensic workdir path contains symlink component: $current"
  done
}

forensic_prepare_workdir() {
  local workdir=$1
  [ -n "$workdir" ] || die "--workdir is required"
  [[ "$workdir" = /* ]] || die "forensic workdir must be absolute: $workdir"
  assert_safe_path "$workdir"
  forensic_assert_no_symlink_components "$workdir"
  mkdir -p "$workdir"
  forensic_assert_no_symlink_components "$workdir"
  [ -d "$workdir" ] && [ ! -L "$workdir" ] || die "could not create safe forensic workdir: $workdir"
}

forensic_require_source() {
  local source=$1 expect_model=$2 expect_serial=$3
  require_block "$source"
  require_source_not_mounted "$source"
  FORENSIC_MODEL=$(lsblk -dn -o MODEL "$source" | sed 's/[[:space:]]*$//')
  FORENSIC_SERIAL=$(lsblk -dn -o SERIAL "$source" | sed 's/[[:space:]]*$//')
  [ -z "$expect_model" ] || [ "$FORENSIC_MODEL" = "$expect_model" ] || die "model mismatch: expected '$expect_model', got '$FORENSIC_MODEL'"
  [ -z "$expect_serial" ] || [ "$FORENSIC_SERIAL" = "$expect_serial" ] || die "serial mismatch: expected '$expect_serial', got '$FORENSIC_SERIAL'"
}

forensic_controller_for_namespace() {
  local source_real base
  source_real=$(canonical_path "$1")
  base=$(basename "$source_real")
  [[ "$base" =~ ^nvme([0-9]+)n[0-9]+$ ]] || die "expected an NVMe namespace device, got: $source_real"
  printf '/dev/nvme%s\n' "${BASH_REMATCH[1]}"
}

forensic_bdf_for_controller() {
  local controller_name
  controller_name=$(basename "$1")
  [ -e "/sys/class/nvme/$controller_name/device" ] || return 1
  basename "$(readlink -f "/sys/class/nvme/$controller_name/device")"
}

forensic_parent_bdf() {
  local bdf=$1 parent_path
  [ -e "/sys/bus/pci/devices/$bdf" ] || return 1
  parent_path=$(dirname "$(readlink -f "/sys/bus/pci/devices/$bdf")")
  basename "$parent_path"
}

forensic_smart_value() {
  local key=$1 file=$2
  awk -F: -v k="$key" '
    $1 ~ ("^" k "[[:space:]]*$") {
      sub(/^[[:space:]]+/, "", $2)
      sub(/[[:space:]]+$/, "", $2)
      print $2
      exit
    }' "$file"
}

forensic_aer_total() {
  local key=$1 file=$2
  [ -f "$file" ] || return 0
  awk -v k="$key" '$1 == k {print $2; exit}' "$file"
}

forensic_sysfs_value() {
  local file=$1
  [ -r "$file" ] || { printf 'UNKNOWN\n'; return; }
  tr ' ' '_' < "$file" | tr -d '\n'
  printf '\n'
}

forensic_visible_rows() {
  local file=$1
  awk -v cols="$FORENSIC_VIEWPORT_COLUMNS" '
    {
      n = length($0)
      rows += (n == 0 ? 1 : int((n - 1) / cols) + 1)
    }
    END { print rows + 0 }
  ' "$file"
}

forensic_print_summary() {
  local file=$1 lines rows
  lines=$(wc -l < "$file")
  rows=$(forensic_visible_rows "$file")
  [ "$lines" -le "$FORENSIC_VIEWPORT_LINES" ] || die "forensic summary has $lines logical lines; limit is $FORENSIC_VIEWPORT_LINES"
  [ "$rows" -le "$FORENSIC_VIEWPORT_LINES" ] || die "forensic summary needs $rows visible rows at ${FORENSIC_VIEWPORT_COLUMNS} columns; limit is $FORENSIC_VIEWPORT_LINES (full evidence remains in files)"
  cat "$file"
}

forensic_first_io_block() {
  grep -E 'Buffer I/O error on dev .*nvme' "$1" | sed -n 's/.*logical block \([0-9][0-9]*\).*/\1/p' | head -n 1 || true
}

forensic_last_io_block() {
  grep -E 'Buffer I/O error on dev .*nvme' "$1" | sed -n 's/.*logical block \([0-9][0-9]*\).*/\1/p' | tail -n 1 || true
}

forensic_analyze_kernel_file() {
  local file=$1 rc=$2
  FORENSIC_TIMEOUTS=$(grep -Eci 'nvme .*I/O .*timeout|nvme .*timeout' "$file" || true)
  FORENSIC_RESET_CONTROLLER=$(grep -Eci 'reset controller' "$file" || true)
  FORENSIC_NOT_READY=$(grep -Eci 'Device not ready; aborting reset' "$file" || true)
  FORENSIC_DISABLED=$(grep -Eci 'Disabling device after reset failure' "$file" || true)
  FORENSIC_BUFFER_ERRORS=$(grep -Eci 'Buffer I/O error on dev .*nvme' "$file" || true)
  FORENSIC_FIRST_IO_BLOCK=$(forensic_first_io_block "$file")
  FORENSIC_LAST_IO_BLOCK=$(forensic_last_io_block "$file")

  if [ "$FORENSIC_DISABLED" -gt 0 ]; then
    FORENSIC_OUTCOME=NVME_RESET_FAILURE_REPRODUCED
  elif [ "$FORENSIC_NOT_READY" -gt 0 ]; then
    FORENSIC_OUTCOME=NVME_RESET_NOT_READY
  elif [ "$FORENSIC_TIMEOUTS" -gt 0 ] || [ "$FORENSIC_RESET_CONTROLLER" -gt 0 ]; then
    FORENSIC_OUTCOME=NVME_TIMEOUT_OR_RESET
  elif [ "$FORENSIC_BUFFER_ERRORS" -gt 0 ]; then
    FORENSIC_OUTCOME=BLOCK_IO_FAILURE_WITHOUT_RESET
  elif [ "$rc" -eq 0 ]; then
    FORENSIC_OUTCOME=SEQUENTIAL_READ_COMPLETED
  else
    FORENSIC_OUTCOME=DDRESCUE_EXIT_UNCLASSIFIED
  fi
}

forensic_write_analysis_summary() {
  local file=$1 rc=$2 output=$3
  forensic_analyze_kernel_file "$file" "$rc"
  {
    printf 'OUTCOME=%s\n' "$FORENSIC_OUTCOME"
    printf 'DDRESCUE_RC=%s\n' "$rc"
    printf 'TIMEOUT_EVENTS=%s\n' "$FORENSIC_TIMEOUTS"
    printf 'RESET_CONTROLLER_EVENTS=%s\n' "$FORENSIC_RESET_CONTROLLER"
    printf 'RESET_NOT_READY_EVENTS=%s\n' "$FORENSIC_NOT_READY"
    printf 'DISABLE_AFTER_RESET_EVENTS=%s\n' "$FORENSIC_DISABLED"
    printf 'BUFFER_IO_ERRORS=%s\n' "$FORENSIC_BUFFER_ERRORS"
    printf 'FIRST_IO_BLOCK=%s\n' "${FORENSIC_FIRST_IO_BLOCK:-NONE}"
    printf 'LAST_IO_BLOCK=%s\n' "${FORENSIC_LAST_IO_BLOCK:-NONE}"
  } > "$output"
}

forensic_capture_baseline() {
  local source=$1 workdir=$2
  local controller controller_name bdf parent smart aer_cor aer_fatal aer_nonfatal
  controller=$(forensic_controller_for_namespace "$source")
  controller_name=$(basename "$controller")
  bdf=$(forensic_bdf_for_controller "$controller" || true)
  parent=''
  [ -z "$bdf" ] || parent=$(forensic_parent_bdf "$bdf" || true)

  mkdir -p "$workdir"
  lsblk -dn -o NAME,MODEL,SERIAL,SIZE,RO,TRAN "$source" > "$workdir/source.txt"
  nvme list > "$workdir/nvme-list.txt" 2>&1 || true
  nvme smart-log "$controller" > "$workdir/smart.txt" 2>&1 || true
  dmesg -T > "$workdir/dmesg.txt" 2>&1 || true

  if [ -n "$bdf" ]; then
    lspci -s "${bdf#0000:}" -vv > "$workdir/pci-endpoint.txt" 2>&1 || true
    grep -h . "/sys/bus/pci/devices/$bdf"/aer_dev_* > "$workdir/aer-endpoint.txt" 2>/dev/null || true
  else
    : > "$workdir/pci-endpoint.txt"
    : > "$workdir/aer-endpoint.txt"
  fi
  if [ -n "$parent" ]; then
    lspci -s "${parent#0000:}" -vv > "$workdir/pci-parent.txt" 2>&1 || true
  else
    : > "$workdir/pci-parent.txt"
  fi

  smart=$workdir/smart.txt
  aer_cor=$(forensic_aer_total TOTAL_ERR_COR "$workdir/aer-endpoint.txt")
  aer_fatal=$(forensic_aer_total TOTAL_ERR_FATAL "$workdir/aer-endpoint.txt")
  aer_nonfatal=$(forensic_aer_total TOTAL_ERR_NONFATAL "$workdir/aer-endpoint.txt")
  {
    printf 'SOURCE=%s\n' "$source"
    printf 'MODEL=%s\n' "$FORENSIC_MODEL"
    printf 'SERIAL=%s\n' "$FORENSIC_SERIAL"
    printf 'RO=%s\n' "$(blockdev --getro "$source" 2>/dev/null || printf UNKNOWN)"
    printf 'CONTROLLER=%s\n' "$controller"
    printf 'NVME_BDF=%s\n' "${bdf:-UNKNOWN}"
    if [ -n "$bdf" ]; then
      printf 'LINK_CURRENT=%s_x%s\n' \
        "$(forensic_sysfs_value "/sys/bus/pci/devices/$bdf/current_link_speed")" \
        "$(forensic_sysfs_value "/sys/bus/pci/devices/$bdf/current_link_width")"
      printf 'LINK_MAX=%s_x%s\n' \
        "$(forensic_sysfs_value "/sys/bus/pci/devices/$bdf/max_link_speed")" \
        "$(forensic_sysfs_value "/sys/bus/pci/devices/$bdf/max_link_width")"
    else
      printf 'LINK_CURRENT=UNKNOWN\nLINK_MAX=UNKNOWN\n'
    fi
    printf 'PARENT_BDF=%s\n' "${parent:-UNKNOWN}"
    printf 'SMART_CRITICAL_WARNING=%s\n' "$(forensic_smart_value critical_warning "$smart")"
    printf 'SMART_TEMPERATURE=%s\n' "$(forensic_smart_value temperature "$smart")"
    printf 'SMART_UNSAFE_SHUTDOWNS=%s\n' "$(forensic_smart_value unsafe_shutdowns "$smart")"
    printf 'SMART_MEDIA_ERRORS=%s\n' "$(forensic_smart_value media_errors "$smart")"
    printf 'SMART_ERROR_LOG_ENTRIES=%s\n' "$(forensic_smart_value num_err_log_entries "$smart")"
    printf 'AER_TOTAL_COR=%s\n' "${aer_cor:-UNKNOWN}"
    printf 'AER_TOTAL_FATAL=%s\n' "${aer_fatal:-UNKNOWN}"
    printf 'AER_TOTAL_NONFATAL=%s\n' "${aer_nonfatal:-UNKNOWN}"
    printf 'EVIDENCE_DIR=%s\n' "$workdir"
  } > "$workdir/summary.txt"
}

cmd_nvme_classify_log() {
  need grep; need sed; need awk; need mktemp
  local kernel_log='' rc=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --kernel-log) kernel_log=${2:-}; shift 2;;
      --ddrescue-rc) rc=${2:-}; shift 2;;
      *) die "unknown nvme-classify-log argument: $1";;
    esac
  done
  [ -n "$kernel_log" ] && [ -n "$rc" ] || die "--kernel-log and --ddrescue-rc are required"
  require_file "$kernel_log"
  [[ "$rc" =~ ^[0-9]+$ ]] || die "--ddrescue-rc must be a non-negative integer"
  local summary
  summary=$(mktemp)
  forensic_write_analysis_summary "$kernel_log" "$rc" "$summary"
  forensic_print_summary "$summary"
  rm -f "$summary"
}

cmd_nvme_baseline() {
  require_root
  need lsblk; need blockdev; need nvme; need lspci; need dmesg; need readlink; need awk
  local source='' expect_model='' expect_serial='' workdir=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --source) source=${2:-}; shift 2;;
      --expect-model) expect_model=${2:-}; shift 2;;
      --expect-serial) expect_serial=${2:-}; shift 2;;
      --workdir) workdir=${2:-}; shift 2;;
      *) die "unknown nvme-baseline argument: $1";;
    esac
  done
  [ -n "$source" ] || die "--source is required"
  forensic_require_source "$source" "$expect_model" "$expect_serial"
  blockdev --setro "$source"
  require_ro_block "$source"
  forensic_prepare_workdir "$workdir"
  forensic_capture_baseline "$source" "$workdir"
  forensic_print_summary "$workdir/summary.txt"
}

cmd_nvme_read_repro() {
  require_root
  need lsblk; need blockdev; need nvme; need lspci; need dmesg; need readlink; need awk; need ddrescue; need timeout; need stdbuf
  local source='' expect_model='' expect_serial='' workdir=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --source) source=${2:-}; shift 2;;
      --expect-model) expect_model=${2:-}; shift 2;;
      --expect-serial) expect_serial=${2:-}; shift 2;;
      --workdir) workdir=${2:-}; shift 2;;
      *) die "unknown nvme-read-repro argument: $1";;
    esac
  done
  [ -n "$source" ] || die "--source is required"
  forensic_require_source "$source" "$expect_model" "$expect_serial"
  blockdev --setro "$source"
  require_ro_block "$source"
  forensic_prepare_workdir "$workdir"

  [ ! -e "$workdir/read-repro.map" ] || die "reproduction map already exists; choose a fresh --workdir"
  [ ! -e "$workdir/ddrescue.log" ] || die "reproduction log already exists; choose a fresh --workdir"

  mkdir -p "$workdir/before"
  forensic_capture_baseline "$source" "$workdir/before"
  : > "$workdir/kernel-delta.txt"

  local kernel_pid
  stdbuf -oL dmesg --follow-new --human > "$workdir/kernel-delta.txt" 2>&1 &
  kernel_pid=$!
  sleep 0.2
  if ! kill -0 "$kernel_pid" 2>/dev/null; then
    wait "$kernel_pid" 2>/dev/null || true
    die "could not start stable dmesg --follow-new capture"
  fi
  trap 'kill "$kernel_pid" 2>/dev/null || true' EXIT

  local rc
  set +e
  ddrescue -f -n "$source" /dev/null "$workdir/read-repro.map" > "$workdir/ddrescue.log" 2>&1
  rc=$?
  set -e
  printf '%s\n' "$rc" > "$workdir/ddrescue.exit"

  kill "$kernel_pid" 2>/dev/null || true
  wait "$kernel_pid" 2>/dev/null || true
  trap - EXIT
  dmesg -T > "$workdir/dmesg-after.txt" 2>&1 || true

  local device_node_present=0 size_query_after=0
  if [ -b "$source" ]; then
    device_node_present=1
    if timeout 5 blockdev --getsize64 "$source" >/dev/null 2>&1; then
      size_query_after=1
      mkdir -p "$workdir/after"
      forensic_capture_baseline "$source" "$workdir/after" || true
    fi
  fi

  forensic_analyze_kernel_file "$workdir/kernel-delta.txt" "$rc"
  {
    printf 'OUTCOME=%s\n' "$FORENSIC_OUTCOME"
    printf 'DDRESCUE_RC=%s\n' "$rc"
    printf 'KERNEL_CAPTURE=follow-new\n'
    printf 'DEVICE_NODE_PRESENT_AFTER=%s\n' "$device_node_present"
    printf 'DEVICE_SIZE_QUERY_AFTER=%s\n' "$size_query_after"
    printf 'TIMEOUT_EVENTS=%s\n' "$FORENSIC_TIMEOUTS"
    printf 'RESET_CONTROLLER_EVENTS=%s\n' "$FORENSIC_RESET_CONTROLLER"
    printf 'RESET_NOT_READY_EVENTS=%s\n' "$FORENSIC_NOT_READY"
    printf 'DISABLE_AFTER_RESET_EVENTS=%s\n' "$FORENSIC_DISABLED"
    printf 'BUFFER_IO_ERRORS=%s\n' "$FORENSIC_BUFFER_ERRORS"
    printf 'FIRST_IO_BLOCK=%s\n' "${FORENSIC_FIRST_IO_BLOCK:-NONE}"
    printf 'LAST_IO_BLOCK=%s\n' "${FORENSIC_LAST_IO_BLOCK:-NONE}"
    printf 'MAP=%s\n' "$workdir/read-repro.map"
    printf 'DDRESCUE_LOG=%s\n' "$workdir/ddrescue.log"
    printf 'KERNEL_DELTA=%s\n' "$workdir/kernel-delta.txt"
    printf 'RESULT_CAPTURED=YES\n'
  } > "$workdir/repro-summary.txt"
  forensic_print_summary "$workdir/repro-summary.txt"
}
