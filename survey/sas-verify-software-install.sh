#!/usr/bin/env bash
set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

MANIFEST=""
SOFTWARE_ID=""
CATALOG="Config/software_registry_evidence.example.json"
OUTPUT="survey/output/software_install_evidence.csv"
JSON_OUT="survey/output/software_install_evidence.json"
RAW_DIR="survey/output/registry-evidence"
TARGET="localhost"
FIXTURE_RAW=""

usage() {
  cat <<'USAGE'
SysAdminSuite Northwell registry-first software verification

Usage:
  bash survey/sas-verify-software-install.sh --software-id sample-viewer [options]

Options:
  --software-id ID       Software ID from catalog (required)
  --catalog PATH         Evidence catalog JSON
  --target HOST          Single target, default localhost
  --manifest PATH        Approved target manifest with HostName/Target column
  --raw-dir PATH         Raw reg.exe output directory
  --fixture-raw PATH     Parse an existing raw fixture instead of running cmd.exe
  --output PATH          CSV output path
  --json PATH            JSON output path
  -h, --help             Show help

Safety:
  Read-only verification. Uses CMD/reg.exe QUERY via survey/sas-reg-query.cmd unless --fixture-raw is supplied.
  Does not run installers, use credentials, modify registry, or change target state.
USAGE
}

fail() { echo "[sas-verify-software-install] ERROR: $*" >&2; exit 1; }
log() { echo "[sas-verify-software-install] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --software-id) SOFTWARE_ID="${2:?missing --software-id value}"; shift 2 ;;
    --catalog) CATALOG="${2:?missing --catalog value}"; shift 2 ;;
    --target) TARGET="${2:?missing --target value}"; shift 2 ;;
    --manifest) MANIFEST="${2:?missing --manifest value}"; shift 2 ;;
    --raw-dir) RAW_DIR="${2:?missing --raw-dir value}"; shift 2 ;;
    --fixture-raw) FIXTURE_RAW="${2:?missing --fixture-raw value}"; shift 2 ;;
    --output) OUTPUT="${2:?missing --output value}"; shift 2 ;;
    --json) JSON_OUT="${2:?missing --json value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

[[ -n "$SOFTWARE_ID" ]] || fail "--software-id is required"
[[ -f "$CATALOG" ]] || fail "Catalog not found: $CATALOG"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

mkdir -p "$RAW_DIR" "$(dirname "$OUTPUT")" "$(dirname "$JSON_OUT")"

raw_files=()
targets=()

if [[ -n "$MANIFEST" ]]; then
  [[ -f "$MANIFEST" ]] || fail "Manifest not found: $MANIFEST"
  mapfile -t targets < <(python3 - "$MANIFEST" <<'PY'
import csv, sys
path = sys.argv[1]
with open(path, newline='', encoding='utf-8-sig') as handle:
    for row in csv.DictReader(handle):
        for key in ('HostName','Hostname','Target','ComputerName','Name'):
            value = (row.get(key) or '').strip()
            if value:
                print(value)
                break
PY
)
else
  targets=("$TARGET")
fi

if [[ ${#targets[@]} -eq 0 ]]; then
  fail "No targets resolved. Use --target or a manifest with HostName/Target column."
fi

if [[ -n "$FIXTURE_RAW" ]]; then
  [[ -f "$FIXTURE_RAW" ]] || fail "Fixture raw file not found: $FIXTURE_RAW"
  raw_files+=("$FIXTURE_RAW")
else
  if ! command -v cmd.exe >/dev/null 2>&1; then
    fail "cmd.exe is required unless --fixture-raw is supplied"
  fi
  for target in "${targets[@]}"; do
    log "Collecting read-only registry evidence for $target"
    raw_path=$(cmd.exe /c survey\\sas-reg-query.cmd --target "$target" --software-id "$SOFTWARE_ID" --output-dir "${RAW_DIR//\//\\}" | tr -d '\r' | tail -n 1)
    [[ -n "$raw_path" ]] || fail "Registry collector did not return an output path for $target"
    raw_files+=("$raw_path")
  done
fi

python3 survey/parse_registry_install_evidence.py \
  --catalog "$CATALOG" \
  --software-id "$SOFTWARE_ID" \
  --target "${targets[0]}" \
  --raw "${raw_files[@]}" \
  --output "$OUTPUT" \
  --json "$JSON_OUT"
