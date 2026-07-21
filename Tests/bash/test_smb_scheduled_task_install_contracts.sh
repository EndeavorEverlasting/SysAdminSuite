#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'test_smb_scheduled_task_install_contracts: FAIL: %s\n' "$*" >&2
  exit 1
}

SCRIPT="bash/apps/sas-install-apps.sh"
CATALOG="configs/software-packages/approved-apps.json"
SET_CATALOG="configs/software-packages/windows-native-package-sets.json"
DOC="docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

bash -n "$SCRIPT"

python3 - "$CATALOG" <<'PY' || exit 1
import json
import sys

with open(sys.argv[1], encoding="utf-8-sig") as handle:
    catalog = json.load(handle)

matches = [package for package in catalog["packages"] if package["id"] == "bca"]
assert len(matches) == 1
bca = matches[0]
assert bca["display_name"] == "Epic BCA Web Shortcut 1.0"
assert bca["source_folder_relative_path"] == r"packages\Epic\EPIC_BCA_Web-Shortcut_1.0"
assert bca["installer_file"] == "EPIC_BCA_Web-Shortcut_1.0.msi"
assert bca["default_install_mode"] == "CopyThenInstall"
assert bca["default_installer_arguments"] == ["/qn", "/norestart"]
assert bca["requires_validated_installer_arguments"] is False
assert bca["install_enabled"] is True
PY

python3 - "$SET_CATALOG" <<'PY' || exit 1
import json
import sys

with open(sys.argv[1], encoding="utf-8-sig") as handle:
    catalog = json.load(handle)

assert catalog["schema_version"] == "sas-windows-native-package-sets/v1"
package_set = next(item for item in catalog["package_sets"] if item["id"] == "cybernet-clinical-workstation")
assert package_set["package_ids"] == [
    "allscripts-eehr-shortcut-uai-2-2",
    "epic-downtime-guide-shortcut-1-0",
    "nuance-dragon-medical-one-2025",
    "hyland-fos-epic-integration-23-1-33-1000",
    "autologon",
]
packages = {item["id"]: item for item in catalog["packages"]}
assert packages["allscripts-eehr-shortcut-uai-2-2"]["entrypoint_file"] == "Allscripts_EEHR-Shortcut-UAI_2.2.msi"
assert packages["allscripts-eehr-shortcut-uai-2-2"]["installer_arguments"] == ["/qb", "/norestart"]
assert packages["epic-downtime-guide-shortcut-1-0"]["staged_files"] == [
    "Epic_Epic_Downtime_Guide-Shortcut_1.0.msi",
    "Install.cmd",
]
assert packages["nuance-dragon-medical-one-2025"]["staged_files"] == [
    "cab1.cab",
    "DMO.Mst",
    "Dragon Medical One.lnk",
    "Install.cmd",
    "Nuance_Dragon_Edge_Extension.msi",
    "Standalone.msi",
]
assert packages["hyland-fos-epic-integration-23-1-33-1000"]["staged_files"] == [
    "EPICFOSCONFIG.XML",
    "FrontOfficeScanning.exe",
    "Hyland Integration for Epic.msi",
    "Hyland_Integration_EPIC.cab",
    "Hyland_Integration_EPIC.Mst",
    "Install.cmd",
    "VC_redist.x64.exe",
]
assert packages["autologon"]["entrypoint_file"] == "NW_AutoLogon_Setup_x64.exe"
assert all(package["install_enabled"] is True for package in packages.values())
PY

DRY_OUTPUT="$TMP_ROOT/dry-run.txt"
bash "$SCRIPT" \
  --targets SYNTHETIC001 \
  --package bca \
  --allow-legacy \
  --dry-run \
  --log-dir "$TMP_ROOT/output" >"$DRY_OUTPUT" 2>&1 \
  || fail "BCA dry run must succeed offline"

for fragment in \
  "transport=dry-run" \
  "Approved package: Epic BCA Web Shortcut 1.0 (bca)" \
  "EPIC_BCA_Web-Shortcut_1.0.msi" \
  "schtasks /Create /S SYNTHETIC001 /RU SYSTEM" \
  "-NonInteractive -ExecutionPolicy Bypass" \
  "Would copy results locally" \
  "remove only run root C:\\ProgramData\\SysAdminSuite\\AppInstall\\app-install-" \
  "DRY_RUN_OK"; do
  grep -Fq -- "$fragment" "$DRY_OUTPUT" || fail "dry run missing: $fragment"
done

