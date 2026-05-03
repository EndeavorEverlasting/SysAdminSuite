#!/usr/bin/env bash
# SysAdminSuite Bash printer identity probe
# Read-only-ish printer recon: ping, SNMP, HTTP scrape, TCP/9100/ZPL, ARP fallback.
# 9100 sends a status/config request and should only be used where approved.

set -euo pipefail

TARGETS=()
TARGET_FILE=""
OUTPUT="bash/transport/output/printer_probe.csv"
COMMUNITIES="public,private,northwell,zebra,netadmin"
TIMEOUT=3
SNMP_ONLY=0
SKIP_9100=0
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Printer Probe

Usage:
  ./bash/transport/sas-printer-probe.sh [options] TARGET...

Options:
  --target VALUE       Add printer hostname/IP
  --targets-file PATH  TXT/CSV-ish file with targets, one per line or first comma field
  --communities CSV    SNMP communities to try. Default: public,private,northwell,zebra,netadmin
  --snmp-only          Skip HTTP, 9100, and ARP fallbacks
  --skip-9100          Do not send raw-port/ZPL request
  --output PATH        Output CSV path
  --timeout SEC        Timeout. Default: 3
  --pass-thru          Print CSV after writing
  -h, --help           Show help

Output columns:
  Timestamp,Target,ResolvedAddress,PingStatus,MAC,Serial,Source,Notes

Risks:
  - SNMP community strings are sensitive and environment-specific.
  - HTTP scrape may expose banners only, not serials.
  - ARP is local-L2 only and not proof of absence.
  - Port 9100/ZPL should be used only where approved; use --skip-9100 if unsure.
USAGE
}
fail(){ printf '[printer-probe] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[printer-probe] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
trim(){ local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGETS+=("${2:?missing value for --target}"); shift 2 ;;
    --targets-file) TARGET_FILE="${2:?missing value for --targets-file}"; shift 2 ;;
    --communities) COMMUNITIES="${2:?missing value for --communities}"; shift 2 ;;
    --snmp-only) SNMP_ONLY=1; shift ;;
    --skip-9100) SKIP_9100=1; shift ;;
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
    line="$(trim "$line")"; [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line%%,*}"; line="$(trim "$line")"; [[ -n "$line" ]] && TARGETS+=("$line")
  done < "$TARGET_FILE"
