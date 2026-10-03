#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERIFIER="$ROOT/tools/package-analysis/verify_dotnet_strong_name.py"
INPUT=""
BASE_RESULT=""
OUTPUT=""
MAX_FILES=50000

usage() {
  cat <<'USAGE'
Usage: invoke-sas-package-strong-name-verification.sh --input PATH --base-result PATH [options]

Options:
  --output DIR
  --max-files N
USAGE
}

while (($#)); do
  case "$1" in
    --input) INPUT=${2:?missing value}; shift 2 ;;
    --base-result) BASE_RESULT=${2:?missing value}; shift 2 ;;
    --output) OUTPUT=${2:?missing value}; shift 2 ;;
    --max-files) MAX_FILES=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$INPUT" ]] || { echo "--input is required" >&2; exit 2; }
[[ -n "$BASE_RESULT" ]] || { echo "--base-result is required" >&2; exit 2; }
[[ -e "$INPUT" ]] || { echo "Input path does not exist: $INPUT" >&2; exit 2; }
[[ -f "$BASE_RESULT" ]] || { echo "Base package result is missing: $BASE_RESULT" >&2; exit 2; }
[[ -f "$VERIFIER" ]] || { echo "Strong-name verifier is missing: $VERIFIER" >&2; exit 2; }
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$ROOT/survey/output/package_strong_name_verification/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTPUT"

python_bin=""
if command -v python3 >/dev/null 2>&1; then
  python_bin=python3
elif command -v python >/dev/null 2>&1; then
  python_bin=python
else
  echo "Python 3 is required but was not found on PATH." >&2
  exit 2
fi

printf '%s\n' 'PACKAGE STRONG-NAME VERIFICATION' "Input: $INPUT" "Base result: $BASE_RESULT" "Output: $OUTPUT"
"$python_bin" "$VERIFIER" \
  --input "$INPUT" \
  --base-result "$BASE_RESULT" \
  --output-dir "$OUTPUT" \
  --max-files "$MAX_FILES"
