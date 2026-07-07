#!/usr/bin/env bash
# Cybernet packet follow-up implementation. Prefer survey/sas-cybernet-detect.sh at the CLI edge.
# Reads naabu -silent stdout (host:port). Optional httpx delegation stays behind --use-httpx.
# Enrichment only under low-noise survey doctrine. See docs/LOW_NOISE_SURVEY_DOCTRINE.md.
set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

SITE=""
INPUT=""
USE_STDIN=0
CYBERNET_DETECT=0
USE_HTTPX=0

usage() {
  cat <<'USAGE'
Usage: bash survey/sas-cybernet-packet-followup.sh --site SITE (--stdin | --input PATH) [options]

Reads naabu -silent lines (host:port) and emits JSONL enrichment on stdout.
Stderr carries [packet-followup] logs only — suitable for piping.

Options:
  --site SITE           Site label (required)
  --stdin               Read host:port lines from stdin
  --input PATH          Read host:port lines from file
  --cybernet-detect     Apply Cybernet heuristics (Windows/RDP/web signals)
  --use-httpx           Delegate to httpx -silent -json when on PATH
  -h, --help            Show help
USAGE
}

log() { printf '[packet-followup] %s\n' "$*" >&2; }
fail() { printf '[packet-followup] ERROR: %s\n' "$*" >&2; exit 1; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required"
}

httpx_bin() {
  if command -v httpx.exe >/dev/null 2>&1; then command -v httpx.exe; return 0; fi
  command -v httpx 2>/dev/null || true
}

process_lines() {
  local py
  py="$(find_python)"
  export SITE CYBERNET_DETECT
  "$py" -c '
import json, os, sys
from datetime import datetime, timezone

site = os.environ.get("SITE", "")
detect = os.environ.get("CYBERNET_DETECT", "0") == "1"

def signal(port_s, host):
    try:
        port = int(port_s)
    except ValueError:
        return "unknown"
    if not detect:
        return "open"
    if port in (445, 139):
        return "windows_endpoint"
    if port == 135:
        return "rpc_reachability"
    if port in (5985, 5986):
        return "winrm"
    if port == 3389:
        return "rdp"
    if port in (80, 443, 8080, 8443):
        return "web_reachability"
    if port == 53:
        return "dns_udp" if host.startswith("u:") else "dns"
    if port == 161:
        return "snmp_udp"
    return "open"

for raw in sys.stdin:
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    host, _, port = line.partition(":")
    if not port:
        continue
    row = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "site": site,
        "host": host,
        "port": int(port) if port.isdigit() else port,
        "protocol": "tcp",
        "reachability": "open",
        "cybernet_signal": signal(port, host),
        "source": "naabu_silent_pipe",
    }
    print(json.dumps(row, separators=(",", ":")))
'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:?}"; shift 2 ;;
    --stdin) USE_STDIN=1; shift ;;
    --input) INPUT="${2:?}"; shift 2 ;;
    --cybernet-detect) CYBERNET_DETECT=1; shift ;;
    --use-httpx) USE_HTTPX=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

[[ -n "$SITE" ]] || fail "--site is required"

if [[ "$USE_HTTPX" -eq 1 ]]; then
  hx="$(httpx_bin)"
  if [[ -n "$hx" ]]; then
    log "Delegating to httpx -silent -json"
    if [[ "$USE_STDIN" -eq 1 ]]; then
      "$hx" -silent -json
      exit 0
    fi
    [[ -n "$INPUT" && -f "$INPUT" ]] || fail "--input required with --use-httpx"
    "$hx" -silent -json -l "$INPUT"
    exit 0
  fi
  log "httpx not on PATH; using built-in Cybernet followup"
fi

if [[ "$USE_STDIN" -eq 1 ]]; then
  process_lines
elif [[ -n "$INPUT" ]]; then
  [[ -f "$INPUT" ]] || fail "Input not found: $INPUT"
  process_lines < "$INPUT"
else
  fail "Pass --stdin or --input"
fi