fi
[[ ${#TARGETS[@]} -gt 0 ]] || fail "No targets provided"
mkdir -p "$(dirname "$OUTPUT")"
IFS=',' read -r -a COMMUNITY_ARRAY <<< "$COMMUNITIES"

norm_mac(){
  local raw="${1:-}" hx out i
  hx="$(printf '%s' "$raw" | tr -cd '[:xdigit:]' | tr '[:lower:]' '[:upper:]')"
  if [[ ${#hx} -ge 12 ]]; then
    hx="${hx:0:12}"; out=""
    for ((i=0;i<12;i+=2)); do [[ -n "$out" ]] && out+=":"; out+="${hx:i:2}"; done
    printf '%s' "$out"
  else printf ''; fi
}
resolve_ip(){ if has_cmd getent; then getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1; exit}'; else printf ''; fi; }
ping_status(){ if ping -c 1 -W "$TIMEOUT" "$1" >/dev/null 2>&1; then printf 'Reachable'; else printf 'NoPing'; fi; }

try_snmp_serial(){
  local ip="$1" comm out val
  has_cmd snmpget || return 0
  for comm in "${COMMUNITY_ARRAY[@]}"; do
    comm="$(trim "$comm")"; [[ -z "$comm" ]] && continue
    out="$(snmpget -v 2c -c "$comm" -t "$TIMEOUT" -r 0 "$ip" 1.3.6.1.2.1.43.5.1.1.17.1 2>/dev/null || true)"
    [[ -z "$out" ]] && out="$(snmpget -v 1 -c "$comm" -t "$TIMEOUT" -r 0 "$ip" 1.3.6.1.2.1.43.5.1.1.17.1 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
      val="$(printf '%s' "$out" | sed -E 's/.*STRING: "?([^" ]+)"?.*/\1/')"
      [[ -n "$val" && "$val" != "$out" ]] && printf '%s|SNMP serial (%s)' "$val" "$comm" && return 0
    fi
  done
}
try_snmp_mac(){
  local ip="$1" comm out mac
  has_cmd snmpwalk || return 0
  for comm in "${COMMUNITY_ARRAY[@]}"; do
    comm="$(trim "$comm")"; [[ -z "$comm" ]] && continue
    out="$(snmpwalk -v 2c -c "$comm" -t "$TIMEOUT" -r 0 -On "$ip" 1.3.6.1.2.1.2.2.1.6 2>/dev/null || true)"
    [[ -z "$out" ]] && out="$(snmpwalk -v 1 -c "$comm" -t "$TIMEOUT" -r 0 -On "$ip" 1.3.6.1.2.1.2.2.1.6 2>/dev/null || true)"
    mac="$(norm_mac "$out")"
    [[ -n "$mac" && "$mac" != "00:00:00:00:00:00" ]] && printf '%s|SNMP ifPhysAddress (%s)' "$mac" "$comm" && return 0
  done
}
try_http(){
  local ip="$1" html mac serial
  has_cmd curl || return 0
  html="$(curl -m "$TIMEOUT" -fsS "http://$ip" 2>/dev/null || true)"
  [[ -z "$html" ]] && return 0
  mac="$(printf '%s' "$html" | grep -Eio '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}' | head -n1 || true)"
  mac="$(norm_mac "$mac")"
  serial="$(printf '%s' "$html" | grep -Eio '(Serial Number|Serial|S/N)[^A-Za-z0-9]{0,12}[A-Za-z0-9_/-]{5,}' | head -n1 | sed -E 's/.*[^A-Za-z0-9_/-]([A-Za-z0-9_/-]{5,})$/\1/' || true)"
  [[ -n "$mac" || -n "$serial" ]] && printf '%s|%s|HTTP scrape' "$mac" "$serial"
}
try_9100(){
  local ip="$1" txt mac serial
  [[ "$SKIP_9100" -eq 1 ]] && return 0
  has_cmd nc || return 0
  txt="$(printf '^XA^HH^XZ\r\n' | nc -w "$TIMEOUT" "$ip" 9100 2>/dev/null || true)"
  [[ -z "$txt" ]] && return 0
  mac="$(printf '%s' "$txt" | grep -Eio '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|[0-9A-Fa-f]{12}' | head -n1 || true)"
  mac="$(norm_mac "$mac")"
  serial="$(printf '%s' "$txt" | grep -Eio '(Serial Number|Serial|S/N)[^A-Za-z0-9]{0,12}[A-Za-z0-9_/-]{5,}' | head -n1 | sed -E 's/.*[^A-Za-z0-9_/-]([A-Za-z0-9_/-]{5,})$/\1/' || true)"
  [[ -n "$mac" || -n "$serial" ]] && printf '%s|%s|9100 ZPL ^HH' "$mac" "$serial"
}
try_arp(){
  local ip="$1" out mac
  out="$(arp -a "$ip" 2>/dev/null || true)"
  mac="$(printf '%s' "$out" | grep -Eio '([0-9a-f]{2}[:-]){5}[0-9a-f]{2}' | head -n1 || true)"
  mac="$(norm_mac "$mac")"
  [[ -n "$mac" ]] && printf '%s|ARP cache' "$mac"
}

csv_escape(){ local s="${1:-}" q='"'; s="${s//$q/$q$q}"; printf '"%s"' "$s"; }
{
  printf 'Timestamp,Target,ResolvedAddress,PingStatus,MAC,Serial,Source,Notes\n'
  for target in "${TARGETS[@]}"; do
    ip="$(resolve_ip "$target")"; [[ -z "$ip" ]] && ip="$target"
    ping="$(ping_status "$ip")"
    mac=""; serial=""; source=(); notes=()
    snmp_s="$(try_snmp_serial "$ip" || true)"; if [[ -n "$snmp_s" ]]; then serial="${snmp_s%%|*}"; source+=("${snmp_s#*|}"); fi
    snmp_m="$(try_snmp_mac "$ip" || true)"; if [[ -n "$snmp_m" ]]; then mac="${snmp_m%%|*}"; source+=("${snmp_m#*|}"); fi
    if [[ "$SNMP_ONLY" -eq 0 ]]; then
      if [[ -z "$mac" || -z "$serial" ]]; then
        http="$(try_http "$ip" || true)"; if [[ -n "$http" ]]; then IFS='|' read -r hmac hserial hsrc <<< "$http"; [[ -z "$mac" ]] && mac="$hmac"; [[ -z "$serial" ]] && serial="$hserial"; source+=("$hsrc"); fi
      fi
      if [[ -z "$mac" || -z "$serial" ]]; then
        zpl="$(try_9100 "$ip" || true)"; if [[ -n "$zpl" ]]; then IFS='|' read -r zmac zserial zsrc <<< "$zpl"; [[ -z "$mac" ]] && mac="$zmac"; [[ -z "$serial" ]] && serial="$zserial"; source+=("$zsrc"); fi
      fi
      if [[ -z "$mac" ]]; then
        arpval="$(try_arp "$ip" || true)"; if [[ -n "$arpval" ]]; then mac="${arpval%%|*}"; source+=("${arpval#*|}"); fi
      fi
    fi
    [[ -z "$mac" ]] && notes+=("MAC unavailable")
    [[ -z "$serial" ]] && notes+=("Serial unavailable")
    [[ "$ping" != "Reachable" ]] && notes+=("Ping failed or ICMP blocked")
    csv_escape "$(date '+%Y-%m-%d %H:%M:%S')"; printf ','; csv_escape "$target"; printf ','; csv_escape "$ip"; printf ','; csv_escape "$ping"; printf ','; csv_escape "$mac"; printf ','; csv_escape "$serial"; printf ','; csv_escape "$(IFS=' | '; echo "${source[*]:-}")"; printf ','; csv_escape "$(IFS='; '; echo "${notes[*]:-}")"; printf '\n'
  done
} > "$OUTPUT"
log "Wrote printer probe CSV: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
