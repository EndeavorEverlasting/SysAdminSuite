#!/usr/bin/env bash
# Minimal Cybernet candidate scan: approved computer host list -> TCP 135+445 only -> local filter.
# Read-only toward targets. No metadata collection. Not a stealth/evasion feature.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_JSON="$REPO_ROOT/Config/cybernet-naabu-profiles.json"
ENSURE_SCRIPT="$SCRIPT_DIR/sas-ensure-naabu.sh"
FILTER_SCRIPT="$SCRIPT_DIR/sas-filter-windows-pc-signature.py"
TARGET_HELPER="$SCRIPT_DIR/lib/sas-target-intake.sh"
NETWORK_GUARD="$SCRIPT_DIR/lib/sas-network-guard.sh"

LIST=""
OUT=""
CANDIDATES_OUT=""
REPORT_OUT=""
DRY_RUN=0
PROFILE="windows_pc_signature_json"

usage() {
  cat <<'USAGE'
SysAdminSuite professional Windows-PC signature scan

Purpose:
  Probe only an approved computer population with TCP 135 and 445, once per port,
  at a bounded rate. Then filter the resulting local evidence so only dual-port
  matches graduate to the Cybernet metadata canary.

This command does not query manufacturer, model, serial, software, shares, services,
credentials, or vulnerability data. It is not a stealth/evasion feature.

Usage:
  bash survey/sas-run-windows-pc-signature.sh --list PATH [options]

Required:
  --list PATH           Approved hostname/IP list from codified intake/staging

Options:
  --out PATH            Naabu JSON evidence (default under logs/nmap/)
  --candidates-out PATH Dual-port candidate host list (default under survey/output/)
  --report-out PATH     Per-host local classification CSV (default under survey/output/)
  --dry-run             Print the exact bounded Naabu command; send no packets
  -h, --help            Show help

The profile contract is Config/cybernet-naabu-profiles.json -> windows_pc_signature_json.
Generated output may contain operational network details. Do not commit it.
USAGE
}

fail() { printf '[pc-signature] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[pc-signature] %s\n' "$*" >&2; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  if command -v py >/dev/null 2>&1; then echo "py -3"; return 0; fi
  fail 'Python 3 is required.'
}

[[ -f "$TARGET_HELPER" ]] || fail "Missing target intake helper: $TARGET_HELPER"
[[ -f "$NETWORK_GUARD" ]] || fail "Missing network guard: $NETWORK_GUARD"
# shellcheck source=survey/lib/sas-target-intake.sh
source "$TARGET_HELPER"
# shellcheck source=survey/lib/sas-network-guard.sh
source "$NETWORK_GUARD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --candidates-out) CANDIDATES_OUT="${2:?}"; shift 2 ;;
    --report-out) REPORT_OUT="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$LIST" ]] || fail '--list is required.'
sas_target_require_input_file "$LIST" 'PC-signature target list' 1 "$REPO_ROOT" || exit 1
[[ -f "$PROFILE_JSON" ]] || fail "Missing generated profile config: $PROFILE_JSON"
[[ -f "$FILTER_SCRIPT" ]] || fail "Missing local signature filter: $FILTER_SCRIPT"

run_id="$(date +%Y%m%d_%H%M%S)"
[[ -n "$OUT" ]] || OUT="logs/nmap/windows_pc_signature_${run_id}.json"
[[ -n "$CANDIDATES_OUT" ]] || CANDIDATES_OUT="survey/output/windows_pc_signature/${run_id}_candidates.txt"
[[ -n "$REPORT_OUT" ]] || REPORT_OUT="survey/output/windows_pc_signature/${run_id}_report.csv"
sas_target_require_output_path "$OUT" 'PC-signature Naabu output' "$REPO_ROOT" || exit 1
sas_target_require_output_path "$CANDIDATES_OUT" 'PC-signature candidate output' "$REPO_ROOT" || exit 1
sas_target_require_output_path "$REPORT_OUT" 'PC-signature report output' "$REPO_ROOT" || exit 1
mkdir -p "$(dirname "$OUT")" "$(dirname "$CANDIDATES_OUT")" "$(dirname "$REPORT_OUT")"

