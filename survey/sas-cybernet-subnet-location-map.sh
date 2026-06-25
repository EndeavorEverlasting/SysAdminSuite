#!/usr/bin/env bash
# SysAdminSuite Cybernet subnet/location inference (read-only CSV enrichment)
set -euo pipefail

usage() {
  cat <<'USAGE'
Cybernet subnet/location inference from approved hostname and IP CSV evidence.

Usage:
  ./survey/sas-cybernet-subnet-location-map.sh [options]

Options:
  --identity-csv PATH       Identity or AD export CSV (repeatable; required unless --identity-glob)
  --identity-glob PATTERN   Glob for identity CSV files (Git Bash)
  --preflight-csv PATH      Preflight CSV (repeatable)
  --tracker-csv PATH        Tracker or diff CSV (repeatable)
  --prefix-config PATH      Hostname prefix to location mapping CSV
  --prefix-len N            IPv4 prefix length for subnet grouping (default: 24)
  --output-prefix PATH      Output prefix (default: survey/output/cybernet_subnet_location)
  --format MODE             csv | json | all (default: all)
  --html                    Write offline HTML report directory
  -h, --help                Show help
USAGE
}

IDENTITY_CSV=()
IDENTITY_GLOB=""
PREFLIGHT_CSV=()
TRACKER_CSV=()
PREFIX_CONFIG=""
PREFIX_LEN=24
OUTPUT_PREFIX="survey/output/cybernet_subnet_location"
FORMAT="all"
HTML=0
PYTHON_CMD=()

find_python() {
  if [[ ${#PYTHON_CMD[@]} -gt 0 ]]; then return 0; fi
  if command -v python3 >/dev/null 2>&1; then PYTHON_CMD=(python3); return 0; fi
  if command -v python >/dev/null 2>&1; then PYTHON_CMD=(python); return 0; fi
  if command -v py >/dev/null 2>&1; then PYTHON_CMD=(py -3); return 0; fi
  echo "[sas-cybernet-subnet-location-map] ERROR: Python 3 required" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity-csv) IDENTITY_CSV+=("${2:?}"); shift 2 ;;
    --identity-glob) IDENTITY_GLOB="${2:?}"; shift 2 ;;
    --preflight-csv) PREFLIGHT_CSV+=("${2:?}"); shift 2 ;;
    --tracker-csv) TRACKER_CSV+=("${2:?}"); shift 2 ;;
    --prefix-config) PREFIX_CONFIG="${2:?}"; shift 2 ;;
    --prefix-len) PREFIX_LEN="${2:?}"; shift 2 ;;
    --output-prefix) OUTPUT_PREFIX="${2:?}"; shift 2 ;;
    --format) FORMAT="${2:?}"; shift 2 ;;
    --html) HTML=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[sas-cybernet-subnet-location-map] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -n "$IDENTITY_GLOB" ]]; then
  shopt -s nullglob
  matches=( $IDENTITY_GLOB )
  shopt -u nullglob
  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "[sas-cybernet-subnet-location-map] ERROR: --identity-glob matched no files: $IDENTITY_GLOB" >&2
    exit 1
  fi
  IDENTITY_CSV+=("${matches[@]}")
fi

if [[ ${#IDENTITY_CSV[@]} -eq 0 && ${#PREFLIGHT_CSV[@]} -eq 0 && ${#TRACKER_CSV[@]} -eq 0 ]]; then
  echo "[sas-cybernet-subnet-location-map] ERROR: supply at least one evidence CSV input" >&2
  usage
  exit 1
fi

find_python
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

args=(--prefix-len "$PREFIX_LEN" --output-prefix "$OUTPUT_PREFIX" --format "$FORMAT")
for path in "${IDENTITY_CSV[@]}"; do args+=(--identity-csv "$path"); done
for path in "${PREFLIGHT_CSV[@]}"; do args+=(--preflight-csv "$path"); done
for path in "${TRACKER_CSV[@]}"; do args+=(--tracker-csv "$path"); done
if [[ -n "$PREFIX_CONFIG" ]]; then args+=(--prefix-config "$PREFIX_CONFIG"); fi
if [[ "$HTML" -eq 1 ]]; then args+=(--html); fi

"${PYTHON_CMD[@]}" "$SCRIPT_DIR/sas-cybernet-subnet-location-map.py" "${args[@]}"
