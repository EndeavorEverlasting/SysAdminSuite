#!/usr/bin/env bash
# SysAdminSuite Alejandro-vs-tracker Cybernet serial diff (read-only workbook inputs)
set -euo pipefail

usage() {
  cat <<'USAGE'
Cybernet Alejandro/tracker serial diff

Usage:
  bash survey/sas-cybernet-tracker-diff.sh --alejandro PATH.xlsx --tracker PATH.xlsx [options]

Options:
  --alejandro PATH          Alejandro-style Cybernet workbook (required)
  --tracker PATH            Deployment tracker workbook (required)
  --tracker-sheet NAME      Default: Deployments
  --output-prefix PREFIX    Default: survey/output/cybernet
  --device-type TYPE        Default: Cybernet
  --header-scan-rows N      Default: 40
  --identity-csv PATH       Optional workstation_identity.csv (enrichment evidence)
  --preflight-csv PATH      Optional network_preflight.csv (ping reachability)
  --ad-serial-csv PATH      Optional AD live-serial export (enrichment candidates)
  --no-progress             Suppress the tech-visible progress bar line
  -h, --help                Show help

Outputs:
  PREFIX_alejandro_unique_serials.csv
  PREFIX_tracker_unique_serials.csv
  PREFIX_alejandro_already_tracked.csv
  PREFIX_alejandro_untracked.csv
  PREFIX_tracker_duplicate_exceptions.csv
  PREFIX_progress_summary.json
  PREFIX_progress_summary.csv
USAGE
}

ALEJANDRO=""
TRACKER=""
TRACKER_SHEET="Deployments"
OUTPUT_PREFIX="survey/output/cybernet"
DEVICE_TYPE="Cybernet"
HEADER_SCAN_ROWS="40"
IDENTITY_CSV=""
PREFLIGHT_CSV=""
AD_SERIAL_CSV=""
NO_PROGRESS=""
PYTHON_CMD=()

find_python() {
  if [[ ${#PYTHON_CMD[@]} -gt 0 ]]; then return 0; fi
  if command -v python3 >/dev/null 2>&1; then PYTHON_CMD=(python3); return 0; fi
  if command -v python >/dev/null 2>&1; then PYTHON_CMD=(python); return 0; fi
  if command -v py >/dev/null 2>&1; then PYTHON_CMD=(py -3); return 0; fi
  echo "[sas-cybernet-tracker-diff] ERROR: Python 3 required" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --alejandro) ALEJANDRO="${2:?}"; shift 2 ;;
    --tracker) TRACKER="${2:?}"; shift 2 ;;
    --tracker-sheet) TRACKER_SHEET="${2:?}"; shift 2 ;;
    --output-prefix) OUTPUT_PREFIX="${2:?}"; shift 2 ;;
    --device-type) DEVICE_TYPE="${2:?}"; shift 2 ;;
    --header-scan-rows) HEADER_SCAN_ROWS="${2:?}"; shift 2 ;;
    --identity-csv) IDENTITY_CSV="${2:?}"; shift 2 ;;
    --preflight-csv) PREFLIGHT_CSV="${2:?}"; shift 2 ;;
    --ad-serial-csv) AD_SERIAL_CSV="${2:?}"; shift 2 ;;
    --no-progress) NO_PROGRESS="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[sas-cybernet-tracker-diff] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$ALEJANDRO" ]] || { echo "[sas-cybernet-tracker-diff] ERROR: --alejandro required" >&2; exit 1; }
[[ -n "$TRACKER" ]] || { echo "[sas-cybernet-tracker-diff] ERROR: --tracker required" >&2; exit 1; }
[[ "$HEADER_SCAN_ROWS" =~ ^[0-9]+$ && "$HEADER_SCAN_ROWS" -ge 1 ]] || {
  echo "[sas-cybernet-tracker-diff] ERROR: --header-scan-rows must be a positive integer" >&2
  exit 1
}

find_python
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIFF_ARGS=(
  --alejandro "$ALEJANDRO"
  --tracker "$TRACKER"
  --tracker-sheet "$TRACKER_SHEET"
  --output-prefix "$OUTPUT_PREFIX"
  --device-type "$DEVICE_TYPE"
  --header-scan-rows "$HEADER_SCAN_ROWS"
)
[[ -n "$IDENTITY_CSV" ]] && DIFF_ARGS+=(--identity-csv "$IDENTITY_CSV")
[[ -n "$PREFLIGHT_CSV" ]] && DIFF_ARGS+=(--preflight-csv "$PREFLIGHT_CSV")
[[ -n "$AD_SERIAL_CSV" ]] && DIFF_ARGS+=(--ad-serial-csv "$AD_SERIAL_CSV")
[[ -n "$NO_PROGRESS" ]] && DIFF_ARGS+=(--no-progress)
"${PYTHON_CMD[@]}" "$SCRIPT_DIR/sas-cybernet-tracker-diff.py" "${DIFF_ARGS[@]}"