WORKER="$(find "$TMP_ROOT/output" -maxdepth 1 -type f -name 'sas-install-worker-package-bca-*.ps1' -print -quit)"
[[ -n "$WORKER" ]] || fail "BCA dry run did not generate a worker"
grep -Fq "Start-Process -FilePath \"msiexec.exe\"" "$WORKER" || fail "worker must use Windows Installer"
grep -Fq -- "-InstallerPattern 'EPIC_BCA_Web-Shortcut_1.0.msi'" "$WORKER" || fail "worker must pin the BCA MSI"
grep -Fq -- "-SilentArgs @('/qn', '/norestart')" "$WORKER" || fail "worker must use cataloged BCA arguments"
grep -Fq 'Worker self-teardown provides best-effort cleanup' "$WORKER" || fail "worker must include fallback teardown"
if grep -Fq '$path:' "$WORKER"; then
  fail "worker teardown warning must not contain invalid PowerShell variable syntax"
fi
grep -Fq '${path}:' "$WORKER" || fail "worker teardown warning must delimit the path variable"

SET_DRY_OUTPUT="$TMP_ROOT/package-set-dry-run.txt"
bash "$SCRIPT" \
  --targets SYNTHETIC001 \
  --package-set cybernet-clinical-workstation \
  --allow-legacy \
  --dry-run \
  --log-dir "$TMP_ROOT/package-set-output" >"$SET_DRY_OUTPUT" 2>&1 \
  || fail "clinical package-set dry run must succeed offline"

for fragment in \
  "Approved package set: Cybernet clinical workstation applications (cybernet-clinical-workstation)" \
  "Allscripts_EEHR-Shortcut-UAI_2.2.msi" \
  "Epic_Epic_Downtime_Guide-Shortcut_1.0.msi" \
  "Nuance_DragonMedicalOne_2025\\DMO.Mst" \
  "Nuance_DragonMedicalOne_2025\\Dragon Medical One.lnk" \
  "Hyland_FOS_Epic-Integration_23.1.33.1000\\Hyland Integration for Epic.msi" \
  "AutoLogonSetup\\NW_AutoLogon_Setup_x64.exe" \
  "DRY_RUN_OK"; do
  grep -Fq -- "$fragment" "$SET_DRY_OUTPUT" || fail "package-set dry run missing: $fragment"
done

SET_WORKER="$(find "$TMP_ROOT/package-set-output" -maxdepth 1 -type f -name 'sas-install-worker-package-set-cybernet-clinical-workstation-*.ps1' -print -quit)"
[[ -n "$SET_WORKER" ]] || fail "package-set dry run did not generate a worker"
[[ "$(grep -Fc '$Results += Install-App' "$SET_WORKER")" -eq 5 ]] || fail "package-set worker must contain five ordered installs"
grep -Fq -- "-Type 'cmd'" "$SET_WORKER" || fail "package-set worker must support approved CMD bundle entrypoints"
grep -Fq -- "-Type 'exe'" "$SET_WORKER" || fail "package-set worker must run the elevated AutoLogon EXE"
grep -Fq '$cmdArguments = '\''/d /s /c ""{0}""' "$SET_WORKER" || fail "CMD bundle execution must preserve quoted entrypoint paths"

# Windows Python emits CRLF. Reproduce that behavior on Linux and prove that
# package metadata is normalized before it reaches paths or console output.
CRLF_BIN="$TMP_ROOT/crlf-bin"
mkdir -p "$CRLF_BIN"
cp Tests/Fixtures/smb_scheduled_task_install/fake-python-crlf.sh "$CRLF_BIN/python3"
chmod +x "$CRLF_BIN/python3"
CRLF_OUTPUT="$TMP_ROOT/crlf-dry-run.txt"
PATH="$CRLF_BIN:$PATH" \
REAL_PYTHON3="$(command -v python3)" \
bash "$SCRIPT" \
  --targets SYNTHETIC001 \
  --package bca \
  --allow-legacy \
  --dry-run \
  --log-dir "$TMP_ROOT/crlf-output" >"$CRLF_OUTPUT" 2>&1 \
  || fail "BCA dry run must accept Windows CRLF metadata"
grep -Fq '[DRY-RUN] Approved package: Epic BCA Web Shortcut 1.0 (bca)' "$CRLF_OUTPUT" \
  || fail "CRLF metadata must not overwrite the approved-package prefix"
grep -Fq '\\nt2kwb972sms01\packages\Epic\EPIC_BCA_Web-Shortcut_1.0\EPIC_BCA_Web-Shortcut_1.0.msi' "$CRLF_OUTPUT" \
  || fail "CRLF metadata must preserve the exact pinned source path"
if grep -q $'\r' "$CRLF_OUTPUT"; then
  fail "controller output must not contain carriage returns from package metadata"
