#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANALYZER="$ROOT/tools/package-analysis/analyze_package.py"
REQUIREMENTS="$ROOT/tools/package-analysis/requirements-optional.txt"
VENV="$ROOT/.venv/package-analysis"
INPUT=""
OUTPUT=""
CREATE_VENV=0
WHEELHOUSE=""
MAX_FILES=50000
MAX_TOTAL_BYTES=107374182400
MAX_CONTENT_BYTES=8388608

usage() {
  cat <<'EOF'
Usage: invoke-sas-package-static-analysis.sh --input PATH [options]

Options:
  --output DIR
  --create-venv
  --offline-wheelhouse DIR   Requires --create-venv; pip uses --no-index.
  --max-files N
  --max-total-bytes N
  --max-content-bytes N
EOF
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
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$INPUT" ]] || { echo "--input is required" >&2; exit 2; }
[[ -e "$INPUT" ]] || { echo "Input path does not exist: $INPUT" >&2; exit 2; }
[[ -f "$ANALYZER" ]] || { echo "Analyzer is missing: $ANALYZER" >&2; exit 2; }
if [[ -n "$WHEELHOUSE" && $CREATE_VENV -ne 1 ]]; then
  echo "--offline-wheelhouse requires --create-venv" >&2
  exit 2
fi
if [[ -n "$WHEELHOUSE" && ! -d "$WHEELHOUSE" ]]; then
  echo "Offline wheelhouse does not exist: $WHEELHOUSE" >&2
  exit 2
fi
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$ROOT/survey/output/package_static_analysis/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTPUT"

PYTHON=${PYTHON:-python3}
if [[ $CREATE_VENV -eq 1 ]]; then
  if [[ ! -x "$VENV/bin/python" ]]; then
    "$PYTHON" -m venv "$VENV"
  fi
  PYTHON="$VENV/bin/python"
  if [[ -n "$WHEELHOUSE" ]]; then
    "$PYTHON" -m pip install --disable-pip-version-check --no-index --find-links "$WHEELHOUSE" -r "$REQUIREMENTS"
  fi
fi

printf '%s\n' \
  'PACKAGE STATIC ANALYSIS' \
  "Input: $INPUT" \
  "Output: $OUTPUT" \
  'Posture: static-only; no package execution, extraction, network activity, or host mutation'

"$PYTHON" "$ANALYZER" \
  --input "$INPUT" \
  --output-dir "$OUTPUT" \
  --max-files "$MAX_FILES" \
  --max-total-bytes "$MAX_TOTAL_BYTES" \
  --max-content-bytes "$MAX_CONTENT_BYTES"

printf '[PASS] Static package evidence written to %s\n' "$OUTPUT"
