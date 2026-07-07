#!/usr/bin/env bash
set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

CONVENTIONS=()
USED_NAMES=()
OUTPUT_DIR="survey/output/hostname-availability"
ARTIFACT_DIR="survey/artifacts/hostname-availability"
RUN_ID="$(date '+%Y%m%d_%H%M%S')"
CANDIDATE_COUNT=10
MAX_GAP_SCAN=5000
SUFFIX_MODE="numeric"
SUFFIX_WIDTH=3
AD_EXPORT=0
AD_SERVER=""
TRACKER_WORKBOOK=""
TICKET_WORKBOOK=""
DNS_CHECK=0
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Hostname Availability Survey

Usage:
  bash survey/sas-survey-hostname-availability.sh \
    --convention WNH270OPR \
    --suffix-mode numeric --width 3 \
    --ad-export \
    --tracker-workbook /path/to/tracker.xlsx \
    --dns-check

Usage, saved evidence only:
  bash survey/sas-survey-hostname-availability.sh \
    --convention WNH270OPR \
    --used-names survey/fixtures/hostname_availability_sample.txt \
    --suffix-mode numeric --width 3

Options:
  --convention PREFIX         Naming prefix (e.g. WNH270OPR). Repeatable.
  --suffix-mode MODE          alphabetic or numeric. Default: numeric
  --width N                   Numeric suffix width. Default: 3
  --used-names PATH           Saved evidence CSV/text/XML. Repeatable.
  --ad-export                 Export AD computers matching each convention prefix (read-only).
  --ad-server FQDN            Optional domain controller for AD export.
  --tracker-workbook PATH     Deployment tracker .xlsx for hostname columns.
  --ticket-workbook PATH      Ticket tracker .xlsx (Hostname Used column).
  --dns-check                 Forward DNS lookup on occupied names and reported candidates.
  --output-dir PATH           Output folder. Default: survey/output/hostname-availability
  --artifact-dir PATH         Evidence artifacts. Default: survey/artifacts/hostname-availability
  --run-id VALUE              Run identifier for output filenames.
  --candidate-count N         Candidates per convention. Default: 10.
  --max-gap-scan N            Max ordinal for gap scan. Default: 5000.
  --pass-thru                 Print summary CSV after writing.
  -h, --help                  Show help.

Safety:
  Read-only. Does not rename devices or modify AD/DNS/tracker data.
  Generated outputs may contain operational hostnames. Do not commit them.
USAGE
}

fail(){ echo "[hostname-survey] ERROR: $*" >&2; exit 1; }
log(){ echo "[hostname-survey] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --convention) CONVENTIONS+=("${2:?}"); shift 2 ;;
    --used-names) USED_NAMES+=("${2:?}"); shift 2 ;;
    --suffix-mode) SUFFIX_MODE="${2:?}"; shift 2 ;;
    --width) SUFFIX_WIDTH="${2:?}"; shift 2 ;;
    --ad-export) AD_EXPORT=1; shift ;;
    --ad-server) AD_SERVER="${2:?}"; shift 2 ;;
    --tracker-workbook) TRACKER_WORKBOOK="${2:?}"; shift 2 ;;
    --ticket-workbook) TICKET_WORKBOOK="${2:?}"; shift 2 ;;
    --dns-check) DNS_CHECK=1; shift ;;
    --output-dir) OUTPUT_DIR="${2:?}"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="${2:?}"; shift 2 ;;
    --run-id) RUN_ID="${2:?}"; shift 2 ;;
    --candidate-count) CANDIDATE_COUNT="${2:?}"; shift 2 ;;
    --max-gap-scan) MAX_GAP_SCAN="${2:?}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

[[ "${#CONVENTIONS[@]}" -gt 0 ]] || fail "At least one --convention is required"
[[ "$SUFFIX_MODE" == "alphabetic" || "$SUFFIX_MODE" == "numeric" ]] || fail "--suffix-mode must be alphabetic or numeric"
[[ "$CANDIDATE_COUNT" =~ ^[0-9]+$ && "$CANDIDATE_COUNT" -ge 1 ]] || fail "--candidate-count must be >= 1"
[[ "$MAX_GAP_SCAN" =~ ^[0-9]+$ ]] || fail "--max-gap-scan must be numeric"
[[ "$SUFFIX_WIDTH" =~ ^[0-9]+$ && "$SUFFIX_WIDTH" -ge 1 ]] || fail "--width must be >= 1"

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
ANALYZER="survey/sas-hostname-availability.py"
[[ -f "$ANALYZER" ]] || fail "Analyzer not found: $ANALYZER"

mkdir -p "$OUTPUT_DIR" "$ARTIFACT_DIR"

