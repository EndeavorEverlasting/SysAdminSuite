#!/usr/bin/env bash
# SysAdminSuite — Imprivata Epic core deployment wrapper
#
# Builds a run-pinned package-set manifest from the three approved Imprivata
# bundle folders, then delegates target staging/execution/cleanup to the
# existing sas-install-apps.sh Windows-native scheduled-task controller.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SAS_INSTALLER="$SCRIPT_DIR/sas-install-apps.sh"

TARGETS_RAW=""
TARGET_FILE=""
DRY_RUN=0
WAIT_TIMEOUT="1800"
LOG_DIR="$REPO_ROOT/bash/apps/output"

usage() {
  cat <<'USAGE'
SysAdminSuite — Imprivata Epic Core Deployment

Installs, in this exact order:
  1. Imprivata OneSign Epic Connector 25.6.40154
  2. Imprivata OneSign Agent 25.1.000.15
  3. Northwell OneSign SecureLock Shortcut 1.0

Usage:
  ./bash/apps/sas-install-imprivata-core.sh --targets HOST1,HOST2 [options]
  ./bash/apps/sas-install-imprivata-core.sh --target-file PATH [options]

Options:
  --targets HOSTS       Comma-separated target hostnames (maximum 25)
  --target-file PATH    Text file with one hostname per line; blank/# lines ignored
  --wait-timeout SEC    Installer-result wait per target (default: 1800)
  --log-dir PATH        Evidence/output directory (default: bash/apps/output)
  --dry-run             Inventory source bundles and print deployment actions only
  -h, --help            Show help

Notes:
  - Uses the current approved Windows admin token; no SMB username/password options.
  - Reads software only from \\nt2kwb972sms01\packages.
  - Recursively inventories each approved bundle folder at launch so Install.cmd
    receives all sibling MSI/CAB/config files it may depend on.
  - The generated run manifest is retained in the log directory for evidence.
  - Live execution delegates to sas-install-apps.sh, which stages to the target,
    runs a one-time task as SYSTEM, retrieves results, and tears down run-scoped files.
USAGE
}

fail() { printf '[sas-imprivata] ERROR: %s\n' "$*" >&2; exit 1; }
log()  { printf '[sas-imprivata] %s\n' "$*" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)      TARGETS_RAW="${2:?missing value for --targets}"; shift 2 ;;
    --target-file)  TARGET_FILE="${2:?missing value for --target-file}"; shift 2 ;;
    --wait-timeout) WAIT_TIMEOUT="${2:?missing value for --wait-timeout}"; shift 2 ;;
    --log-dir)      LOG_DIR="${2:?missing value for --log-dir}"; shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    --)             shift; break ;;
    -*)             fail "Unknown option: $1" ;;
    *)              fail "Unexpected argument: $1" ;;
  esac
done

[[ -x "$SAS_INSTALLER" || -f "$SAS_INSTALLER" ]] || fail "missing SAS installer controller: $SAS_INSTALLER"
has_cmd python3 || fail "python3 is required"
[[ "$WAIT_TIMEOUT" =~ ^[0-9]+$ && "$WAIT_TIMEOUT" -ge 10 && "$WAIT_TIMEOUT" -le 7200 ]] \
  || fail "--wait-timeout must be 10-7200 seconds"

if [[ -n "$TARGETS_RAW" && -n "$TARGET_FILE" ]]; then
  fail "use --targets or --target-file, not both"
fi
if [[ -n "$TARGET_FILE" ]]; then
  [[ -f "$TARGET_FILE" ]] || fail "target file not found: $TARGET_FILE"
  TARGETS_RAW="$(python3 - "$TARGET_FILE" <<'PY'
import sys

path = sys.argv[1]
hosts = []
with open(path, encoding="utf-8-sig") as handle:
    for raw in handle:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "#" in line:
            line = line.split("#", 1)[0].strip()
        if line:
            hosts.append(line)
print(",".join(hosts))
PY
  )"
fi
[[ -n "$TARGETS_RAW" ]] || fail "--targets or --target-file is required"

mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y%m%d_%H%M%S')"
MANIFEST="$LOG_DIR/imprivata-epic-core-manifest-${STAMP}.json"

