#!/usr/bin/env bash
# SysAdminSuite local subnet finder.
# Purpose: collect local adapter context and produce candidate IPv4 CIDRs for approved inventory work.

set -euo pipefail

VERSION="0.1.0"
SITE="site"
OUTPUT_ROOT="survey/output/local_subnet_finder"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
CIDRS=()
CHUNK_PREFIX=24
MAX_CHUNKS_PER_NETWORK=16
PYTHON_CMD=()

usage() {
  cat <<'USAGE'
SysAdminSuite Local Subnet Finder

Usage:
  bash survey/sas-find-local-subnets.sh [options]

Auto-detect from the connected admin workstation:
  bash survey/sas-find-local-subnets.sh --site nsuh

Normalize explicit approved CIDRs:
  bash survey/sas-find-local-subnets.sh --site nsuh --cidr 10.10.10.0/24 --cidr 10.10.11.0/24

Options:
  --site NAME                 Site/run label used in output paths. Default: site
  --cidr CIDR                 Approved IPv4 CIDR. Can be repeated
  --output-root DIR           Root output dir. Default: survey/output/local_subnet_finder
  --run-id ID                 Run id. Default: timestamp
  --chunk-prefix PREFIX       Chunk wider networks to PREFIX. Default: 24
  --max-chunks-per-network N  Max chunks emitted from one direct network. Default: 16
  -h, --help                  Show help

Output:
  - context/ipconfig_all.txt
  - context/route_print.txt
  - context/arp_initial.txt
  - subnet_candidates.csv
  - subnet_candidates.txt
  - SUMMARY.md

Generated output may contain operational network details. Do not commit it.
USAGE
}

log() { printf '[local-subnet-finder] %s\n' "$*" >&2; }
fail() { printf '[local-subnet-finder] ERROR: %s\n' "$*" >&2; exit 1; }

find_python() {
  if [[ ${#PYTHON_CMD[@]} -gt 0 ]]; then return 0; fi
  if command -v python3 >/dev/null 2>&1; then PYTHON_CMD=(python3); return 0; fi
  if command -v python >/dev/null 2>&1; then PYTHON_CMD=(python); return 0; fi
  if command -v py >/dev/null 2>&1; then PYTHON_CMD=(py -3); return 0; fi
  fail "Python 3 is required. Install Python or add python3/python/py to PATH."
}

validate_site() {
  SITE="$(printf '%s' "$SITE" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')"
  [[ -n "$SITE" ]] || SITE="site"
}

capture_context() {
  local context_dir="$1"
  mkdir -p "$context_dir"
  if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c ipconfig /all > "$context_dir/ipconfig_all.txt" 2>&1 || true
    cmd.exe /c route print > "$context_dir/route_print.txt" 2>&1 || true
    cmd.exe /c arp -a > "$context_dir/arp_initial.txt" 2>&1 || true
  else
    ip addr > "$context_dir/ip_addr.txt" 2>&1 || true
    ip route > "$context_dir/ip_route.txt" 2>&1 || true
    : > "$context_dir/ipconfig_all.txt"
  fi

  if [[ -f survey/sas-device-snapshot.sh ]]; then
    bash survey/sas-device-snapshot.sh --output-file "$context_dir/device_snapshot.txt" >/dev/null 2>&1 || true
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:?missing value for --site}"; shift 2 ;;
    --cidr) CIDRS+=("${2:?missing value for --cidr}"); shift 2 ;;
    --output-root) OUTPUT_ROOT="${2:?missing value for --output-root}"; shift 2 ;;
    --run-id) RUN_ID="${2:?missing value for --run-id}"; shift 2 ;;
    --chunk-prefix) CHUNK_PREFIX="${2:?missing value for --chunk-prefix}"; shift 2 ;;
    --max-chunks-per-network) MAX_CHUNKS_PER_NETWORK="${2:?missing value for --max-chunks-per-network}"; shift 2 ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

validate_site
find_python
[[ -f survey/sas-local-subnet-candidates.py ]] || fail "Missing helper: survey/sas-local-subnet-candidates.py"

RUN_DIR="$OUTPUT_ROOT/${SITE}_${RUN_ID}"
CONTEXT_DIR="$RUN_DIR/context"
CANDIDATE_CSV="$RUN_DIR/subnet_candidates.csv"
CANDIDATE_LIST="$RUN_DIR/subnet_candidates.txt"
SUMMARY="$RUN_DIR/SUMMARY.md"

mkdir -p "$RUN_DIR" "$CONTEXT_DIR"
log "Run directory: $RUN_DIR"

capture_context "$CONTEXT_DIR"

args=(
  survey/sas-local-subnet-candidates.py
  --output "$CANDIDATE_CSV"
  --list-output "$CANDIDATE_LIST"
  --chunk-prefix "$CHUNK_PREFIX"
  --max-chunks-per-network "$MAX_CHUNKS_PER_NETWORK"
)

if [[ ${#CIDRS[@]} -gt 0 ]]; then
  for cidr in "${CIDRS[@]}"; do args+=(--cidr "$cidr"); done
else
  [[ -s "$CONTEXT_DIR/ipconfig_all.txt" ]] || fail "No local ipconfig output was captured. Provide explicit --cidr."
  args+=(--ipconfig "$CONTEXT_DIR/ipconfig_all.txt")
fi

"${PYTHON_CMD[@]}" "${args[@]}"

{
  echo "# Local Subnet Finder Summary"
  echo
  echo "Site: $SITE"
  echo "Run ID: $RUN_ID"
  echo "Run directory: $RUN_DIR"
  echo "Completed: $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "## Candidate CIDRs"
  echo
  sed 's/^/- /' "$CANDIDATE_LIST"
  echo
  echo "## Key files"
  echo
  echo "- Candidate CSV: $CANDIDATE_CSV"
  echo "- Candidate list: $CANDIDATE_LIST"
  echo "- Context directory: $CONTEXT_DIR"
  echo
  echo "## Handling"
  echo
  echo "Keep generated files local unless approved for handoff. Do not commit operational output."
} > "$SUMMARY"

cat "$CANDIDATE_LIST"
log "Done. Summary: $SUMMARY"