fi

if bash "$SCRIPT" --targets SYNTHETIC001 --list workstation-baseline --package bca --allow-legacy --dry-run --log-dir "$TMP_ROOT/both" >"$TMP_ROOT/both.txt" 2>&1; then
  fail "list and package together must fail closed"
fi
grep -Fq 'use exactly one of --list, --package, or --package-set' "$TMP_ROOT/both.txt" || fail "selection conflict must be explained"

if bash "$SCRIPT" --targets SYNTHETIC001 --package not-approved --allow-legacy --dry-run --log-dir "$TMP_ROOT/unknown" >"$TMP_ROOT/unknown.txt" 2>&1; then
  fail "unknown package must fail closed"
fi
grep -Fq 'approved package id not found or ambiguous' "$TMP_ROOT/unknown.txt" || fail "unknown package failure must be explained"

TOO_MANY_TARGETS="$(python3 - <<'PY'
print(",".join(f"SYNTHETIC{number:03d}" for number in range(1, 27)))
PY
)"
if bash "$SCRIPT" --targets "$TOO_MANY_TARGETS" --package bca --allow-legacy --dry-run --log-dir "$TMP_ROOT/too-many" >"$TMP_ROOT/too-many.txt" 2>&1; then
  fail "more than 25 targets must fail closed"
fi
grep -Fq 'Target count exceeds the guarded maximum of 25' "$TMP_ROOT/too-many.txt" \
  || fail "target-count failure must be explained"

# Exercise the live orchestration against a local fixture transport. These
# executables model only the PowerShell Copy-Item/Test-Path operations and the
# schtasks lifecycle used by the controller; they never contact a network.
FAKE_BIN="$TMP_ROOT/fake-bin"
SIM_REMOTE_ROOT="$TMP_ROOT/fixture-target"
SIM_TASK_STATE="$TMP_ROOT/fixture-task.state"
SIM_TASK_LOG="$TMP_ROOT/fixture-task.log"
mkdir -p "$FAKE_BIN" "$SIM_REMOTE_ROOT"
cp Tests/Fixtures/smb_scheduled_task_install/fake-powershell.sh "$FAKE_BIN/powershell.exe"
cp Tests/Fixtures/smb_scheduled_task_install/fake-schtasks.sh "$FAKE_BIN/schtasks.exe"
chmod +x "$FAKE_BIN/powershell.exe" "$FAKE_BIN/schtasks.exe"

LIVE_OUTPUT="$TMP_ROOT/live-success.txt"
PATH="$FAKE_BIN:$PATH" \
SIM_REMOTE_ROOT="$SIM_REMOTE_ROOT" \
SIM_TASK_STATE="$SIM_TASK_STATE" \
SIM_TASK_LOG="$SIM_TASK_LOG" \
SKIP_NMAP=1 \
bash "$SCRIPT" \
  --targets SYNTHETIC001 \
  --package bca \
  --allow-legacy \
  --wait-timeout 10 \
  --log-dir "$TMP_ROOT/live-output" >"$LIVE_OUTPUT" 2>&1 \
  || fail "fixture Windows-native BCA install must succeed"

for fragment in \
  'transport=windows-native' \
  'Staged pinned package: EPIC_BCA_Web-Shortcut_1.0.msi' \
  'Worker syntax preflight passed with Windows PowerShell.' \
  'Task triggered; waiting up to 10s' \
  'Result copied locally:' \
  'HOST_OK' \
  'Cleanup complete: task and run-scoped staging removed or already absent.'; do
  grep -Fq -- "$fragment" "$LIVE_OUTPUT" || fail "fixture live run missing: $fragment"
done
[[ ! -e "$SIM_TASK_STATE" ]] || fail "fixture scheduled task was not removed"
if find "$SIM_REMOTE_ROOT" -type d -name 'app-install-*' -print -quit | grep -q .; then
  fail "fixture run-scoped target staging was not removed"
fi
find "$TMP_ROOT/live-output" -maxdepth 1 -type f -name '*.results.csv' -print -quit | grep -q . \
  || fail "fixture result CSV was not copied to the controller"
for action in /Create /Run /Query /Delete; do
  grep -Fq -- "$action" "$SIM_TASK_LOG" || fail "fixture task lifecycle missing: $action"
done