log "Inventorying approved Imprivata source bundles from \\nt2kwb972sms01\packages ..."
python3 - "$MANIFEST" <<'PY'
import json
import ntpath
import os
import sys
from datetime import datetime, timezone

output_path = sys.argv[1]
software_share_root = "\\\\nt2kwb972sms01\\"
packages = [
    {
        "id": "imprivata-onesign-epic-connector-25-6-40154",
        "display_name": "Imprivata OneSign Epic Connector 25.6.40154",
        "source_folder_relative_path": r"packages\Epic_TPI_Installer\Core\Imprivata_OnesignEpicConnector_25.6.40154",
    },
    {
        "id": "imprivata-onesign-agent-25-1-000-15",
        "display_name": "Imprivata OneSign Agent 25.1.000.15",
        "source_folder_relative_path": r"packages\Epic_TPI_Installer\Core\Imprivata_OneSignAgent_25.1.000.15",
    },
    {
        "id": "northwell-onesign-securelock-shortcut-1-0",
        "display_name": "Northwell OneSign SecureLock Shortcut 1.0",
        "source_folder_relative_path": r"packages\Epic_TPI_Installer\Core\Northwell_OneSign-SecureLock-Shortcut_1.0",
    },
]

resolved = []
for package in packages:
    source = ntpath.join(software_share_root, package["source_folder_relative_path"])
    if not os.path.isdir(source):
        raise SystemExit(f"approved source folder is unavailable: {source}")

    entrypoint = ntpath.join(source, "Install.cmd")
    if not os.path.isfile(entrypoint):
        raise SystemExit(f"Install.cmd is missing from approved source folder: {source}")

    staged_files = []
    for current_root, dirs, files in os.walk(source, followlinks=False):
        dirs.sort(key=str.lower)
        files.sort(key=str.lower)
        for filename in files:
            full_path = ntpath.join(current_root, filename)
            relative = ntpath.relpath(full_path, source).replace("/", "\\")
            parts = relative.split("\\")
            if (
                not relative
                or ntpath.isabs(relative)
                or ".." in parts
                or any(part in {"", "."} for part in parts)
                or any(char in relative for char in '<>:"|?*')
            ):
                raise SystemExit(f"unsafe source file discovered in {source}: {relative}")
            staged_files.append(relative)

    if not staged_files:
        raise SystemExit(f"approved source folder contains no files: {source}")
    if len(staged_files) > 50:
        raise SystemExit(
            f"approved bundle exceeds the current SAS package-set limit of 50 files: "
            f"{package['id']} has {len(staged_files)} files"
        )
    if "Install.cmd" not in staged_files:
        raise SystemExit(f"Install.cmd was not included in recursive inventory: {source}")

    resolved.append(
        {
            "id": package["id"],
            "display_name": package["display_name"],
            "source_folder_relative_path": package["source_folder_relative_path"],
            "package_kind": "bundle",
            "entrypoint_file": "Install.cmd",
            "staged_files": staged_files,
            "installer_type": "cmd",
            "installer_arguments": [],
            "install_enabled": True,
            "inventory_file_count": len(staged_files),
        }
    )

manifest = {
    "schema_version": "sas-windows-native-package-sets/v1",
    "software_share_root": software_share_root,
    "generated_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "generated_for": "imprivata-epic-core",
    "source_inventory_policy": "recursive_files_pinned_per_run_before_target_contact",
    "package_sets": [
        {
            "id": "imprivata-epic-core",
            "display_name": "Imprivata Epic core applications",
            "package_ids": [package["id"] for package in resolved],
        }
    ],
    "packages": resolved,
}

with open(output_path, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")

for package in resolved:
    print(f"{package['display_name']}: {package['inventory_file_count']} files")
print(f"Manifest: {output_path}")
PY

log "Run-pinned package manifest written: $MANIFEST"

CMD=(
  bash "$SAS_INSTALLER"
  --targets "$TARGETS_RAW"
  --package-set imprivata-epic-core
  --package-set-catalog "$MANIFEST"
  --allow-legacy
  --wait-timeout "$WAIT_TIMEOUT"
  --log-dir "$LOG_DIR"
)
if [[ "$DRY_RUN" -eq 1 ]]; then
  CMD+=(--dry-run)
fi

log "Delegating deployment to sas-install-apps.sh"
"${CMD[@]}"
