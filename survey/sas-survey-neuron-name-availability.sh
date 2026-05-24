#!/usr/bin/env bash
set -euo pipefail

CONVENTIONS=()
TARGETS=()
TARGET_FILE=""
USED_NAMES=()
OUTPUT_DIR="survey/output/neuron-name-availability"
ARTIFACT_DIR="survey/artifacts/neuron-name-availability"
RUN_ID="$(date '+%Y%m%d_%H%M%S')"
CANDIDATE_COUNT=10
MAX_GAP_SCAN=5000
SKIP_NMAP=0
PASS_THRU=0

usage(){ cat <<'USAGE'
SysAdminSuite Neuron Name Availability Survey

Usage:
  bash survey/sas-survey-neuron-name-availability.sh \
    --convention LIJ-MACH- \
    --target 10.10.20.0/24

Options:
  --convention PREFIX     Naming prefix, e.g. LIJ-MACH- or CCMC-MACH-. Repeatable.
  --target CIDR_OR_HOST   Approved nmap target/CIDR. Repeatable.
  --target-file PATH      File containing approved targets/CIDRs, one per line. # comments allowed.
  --used-names PATH       Existing text/CSV evidence containing known names. Repeatable.
  --output-dir PATH       Output folder for summary/detail/dashboard.
  --artifact-dir PATH     Folder for preserved nmap XML/text artifacts.
  --run-id VALUE          Run identifier used in artifact names. Default timestamp.
  --candidate-count N     Candidate names to report per convention. Default 10.
  --max-gap-scan N        Max ordinal to scan for gaps. Default 5000. Use 0 through highest observed.
  --skip-nmap             Do not run nmap. Use --used-names only.
  --pass-thru             Print summary CSV after writing.
  -h, --help              Show help.

Safety:
  This wrapper runs nmap -sn only against explicit approved targets.
  It preserves XML/text artifacts and then parses them. It does not rename devices.
  Generated outputs may contain operational hostnames or site data. Do not commit them.
USAGE
}

fail(){ echo "[neuron-name-survey] ERROR: $*" >&2; exit 1; }
log(){ echo "[neuron-name-survey] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --convention) CONVENTIONS+=("${2:?missing --convention value}"); shift 2 ;;
    --target) TARGETS+=("${2:?missing --target value}"); shift 2 ;;
    --target-file) TARGET_FILE="${2:?missing --target-file value}"; shift 2 ;;
    --used-names) USED_NAMES+=("${2:?missing --used-names value}"); shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?missing --output-dir value}"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="${2:?missing --artifact-dir value}"; shift 2 ;;
    --run-id) RUN_ID="${2:?missing --run-id value}"; shift 2 ;;
    --candidate-count) CANDIDATE_COUNT="${2:?missing --candidate-count value}"; shift 2 ;;
    --max-gap-scan) MAX_GAP_SCAN="${2:?missing --max-gap-scan value}"; shift 2 ;;
    --skip-nmap) SKIP_NMAP=1; shift ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ "${#CONVENTIONS[@]}" -gt 0 ]] || fail "At least one --convention is required"
[[ "$CANDIDATE_COUNT" =~ ^[0-9]+$ ]] || fail "--candidate-count must be numeric"
[[ "$CANDIDATE_COUNT" -ge 1 ]] || fail "--candidate-count must be >= 1"
[[ "$MAX_GAP_SCAN" =~ ^[0-9]+$ ]] || fail "--max-gap-scan must be numeric"

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
ANALYZER="survey/sas-neuron-name-availability.py"
[[ -f "$ANALYZER" ]] || fail "Analyzer not found: $ANALYZER"

if [[ -n "$TARGET_FILE" ]]; then
  [[ -f "$TARGET_FILE" ]] || fail "Target file not found: $TARGET_FILE"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    target="$(echo "$raw" | sed 's/#.*$//' | xargs)"
    [[ -n "$target" ]] && TARGETS+=("$target")
  done < "$TARGET_FILE"
fi

if [[ "$SKIP_NMAP" -eq 0 && "${#TARGETS[@]}" -eq 0 ]]; then
  fail "Supply at least one --target or --target-file, or use --skip-nmap with --used-names evidence"
fi

if [[ "$SKIP_NMAP" -eq 1 && "${#USED_NAMES[@]}" -eq 0 ]]; then
  fail "--skip-nmap requires at least one --used-names evidence file"
fi

mkdir -p "$OUTPUT_DIR" "$ARTIFACT_DIR"

NMAP_XMLS=()
if [[ "$SKIP_NMAP" -eq 0 ]]; then
  command -v nmap >/dev/null 2>&1 || fail "nmap is required unless --skip-nmap is used"
  idx=1
  for target in "${TARGETS[@]}"; do
    safe_target="$(echo "$target" | tr '/:.' '____' | tr -cd 'A-Za-z0-9_-')"
    base="$ARTIFACT_DIR/${RUN_ID}_${idx}_${safe_target}"
    xml_path="${base}.xml"
    normal_path="${base}.nmap"
    log "Running nmap host discovery for approved target: $target"
    nmap -sn "$target" -oX "$xml_path" -oN "$normal_path"
    NMAP_XMLS+=("$xml_path")
    idx=$((idx + 1))
  done
fi

SUMMARY_OUT="$OUTPUT_DIR/${RUN_ID}_neuron_name_availability_summary.csv"
DETAIL_OUT="$OUTPUT_DIR/${RUN_ID}_neuron_name_availability_detail.csv"
DASHBOARD_OUT="$OUTPUT_DIR/${RUN_ID}_neuron_name_availability.html"

ARGS=()
for convention in "${CONVENTIONS[@]}"; do ARGS+=(--convention "$convention"); done
for xml in "${NMAP_XMLS[@]}"; do ARGS+=(--nmap-xml "$xml"); done
for evidence in "${USED_NAMES[@]}"; do ARGS+=(--used-names "$evidence"); done
ARGS+=(--summary-output "$SUMMARY_OUT" --detail-output "$DETAIL_OUT" --dashboard "$DASHBOARD_OUT" --candidate-count "$CANDIDATE_COUNT" --max-gap-scan "$MAX_GAP_SCAN")

python3 "$ANALYZER" "${ARGS[@]}"

log "Summary CSV: $SUMMARY_OUT"
log "Detail CSV: $DETAIL_OUT"
log "Dashboard HTML: $DASHBOARD_OUT"
[[ "$PASS_THRU" -eq 1 ]] && cat "$SUMMARY_OUT" || true