if [[ "$AD_EXPORT" -eq 1 ]]; then
  AD_SCRIPT="survey/sas-ad-computer-prefix-export.ps1"
  [[ -f "$AD_SCRIPT" ]] || fail "AD export script not found: $AD_SCRIPT"
  idx=1
  for convention in "${CONVENTIONS[@]}"; do
    prefix="$(echo "$convention" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
    ad_out="$ARTIFACT_DIR/${RUN_ID}_ad_${idx}_${prefix}.csv"
    log "Exporting AD prefix evidence: $prefix"
    if [[ -n "$AD_SERVER" ]]; then
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$AD_SCRIPT" -Prefix "$prefix" -Output "$ad_out" -Server "$AD_SERVER"
    else
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$AD_SCRIPT" -Prefix "$prefix" -Output "$ad_out"
    fi
    USED_NAMES+=("$ad_out")
    idx=$((idx + 1))
  done
fi

if [[ -n "$TRACKER_WORKBOOK" || -n "$TICKET_WORKBOOK" ]]; then
  tracker_out="$ARTIFACT_DIR/${RUN_ID}_tracker_hostnames.csv"
  EXTRACT_ARGS=(--output "$tracker_out")
  [[ -n "$TRACKER_WORKBOOK" ]] && EXTRACT_ARGS+=(--workbook "$TRACKER_WORKBOOK")
  [[ -n "$TICKET_WORKBOOK" ]] && EXTRACT_ARGS+=(--ticket-workbook "$TICKET_WORKBOOK")
  log "Extracting tracker hostname evidence"
  bash survey/sas-extract-tracker-hostnames.sh "${EXTRACT_ARGS[@]}"
  USED_NAMES+=("$tracker_out")
fi

run_analyzer(){
  local summary="$1" detail="$2" dashboard="$3"
  local -a args=()
  for convention in "${CONVENTIONS[@]}"; do args+=(--convention "$convention"); done
  for evidence in "${USED_NAMES[@]}"; do args+=(--used-names "$evidence"); done
  args+=(
    --suffix-mode "$SUFFIX_MODE"
    --width "$SUFFIX_WIDTH"
    --summary-output "$summary"
    --detail-output "$detail"
    --dashboard "$dashboard"
    --candidate-count "$CANDIDATE_COUNT"
    --max-gap-scan "$MAX_GAP_SCAN"
  )
  python3 "$ANALYZER" "${args[@]}"
}

SUMMARY_OUT="$OUTPUT_DIR/${RUN_ID}_hostname_availability_summary.csv"
DETAIL_OUT="$OUTPUT_DIR/${RUN_ID}_hostname_availability_detail.csv"
DASHBOARD_OUT="$OUTPUT_DIR/${RUN_ID}_hostname_availability.html"

if [[ "${#USED_NAMES[@]}" -eq 0 ]]; then
  fail "Supply --used-names, --ad-export, and/or --tracker-workbook evidence"
fi

run_analyzer "$SUMMARY_OUT" "$DETAIL_OUT" "$DASHBOARD_OUT"

if [[ "$DNS_CHECK" -eq 1 ]]; then
  DNS_LIST="$ARTIFACT_DIR/${RUN_ID}_dns_check_hostnames.txt"
  python3 - "$DETAIL_OUT" "$SUMMARY_OUT" "$DNS_LIST" <<'PY'
import csv, sys
detail, summary, out = sys.argv[1:4]
names = set()
with open(detail, newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        name = (row.get("Name") or "").strip().upper()
        if name:
            names.add(name)
with open(summary, newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        for field in ("FirstGapName", "NextAfterHighestName", "GapCandidates", "NextCandidates"):
            for part in (row.get(field) or "").split(";"):
                part = part.strip().upper()
                if part:
                    names.add(part)
with open(out, "w", encoding="utf-8") as handle:
    for name in sorted(names):
        handle.write(name + "\n")
PY
  if [[ -s "$DNS_LIST" ]]; then
    dns_out="$ARTIFACT_DIR/${RUN_ID}_dns_evidence.csv"
    log "Running forward DNS checks"
    bash survey/sas-dns-hostname-evidence.sh --hostnames-file "$DNS_LIST" --output "$dns_out"
    USED_NAMES+=("$dns_out")
    run_analyzer "$SUMMARY_OUT" "$DETAIL_OUT" "$DASHBOARD_OUT"
  fi
fi

log "Summary CSV: $SUMMARY_OUT"
log "Detail CSV: $DETAIL_OUT"
log "Dashboard HTML: $DASHBOARD_OUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$SUMMARY_OUT" || true
