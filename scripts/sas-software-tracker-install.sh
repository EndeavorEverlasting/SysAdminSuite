#!/usr/bin/env bash
# SysAdminSuite — Software Tracker install planner/runner
# Primary operator surface for new Software Tracker install work: Bash + Python.

set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

usage() {
  cat <<'USAGE'
SysAdminSuite — guarded Software Tracker install automation

Usage:
  bash scripts/sas-software-tracker-install.sh --tracker PATH [options]

Options:
  --tracker PATH       Software Tracker workbook (.xlsx)
  --list NAME          Catalog/list name filter
  --software NAME      Single software name filter
  --config PATH        JSON config with pathAliases
  --output-dir PATH    Report directory (default: survey/output/software-tracker-install)
  --execute            Run allowed installer commands (dry-run is the default)
  --allow-discovered-folder-installs
                       Permit folder-discovered installers, only with --execute
  -h, --help           Show help

Safety:
  - Dry-run is default.
  - URLs are never opened or executed.
  - EXE installers require explicit silent arguments before execution.
  - Folder paths are manual-review unless --execute and
    --allow-discovered-folder-installs are both present.
  - Reports are written locally as JSON, CSV, and text.
USAGE
}

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tracker) args+=(--tracker-path "${2:?missing value for --tracker}"); shift 2 ;;
    --list) args+=(--list-name "${2:?missing value for --list}"); shift 2 ;;
    --software) args+=(--software-name "${2:?missing value for --software}"); shift 2 ;;
    --config) args+=(--config "${2:?missing value for --config}"); shift 2 ;;
    --output-dir) args+=(--output-dir "${2:?missing value for --output-dir}"); shift 2 ;;
    --execute) args+=(--execute); shift ;;
    --allow-discovered-folder-installs) args+=(--allow-discovered-folder-installs); shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "[software-tracker-install] ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) echo "[software-tracker-install] ERROR: Unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ${#args[@]} -eq 0 ]]; then
  usage >&2
  exit 2
fi

cd "$REPO_ROOT"
exec "$PYTHON_BIN" scripts/software_tracker_installs.py "${args[@]}"
