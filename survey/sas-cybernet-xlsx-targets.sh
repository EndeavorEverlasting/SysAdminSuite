#!/usr/bin/env bash
# SysAdminSuite Cybernet xlsx target ingester (Bash wrapper)
set -euo pipefail

usage() {
  cat <<'USAGE'
Cybernet XLSX target ingester (read-only, offline)

Usage:
  ./survey/sas-cybernet-xlsx-targets.sh --workbook PATH.xlsx [options]

Options:
  --workbook PATH           Primary Alejandro-style workbook (required)
  --enrichment PATH         Optional enrichment workbook (repeatable)
  --output PATH             Manifest CSV (default: survey/output/cybernet_alejandro_targets.csv)
  --report PATH             Enrichment report CSV
  --gaps PATH               Gap report CSV
  --device-type TYPE        Default: Cybernet
  -h, --help                Show help
USAGE
}

WORKBOOK=""
ENRICHMENT=()
OUTPUT="survey/output/cybernet_alejandro_targets.csv"
REPORT="survey/output/cybernet_alejandro_enrichment_report.csv"
GAPS="survey/output/cybernet_alejandro_gaps.csv"
DEVICE_TYPE="Cybernet"
PYTHON_CMD=()

find_python() {
  if [[ ${#PYTHON_CMD[@]} -gt 0 ]]; then return 0; fi
  if command -v python3 >/dev/null 2>&1; then PYTHON_CMD=(python3); return 0; fi
  if command -v python >/dev/null 2>&1; then PYTHON_CMD=(python); return 0; fi
  if command -v py >/dev/null 2>&1; then PYTHON_CMD=(py -3); return 0; fi
  echo "[sas-cybernet-xlsx] ERROR: Python 3 required" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workbook) WORKBOOK="${2:?}"; shift 2 ;;
    --enrichment) ENRICHMENT+=("$2"); shift 2 ;;
    --output) OUTPUT="${2:?}"; shift 2 ;;
    --report) REPORT="${2:?}"; shift 2 ;;
    --gaps) GAPS="${2:?}"; shift 2 ;;
    --device-type) DEVICE_TYPE="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[sas-cybernet-xlsx] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$WORKBOOK" ]] || { echo "[sas-cybernet-xlsx] ERROR: --workbook required" >&2; exit 1; }
find_python
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
args=(--workbook "$WORKBOOK" --output "$OUTPUT" --report "$REPORT" --gaps "$GAPS" --device-type "$DEVICE_TYPE")
for e in "${ENRICHMENT[@]}"; do args+=(--enrichment "$e"); done
"${PYTHON_CMD[@]}" "$SCRIPT_DIR/sas-cybernet-xlsx-targets.py" "${args[@]}"
