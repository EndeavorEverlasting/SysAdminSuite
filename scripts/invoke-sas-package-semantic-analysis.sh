#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE_WRAPPER="$ROOT/scripts/invoke-sas-package-static-analysis.sh"
SEMANTIC="$ROOT/tools/package-analysis/enrich_package_semantics.py"
VENV="$ROOT/.venv/package-analysis"
INPUT=""
OUTPUT=""
CREATE_VENV=0
WHEELHOUSE=""
MAX_FILES=50000
MAX_TOTAL_BYTES=107374182400
MAX_CONTENT_BYTES=8388608
MAX_SEMANTIC_BYTES=16777216

usage() {
  cat <<'USAGE'
Usage: invoke-sas-package-semantic-analysis.sh --input PATH [options]

Options:
  --output DIR
  --create-venv
  --offline-wheelhouse DIR
  --max-files N
  --max-total-bytes N
  --max-content-bytes N
  --max-semantic-bytes N
USAGE
}

while (($#)); do
  case "$1" in
    --input) INPUT=${2:?missing value}; shift 2 ;;
    --output) OUTPUT=${2:?missing value}; shift 2 ;;
    --create-venv) CREATE_VENV=1; shift ;;
    --offline-wheelhouse) WHEELHOUSE=${2:?missing value}; shift 2 ;;
    --max-files) MAX_FILES=${2:?missing value}; shift 2 ;;
    --max-total-bytes) MAX_TOTAL_BYTES=${2:?missing value}; shift 2 ;;
    --max-content-bytes) MAX_CONTENT_BYTES=${2:?missing value}; shift 2 ;;
    --max-semantic-bytes) MAX_SEMANTIC_BYTES=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$INPUT" ]] || { echo "--input is required" >&2; exit 2; }
[[ -e "$INPUT" ]] || { echo "Input path does not exist: $INPUT" >&2; exit 2; }
[[ -f "$BASE_WRAPPER" ]] || { echo "Base analyzer wrapper is missing: $BASE_WRAPPER" >&2; exit 2; }
[[ -f "$SEMANTIC" ]] || { echo "Semantic analyzer is missing: $SEMANTIC" >&2; exit 2; }
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$ROOT/survey/output/package_semantic_analysis/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTPUT"

base_args=(--input "$INPUT" --output "$OUTPUT" --max-files "$MAX_FILES" --max-total-bytes "$MAX_TOTAL_BYTES" --max-content-bytes "$MAX_CONTENT_BYTES")
if [[ $CREATE_VENV -eq 1 ]]; then base_args+=(--create-venv); fi
if [[ -n "$WHEELHOUSE" ]]; then base_args+=(--offline-wheelhouse "$WHEELHOUSE"); fi

printf '%s\n' 'PACKAGE SEMANTIC ANALYSIS' "Input: $INPUT" "Output: $OUTPUT" 'Phase 1: canonical static inventory and hash evidence'
bash "$BASE_WRAPPER" "${base_args[@]}"

BASE_RESULT="$OUTPUT/package_analysis.json"
[[ -f "$BASE_RESULT" ]] || { echo "Base package result is missing: $BASE_RESULT" >&2; exit 2; }
PYTHON=${PYTHON:-python3}
if [[ $CREATE_VENV -eq 1 && -x "$VENV/bin/python" ]]; then PYTHON="$VENV/bin/python"; fi

printf '%s\n' 'Phase 2: hash-verified semantic enrichment and harness requirements'
"$PYTHON" "$SEMANTIC" --input "$INPUT" --base-result "$BASE_RESULT" --output-dir "$OUTPUT" --max-files "$MAX_FILES" --max-semantic-bytes "$MAX_SEMANTIC_BYTES"
printf '[PASS] Static and semantic package evidence written to %s\n' "$OUTPUT"
