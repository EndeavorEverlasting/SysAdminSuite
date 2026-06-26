#!/usr/bin/env bash
# Export an approved AD computer CSV into SysAdminSuite's dashboard-ready
# registered-population roster. This is an offline wrapper around
# sas-ad-reconcile.sh: it does not query AD, DNS, Naabu, Nmap, or target hosts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILE="$ROOT/survey/sas-ad-reconcile.sh"
OUTPUT_DIR="$ROOT/survey/output/ad_registered_population"

usage() {
  cat <<'USAGE'
Usage: bash survey/sas-export-ad-registered-population.sh --ad-csv PATH [options]

Build a dashboard-ready AD registered population roster from an approved AD CSV
export. AD is the registered-device authority; network and identity evidence are
optional comparison layers, not proof supplied by AD.

Options mirror sas-ad-reconcile.sh:
  --ad-csv PATH         Required approved AD computer CSV export
  --evidence-csv PATH   Optional approved manifest/tracker evidence CSV
  --network-csv PATH    Optional pre-validated reachability evidence CSV
  --serial-csv PATH     Optional live-serial / identity evidence CSV
  --output-dir PATH     Output directory (default: survey/output/ad_registered_population)
  --prefix PREFIX       Optional hostname prefix filter (e.g. CYB, WNH)
  --stale-days N        Days before LastLogonDate is stale (default inherited)
  --pass-thru           Print underlying ad_summary.json
  -h, --help            Show help

Outputs include ad_registered_normalized.csv, AD bucket CSVs, target lists,
ad_summary.json, and README.txt. Keep live exports and generated outputs local
in ignored paths such as logs/targets/ and survey/output/.
USAGE
}

fail() { echo "[ad-registered-population] ERROR: $*" >&2; exit 1; }
log() { echo "[ad-registered-population] $*" >&2; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required"
}

# Capture --output-dir into OUTPUT_DIR and forward everything else verbatim.
# The reconcile output directory is appended exactly once below, so the
# underlying script never receives a duplicate --output-dir flag.
args=()
have_ad_csv=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --ad-csv) have_ad_csv=1; args+=("$1" "${2:?}"); shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?}"; shift 2 ;;
    --evidence-csv|--network-csv|--serial-csv|--prefix|--stale-days)
      args+=("$1" "${2:?}"); shift 2 ;;
    --pass-thru|--version) args+=("$1"); shift ;;
    *) fail "Unknown argument: $1 (run with --help)" ;;
  esac
done

[[ "$have_ad_csv" -eq 1 ]] || fail "--ad-csv is required; place approved exports in logs/targets/ or pass an explicit scoped CSV"
[[ -f "$RECONCILE" ]] || fail "Missing reconcile script: $RECONCILE"

log "Building AD registered population roster from approved CSV input"
bash "$RECONCILE" "${args[@]}" --output-dir "$OUTPUT_DIR"

summary="$OUTPUT_DIR/ad_summary.json"
if [[ -f "$summary" ]]; then
  py="$(find_python)"
  "$py" - "$summary" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
counts = summary.get("counts", {})
print("AD REGISTERED POPULATION ROSTER SUMMARY:")
print(f"- Population authority: {summary.get('population_authority', 'ad_registered')}")
print(f"- Query mode used: {summary.get('query_mode_used', 'imported approved AD CSV')}")
print(f"- Fallback mode used: {summary.get('fallback_mode_used', 'offline/static evidence')}")
print(f"- Output directory: {summary.get('output_dir', '')}")
print(f"- Registered rows: {counts.get('ad_registered_normalized', 0)}")
print(f"- Enabled target hostnames: {counts.get('ad_targets_hostnames', 0)}")
print(f"- Disabled objects: {counts.get('ad_disabled', 0)}")
print(f"- Stale objects: {counts.get('ad_stale', 0)}")
print(f"- Missing DNS: {counts.get('ad_missing_dns', 0)}")
print(f"- Duplicate candidates: {counts.get('ad_duplicates', 0)}")
print(f"- AD-only rows: {counts.get('ad_only', 0)}")
print(f"- Evidence-only rows: {counts.get('evidence_only', 0)}")
print("- Evidence committed: none; generated outputs are local/ignored")
PY
fi

log "Dashboard roster ready: $OUTPUT_DIR/ad_registered_normalized.csv"