: > "$SIM_TASK_LOG"
SET_LIVE_OUTPUT="$TMP_ROOT/package-set-live-success.txt"
PATH="$FAKE_BIN:$PATH" \
SIM_REMOTE_ROOT="$SIM_REMOTE_ROOT" \
SIM_TASK_STATE="$SIM_TASK_STATE" \
SIM_TASK_LOG="$SIM_TASK_LOG" \
SKIP_NMAP=1 \
bash "$SCRIPT" \
  --targets SYNTHETIC001 \
  --package-set cybernet-clinical-workstation \
  --allow-legacy \
  --wait-timeout 10 \
  --log-dir "$TMP_ROOT/package-set-live-output" >"$SET_LIVE_OUTPUT" 2>&1 \
  || fail "fixture Windows-native clinical package-set install must succeed"

for fragment in \
  'transport=windows-native' \
  'Staged approved package set: cybernet-clinical-workstation (17 files)' \
  'Task triggered; waiting up to 10s' \
  'Result copied locally:' \
  'HOST_OK' \
  'Cleanup complete: task and run-scoped staging removed or already absent.'; do
  grep -Fq -- "$fragment" "$SET_LIVE_OUTPUT" || fail "fixture package-set run missing: $fragment"
done
SET_RESULT="$(find "$TMP_ROOT/package-set-live-output" -maxdepth 1 -type f -name '*.results.csv' -print -quit)"
[[ -n "$SET_RESULT" ]] || fail "fixture package-set result CSV was not copied"
[[ "$(tail -n +2 "$SET_RESULT" | wc -l | tr -d ' ')" -eq 5 ]] || fail "fixture package-set result must contain five package rows"
[[ ! -e "$SIM_TASK_STATE" ]] || fail "fixture package-set scheduled task was not removed"
if find "$SIM_REMOTE_ROOT" -type d -name 'app-install-*' -print -quit | grep -q .; then
  fail "fixture package-set run-scoped target staging was not removed"
fi

: > "$SIM_TASK_LOG"
FAILED_OUTPUT="$TMP_ROOT/live-failure.txt"
if PATH="$FAKE_BIN:$PATH" \
  SIM_REMOTE_ROOT="$SIM_REMOTE_ROOT" \
  SIM_TASK_STATE="$SIM_TASK_STATE" \
  SIM_TASK_LOG="$SIM_TASK_LOG" \
  SIM_RESULT_STATUS=Failed \
  SKIP_NMAP=1 \
  bash "$SCRIPT" \
    --targets SYNTHETIC001 \
    --package bca \
    --allow-legacy \
    --wait-timeout 10 \
    --log-dir "$TMP_ROOT/failed-output" >"$FAILED_OUTPUT" 2>&1; then
  fail "fixture failed installer result must return nonzero"
fi
grep -Fq 'FAILED_RESULT: Epic BCA Web Shortcut 1.0: Failed: fixture installer failure' "$FAILED_OUTPUT" \
  || fail "failed installer result must be reported locally"
grep -Fq 'HOST_FAILED' "$FAILED_OUTPUT" || fail "failed installer result must classify the host as failed"
grep -Fq 'Cleanup complete: task and run-scoped staging removed or already absent.' "$FAILED_OUTPUT" \
  || fail "failed installer path must still clean up"
[[ ! -e "$SIM_TASK_STATE" ]] || fail "failed fixture scheduled task was not removed"
if find "$SIM_REMOTE_ROOT" -type d -name 'app-install-*' -print -quit | grep -q .; then
  fail "failed fixture run-scoped target staging was not removed"
fi

grep -Fq 'MSYS_NO_PATHCONV=1 schtasks.exe /Create' "$SCRIPT" || fail "Git Bash task creation must disable MSYS path conversion"
grep -Fq 'Windows-native transport uses the current approved admin token' "$SCRIPT" || fail "native transport must reject supplied SMB credentials"
grep -Fq 'native_remove_run_root' "$SCRIPT" || fail "native transport must implement run-root cleanup"
grep -Fq 'Result copied locally:' "$SCRIPT" || fail "controller must retrieve result evidence"
if grep -Fq 'cmd.exe /c "$CREATE_CMD"' "$SCRIPT"; then
  fail "native task creation must not depend on cmd.exe command-string parsing"
fi

for fragment in \
  'does not require `smbclient`' \
  'does not accept WinRM' \
  '--package bca' \
  '--package-set cybernet-clinical-workstation' \
  'Allscripts EEHR Shortcut UAI 2.2' \
  'Nuance Dragon Medical One 2025' \
  'Hyland FOS Epic Integration 23.1.33.1000' \
  'AutoLogon runs last' \
  'This fallback does not provide the canonical WinRM lane'; do
  grep -Fq -- "$fragment" "$DOC" || fail "documentation missing: $fragment"
done

echo "test_smb_scheduled_task_install_contracts: PASS"
