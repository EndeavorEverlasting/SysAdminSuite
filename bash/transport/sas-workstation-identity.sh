#!/usr/bin/env bash
# SysAdminSuite Bash workstation/Cybernet identity adapter
# Read-only identity collection with ordered transports.
# Current transports: DNS, ping, ARP, optional SSH. Future: WMI/RPC, SMB, WinRM, vendor/API.

set -euo pipefail

TARGETS=()
TARGET_FILE=""
OUTPUT="bash/transport/output/workstation_identity.csv"
TIMEOUT=5
ALLOW_SSH=0
SSH_USER=""
SSH_KEY=""
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Workstation Identity Adapter

Usage:
  ./bash/transport/sas-workstation-identity.sh [options] TARGET...

Options:
  --target VALUE       Add hostname/IP target
  --targets-file PATH  TXT/CSV-ish file with targets, one per line or first comma field
  --output PATH        Output CSV path
  --timeout SEC        Per-target timeout. Default: 5
  --allow-ssh          Enable SSH read-only identity commands
  --ssh-user USER      SSH username, required when --allow-ssh is used
  --ssh-key PATH       Optional SSH private key
  --pass-thru          Print CSV after writing
  -h, --help           Show help

Output columns:
  Timestamp,Target,ResolvedAddress,PingStatus,DnsName,ObservedHostName,ObservedSerial,ObservedMACs,TransportUsed,IdentityStatus,Notes

Safety:
  - Read-only.
  - SSH is disabled unless explicitly enabled.
  - No remote staging, no scheduled tasks, no registry edits, no printer mapping.

Known limitation:
  Bash alone cannot natively perform Windows WMI/DCOM. This adapter is structured so an approved WMI/RPC/SMB bridge can be added later without changing downstream audit tools.
USAGE
}

fail(){ printf '[workstation-identity] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[workstation-identity] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
trim(){ local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
csv_escape(){ local s="${1:-}"; s="${s//"/""}"; printf '"%s"' "$s"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGETS+=("${2:?missing value for --target}"); shift 2 ;;
    --targets-file) TARGET_FILE="${2:?missing value for --targets-file}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?missing value for --timeout}"; shift 2 ;;
    --allow-ssh) ALLOW_SSH=1; shift ;;
    --ssh-user) SSH_USER="${2:?missing value for --ssh-user}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:?missing value for --ssh-key}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do TARGETS+=("$1"); shift; done ;;
    -*) fail "Unknown option: $1" ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -ge 1 ]] || fail "--timeout must be positive integer"
if [[ "$ALLOW_SSH" -eq 1 && -z "$SSH_USER" ]]; then fail "--ssh-user is required with --allow-ssh"; fi
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
  else printf '%s' "$(trim "$raw")"; fi
}
resolve_ip(){ if has_cmd getent; then getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1; exit}'; else printf ''; fi; }
resolve_name(){ if has_cmd getent; then getent hosts "$1" 2>/dev/null | awk 'NR==1{print $2; exit}'; else printf ''; fi; }
ping_status(){ if ping -c 1 -W "$TIMEOUT" "$1" >/dev/null 2>&1; then printf 'Reachable'; else printf 'NoPing'; fi; }
arp_mac(){ local out mac; out="$(arp -a "$1" 2>/dev/null || true)"; mac="$(printf '%s' "$out" | grep -Eio '([0-9a-f]{2}[:-]){5}[0-9a-f]{2}' | head -n1 || true)"; norm_mac "$mac"; }
ssh_identity(){
  local target="$1" dest cmd result lines host serial macs note
  [[ "$ALLOW_SSH" -eq 1 ]] || { printf '|||SSHDisabled'; return; }
  has_cmd ssh || { printf '|||SSHNotInstalled'; return; }
  dest="${SSH_USER}@${target}"
  cmd=(ssh -o BatchMode=yes -o ConnectTimeout="$TIMEOUT")
  [[ -n "$SSH_KEY" ]] && cmd+=(-i "$SSH_KEY")
  cmd+=("$dest" "hostname; (cat /sys/class/dmi/id/product_serial 2>/dev/null || dmidecode -s system-serial-number 2>/dev/null || wmic bios get serialnumber 2>/dev/null | awk 'NR==2{print}' || true); (ip link 2>/dev/null | awk '/link\/ether/ {print \$2}' | paste -sd ';' - || getmac 2>/dev/null | awk '/[0-9A-Fa-f][:-]/{print \$1}' | paste -sd ';' - || true)")
  if ! result="$("${cmd[@]}" 2>&1)"; then
    note="SSHFailed:$(printf '%s' "$result" | head -c 120)"
    printf '|||%s' "$note"
    return
  fi
  mapfile -t lines <<< "$result"
  host="$(trim "${lines[0]:-}")"; serial="$(trim "${lines[1]:-}")"; macs="$(trim "${lines[2]:-}")"
  printf '%s|%s|%s|SSH' "$host" "$serial" "$macs"
}
identity_status(){
  local ping="$1" host="$2" serial="$3" macs="$4"
  if [[ -n "$host" || -n "$serial" || -n "$macs" ]]; then printf 'IdentityCollected'; return; fi
  if [[ "$ping" == "Reachable" ]]; then printf 'ReachableNeedsApprovedIdentityTransport'; return; fi
  printf 'UnreachableOrBlocked'
}

{
  printf 'Timestamp,Target,ResolvedAddress,PingStatus,DnsName,ObservedHostName,ObservedSerial,ObservedMACs,TransportUsed,IdentityStatus,Notes\n'
  for target in "${TARGETS[@]}"; do
    ip="$(resolve_ip "$target")"; dns="$(resolve_name "${ip:-$target}")"; ping="$(ping_status "${ip:-$target}")"
    observed_host=""; observed_serial=""; observed_macs=""; transport=""; notes=()
    if [[ "$ALLOW_SSH" -eq 1 ]]; then
      ssh_out="$(ssh_identity "${ip:-$target}")"
      IFS='|' read -r observed_host observed_serial observed_macs transport <<< "$ssh_out"
      [[ "$transport" == SSHFailed:* || "$transport" == SSHNotInstalled || "$transport" == SSHDisabled ]] && notes+=("$transport") && transport=""
    fi
    if [[ -z "$observed_macs" ]]; then
      amac="$(arp_mac "${ip:-$target}")"; [[ -n "$amac" ]] && observed_macs="$amac" && transport="${transport:+$transport+}ARP"
    fi
    [[ -z "$ip" ]] && notes+=("DNS unresolved")
    [[ "$ping" != "Reachable" ]] && notes+=("ICMP failed or blocked")
    status="$(identity_status "$ping" "$observed_host" "$observed_serial" "$observed_macs")"
    csv_escape "$(date '+%Y-%m-%d %H:%M:%S')"; printf ','; csv_escape "$target"; printf ','; csv_escape "$ip"; printf ','; csv_escape "$ping"; printf ','; csv_escape "$dns"; printf ','; csv_escape "$observed_host"; printf ','; csv_escape "$observed_serial"; printf ','; csv_escape "$observed_macs"; printf ','; csv_escape "$transport"; printf ','; csv_escape "$status"; printf ','; csv_escape "$(IFS='; '; echo "${notes[*]:-}")"; printf '\n'
  done
} > "$OUTPUT"
log "Wrote workstation identity CSV: $OUTPUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
