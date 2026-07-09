#!/usr/bin/env bash
# Canonical Cybernet-detect enrichment CLI for naabu -silent host:port pipelines.
# Emits JSONL on stdout; stderr carries logs only. See docs/LOW_NOISE_SURVEY_DOCTRINE.md.
set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOLLOWUP="${SCRIPT_DIR}/sas-cybernet-packet-followup.sh"

SITE=""
USE_STDIN=0
INPUT=""
USE_HTTPX=0

usage() {
  cat <<'USAGE'
Usage: bash survey/sas-cybernet-detect.sh --site SITE (--stdin | --input PATH) [--jsonl] [--use-httpx]

Local enrichment for naabu -silent host:port pipelines. Emits JSONL on stdout.
Stderr carries [cybernet-detect] / [packet-followup] logs only — suitable for piping.

Options:
  --site SITE      Site label (required)
  --stdin          Read host:port lines from stdin
  --input PATH     Read host:port lines from file
  --jsonl          Accepted for doctrine/doc compatibility (output is always JSONL)
  --use-httpx      Optional: delegate to httpx when on PATH (via followup wrapper)
  -h, --help       Show help
USAGE
}

fail() { printf '[cybernet-detect] ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:?}"; shift 2 ;;
    --stdin) USE_STDIN=1; shift ;;
    --input) INPUT="${2:?}"; shift 2 ;;
    --jsonl) shift ;;
    --use-httpx) USE_HTTPX=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

OFFLINE_ENRICHMENT_MODE=0
if [[ ("${USE_STDIN:-0}" -eq 1 || -n "${INPUT:-}") && "${USE_HTTPX:-0}" -eq 0 ]]; then
  OFFLINE_ENRICHMENT_MODE=1
fi
if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" && "$OFFLINE_ENRICHMENT_MODE" -ne 1 ]]; then
  sas_require_northwell_wifi
fi

[[ -n "$SITE" ]] || fail "--site is required"

args=(--site "$SITE" --cybernet-detect)
[[ "$USE_STDIN" -eq 1 ]] && args+=(--stdin)
[[ -n "$INPUT" ]] && args+=(--input "$INPUT")
[[ "$USE_HTTPX" -eq 1 ]] && args+=(--use-httpx)

if [[ "$USE_STDIN" -eq 0 && -z "$INPUT" ]]; then
  fail "Pass --stdin or --input"
fi

exec bash "$FOLLOWUP" "${args[@]}"
