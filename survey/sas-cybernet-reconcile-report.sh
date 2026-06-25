#!/usr/bin/env bash
# SysAdminSuite Cybernet reconciliation HTML report (read-only local inputs)
set -euo pipefail

usage() {
  cat <<'USAGE'
Cybernet reconciliation HTML report

Usage:
  bash survey/sas-cybernet-reconcile-report.sh --alejandro PATH.xlsx --tracker PATH.xlsx [options]

Options:
  --alejandro PATH          Alejandro-style Cybernet workbook (required)
  --tracker PATH            Deployment tracker workbook (required)
  --tracker-sheet NAME      Default: Deployments
  --identity-csv PATH       workstation_identity.csv; repeatable
  --identity-glob PATTERN   glob for workstation_identity*.csv; repeatable
  --preflight-csv PATH      network_preflight.csv; repeatable
  --output-dir DIR          Default: survey/output/cybernet_reconciliation_report
  --header-scan-rows N      Default: 40
  -h, --help                Show help

Outputs:
  DIR/index.html
  DIR/confirmations.html
  DIR/duplicates.html
  DIR/conflicts.html
  DIR/drift.html
  DIR/unaccounted.html
  DIR/coverage.html
  DIR/remaining.html
  DIR/anomalies.html
  DIR/style.css
  DIR/data.js
USAGE
}

ALEJANDRO=""
TRACKER=""
TRACKER_SHEET="Deployments"
OUTPUT_DIR="survey/output/cybernet_reconciliation_report"
HEADER_SCAN_ROWS="40"
IDENTITY_ARGS=()
PREFLIGHT_ARGS=()
PYTHON_CMD=()

find_python() {
  if [[ ${#PYTHON_CMD[@]} -gt 0 ]]; then return 0; fi
  # Prefer python3, then the py launcher, then bare python. Each candidate is
  # validated by actually running Python 3 so the Windows Store stub (which
  # answers `command -v python` but is not a real interpreter) is skipped.
  local cand
  for cand in "python3" "py -3" "python"; do
    # shellcheck disable=SC2086
    if $cand -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
      # shellcheck disable=SC2206
      PYTHON_CMD=($cand)
      return 0
    fi
  done
  echo "[sas-cybernet-reconcile-report] ERROR: Python 3 required" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --alejandro) ALEJANDRO="${2:?}"; shift 2 ;;
    --tracker) TRACKER="${2:?}"; shift 2 ;;
    --tracker-sheet) TRACKER_SHEET="${2:?}"; shift 2 ;;
    --identity-csv) IDENTITY_ARGS+=(--identity-csv "${2:?}"); shift 2 ;;
    --identity-glob) IDENTITY_ARGS+=(--identity-glob "${2:?}"); shift 2 ;;
    --preflight-csv) PREFLIGHT_ARGS+=(--preflight-csv "${2:?}"); shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?}"; shift 2 ;;
    --header-scan-rows) HEADER_SCAN_ROWS="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[sas-cybernet-reconcile-report] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$ALEJANDRO" ]] || { echo "[sas-cybernet-reconcile-report] ERROR: --alejandro required" >&2; exit 1; }
[[ -n "$TRACKER" ]] || { echo "[sas-cybernet-reconcile-report] ERROR: --tracker required" >&2; exit 1; }
[[ "$HEADER_SCAN_ROWS" =~ ^[0-9]+$ && "$HEADER_SCAN_ROWS" -ge 1 ]] || {
  echo "[sas-cybernet-reconcile-report] ERROR: --header-scan-rows must be a positive integer" >&2
  exit 1
}

find_python
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${PYTHON_CMD[@]}" "$SCRIPT_DIR/sas-cybernet-reconcile-report.py" \
  --alejandro "$ALEJANDRO" \
  --tracker "$TRACKER" \
  --tracker-sheet "$TRACKER_SHEET" \
  --output-dir "$OUTPUT_DIR" \
  --header-scan-rows "$HEADER_SCAN_ROWS" \
  "${IDENTITY_ARGS[@]}" \
  "${PREFLIGHT_ARGS[@]}"
