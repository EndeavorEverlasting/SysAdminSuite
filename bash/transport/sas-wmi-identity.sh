#!/usr/bin/env bash
# SysAdminSuite optional WMI identity adapter
# Read-only Windows identity collection through an approved WMI transport.
# This is disabled unless called directly or wired via --allow-wmi from sas-workstation-identity.sh.

set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"
# shellcheck source=survey/lib/sas-progress.sh
source "$SAS_REPO_ROOT/survey/lib/sas-progress.sh"

TARGETS=()
TARGET_FILE=""
OUTPUT="bash/transport/output/wmi_identity.csv"
TIMEOUT=8
WMI_USER=""
WMI_PASS=""
WMI_DOMAIN=""
WMI_CLIENT="${SAS_WMI_CLIENT:-auto}"
DEBUG="${SAS_WMI_DEBUG:-${SAS_DEBUG:-0}}"
LOG_FILE="${SAS_WMI_LOG_FILE:-}"
PASS_THRU=0
NO_PROGRESS=0

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
  --wmi-client MODE    WMI client: auto, wmic, or powershell. Default: auto.
  --debug              Print safe diagnostic logging to stderr.
  --log-file PATH      Write safe diagnostic logging to a local file.
  --pass-thru          Print CSV after writing
  --no-progress        Suppress progress bars
  -h, --help           Show help

Environment variables:
  SAS_WMI_USER
  SAS_WMI_PASS
  SAS_WMI_DOMAIN
  SAS_WMI_CLIENT
  SAS_WMI_DEBUG
  SAS_WMI_LOG_FILE

Output columns:
  Timestamp,Target,ObservedHostName,ObservedSerial,ObservedMACs,WmiStatus,Notes

Safety:
  - Read-only WMI queries only.
  - No remote staging.
  - No scheduled tasks.
  - No registry edits.
  - No credentials are written to output or diagnostic logs.

Known limitations:
  - `wmic` mode requires an approved `wmic`/Samba WMI client on the Bash host.
  - `powershell` mode uses local Windows PowerShell WMI cmdlets from Git Bash.
  - Firewalls, DCOM/RPC policy, and permissions may block collection.
  - This adapter is optional. Failure should produce NeedsPrivilegedSurvey, not silent confidence.
USAGE
}

fail(){ sas_progress_fail "$*"; printf '[wmi-identity] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[wmi-identity] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
trim(){ local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
csv_escape(){ local s="${1:-}" q='"'; s="${s//$q/$q$q}"; printf '"%s"' "$s"; }
flag_state(){ [[ -n "${1:-}" ]] && printf 'set' || printf 'unset'; }
debug_enabled(){ [[ "$DEBUG" == "1" || "$DEBUG" == "true" || "$DEBUG" == "yes" || -n "$LOG_FILE" ]]; }
diagnostic(){
  local line
  debug_enabled || return 0
  line="$(date '+%Y-%m-%d %H:%M:%S') [wmi-identity] $*"
  printf '%s\n' "$line" >&2
  if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '%s\n' "$line" >> "$LOG_FILE"
  fi
}
sanitize_field(){ local s="${1:-}"; s="${s//$'\r'/ }"; s="${s//$'\n'/ }"; s="${s//|/ }"; printf '%s' "$s"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGETS+=("${2:?missing value for --target}"); shift 2 ;;
    --targets-file) TARGET_FILE="${2:?missing value for --targets-file}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?missing value for --timeout}"; shift 2 ;;
    --wmi-user) WMI_USER="${2:?missing value for --wmi-user}"; shift 2 ;;
    --wmi-pass) WMI_PASS="${2:?missing value for --wmi-pass}"; shift 2 ;;
    --wmi-domain) WMI_DOMAIN="${2:?missing value for --wmi-domain}"; shift 2 ;;
    --wmi-client) WMI_CLIENT="${2:?missing value for --wmi-client}"; shift 2 ;;
    --debug) DEBUG=1; shift ;;
    --log-file) LOG_FILE="${2:?missing value for --log-file}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    --no-progress) NO_PROGRESS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do TARGETS+=("$1"); shift; done ;;
    -*) fail "Unknown option: $1" ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

WMI_USER="${WMI_USER:-${SAS_WMI_USER:-}}"
WMI_PASS="${WMI_PASS:-${SAS_WMI_PASS:-}}"
WMI_DOMAIN="${WMI_DOMAIN:-${SAS_WMI_DOMAIN:-}}"
if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -ge 1 ]] || fail "--timeout must be positive integer"
case "$WMI_CLIENT" in
  auto|wmic|powershell) ;;
  *) fail "--wmi-client must be auto, wmic, or powershell" ;;