# Explicit computer hosts only. Refuse CIDRs/ranges/wildcards in this lane so an AD/tracker
# population cannot silently turn into an unbounded network sweep.
count=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="${raw%%#*}"
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue
  [[ "$line" != *'/'* ]] || fail "CIDR is not allowed in the professional PC-signature host-list lane: $line"
  [[ "$line" != *'*'* && "$line" != *'?'* && "$line" != *'['* ]] || fail "Wildcard target is not allowed: $line"
  [[ ! "$line" =~ ^[0-9.]+-[0-9.] ]] || fail "IP range is not allowed: $line"
  count=$((count + 1))
done < "$LIST"
[[ "$count" -gt 0 ]] || fail "Target list is empty: $LIST"
[[ "$count" -le 256 ]] || fail "Target list has $count entries; professional PC-signature cap is 256. Split the approved computer population."

py="$(find_python)"
mapfile -t profile_values < <($py - "$PROFILE_JSON" "$PROFILE" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = json.load(fh)
p = cfg.get('profiles', {}).get(sys.argv[2])
if not p:
    raise SystemExit('missing windows_pc_signature_json profile')
if p.get('ports') != '135,445':
    raise SystemExit('PC-signature profile must contain exactly TCP 135,445')
if int(p.get('retries', -1)) != 0:
    raise SystemExit('PC-signature profile must set retries=0')
if int(p.get('defaultRate', 0)) <= 0 or int(p.get('defaultRate', 0)) > 50:
    raise SystemExit('PC-signature profile defaultRate must be in 1..50')
if p.get('outputFormat') != 'json' or p.get('pipelineFollowup'):
    raise SystemExit('PC-signature profile must be JSON with no automatic follow-up')
print(p['ports'])
print(p['retries'])
print(p['defaultRate'])
print('1' if p.get('excludeCdn') else '0')
PY
)
[[ ${#profile_values[@]} -eq 4 ]] || fail 'Could not resolve PC-signature profile.'
ports="${profile_values[0]}"
retries="${profile_values[1]}"
rate="${profile_values[2]}"
exclude_cdn="${profile_values[3]}"

ensure_args=()
[[ "$DRY_RUN" -eq 1 ]] && ensure_args+=(--dry-run)
naabu_bin="$(bash "$ENSURE_SCRIPT" "${ensure_args[@]}")"
[[ -n "$naabu_bin" ]] || fail 'Naabu bootstrap returned no executable path.'
args=(-list "$LIST" -p "$ports" -silent -duc -retries "$retries" -rate "$rate" -json -o "$OUT")
[[ "$exclude_cdn" == '1' ]] && args+=(-ec)

printf '[pc-signature] Targets: %s | ports: %s | retries: %s | rate: %s\n' "$count" "$ports" "$retries" "$rate" >&2
printf '[pc-signature] Metadata collection: NONE\n' >&2
printf '[pc-signature] Candidate rule: BOTH TCP 135 AND 445 observed open\n' >&2

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '[pc-signature] DRY-RUN:' >&2
  printf ' %q' "$naabu_bin" "${args[@]}" >&2
  printf '\n' >&2
  exit 0
fi

sas_require_northwell_wifi
"$naabu_bin" "${args[@]}"
$py "$FILTER_SCRIPT" --input "$OUT" --candidates-out "$CANDIDATES_OUT" --report-out "$REPORT_OUT"

log "Naabu evidence: $OUT"
log "Dual-port candidates: $CANDIDATES_OUT"
log "Classification report: $REPORT_OUT"
log 'Next lane: metadata canary in Windows PowerShell, max five explicit candidates at a time.'
