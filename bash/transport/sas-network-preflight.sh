#!/usr/bin/env bash
# SysAdminSuite Bash network preflight
# Read-only DNS, ping, and TCP checks for workstations/printers.

set -euo pipefail

TARGETS=()
TARGET_FILE=""
OUTPUT="bash/transport/output/network_preflight.csv"
PORTS="135,139,445,3389,515,631,9100"
TIMEOUT=3
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Network Preflight

Usage:
  ./bash/transport/sas-network-preflight.sh [options] TARGET...

Options:
  --target VALUE       Add target hostname/IP
  --targets-file PATH  TXT/CSV-ish file with targets, one per line or first comma field
  --ports CSV          TCP ports to check. Default: 135,139,445,3389,515,631,9100
  --output PATH        Output CSV path
  --timeout SEC        Per-check timeout. Default: 3
  --pass-thru          Print CSV after writing
  -h, --help           Show help

Read-only. No remote mutation.
USAGE
}
fail(){ printf '[network-preflight] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[network-preflight] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
trim(){ local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGETS+=("${2:?missing value for --target}"); shift 2 ;;
    --targets-file) TARGET_FILE="${2:?missing value for --targets-file}"; shift 2 ;;
    --ports) PORTS="${2:?missing value for --ports}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?missing value for --timeout}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do TARGETS+=("$1"); shift; done ;;
    -*) fail "Unknown option: $1" ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -ge 1 ]] || fail "--timeout must be positive integer"
if [[ -n "$TARGET_FILE" ]]; then
  [[ -f "$TARGET_FILE" ]] || fail "targets file not found: $TARGET_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line%%,*}"
    line="$(trim "$line")"
    [[ -n "$line" ]] && TARGETS+=("$line")
  done < "$TARGET_FILE"
fi
[[ ${#TARGETS[@]} -gt 0 ]] || fail "No targets provided"
mkdir -p "$(dirname "$OUTPUT")"

IFS=',' read -r -a PORT_ARRAY <<< "$PORTS"

resolve_ip(){
  local t="$1"
  if has_cmd getent; then getent ahostsv4 "$t" 2>/dev/null | awk 'NR==1{print $1; exit}'; return; fi
  if has_cmd nslookup; then nslookup "$t" 2>/dev/null | awk '/^Address: /{print $2}' | tail -n 1; return; fi
  printf ''
}

ping_status(){
  local t="$1"
  if ping -c 1 -W "$TIMEOUT" "$t" >/dev/null 2>&1; then printf 'Reachable'; else printf 'NoPing'; fi
}

tcp_status(){
  local host="$1" port="$2"
  if has_cmd nc; then
    if nc -z -w "$TIMEOUT" "$host" "$port" >/dev/null 2>&1; then printf 'Open'; else printf 'ClosedOrFiltered'; fi
    return
  fi
  if has_cmd timeout; then
    if timeout "$TIMEOUT" bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1; then printf 'Open'; else printf 'ClosedOrFiltered'; fi
    return
  fi
  printf 'NotChecked'
}

{
  printf 'Timestamp,Target,ResolvedAddress,PingStatus,Port,PortStatus\n'
  for target in "${TARGETS[@]}"; do
    ip="$(resolve_ip "$target")"
    ping="$(ping_status "${ip:-$target}")"
    for port in "${PORT_ARRAY[@]}"; do
      port="$(trim "$port")"
      [[ -z "$port" ]] && continue
      status="$(tcp_status "${ip:-$target}" "$port")"
      printf '"%s","%s","%s","%s","%s","%s"\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" "$ip" "$ping" "$port" "$status"
    done
  done
} > "$OUTPUT"

log "Wrote preflight CSV: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
