#!/usr/bin/env bash
# SysAdminSuite Site Subnet Discovery
# Shape: Recon -> Decide -> Act -> Log -> Export
# Read-only local collector for authorized internal support work.

set -Eeuo pipefail

SITE_CODE=""
OUTPUT_ROOT="${USERPROFILE:-${HOME:-.}}/SysAdminSuite/Runs"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/sas_discover_local_subnets.sh --site-code <SITE> [options]

Options:
  --site-code <SITE>       Required site code, e.g. NSUH, LIJMC, CCMC.
  --output-root <path>     Default: $USERPROFILE/SysAdminSuite/Runs.
  --dry-run                Create run folder and show intended local commands.
  -h, --help               Show help.

Purpose:
  Collect local network evidence that can support a site subnet inventory.
  This script does not run nmap and does not mutate the workstation.
EOF
}

fail() { echo "ERROR: $*" >&2; exit 1; }
trim() { local v="$*"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'; }
safe_token() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
portable_hostname() { hostname.exe 2>/dev/null || hostname 2>/dev/null || echo unknown-host; }
portable_whoami() { whoami.exe 2>/dev/null || whoami 2>/dev/null || echo unknown-user; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-code) [[ $# -ge 2 ]] || fail "--site-code requires value"; SITE_CODE="$(trim "$2")"; shift 2 ;;
    --output-root) [[ $# -ge 2 ]] || fail "--output-root requires value"; OUTPUT_ROOT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$SITE_CODE" ]] || fail "--site-code is required"
SITE_TOKEN="$(safe_token "$SITE_CODE")"
HOST="$(portable_hostname)"
STAMP="$(date +"%Y%m%d_%H%M%S")"
RUN_ID="SAS_SITE_SUBNET_DISCOVERY_${SITE_TOKEN}_${HOST}_${STAMP}"
RUN_DIR="$OUTPUT_ROOT/$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
RAW_DIR="$RUN_DIR/raw/local"
EXPORT_DIR="$RUN_DIR/exports"
mkdir -p "$LOG_DIR" "$RAW_DIR" "$EXPORT_DIR"
EVENT_LOG="$LOG_DIR/events.jsonl"
TRACE_LOG="$LOG_DIR/trace.log"

log_event() {
  local stage="$1" level="$2" msg="$3" data="${4:-}" ts
  ts="$(now_iso)"
  printf '{"timestamp":"%s","run_id":"%s","site_code":"%s","stage":"%s","level":"%s","message":"%s","data":"%s"}\n' \
    "$(json_escape "$ts")" "$(json_escape "$RUN_ID")" "$(json_escape "$SITE_CODE")" "$(json_escape "$stage")" "$(json_escape "$level")" "$(json_escape "$msg")" "$(json_escape "$data")" >> "$EVENT_LOG"
  printf '[%s][%s] %s\n' "$stage" "$level" "$msg" | tee -a "$TRACE_LOG" >/dev/null
}

capture() {
  local label="$1" out="$2"; shift 2
  { echo "# $label"; echo "# command: $*"; echo "# captured_at: $(now_iso)"; echo; } > "$out"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN" >> "$out"
    echo "# exit_code: 0" >> "$out"
    return 0
  fi
  set +e
  "$@" >> "$out" 2>&1
  local code=$?
  set -e
  { echo; echo "# exit_code: $code"; } >> "$out"
}

log_event START INFO "Site subnet discovery started"
log_event RECON INFO "Collecting local network evidence"

capture hostname "$RAW_DIR/hostname.txt" hostname.exe
capture whoami "$RAW_DIR/whoami.txt" whoami.exe
capture windows-version "$RAW_DIR/windows_version.txt" cmd.exe /c ver
capture ipconfig "$RAW_DIR/ipconfig_all.txt" cmd.exe /c ipconfig /all
capture route "$RAW_DIR/route_print.txt" cmd.exe /c route print
capture arp "$RAW_DIR/arp_a.txt" cmd.exe /c arp -a
capture getmac "$RAW_DIR/getmac.txt" cmd.exe /c getmac /v /fo list
capture netsh-interface "$RAW_DIR/netsh_interface.txt" cmd.exe /c netsh interface show interface

log_event DECIDE INFO "Building subnet candidate exports"
CANDIDATES="$EXPORT_DIR/local_subnet_candidates.csv"
GATEWAYS="$EXPORT_DIR/local_gateways.csv"
ROUTES="$EXPORT_DIR/local_routes.csv"
JSON="$EXPORT_DIR/site_subnet_candidates.json"
REPORT="$EXPORT_DIR/site_subnet_discovery_report.md"

printf 'site_code,candidate,kind,source,confidence,evidence,notes\n' > "$CANDIDATES"
printf 'site_code,gateway,source,confidence,evidence\n' > "$GATEWAYS"
printf 'site_code,route_line,source,confidence\n' > "$ROUTES"

if [[ "$DRY_RUN" -eq 0 && -s "$RAW_DIR/ipconfig_all.txt" ]]; then
  grep -E "IPv4 Address|Default Gateway" "$RAW_DIR/ipconfig_all.txt" | sed 's/^[[:space:]]*//' > "$EXPORT_DIR/ipconfig_signal_lines.txt" || true
  while IFS= read -r line; do
    value="${line##*:}"
    value="${value//(Preferred)/}"
    value="$(trim "$value")"
    if [[ "$line" == *"IPv4 Address"* && "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf '%s,%s,ipv4,ipconfig,high,IPv4 Address,interface address observed locally\n' "$SITE_CODE" "$value" >> "$CANDIDATES"
    fi
    if [[ "$line" == *"Default Gateway"* && "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf '%s,%s,gateway,ipconfig,medium,Default Gateway,gateway observed locally\n' "$SITE_CODE" "$value" >> "$CANDIDATES"
      printf '%s,%s,ipconfig,medium,Default Gateway\n' "$SITE_CODE" "$value" >> "$GATEWAYS"
    fi
  done < "$EXPORT_DIR/ipconfig_signal_lines.txt"
fi

if [[ "$DRY_RUN" -eq 0 && -s "$RAW_DIR/route_print.txt" ]]; then
  grep -E '^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$RAW_DIR/route_print.txt" | head -200 > "$EXPORT_DIR/route_signal_lines.txt" || true
  while IFS= read -r line; do
    clean="$(echo "$line" | tr ',' ';' | sed 's/^[[:space:]]*//')"
    printf '%s,"%s",route-print,medium\n' "$SITE_CODE" "$clean" >> "$ROUTES"
  done < "$EXPORT_DIR/route_signal_lines.txt"
fi

cat > "$JSON" <<EOF
{"run_id":"$(json_escape "$RUN_ID")","site_code":"$(json_escape "$SITE_CODE")","hostname":"$(json_escape "$HOST")","candidate_csv":"$(json_escape "$CANDIDATES")","gateway_csv":"$(json_escape "$GATEWAYS")","routes_csv":"$(json_escape "$ROUTES")"}
EOF

cat > "$REPORT" <<EOF
# SysAdminSuite Site Subnet Discovery Report

| Field | Value |
|---|---|
| Run ID | $RUN_ID |
| Site Code | $SITE_CODE |
| Hostname | $HOST |
| User | $(portable_whoami) |
| Dry Run | $DRY_RUN |

## Purpose

This report captures local evidence that may identify candidate site subnets. It does not prove ownership, authorization, VLAN scope, or complete subnet coverage.

## Outputs

- Candidate subnet evidence: \`$CANDIDATES\`
- Gateway evidence: \`$GATEWAYS\`
- Route evidence: \`$ROUTES\`
- Raw local evidence: \`$RAW_DIR\`
- Event log: \`$EVENT_LOG\`
EOF

log_event EXPORT INFO "Discovery exports written" "export_dir=$EXPORT_DIR"
log_event END INFO "Site subnet discovery completed" "run_dir=$RUN_DIR"

echo "DONE"
echo "Run Directory: $RUN_DIR"
echo "Report: $REPORT"
