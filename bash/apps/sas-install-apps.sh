#!/usr/bin/env bash
# SysAdminSuite — sas-install-apps.sh
# Compatibility wrapper for the canonical PowerShell validated-deployment front
# door, plus the preserved named-list/package controller until parity is retired.
# For each target: verifies admin-share access, drops a generated PowerShell
# worker script (sas-install-worker.ps1), then creates and triggers a scheduled
# task mirroring the pattern in mapping/Controllers/Map-Run-Controller.ps1.
# The canonical --request mode does not require --allow-legacy. The older
# --list/--package compatibility mode retains that explicit gate.
#
# Usage:
#   ./bash/apps/sas-install-apps.sh --targets HOST1,HOST2 --list LIST_NAME [options]
#   ./bash/apps/sas-install-apps.sh --targets HOST1 --package PACKAGE_ID [options]
#
# Examples:
#   ./bash/apps/sas-install-apps.sh --targets WKS001,WKS002 --list workstation-baseline
#   ./bash/apps/sas-install-apps.sh --targets WKS001 --list lab-tools --dry-run
#   ./bash/apps/sas-install-apps.sh --targets WKS001 --package example-msi --dry-run

set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"

TARGETS_RAW=""
LIST_NAME=""
PACKAGE_ID=""
REQUEST_PATH=""
CANONICAL_TRANSPORT="WinRM"
TRANSPORT_PREFLIGHT_PATH=""
SOURCES_YAML="Config/sources.yaml"
PACKAGE_CATALOG="configs/software-packages/approved-apps.json"
REPO_ROOT="${SAS_REPO_ROOT:-C:\SoftwareRepo}"
SHARE="C$"
REMOTE_BASE_ROOT='C:\ProgramData\SysAdminSuite\AppInstall'
REMOTE_PWSH='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
TASK_NAME="SysAdminSuite_AppInstall"
SMB_USER="${SAS_SMB_USER:-}"
SMB_PASS="${SAS_SMB_PASS:-}"
SMB_DOMAIN="${SAS_SMB_DOMAIN:-}"
TIMEOUT=10
WAIT_TIMEOUT=1800
DRY_RUN=0
ALLOW_LEGACY=0
NO_TEARDOWN=0
LOG_DIR="bash/apps/output"

usage() {
  cat <<'USAGE'
SysAdminSuite — Remote App Installer Orchestrator

Usage:
  ./bash/apps/sas-install-apps.sh --request PATH --transport VALUE [--transport-preflight PATH] [--dry-run]
  ./bash/apps/sas-install-apps.sh --targets HOST1,HOST2,... (--list LIST_NAME | --package PACKAGE_ID) [options]

Options:
  --request PATH      Closed validated-deployment request for the canonical PowerShell front door
  --transport VALUE  Auto, WinRM, or SmbScheduledTask (default: WinRM)
  --transport-preflight PATH
                      Fresh single-target P02 result required by Auto/SmbScheduledTask
  --targets HOSTS     Comma-separated target hostnames (maximum 25)
  --list NAME         Named app list from sources.yaml
  --package ID        One package from configs/software-packages/approved-apps.json
  --yaml PATH         Path to sources.yaml (default: Config/sources.yaml)
  --catalog PATH      Approved package catalog (default: configs/software-packages/approved-apps.json)
  --repo-root PATH    Remote path to software repo on targets (default: C:\SoftwareRepo)
  --share NAME        Admin share name (default: C$)
  --remote-base PATH  Target staging parent (default: C:\ProgramData\SysAdminSuite\AppInstall)
  --remote-pwsh PATH  Path to powershell.exe on remote hosts
  --task-name NAME    Scheduled task name (default: SysAdminSuite_AppInstall)
  --smb-user USER     SMB username (or set SAS_SMB_USER)
  --smb-pass PASS     SMB password (or set SAS_SMB_PASS)
  --smb-domain DOM    SMB domain (or set SAS_SMB_DOMAIN)
  --timeout SEC       SMB timeout seconds (default: 10)
  --wait-timeout SEC  Maximum installer-result wait per target (default: 1800)
  --dry-run           Generate worker script and print schtasks commands without executing
  --allow-legacy      Enable only the preserved --list/--package compatibility mode
  --no-teardown       Debug only: leave transient worker/launcher/task artifacts on targets
  --log-dir PATH      Output log directory (default: bash/apps/output)
  -h, --help          Show help

Environment variables:
  SAS_SMB_USER, SAS_SMB_PASS, SAS_SMB_DOMAIN, SAS_REPO_ROOT

Notes:
  - --request delegates to scripts/Invoke-SasValidatedSoftwareDeployment.ps1 and is the primary supported path.
  - The canonical SmbScheduledTask mode uses the current Windows token and never accepts SMB secrets.
  - --list/--package is temporary compatibility mode and retains its legacy gate until parity tests pass.
  - On Windows, uses the current approved admin token with PowerShell Copy-Item and schtasks.exe.
  - On non-Windows hosts, smbclient remains available for admin-share transport.
  - The generated worker script (sas-install-worker.ps1) is dropped via admin share,
    then a one-time scheduled task runs it as SYSTEM on each target.
  - Results are copied back under bash/apps/output before run-scoped target staging is removed.
USAGE
}

fail() { printf '[sas-install] ERROR: %s\n' "$*" >&2; exit 1; }
log()  { printf '[sas-install] %s\n' "$*" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

windows_path() {
  local path="$1"
  if [[ "$path" == \\\\* ]]; then
    printf '%s' "$path"
  elif has_cmd cygpath; then
    cygpath -w "$path"
  else
    printf '%s' "$path"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)     TARGETS_RAW="${2:?missing value for --targets}"; shift 2 ;;
    --request)     REQUEST_PATH="${2:?missing value for --request}"; shift 2 ;;
    --transport)   CANONICAL_TRANSPORT="${2:?missing value for --transport}"; shift 2 ;;
    --transport-preflight) TRANSPORT_PREFLIGHT_PATH="${2:?missing value for --transport-preflight}"; shift 2 ;;
    --list)        LIST_NAME="${2:?missing value for --list}"; shift 2 ;;
    --package)     PACKAGE_ID="${2:?missing value for --package}"; shift 2 ;;
    --yaml)        SOURCES_YAML="${2:?missing value for --yaml}"; shift 2 ;;
    --catalog)     PACKAGE_CATALOG="${2:?missing value for --catalog}"; shift 2 ;;
    --repo-root)   REPO_ROOT="${2:?missing value for --repo-root}"; shift 2 ;;
    --share)       SHARE="${2:?missing value for --share}"; shift 2 ;;
    --remote-base) REMOTE_BASE_ROOT="${2:?missing value for --remote-base}"; shift 2 ;;
    --remote-pwsh) REMOTE_PWSH="${2:?missing value for --remote-pwsh}"; shift 2 ;;
    --task-name)   TASK_NAME="${2:?missing value for --task-name}"; shift 2 ;;
    --smb-user)    SMB_USER="${2:?missing value for --smb-user}"; shift 2 ;;
    --smb-pass)    SMB_PASS="${2:?missing value for --smb-pass}"; shift 2 ;;
    --smb-domain)  SMB_DOMAIN="${2:?missing value for --smb-domain}"; shift 2 ;;
    --timeout)     TIMEOUT="${2:?missing value for --timeout}"; shift 2 ;;
    --wait-timeout) WAIT_TIMEOUT="${2:?missing value for --wait-timeout}"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --allow-legacy) ALLOW_LEGACY=1; shift ;;
    --no-teardown) NO_TEARDOWN=1; shift ;;
    --log-dir)     LOG_DIR="${2:?missing value for --log-dir}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    --) shift; break ;;
    -*) fail "Unknown option: $1" ;;
    *) fail "Unexpected argument: $1" ;;
  esac