esac
if [[ -n "$TARGET_FILE" ]]; then
  [[ -f "$TARGET_FILE" ]] || fail "targets file not found: $TARGET_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"; [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line%%,*}"; line="$(trim "$line")"; [[ -n "$line" ]] && TARGETS+=("$line")
  done < "$TARGET_FILE"
fi
[[ ${#TARGETS[@]} -gt 0 ]] || fail "No targets provided"
mkdir -p "$(dirname "$OUTPUT")"
[[ "$NO_PROGRESS" -eq 1 ]] && sas_progress_disable
sas_progress_start "${#TARGETS[@]}" "WMI identity"
completed=0
trap 'rc=$?; if (( rc != 0 )); then sas_progress_fail "stopped with exit $rc"; fi' EXIT

TMP_DIR="$(mktemp -d)"
cleanup(){ local rc=$?; rm -rf "$TMP_DIR"; if (( rc != 0 )); then sas_progress_fail "stopped with exit $rc"; fi; }
trap cleanup EXIT
PS_WMI_SCRIPT="$TMP_DIR/sas-wmi-query.ps1"

cat > "$PS_WMI_SCRIPT" <<'PS1'
param(
  [Parameter(Mandatory=$true)][string]$Target
)
$ErrorActionPreference = 'Stop'
function New-Result {
  param(
    [string]$Status,
    [string]$HostName = '',
    [string]$Serial = '',
    [string]$Macs = '',
    [string]$Notes = ''
  )
  [pscustomobject]@{
    Status = $Status
    ObservedHostName = $HostName
    ObservedSerial = $Serial
    ObservedMACs = $Macs
    Notes = $Notes
  } | ConvertTo-Json -Compress
}
try {
  $user = $env:SAS_WMI_USER
  $pass = $env:SAS_WMI_PASS
  $domain = $env:SAS_WMI_DOMAIN
  $credential = $null
  if ($user) {
    $account = if ($domain) { "$domain\$user" } else { $user }
    $secure = ConvertTo-SecureString ($pass | ForEach-Object { $_ }) -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($account, $secure)
  }
  $base = @{ ComputerName = $Target; ErrorAction = 'Stop' }
  if ($credential) { $base.Credential = $credential }
  $computer = Get-WmiObject @base -Class Win32_ComputerSystem | Select-Object -First 1
  $bios = Get-WmiObject @base -Class Win32_BIOS | Select-Object -First 1
  $nics = Get-WmiObject @base -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
  $macs = @($nics | ForEach-Object { $_.MACAddress } | Where-Object { $_ }) -join ';'
  if ($computer.Name -or $bios.SerialNumber -or $macs) {
    New-Result -Status 'WmiIdentityCollected' -HostName ([string]$computer.Name) -Serial ([string]$bios.SerialNumber) -Macs ([string]$macs) -Notes 'PowerShellWMI'
  } else {
    New-Result -Status 'WmiNoIdentityReturned' -Notes 'PowerShellWMI returned no host, serial, or MAC values'
  }
} catch {
  $message = $_.Exception.Message
  if ($message.Length -gt 220) { $message = $message.Substring(0,220) }
  New-Result -Status 'WmiQueryFailed' -Notes ("PowerShellWMI: " + $message)
}
PS1

norm_mac(){
  local raw="${1:-}" hx out i
  hx="$(printf '%s' "$raw" | tr -cd '[:xdigit:]' | tr '[:lower:]' '[:upper:]')"
  if [[ ${#hx} -eq 12 ]]; then
    out=""; for ((i=0;i<12;i+=2)); do [[ -n "$out" ]] && out+=":"; out+="${hx:i:2}"; done; printf '%s' "$out"
  else printf ''; fi
}

powershell_cmd(){
  local candidate
  for candidate in powershell.exe /c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe; do
    if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return; fi
    [[ -x "$candidate" ]] && { printf '%s' "$candidate"; return; }
  done
  return 1
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

json_field(){
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    data=json.loads(sys.argv[1])
except Exception:
    data={}
print(data.get(sys.argv[2], '') or '')
PY
}

run_powershell_wmi(){
  local target="$1" ps err raw rc err_text
  ps="$(powershell_cmd 2>/dev/null || true)"
  if [[ -z "$ps" ]]; then
    diagnostic "target=$target client=powershell status=WmiClientMissing reason=powershell.exe_not_found"
    printf '{"Status":"WmiClientMissing","Notes":"powershell.exe not found"}'
    return
  fi
  diagnostic "target=$target client=powershell path=$ps action=start"
  err="$TMP_DIR/powershell_${target//[^A-Za-z0-9_.-]/_}.err"
  raw="$($ps -NoProfile -NonInteractive -File "$PS_WMI_SCRIPT" -Target "$target" 2>"$err")"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    err_text="$(head -c 220 "$err" 2>/dev/null || true)"
    err_text="$(sanitize_field "$err_text")"
    diagnostic "target=$target client=powershell status=WmiQueryFailed rc=$rc stderr=${err_text:-none}"
    printf '{"Status":"WmiQueryFailed","Notes":"PowerShellWMI execution failed"}'
    return
  fi
  printf '%s' "$raw"
}

collect_with_wmic(){
  local target="$1" host_raw serial_raw mac_raw host serial macs status notes
  diagnostic "target=$target client=wmic action=start"
  host_raw="$(run_wmic_query "$target" 'SELECT Name FROM Win32_ComputerSystem')"
  serial_raw="$(run_wmic_query "$target" 'SELECT SerialNumber FROM Win32_BIOS')"
  mac_raw="$(run_wmic_query "$target" 'SELECT MACAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=True')"
  if printf '%s%s%s' "$host_raw" "$serial_raw" "$mac_raw" | grep -Eiq 'NT_STATUS|ERROR|failed|denied|timed out|timeout'; then
    printf 'WmiQueryFailed||||WMI query failed or denied|wmic'
    return
  fi
  host="$(printf '%s
' "$host_raw" | extract_first_value | head -n1)"
  serial="$(printf '%s
' "$serial_raw" | extract_first_value | head -n1)"
  macs="$(printf '%s
' "$mac_raw" | extract_macs)"
  if [[ -n "$host" || -n "$serial" || -n "$macs" ]]; then status="WmiIdentityCollected"; notes="wmic"; else status="WmiNoIdentityReturned"; notes="wmic returned no host, serial, or MAC values"; fi
  printf '%s|%s|%s|%s|%s|wmic' "$status" "$(sanitize_field "$host")" "$(sanitize_field "$serial")" "$(sanitize_field "$macs")" "$(sanitize_field "$notes")"
}

collect_with_powershell(){
  local target="$1" raw status host serial macs notes
  raw="$(run_powershell_wmi "$target")"
  status="$(json_field "$raw" Status)"
  host="$(json_field "$raw" ObservedHostName)"
  serial="$(json_field "$raw" ObservedSerial)"
  macs="$(json_field "$raw" ObservedMACs)"
  notes="$(json_field "$raw" Notes)"
  printf '%s|%s|%s|%s|%s|powershell' "$(sanitize_field "${status:-WmiQueryFailed}")" "$(sanitize_field "$host")" "$(sanitize_field "$serial")" "$(sanitize_field "$macs")" "$(sanitize_field "$notes")"
}

collect_identity(){
  local target="$1"
  case "$WMI_CLIENT" in
    wmic)
      if has_cmd wmic; then collect_with_wmic "$target"; else printf 'WmiClientMissing||||wmic client not installed|wmic'; fi
      ;;
    powershell)
      collect_with_powershell "$target"
      ;;
    auto)
      if has_cmd wmic; then collect_with_wmic "$target"; else collect_with_powershell "$target"; fi
      ;;
  esac
}

diagnostic "start output=$OUTPUT target_count=${#TARGETS[@]} timeout=$TIMEOUT wmi_client=$WMI_CLIENT wmi_user=$(flag_state "$WMI_USER") wmi_pass=$(flag_state "$WMI_PASS") wmi_domain=$(flag_state "$WMI_DOMAIN")"
diagnostic "tooling wmic=$(if has_cmd wmic; then printf found; else printf missing; fi) powershell=$(powershell_cmd 2>/dev/null || printf missing)"

{
  printf 'Timestamp,Target,ObservedHostName,ObservedSerial,ObservedMACs,WmiStatus,Notes\n'
  for target in "${TARGETS[@]}"; do
    sas_progress_update "$completed" "checking $target"
    result="$(collect_identity "$target")"
    IFS='|' read -r status host serial macs notes client <<< "$result"
    diagnostic "target=$target client=${client:-unknown} status=${status:-unknown} host_collected=$([[ -n "$host" ]] && printf yes || printf no) serial_collected=$([[ -n "$serial" ]] && printf yes || printf no) macs_collected=$([[ -n "$macs" ]] && printf yes || printf no) notes=$(sanitize_field "$notes")"
    csv_escape "$(date '+%Y-%m-%d %H:%M:%S')"; printf ','; csv_escape "$target"; printf ','; csv_escape "$host"; printf ','; csv_escape "$serial"; printf ','; csv_escape "$macs"; printf ','; csv_escape "$status"; printf ','; csv_escape "$notes"; printf '\n'
    completed=$((completed + 1))
    sas_progress_update "$completed" "finished $target"
  done
} > "$OUTPUT"
sas_progress_complete "wrote $OUTPUT"
log "Wrote WMI identity CSV: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
