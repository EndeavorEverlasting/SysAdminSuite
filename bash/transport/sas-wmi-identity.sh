#!/usr/bin/env bash
# SysAdminSuite optional WMI identity adapter
# Read-only Windows identity collection through an approved wmic-compatible client.
# This is disabled unless called directly or wired via --allow-wmi from sas-workstation-identity.sh.

set -euo pipefail

TARGETS=()
TARGET_FILE=""
OUTPUT="bash/transport/output/wmi_identity.csv"
TIMEOUT=8
WMI_USER=""
WMI_PASS=""
WMI_DOMAIN=""
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite WMI Identity Adapter

Usage:
  ./bash/transport/sas-wmi-identity.sh [options] TARGET...

Options:
  --target VALUE       Add hostname/IP target
  --targets-file PATH  TXT/CSV-ish file with targets, one per line or first comma field
  --output PATH        Output CSV path
  --timeout SEC        Per-query timeout. Default: 8
  --wmi-user USER      Optional WMI username. Prefer environment variable SAS_WMI_USER.
  --wmi-pass PASS      Optional WMI password. Prefer environment variable SAS_WMI_PASS.
  --wmi-domain DOMAIN  Optional domain. Prefer environment variable SAS_WMI_DOMAIN.
  --pass-thru          Print CSV after writing
  -h, --help           Show help

Environment variables:
  SAS_WMI_USER
  SAS_WMI_PASS
  SAS_WMI_DOMAIN

Output columns:
  Timestamp,Target,ObservedHostName,ObservedSerial,ObservedMACs,WmiStatus,Notes

Safety:
  - Read-only WMI queries only.
  - No remote staging.
  - No scheduled tasks.
  - No registry edits.
  - No credentials are written to output.

Known limitations:
  - Requires an approved `wmic`/Samba WMI client on the Bash host.
  - Firewalls, DCOM/RPC policy, and permissions may block collection.
  - This adapter is optional. Failure should produce NeedsPrivilegedSurvey, not silent confidence.
USAGE
}

fail(){ printf '[wmi-identity] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[wmi-identity] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
trim(){ local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
csv_escape(){ local s="${1:-}"; s="${s//"/""}"; printf '"%s"' "$s"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGETS+=("${2:?missing value for --target}"); shift 2 ;;
    --targets-file) TARGET_FILE="${2:?missing value for --targets-file}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?missing value for --timeout}"; shift 2 ;;
    --wmi-user) WMI_USER="${2:?missing value for --wmi-user}"; shift 2 ;;
    --wmi-pass) WMI_PASS="${2:?missing value for --wmi-pass}"; shift 2 ;;
    --wmi-domain) WMI_DOMAIN="${2:?missing value for --wmi-domain}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do TARGETS+=("$1"); shift; done ;;
    -*) fail "Unknown option: $1" ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

WMI_USER="${WMI_USER:-${SAS_WMI_USER:-}}"
WMI_PASS="${WMI_PASS:-${SAS_WMI_PASS:-}}"
WMI_DOMAIN="${WMI_DOMAIN:-${SAS_WMI_DOMAIN:-}}"
[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -ge 1 ]] || fail "--timeout must be positive integer"
if [[ -n "$TARGET_FILE" ]]; then
  [[ -f "$TARGET_FILE" ]] || fail "targets file not found: $TARGET_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"; [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line%%,*}"; line="$(trim "$line")"; [[ -n "$line" ]] && TARGETS+=("$line")
  done < "$TARGET_FILE"
fi
[[ ${#TARGETS[@]} -gt 0 ]] || fail "No targets provided"
mkdir -p "$(dirname "$OUTPUT")"

norm_mac(){
  local raw="${1:-}" hx out i
  hx="$(printf '%s' "$raw" | tr -cd '[:xdigit:]' | tr '[:lower:]' '[:upper:]')"
  if [[ ${#hx} -eq 12 ]]; then
    out=""; for ((i=0;i<12;i+=2)); do [[ -n "$out" ]] && out+=":"; out+="${hx:i:2}"; done; printf '%s' "$out"
  else printf ''; fi
}

wmi_base_args(){
  local target="$1" auth=""
  if [[ -n "$WMI_USER" ]]; then
    if [[ -n "$WMI_DOMAIN" ]]; then auth="${WMI_DOMAIN}\\${WMI_USER}%${WMI_PASS}"; else auth="${WMI_USER}%${WMI_PASS}"; fi
    printf -- '-U
%s
//%s
' "$auth" "$target"
  else
    printf -- '//%s
' "$target"
  fi
}

run_wmic_query(){
  local target="$1" query="$2" args=() line
  if ! has_cmd wmic; then printf 'WMIC_NOT_INSTALLED'; return; fi
  while IFS= read -r line; do [[ -n "$line" ]] && args+=("$line"); done < <(wmi_base_args "$target")
  if has_cmd timeout; then
    timeout "$TIMEOUT" wmic "${args[@]}" "$query" 2>&1 || true
  else
    wmic "${args[@]}" "$query" 2>&1 || true
  fi
}

extract_first_value(){
  awk -F'|' 'NF>1 && NR>1 {for(i=2;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/, "", $i); if($i != ""){print $i; exit}}}'
}

extract_macs(){
  grep -Eio '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}' | while read -r m; do norm_mac "$m"; done | awk 'NF' | sort -u | paste -sd ';' -
}

{
  printf 'Timestamp,Target,ObservedHostName,ObservedSerial,ObservedMACs,WmiStatus,Notes\n'
  for target in "${TARGETS[@]}"; do
    notes=(); status="NotChecked"; host=""; serial=""; macs=""
    if ! has_cmd wmic; then
      status="WmiClientMissing"; notes+=("wmic client not installed")
    else
      host_raw="$(run_wmic_query "$target" 'SELECT Name FROM Win32_ComputerSystem')"
      serial_raw="$(run_wmic_query "$target" 'SELECT SerialNumber FROM Win32_BIOS')"
      mac_raw="$(run_wmic_query "$target" 'SELECT MACAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=True')"
      if printf '%s%s%s' "$host_raw" "$serial_raw" "$mac_raw" | grep -Eiq 'NT_STATUS|ERROR|failed|denied|timed out|timeout'; then
        status="WmiQueryFailed"; notes+=("WMI query failed or denied")
      else
        host="$(printf '%s
' "$host_raw" | extract_first_value | head -n1)"
        serial="$(printf '%s
' "$serial_raw" | extract_first_value | head -n1)"
        macs="$(printf '%s
' "$mac_raw" | extract_macs)"
        if [[ -n "$host" || -n "$serial" || -n "$macs" ]]; then status="WmiIdentityCollected"; else status="WmiNoIdentityReturned"; fi
      fi
    fi
    csv_escape "$(date '+%Y-%m-%d %H:%M:%S')"; printf ','; csv_escape "$target"; printf ','; csv_escape "$host"; printf ','; csv_escape "$serial"; printf ','; csv_escape "$macs"; printf ','; csv_escape "$status"; printf ','; csv_escape "$(IFS='; '; echo "${notes[*]:-}")"; printf '\n'
  done
} > "$OUTPUT"
log "Wrote WMI identity CSV: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