done

if [[ -n "$REQUEST_PATH" ]]; then
  [[ -z "$TARGETS_RAW" && -z "$LIST_NAME" && -z "$PACKAGE_ID" ]] \
    || fail "--request cannot be combined with the --targets/--list/--package compatibility mode"
  [[ "$CANONICAL_TRANSPORT" =~ ^(Auto|WinRM|SmbScheduledTask)$ ]] \
    || fail "--transport must be Auto, WinRM, or SmbScheduledTask"
  [[ "$ALLOW_LEGACY" -eq 0 ]] || fail "--allow-legacy is not used by the canonical --request mode"
  [[ "$NO_TEARDOWN" -eq 0 ]] || fail "--no-teardown is forbidden by the canonical --request mode"
  [[ -z "$SMB_USER" && -z "$SMB_PASS" && -z "$SMB_DOMAIN" ]] \
    || fail "canonical deployment uses the current Windows token; do not supply SMB credential options or environment variables"
  [[ -f "$REQUEST_PATH" ]] || fail "validated deployment request not found: $REQUEST_PATH"
  if [[ "$CANONICAL_TRANSPORT" =~ ^(Auto|SmbScheduledTask)$ ]]; then
    [[ -n "$TRANSPORT_PREFLIGHT_PATH" ]] || fail "$CANONICAL_TRANSPORT requires --transport-preflight PATH"
    [[ -f "$TRANSPORT_PREFLIGHT_PATH" ]] || fail "transport preflight result not found: $TRANSPORT_PREFLIGHT_PATH"
  fi
  has_cmd powershell.exe || fail "canonical --request mode requires Windows PowerShell (powershell.exe)"

  CANONICAL_SCRIPT="$(windows_path "$SAS_REPO_ROOT/scripts/Invoke-SasValidatedSoftwareDeployment.ps1")"
  REQUEST_WINDOWS="$(windows_path "$REQUEST_PATH")"
  CANONICAL_ARGS=(-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$CANONICAL_SCRIPT" -RequestPath "$REQUEST_WINDOWS" -Transport "$CANONICAL_TRANSPORT")
  if [[ -n "$TRANSPORT_PREFLIGHT_PATH" ]]; then
    PREFLIGHT_WINDOWS="$(windows_path "$TRANSPORT_PREFLIGHT_PATH")"
    CANONICAL_ARGS+=(-TransportPreflightPath "$PREFLIGHT_WINDOWS")
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    CANONICAL_ARGS+=(-WhatIf)
  else
    CANONICAL_ARGS+=(-AllowTargetMutation)
  fi
  MSYS_NO_PATHCONV=1 powershell.exe "${CANONICAL_ARGS[@]}"
  exit $?
fi

LEGACY_GATE_ARGS=(--tool "bash/apps/sas-install-apps.sh")
if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

[[ "$ALLOW_LEGACY" -eq 1 ]] && LEGACY_GATE_ARGS+=(--allow-legacy)
bash scripts/sas-legacy-gate.sh "${LEGACY_GATE_ARGS[@]}" || exit $?
if [[ "$NO_TEARDOWN" -eq 1 && "$ALLOW_LEGACY" -ne 1 && "${SAS_ALLOW_LEGACY_TOOLS:-0}" != "1" ]]; then
  fail "--no-teardown requires --allow-legacy or SAS_ALLOW_LEGACY_TOOLS=1"
fi

[[ -n "$TARGETS_RAW" ]] || fail "--targets is required"
if [[ -n "$LIST_NAME" && -n "$PACKAGE_ID" ]]; then
  fail "use exactly one of --list or --package"
fi
if [[ -z "$LIST_NAME" && -z "$PACKAGE_ID" ]]; then
  fail "one of --list or --package is required"
fi
has_cmd python3 || fail "python3 is required"
if [[ -n "$LIST_NAME" ]]; then
  [[ -f "$SOURCES_YAML" ]] || fail "sources.yaml not found: $SOURCES_YAML"
else
  [[ -f "$PACKAGE_CATALOG" ]] || fail "approved package catalog not found: $PACKAGE_CATALOG"
  LIST_NAME="package-${PACKAGE_ID}"
fi

# Input validation — reject shell metacharacters in user-supplied values
[[ "$LIST_NAME" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "--list contains invalid characters: $LIST_NAME"
[[ -z "$PACKAGE_ID" || "$PACKAGE_ID" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "--package contains invalid characters: $PACKAGE_ID"
[[ "$TASK_NAME" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "--task-name contains invalid characters: $TASK_NAME"
[[ "$SHARE"     =~ ^[A-Za-z0-9_\$]+$  ]] || fail "--share contains invalid characters: $SHARE"
[[ "$SHARE" == 'C$' ]] || fail "--share must be C$ because target staging is constrained to the C: drive"
[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -ge 1 && "$TIMEOUT" -le 300 ]] || fail "--timeout must be 1-300 seconds"
[[ "$WAIT_TIMEOUT" =~ ^[0-9]+$ && "$WAIT_TIMEOUT" -ge 10 && "$WAIT_TIMEOUT" -le 7200 ]] || fail "--wait-timeout must be 10-7200 seconds"
[[ "$REMOTE_BASE_ROOT" =~ ^C:\\ProgramData\\SysAdminSuite\\AppInstall(\\[A-Za-z0-9_.-]+)*$ ]] \
  || fail "--remote-base must remain under C:\\ProgramData\\SysAdminSuite\\AppInstall"

IFS=',' read -r -a TARGETS_UNSANITIZED <<< "$TARGETS_RAW"
TARGETS=()
for _t in "${TARGETS_UNSANITIZED[@]}"; do
  _t="$(echo "$_t" | tr -d ' ')"
  [[ -z "$_t" ]] && continue
  [[ "$_t" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "Target hostname contains invalid characters: $_t"
  TARGETS+=("$_t")
done
[[ "${#TARGETS[@]}" -gt 0 ]] || fail "No valid targets after sanitizing --targets"
[[ "${#TARGETS[@]}" -le 25 ]] || fail "Target count exceeds the guarded maximum of 25"

mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y%m%d_%H%M%S')"
RUN_ID="app-install-${STAMP}-$$"
REMOTE_BASE="${REMOTE_BASE_ROOT}\\${RUN_ID}"
TASK_NAME="${TASK_NAME}_${STAMP}_$$"
WORKER_SCRIPT_PATH="$LOG_DIR/sas-install-worker-${LIST_NAME}-${STAMP}.ps1"
PACKAGE_SOURCE_PATH=""
PACKAGE_DISPLAY_NAME=""
PACKAGE_INSTALLER_FILE=""
PACKAGE_TYPE=""
PACKAGE_ARGUMENTS_JSON="[]"

if [[ -n "$PACKAGE_ID" ]]; then
  PACKAGE_METADATA="$(python3 - "$PACKAGE_CATALOG" "harness/api/sas-harness-api.json" "$PACKAGE_ID" <<'PY'
import json
import ntpath
import sys

catalog_path, api_path, package_id = sys.argv[1:]
with open(catalog_path, encoding="utf-8-sig") as handle:
    catalog = json.load(handle)
with open(api_path, encoding="utf-8-sig") as handle:
    api = json.load(handle)

root = str(catalog.get("software_share_root", "")).strip().replace("/", "\\").rstrip("\\") + "\\"
approved = {
    str(item).strip().replace("/", "\\").rstrip("\\").lower() + "\\"
    for item in api.get("posture", {}).get("approved_software_sources", [])
}
if root.lower() not in approved:
    raise SystemExit("catalog software_share_root is not approved by harness/api/sas-harness-api.json")

matches = [item for item in catalog.get("packages", []) if str(item.get("id", "")).lower() == package_id.lower()]
if len(matches) != 1:
    raise SystemExit(f"approved package id not found or ambiguous: {package_id}")
package = matches[0]
if not package.get("install_enabled"):
    raise SystemExit(f"package is not enabled for installation: {package_id}")

folder = str(package.get("source_folder_relative_path") or "").strip().strip("\\/").replace("/", "\\")
installer = str(package.get("installer_file") or "").strip().lstrip("\\/")
if not folder or not installer or ".." in folder.split("\\") or ".." in installer.replace("/", "\\").split("\\"):
    raise SystemExit(f"package does not have a safe pinned installer path: {package_id}")
if ntpath.isabs(folder) or ntpath.isabs(installer):
    raise SystemExit(f"package installer path must remain relative to the approved root: {package_id}")
if ntpath.basename(installer) != installer or any(char in installer for char in '<>:"/\\|?*'):
    raise SystemExit(f"package installer_file must be one pinned filename: {package_id}")

extension = ntpath.splitext(installer)[1].lower()
if extension not in {".msi", ".exe"}:
    raise SystemExit(f"scheduled-task package mode supports pinned MSI or EXE installers only: {installer}")
raw_arguments = package.get("default_installer_arguments", [])
if not isinstance(raw_arguments, list):
    raise SystemExit(f"package default_installer_arguments must be an array: {package_id}")
arguments = [str(item) for item in raw_arguments if str(item).strip()]
if package.get("requires_validated_installer_arguments") and not arguments:
    raise SystemExit(f"package requires validated installer arguments before live or dry-run use: {package_id}")

print(root + folder + "\\" + installer)
print(str(package.get("display_name") or package_id))
print(installer)
print(extension.lstrip("."))
print(json.dumps(arguments, separators=(",", ":")))
PY
  )" || fail "could not resolve approved package metadata: $PACKAGE_ID"
  mapfile -t PACKAGE_FIELDS <<< "$PACKAGE_METADATA"
  [[ "${#PACKAGE_FIELDS[@]}" -eq 5 ]] || fail "approved package metadata was incomplete: $PACKAGE_ID"
  # Native Windows Python writes CRLF even when invoked from Git Bash. mapfile
  # removes LF but preserves CR, so normalize each metadata field before it is
  # used as a UNC source, filename, installer type, or JSON argument payload.
  for _package_field_index in "${!PACKAGE_FIELDS[@]}"; do
    PACKAGE_FIELDS[$_package_field_index]="${PACKAGE_FIELDS[$_package_field_index]%$'\r'}"
  done
  PACKAGE_SOURCE_PATH="${PACKAGE_FIELDS[0]}"
  PACKAGE_DISPLAY_NAME="${PACKAGE_FIELDS[1]}"
  PACKAGE_INSTALLER_FILE="${PACKAGE_FIELDS[2]}"
  PACKAGE_TYPE="${PACKAGE_FIELDS[3]}"
  PACKAGE_ARGUMENTS_JSON="${PACKAGE_FIELDS[4]}"
fi

# Write Python worker-generator to temp file — avoids bash double-quote expansion
# issues that occur with python3 -c "$var" when Python code contains " characters.
_PY_WORKER_GEN="$(mktemp /tmp/sas-install-XXXXXX.py)"
trap 'rm -f "$_PY_WORKER_GEN"' EXIT

cat > "$_PY_WORKER_GEN" << 'PYEOF'
import sys, json

yaml_path   = sys.argv[1]
list_name   = sys.argv[2]
repo_root   = sys.argv[3]
remote_base = sys.argv[4]
package_id = sys.argv[5]
package_display_name = sys.argv[6]
package_installer_file = sys.argv[7]
package_type = sys.argv[8]
package_arguments = json.loads(sys.argv[9])

def parse_sources_yaml(path):
    with open(path, encoding='utf-8-sig') as f:
        lines = f.readlines()
    apps = []; lists = {}; i = 0; n = len(lines)

    def strip_comment(s):
        result = []; in_sq = False
        for ch in s:
            if ch == "'" and not in_sq: in_sq = True; result.append(ch); continue
            if ch == "'" and in_sq: in_sq = False; result.append(ch); continue
            if ch == '#' and not in_sq: break
            result.append(ch)
        return ''.join(result).rstrip()

    def unquote(s):
        s = s.strip()
        if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
            return s[1:-1]
        return s

    def indent_of(line): return len(line) - len(line.lstrip())

    while i < n:
        raw = lines[i]; line = strip_comment(raw).rstrip(); stripped = line.lstrip()
        if not stripped or stripped.startswith('#'): i += 1; continue
        ind = indent_of(raw)
        if ind == 0 and ':' in stripped:
            key = stripped.split(':', 1)[0].strip()
            if key == 'apps':
                i += 1
                while i < n:
                    raw2 = lines[i]; line2 = strip_comment(raw2).rstrip(); stripped2 = line2.lstrip()
                    if not stripped2 or stripped2.startswith('#'): i += 1; continue
                    ind2 = indent_of(raw2)
                    if ind2 == 0 and not stripped2.startswith('-'): break
                    if stripped2.startswith('- ') and ind2 == 2:
                        app = {}
                        rest = stripped2[2:].strip()
                        if ':' in rest:
                            k2, v2 = rest.split(':', 1); app[k2.strip()] = unquote(v2.strip())
                        i += 1
                        while i < n:
                            raw3 = lines[i]; line3 = strip_comment(raw3).rstrip(); stripped3 = line3.lstrip()
                            if not stripped3 or stripped3.startswith('#'): i += 1; continue
                            ind3 = indent_of(raw3)
                            if ind3 <= 2 and ind3 != 4: break
                            if ':' in stripped3:
                                k3, v3 = stripped3.split(':', 1); app[k3.strip()] = unquote(v3.strip())
                            i += 1
                        apps.append(app)
                    else: i += 1
                continue
            elif key == 'lists':
                i += 1; cur = None
                while i < n:
                    raw2 = lines[i]; line2 = strip_comment(raw2).rstrip(); stripped2 = line2.lstrip()
                    if not stripped2 or stripped2.startswith('#'): i += 1; continue
                    ind2 = indent_of(raw2)
                    if ind2 == 0 and not stripped2.startswith('-'): break
                    if ind2 == 2 and ':' in stripped2 and not stripped2.startswith('-'):
                        cur = stripped2.rstrip(':').strip(); lists[cur] = []; i += 1; continue
                    if ind2 == 4 and stripped2.startswith('- ') and cur:
                        lists[cur].append(stripped2[2:].strip().strip("'\"")); i += 1; continue
                    i += 1
                continue
        i += 1
    return {'apps': apps, 'lists': lists}

if package_id:
    apps = [{
        'name': package_display_name,
        'filename_template': package_installer_file,
        'type': package_type,
        'silent_args': package_arguments,
        'detect_type': '',
        'detect_value': '',
    }]
else:
    data = parse_sources_yaml(yaml_path)
    if list_name not in data['lists']:
        available = ', '.join(data['lists'].keys())
        print(f"# ERROR: List '{list_name}' not found. Available: {available}")
        sys.exit(1)

    wanted = set(data['lists'][list_name])
    apps = [a for a in data['apps'] if a.get('name', '') in wanted]

print(f"""<# ============================================================
  SysAdminSuite — App Install Worker
  Generated by sas-install-apps.sh
  List: {list_name}
  Apps: {len(apps)}
  Do not edit — regenerate by re-running sas-install-apps.sh
============================================================ #>

$ErrorActionPreference = "Stop"
$ResultsDir = Join-Path "{remote_base}" "results"
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
$ResultsFile = Join-Path $ResultsDir "install_results_{list_name}.csv"
# Prefer staged directory (populated by sas-stage-fileshare.sh), fall back to main installers dir
$StagedDir    = "{repo_root}\\staged\\{list_name}"
$InstallersDir = "{repo_root}\\installers"
$RepoInstallersDir = if (Test-Path $StagedDir) {{ $StagedDir }} else {{ $InstallersDir }}
Write-Host "Installer search path: $RepoInstallersDir" -ForegroundColor Cyan
$Results = @()

function Normalize-RegPath {{
  param([string]$Path)
  # Convert bare hive names to PowerShell provider-qualified syntax (e.g. HKLM:, HKCU:)
  $Path = $Path -replace '^HKEY_LOCAL_MACHINE\\\\', 'HKLM:\\'
  $Path = $Path -replace '^HKLM\\\\(?!:)', 'HKLM:\\'
  $Path = $Path -replace '^HKEY_CURRENT_USER\\\\', 'HKCU:\\'
  $Path = $Path -replace '^HKCU\\\\(?!:)', 'HKCU:\\'
  $Path = $Path -replace '^HKEY_CLASSES_ROOT\\\\', 'HKCR:\\'
  $Path = $Path -replace '^HKCR\\\\(?!:)', 'HKCR:\\'
  $Path = $Path -replace '^HKEY_USERS\\\\', 'HKU:\\'
  $Path = $Path -replace '^HKU\\\\(?!:)', 'HKU:\\'
  return $Path
}}

function Resolve-InstallerFile {{
  param([string]$InstallerDir, [string]$FilePattern, [string]$AssetRegex = "")
  # When asset_regex is provided, match by regex (for {{asset}} entries like Git, Obsidian, Tesseract)
  if ($AssetRegex) {{
    $found = Get-ChildItem -Path $InstallerDir -ErrorAction SilentlyContinue |
             Where-Object {{ $_.Name -match $AssetRegex }} |
             Sort-Object Name | Select-Object -Last 1
    if ($found) {{ return $found.Name }}
    return $null
  }}
  if ($FilePattern -match "[\\*\\?]") {{
    $found = Get-ChildItem -Path $InstallerDir -Filter $FilePattern -ErrorAction SilentlyContinue |
             Sort-Object Name | Select-Object -Last 1
    if ($found) {{ return $found.Name }}
    return $null
  }}
  if (Test-Path (Join-Path $InstallerDir $FilePattern)) {{ return $FilePattern }}
  return $null
}}

function Install-App {{
  param($Name, $InstallerPattern, $AssetRegex, $Type, [string[]]$SilentArgs, $DetectType, $DetectValue)
  $result = [pscustomobject]@{{
    Name          = $Name
    InstallerFile = if ($InstallerPattern) {{ $InstallerPattern }} else {{ "(regex:$AssetRegex)" }}
    ExitCode      = $null
    Detected      = $false
    Status        = "NotStarted"
    Timestamp     = (Get-Date -Format "s")
    Error         = ""
  }}
  try {{
    $resolvedName = Resolve-InstallerFile -InstallerDir $RepoInstallersDir -FilePattern $InstallerPattern -AssetRegex $AssetRegex
    if (-not $resolvedName) {{
      $result.Status = "MissingInstaller"
      $result.Error  = "Installer not found in $RepoInstallersDir matching: $InstallerPattern"
      return $result
    }}
    $installer = Join-Path $RepoInstallersDir $resolvedName
    $result.InstallerFile = $resolvedName
    $exitCode = 0
    switch ($Type.ToLower()) {{
      "msi" {{
        $argumentList = @('/i', ('"{{0}}"' -f $installer)) + @($SilentArgs)
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentList -Wait -PassThru -NoNewWindow
        $exitCode = $p.ExitCode
      }}
      "exe" {{
        $p = Start-Process -FilePath $installer -ArgumentList $SilentArgs -Wait -PassThru -NoNewWindow
        $exitCode = $p.ExitCode
      }}
      "msix" {{
        Add-AppxPackage -Path $installer -ErrorAction Stop
      }}
      "zip" {{
        Expand-Archive -Path $installer -DestinationPath (Split-Path $installer -Parent) -Force
      }}
      default {{
        throw "Unknown installer type: $Type"
      }}
    }}
    $result.ExitCode = $exitCode
    switch ($DetectType.ToLower()) {{
      "regkey" {{
        $regPath = Normalize-RegPath $DetectValue
        $result.Detected = ($null -ne (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue))
      }}
      "file"   {{ $result.Detected = Test-Path $DetectValue }}
      default  {{ $result.Detected = ($exitCode -in @(0, 3010)) }}
    }}
    $result.Status = if ($result.Detected) {{ "Installed" }} elseif ($exitCode -in @(0,3010)) {{ "ExitOK_NotDetected" }} else {{ "Failed" }}
  }} catch {{
    $result.Status = "Error"
    $result.Error  = $_.Exception.Message
  }}
  $result
}}
""")

def ps_literal(value):
    return "'" + str(value).replace("'", "''") + "'"

def ps_array(values):
    return "@(" + ", ".join(ps_literal(value) for value in values) + ")"

for a in apps:
    name       = a.get('name', '')
    ft         = a.get('filename_template', '') or ''
    ver        = a.get('version', '') or ''
    asset_rx   = (a.get('asset_regex', '') or '').replace('"', '`"')
    has_asset  = '{{asset}}' in ft
    # For {{asset}} entries: pass the asset_regex and leave InstallerPattern empty
    # For versioned/static entries: resolve {{version}} in both filename and asset_regex
    if has_asset:
        ft_r     = ''
        # substitute {{version}} in asset_regex too (for pinned github entries)
        asset_rx = asset_rx.replace('{{version}}', ver)
    else:
        ft_r     = ft.replace('{{version}}', ver)
        asset_rx = asset_rx.replace('{{version}}', ver)
    dtype      = a.get('type', '') or 'exe'
    raw_sargs  = a.get('silent_args', '') or ''
    sargs      = raw_sargs if isinstance(raw_sargs, list) else [raw_sargs]
    sargs      = [str(value) for value in sargs if str(value)]
    detype     = a.get('detect_type', '') or ''
    deval      = (a.get('detect_value', '') or '').replace('"', '`"')
    display_name = a.get('name', '')
    print(f'$Results += Install-App -Name {ps_literal(name)} -InstallerPattern {ps_literal(ft_r)} -AssetRegex {ps_literal(asset_rx)} -Type {ps_literal(dtype)} -SilentArgs {ps_array(sargs)} -DetectType {ps_literal(detype)} -DetectValue {ps_literal(deval)}')
    print(f'Write-Host ("  [{{0}}] {{1}}" -f $Results[-1].Status, {ps_literal(display_name)})')
    print()

print("""
$Results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $ResultsFile
Write-Host "Results written: $ResultsFile" -ForegroundColor Green
$failed = $Results | Where-Object { $_.Status -notin @("Installed","ExitOK_NotDetected") }
if ($failed) { Write-Warning "Failed installs: $($failed.Count)"; $failed | Format-Table Name,Status,Error -Auto }
""")
PYEOF

# ---------------------------------------------------------------------------
# Generate the PowerShell worker script from a named sources list or approved package.
# ---------------------------------------------------------------------------
log "Generating worker script for list: $LIST_NAME"

EFFECTIVE_REPO_ROOT="$REPO_ROOT"
if [[ -n "$PACKAGE_ID" ]]; then
  EFFECTIVE_REPO_ROOT="$REMOTE_BASE"
fi
python3 "$_PY_WORKER_GEN" \
  "$SOURCES_YAML" "$LIST_NAME" "$EFFECTIVE_REPO_ROOT" "$REMOTE_BASE" \
  "$PACKAGE_ID" "$PACKAGE_DISPLAY_NAME" "$PACKAGE_INSTALLER_FILE" "$PACKAGE_TYPE" "$PACKAGE_ARGUMENTS_JSON" \
  > "$WORKER_SCRIPT_PATH"

# Check that python succeeded and the worker doesn't start with an error comment
if head -1 "$WORKER_SCRIPT_PATH" | grep -q '^# ERROR:'; then
  ERR="$(head -1 "$WORKER_SCRIPT_PATH")"
  rm -f "$WORKER_SCRIPT_PATH"
  fail "$ERR"
fi

log "Worker script written: $WORKER_SCRIPT_PATH"

if [[ "$NO_TEARDOWN" -eq 0 ]]; then
  cat >> "$WORKER_SCRIPT_PATH" <<EOF

# Worker self-teardown provides best-effort cleanup if the controller is interrupted.
try {
  schtasks.exe /Delete /TN "$TASK_NAME" /F | Out-Null
} catch {
  Write-Warning "Teardown warning deleting scheduled task: \$($_.Exception.Message)"
}
foreach (\$path in @((Join-Path \$PSScriptRoot 'Start-Installer.ps1'), \$PSCommandPath)) {
  try {
    if (\$path -and (Test-Path -LiteralPath \$path)) {
      Remove-Item -LiteralPath \$path -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Warning "Teardown warning removing transient payload \${path}: \$($_.Exception.Message)"
  }
}
EOF
  log "Worker teardown enabled for transient payloads and scheduled task."
else
  log "WARN: --no-teardown requested; transient target payloads may remain for debugging."
fi

if has_cmd powershell.exe; then
  WORKER_SCRIPT_WINDOWS="$(windows_path "$WORKER_SCRIPT_PATH")"
  if ! SAS_WORKER_PATH="$WORKER_SCRIPT_WINDOWS" MSYS_NO_PATHCONV=1 \
      powershell.exe -NoProfile -NonInteractive -Command \
      '$tokens = $null; $errors = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($env:SAS_WORKER_PATH, [ref]$tokens, [ref]$errors); if (@($errors).Count -gt 0) { foreach ($parseError in $errors) { [Console]::Error.WriteLine(("WORKER_PARSE_ERROR: {0}: {1}" -f $parseError.Extent.Text, $parseError.Message)) }; exit 1 }'; then
    fail "generated PowerShell worker failed local syntax preflight"
  fi
  log "Worker syntax preflight passed with Windows PowerShell."
fi

# ---------------------------------------------------------------------------
# Admin-share transport helpers
# ---------------------------------------------------------------------------
smb_auth_args() {
  local args=()
  if [[ -n "$SMB_USER" ]]; then
    args+=(-U "${SMB_USER}%${SMB_PASS}")
  else
    args+=(-N)
  fi
  [[ -n "$SMB_DOMAIN" ]] && args+=(-W "$SMB_DOMAIN")
  printf '%s\0' "${args[@]}"
}

run_smb_cmd() {
  local target="$1" cmd="$2"
  local admin_share="//${target}/${SHARE}"
  local args=() part
  while IFS= read -r -d '' part; do args+=("$part"); done < <(smb_auth_args)
  if has_cmd timeout; then
    timeout "$TIMEOUT" smbclient "$admin_share" "${args[@]}" -c "$cmd" 2>&1 || true
  else
    smbclient "$admin_share" "${args[@]}" -c "$cmd" 2>&1 || true
  fi
}

smb_put() {
  local target="$1" local_file="$2" remote_path="$3"
  local admin_share="//${target}/${SHARE}"
  local args=() part
  while IFS= read -r -d '' part; do args+=("$part"); done < <(smb_auth_args)
  local remote_win="${remote_path//\//\\}"
  local remote_dir_win
  remote_dir_win="$(dirname "$remote_path" | sed 's|/|\\|g')"
  local cmd="mkdir \"${remote_dir_win}\"; put \"${local_file}\" \"${remote_win}\""
  local out
  if has_cmd timeout; then
    out="$(timeout "$TIMEOUT" smbclient "$admin_share" "${args[@]}" -c "$cmd" 2>&1 || true)"
  else
    out="$(smbclient "$admin_share" "${args[@]}" -c "$cmd" 2>&1 || true)"
  fi
  if echo "$out" | grep -iq 'NT_STATUS_ACCESS\|NT_STATUS_HOST\|Connection.*failed\|timed out'; then
    printf 'smb_put FAIL: %s\n' "$out" >&2; return 1
  fi
  return 0
}

remote_unc_path() {
  local target="$1" remote_path="$2"
  local remote_win="${remote_path//\//\\}"
  printf '\\\\%s\\%s\\%s' "$target" "$SHARE" "$remote_win"
}

native_test_share() {
  local target="$1"
  SAS_ADMIN_SHARE="\\\\${target}\\${SHARE}" MSYS_NO_PATHCONV=1 \
    powershell.exe -NoProfile -NonInteractive -Command \
      '$ErrorActionPreference="Stop"; if (-not (Test-Path -LiteralPath $env:SAS_ADMIN_SHARE -PathType Container)) { exit 3 }' \
      >/dev/null 2>&1
}

native_put() {
  local target="$1" local_file="$2" remote_path="$3"
  local source_win destination_unc
  source_win="$(windows_path "$local_file")"
  destination_unc="$(remote_unc_path "$target" "$remote_path")"
  SAS_COPY_SOURCE="$source_win" SAS_COPY_DESTINATION="$destination_unc" MSYS_NO_PATHCONV=1 \
    powershell.exe -NoProfile -NonInteractive -Command \
      '$ErrorActionPreference="Stop"; $parent = Split-Path -Parent $env:SAS_COPY_DESTINATION; New-Item -ItemType Directory -Path $parent -Force | Out-Null; Copy-Item -LiteralPath $env:SAS_COPY_SOURCE -Destination $env:SAS_COPY_DESTINATION -Force' \
      >/dev/null
}

native_remote_file_exists() {
  local target="$1" remote_path="$2" remote_unc
  remote_unc="$(remote_unc_path "$target" "$remote_path")"
  SAS_REMOTE_PATH="$remote_unc" MSYS_NO_PATHCONV=1 \
    powershell.exe -NoProfile -NonInteractive -Command \
      'if (Test-Path -LiteralPath $env:SAS_REMOTE_PATH -PathType Leaf) { exit 0 }; exit 1' \
      >/dev/null 2>&1
}

native_get() {
  local target="$1" remote_path="$2" local_file="$3"
  local source_unc destination_win
  source_unc="$(remote_unc_path "$target" "$remote_path")"
  destination_win="$(windows_path "$local_file")"
  SAS_COPY_SOURCE="$source_unc" SAS_COPY_DESTINATION="$destination_win" MSYS_NO_PATHCONV=1 \
    powershell.exe -NoProfile -NonInteractive -Command \
      '$ErrorActionPreference="Stop"; Copy-Item -LiteralPath $env:SAS_COPY_SOURCE -Destination $env:SAS_COPY_DESTINATION -Force' \
      >/dev/null
}

native_remove_run_root() {
  local target="$1" remote_path="$2" remote_unc
  [[ "$remote_path" =~ ^ProgramData/SysAdminSuite/AppInstall(/[A-Za-z0-9_.-]+)*/app-install-[0-9]{8}_[0-9]{6}-[0-9]+$ ]] \
    || { printf 'Refusing cleanup outside validated run root: %s\n' "$remote_path" >&2; return 1; }
  remote_unc="$(remote_unc_path "$target" "$remote_path")"
  SAS_REMOTE_RUN_ROOT="$remote_unc" MSYS_NO_PATHCONV=1 \
    powershell.exe -NoProfile -NonInteractive -Command \
      '$ErrorActionPreference="Stop"; $run = $env:SAS_REMOTE_RUN_ROOT; if (Test-Path -LiteralPath $run) { Remove-Item -LiteralPath $run -Recurse -Force }; $parent = Split-Path -Parent $run; if ((Test-Path -LiteralPath $parent) -and @(Get-ChildItem -LiteralPath $parent -Force).Count -eq 0) { Remove-Item -LiteralPath $parent -Force }' \
      >/dev/null
}

smb_get() {
  local target="$1" remote_path="$2" local_file="$3"
  local remote_win="${remote_path//\//\\}"
  local out
  out="$(run_smb_cmd "$target" "get \"${remote_win}\" \"${local_file}\"")"
  ! echo "$out" | grep -Eiq 'NT_STATUS_|Error|failed'
}

remote_put() {
  local target="$1" local_file="$2" remote_path="$3"
  if [[ "$TRANSPORT" == "windows-native" ]]; then
    native_put "$target" "$local_file" "$remote_path"
  else
    smb_put "$target" "$local_file" "$remote_path"
  fi
}

remote_file_exists() {
  local target="$1" remote_path="$2"
  if [[ "$TRANSPORT" == "windows-native" ]]; then
    native_remote_file_exists "$target" "$remote_path"
  else
    local remote_win="${remote_path//\//\\}"
    run_smb_cmd "$target" "allinfo \"${remote_win}\"" | grep -q 'attributes:'
  fi
}

remote_get() {
  local target="$1" remote_path="$2" local_file="$3"
  if [[ "$TRANSPORT" == "windows-native" ]]; then
    native_get "$target" "$remote_path" "$local_file"
  else
    smb_get "$target" "$remote_path" "$local_file"
  fi
}

remove_remote_run_root() {
  local target="$1"
  if [[ "$TRANSPORT" == "windows-native" ]]; then
    native_remove_run_root "$target" "$REMOTE_BASE_SMB"
  else
    run_smb_cmd "$target" "deltree \"${REMOTE_BASE_SMB//\//\\}\"" >/dev/null
  fi
}

delete_remote_task() {
  local target="$1"
  local query_output delete_output
  if ! query_output="$(MSYS_NO_PATHCONV=1 schtasks.exe /Query /S "$target" /TN "$TASK_NAME" 2>&1)"; then
    if echo "$query_output" | grep -Eiq 'cannot find|does not exist|not exist'; then
      return 0
    fi
    printf 'Scheduled-task cleanup query failed on %s: %s\n' "$target" "$query_output" >&2
    return 1
  fi
  if ! delete_output="$(MSYS_NO_PATHCONV=1 schtasks.exe /Delete /S "$target" /TN "$TASK_NAME" /F 2>&1)"; then
    printf 'Scheduled-task cleanup failed on %s: %s\n' "$target" "$delete_output" >&2
    return 1
  fi
}

TRANSPORT="dry-run"
if [[ "$DRY_RUN" -eq 0 ]]; then
  if has_cmd powershell.exe && has_cmd schtasks.exe; then
    TRANSPORT="windows-native"
    if [[ -n "$SMB_USER" || -n "$SMB_PASS" || -n "$SMB_DOMAIN" ]]; then
      fail "Windows-native transport uses the current approved admin token; do not supply SMB credential options"
    fi
  elif has_cmd smbclient && has_cmd schtasks.exe; then
    TRANSPORT="smbclient"
  else
    fail "requires Windows powershell.exe + schtasks.exe, or smbclient + schtasks.exe"
  fi
fi
if [[ -n "$PACKAGE_ID" && "$DRY_RUN" -eq 0 && "$TRANSPORT" != "windows-native" ]]; then
  fail "approved-package mode requires the Windows-native admin-share transport"
fi

# ---------------------------------------------------------------------------
# Per-host orchestration
# ---------------------------------------------------------------------------
REMOTE_BASE_UNIX="${REMOTE_BASE//\\//}"
REMOTE_WORKER_REMOTE="${REMOTE_BASE}\\sas-install-worker.ps1"
REMOTE_LAUNCHER_REMOTE="${REMOTE_BASE}\\Start-Installer.ps1"
# SMB-relative path: strip drive letter prefix (C:/ProgramData/... -> ProgramData/...)
# so smbclient resolves correctly under \\HOST\C$ without doubling the drive letter.
REMOTE_BASE_SMB="${REMOTE_BASE_UNIX#*/}"
REMOTE_BASE_SMB_WIN="${REMOTE_BASE_SMB//\//\\}"
REMOTE_WORKER_PATH="${REMOTE_BASE_SMB}/sas-install-worker.ps1"
REMOTE_LAUNCHER_PATH="${REMOTE_BASE_SMB}/Start-Installer.ps1"
REMOTE_RESULT_PATH="${REMOTE_BASE_SMB}/results/install_results_${LIST_NAME}.csv"

SUCCESS_COUNT=0
FAIL_COUNT=0

for TARGET in "${TARGETS[@]}"; do
  LOG_HOST="$LOG_DIR/sas-install-${TARGET}-${LIST_NAME}-${STAMP}.log"
  log "=== Processing target: $TARGET ==="

  _host_ok=0
  {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $TARGET selection=$LIST_NAME transport=$TRANSPORT"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY-RUN] Would copy worker to \\\\${TARGET}\\${SHARE}\\${REMOTE_BASE_SMB_WIN}\\sas-install-worker.ps1"
      if [[ -n "$PACKAGE_ID" ]]; then
        echo "[DRY-RUN] Approved package: ${PACKAGE_DISPLAY_NAME} (${PACKAGE_ID})"
        echo "[DRY-RUN] Pinned installer: ${PACKAGE_SOURCE_PATH}"
        echo "[DRY-RUN] Would stage installer to \\\\${TARGET}\\${SHARE}\\${REMOTE_BASE_SMB_WIN}\\staged\\${LIST_NAME}\\${PACKAGE_INSTALLER_FILE}"
      fi
      echo "[DRY-RUN] schtasks /Create /S ${TARGET} /RU SYSTEM /SC ONCE /ST HH:MM /TN ${TASK_NAME} /TR \"\\\"${REMOTE_PWSH}\\\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \\\"${REMOTE_LAUNCHER_REMOTE}\\\"\" /RL HIGHEST /F"
      echo "[DRY-RUN] schtasks /Run /S ${TARGET} /TN ${TASK_NAME}"
      if [[ "$NO_TEARDOWN" -eq 0 ]]; then
        echo "[DRY-RUN] Would copy results locally, delete task ${TASK_NAME}, and remove only run root ${REMOTE_BASE}"
      else
        echo "[DRY-RUN] --no-teardown would leave worker artifacts for debugging"
      fi
      echo "DRY_RUN_OK"
    else
      _deploy_ok=1
      _task_created=0
      if [[ "$TRANSPORT" == "windows-native" ]]; then
        if ! native_test_share "$TARGET"; then
          echo "ERROR: Admin share unavailable or access denied: \\\\${TARGET}\\${SHARE}"
          _deploy_ok=0
        fi
      else
        RECON_OUT="$(run_smb_cmd "$TARGET" "pwd")"
        if echo "$RECON_OUT" | grep -Eiq 'NT_STATUS_ACCESS_DENIED|LOGON_FAILURE|NT_STATUS_HOST_UNREACHABLE|Connection.*failed|timed out'; then
          echo "ERROR: Admin share unavailable or access denied: \\\\${TARGET}\\${SHARE}"
          _deploy_ok=0
        fi
      fi
      [[ "$_deploy_ok" -eq 1 ]] && echo "Share reachable: \\\\${TARGET}\\${SHARE}"

      if [[ "$_deploy_ok" -eq 1 && -n "$PACKAGE_ID" ]]; then
        REMOTE_PACKAGE_PATH="${REMOTE_BASE_SMB}/staged/${LIST_NAME}/${PACKAGE_INSTALLER_FILE}"
        if remote_put "$TARGET" "$PACKAGE_SOURCE_PATH" "$REMOTE_PACKAGE_PATH"; then
          echo "Staged pinned package: ${PACKAGE_INSTALLER_FILE}"
        else
          echo "ERROR: Failed to stage approved package from ${PACKAGE_SOURCE_PATH}"
          _deploy_ok=0
        fi
      fi

      if [[ "$_deploy_ok" -eq 1 ]] && ! remote_put "$TARGET" "$WORKER_SCRIPT_PATH" "$REMOTE_WORKER_PATH"; then
        echo "ERROR: Failed to copy worker script to $TARGET"
        _deploy_ok=0
      fi

      LAUNCHER_TMP="$LOG_DIR/launcher-${TARGET}-${STAMP}.ps1"
      if [[ "$_deploy_ok" -eq 1 ]]; then
        printf '$ErrorActionPreference = "Stop"\n& "%s"\n' "$REMOTE_WORKER_REMOTE" > "$LAUNCHER_TMP"
        if remote_put "$TARGET" "$LAUNCHER_TMP" "$REMOTE_LAUNCHER_PATH"; then
          echo "Copied transient worker and launcher."
        else
          echo "ERROR: Failed to copy launcher to $TARGET"
          _deploy_ok=0
        fi
      fi
      rm -f "$LAUNCHER_TMP"

      if [[ "$_deploy_ok" -eq 1 ]]; then
        WHEN="$(date -d '+1 minute' '+%H:%M' 2>/dev/null || date -v+1M '+%H:%M' 2>/dev/null || echo '00:01')"
        TASK_CMD="\"${REMOTE_PWSH}\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"${REMOTE_LAUNCHER_REMOTE}\""
        echo "Scheduling one-time task: $TASK_NAME on $TARGET at $WHEN"
        if MSYS_NO_PATHCONV=1 schtasks.exe /Create /S "$TARGET" /RU SYSTEM /SC ONCE /ST "$WHEN" \
            /TN "$TASK_NAME" /TR "$TASK_CMD" /RL HIGHEST /F; then
          _task_created=1
          if MSYS_NO_PATHCONV=1 schtasks.exe /Run /S "$TARGET" /TN "$TASK_NAME"; then
            echo "Task triggered; waiting up to ${WAIT_TIMEOUT}s for installer result."
          else
            echo "ERROR: schtasks /Run failed on $TARGET"
            _deploy_ok=0
          fi
        else
          echo "ERROR: schtasks /Create failed on $TARGET"
          _deploy_ok=0
        fi
      fi

      LOCAL_RESULT="$LOG_DIR/sas-install-${TARGET}-${LIST_NAME}-${STAMP}.results.csv"
      if [[ "$_deploy_ok" -eq 1 ]]; then
        DEADLINE=$((SECONDS + WAIT_TIMEOUT))
        while ! remote_file_exists "$TARGET" "$REMOTE_RESULT_PATH"; do
          if (( SECONDS >= DEADLINE )); then
            echo "ERROR: Timed out waiting for installer result on $TARGET"
            _deploy_ok=0
            break
          fi
          sleep 2
        done
      fi

      if [[ "$_deploy_ok" -eq 1 ]]; then
        if remote_get "$TARGET" "$REMOTE_RESULT_PATH" "$LOCAL_RESULT"; then
          echo "Result copied locally: $LOCAL_RESULT"
          if python3 - "$LOCAL_RESULT" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="", encoding="utf-8-sig") as handle:
    rows = list(csv.DictReader(handle))
if not rows:
    raise SystemExit("installer result is empty")
allowed = {"Installed", "ExitOK_NotDetected"}
failed = [row for row in rows if row.get("Status") not in allowed]
if failed:
    for row in failed:
        print(f"FAILED_RESULT: {row.get('Name')}: {row.get('Status')}: {row.get('Error')}")
    raise SystemExit(1)
PY
          then
            echo "Installer result accepted; completing teardown verification."
          else
            echo "ERROR: Installer result contains failed or unresolved rows"
            _deploy_ok=0
          fi
        else
          echo "ERROR: Could not copy installer result from $TARGET"
          _deploy_ok=0
        fi
      fi

      if [[ "$NO_TEARDOWN" -eq 0 ]]; then
        _cleanup_ok=1
        if [[ "$_task_created" -eq 1 ]] && ! delete_remote_task "$TARGET"; then
          echo "ERROR: Cleanup could not verify scheduled-task removal: ${TASK_NAME}"
          _cleanup_ok=0
        fi
        if remove_remote_run_root "$TARGET"; then
          echo "Run-scoped staging cleanup complete or already absent."
        else
          echo "ERROR: Cleanup failed for run root ${REMOTE_BASE}"
          _cleanup_ok=0
        fi
        if [[ "$_cleanup_ok" -eq 1 ]]; then
          echo "Cleanup complete: task and run-scoped staging removed or already absent."
        else
          _deploy_ok=0
        fi
      else
        echo "WARN: Debug retention enabled; remote run root retained: ${REMOTE_BASE}"
      fi

      if [[ "$_deploy_ok" -eq 1 ]]; then
        echo "HOST_OK"
      else
        echo "HOST_FAILED"
      fi
    fi
  } 2>&1 | tee "$LOG_HOST"
  if grep -q 'DRY_RUN_OK\|HOST_OK' "$LOG_HOST" && ! grep -q 'HOST_FAILED' "$LOG_HOST"; then
    _host_ok=1
  fi

  if [[ "$_host_ok" -eq 1 ]]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

log "=== Complete: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed ==="
log "Worker script: $WORKER_SCRIPT_PATH"
[[ "$FAIL_COUNT" -gt 0 ]] && exit 1 || exit 0
