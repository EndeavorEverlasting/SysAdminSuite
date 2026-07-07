#!/usr/bin/env bash
# Read-only forward DNS checks for hostname naming evidence.
set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

HOSTNAMES=()
HOSTNAME_FILE=""
OUTPUT=""
TIMEOUT=3

usage(){ cat <<'USAGE'
SysAdminSuite DNS Hostname Evidence

Usage:
  bash survey/sas-dns-hostname-evidence.sh --hostname WNH270OPR001 ...
  bash survey/sas-dns-hostname-evidence.sh --hostnames-file names.txt --output evidence.csv

Options:
  --hostname VALUE        Hostname to check. Repeatable.
  --hostnames-file PATH   One hostname per line (# comments allowed).
  --output PATH           Output CSV path (required).
  --timeout SEC           Lookup timeout hint. Default: 3
  -h, --help              Show help

Read-only. Does not modify DNS.
USAGE
}

fail(){ echo "[dns-hostname] ERROR: $*" >&2; exit 1; }
trim(){ local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

resolve_host(){
  local host="$1"
  local ip=""
  if has_cmd getent; then
    ip="$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1; exit}')"
  elif has_cmd nslookup; then
    ip="$(nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2}' | tail -n 1)"
  fi
  if [[ -n "$ip" ]]; then
    printf 'Resolved|%s' "$ip"
  else
    printf 'NoRecord|'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname) HOSTNAMES+=("${2:?}"); shift 2 ;;
    --hostnames-file) HOSTNAME_FILE="${2:?}"; shift 2 ;;
    --output) OUTPUT="${2:?}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

[[ -n "$OUTPUT" ]] || fail "--output is required"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || fail "--timeout must be numeric"

if [[ -n "$HOSTNAME_FILE" ]]; then
  [[ -f "$HOSTNAME_FILE" ]] || fail "hostnames file not found: $HOSTNAME_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    HOSTNAMES+=("$line")
  done < "$HOSTNAME_FILE"
fi

[[ "${#HOSTNAMES[@]}" -gt 0 ]] || fail "No hostnames supplied"
mkdir -p "$(dirname "$OUTPUT")"

{
  printf '"HostName","LookupStatus","ResolvedAddress","EvidenceSource"\n'
  for host in "${HOSTNAMES[@]}"; do
    host="$(echo "$host" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
    [[ -n "$host" ]] || continue
    result="$(resolve_host "$host")"
    status="${result%%|*}"
    ip="${result#*|}"
    printf '"%s","%s","%s","dns_forward"\n' "$host" "$status" "$ip"
  done
} > "$OUTPUT"

echo "[dns-hostname] Wrote DNS evidence: $OUTPUT (${#HOSTNAMES[@]} hostnames)" >&2
