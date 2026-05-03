#!/usr/bin/env bash
# SysAdminSuite — sas-install-apps.sh
# Orchestrates silent installation of apps on remote Windows hosts.
# For each target: verifies admin-share access, drops a generated PowerShell
# worker script (sas-install-worker.ps1), then creates and triggers a scheduled
# task mirroring the pattern in mapping/Controllers/Map-Run-Controller.ps1.
#
# Usage:
#   ./bash/apps/sas-install-apps.sh --targets HOST1,HOST2 --list LIST_NAME [options]
#
# Examples:
#   ./bash/apps/sas-install-apps.sh --targets WKS001,WKS002 --list workstation-baseline
#   ./bash/apps/sas-install-apps.sh --targets WKS001 --list lab-tools --dry-run

set -euo pipefail

TARGETS_RAW=""
LIST_NAME=""
SOURCES_YAML="Config/sources.yaml"
REPO_ROOT="${SAS_REPO_ROOT:-C:\SoftwareRepo}"
SHARE="C$"
REMOTE_BASE='C:\ProgramData\SysAdminSuite\AppInstall'
REMOTE_PWSH='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
TASK_NAME="SysAdminSuite_AppInstall"
SMB_USER="${SAS_SMB_USER:-}"
SMB_PASS="${SAS_SMB_PASS:-}"
SMB_DOMAIN="${SAS_SMB_DOMAIN:-}"
TIMEOUT=10
DRY_RUN=0
LOG_DIR="bash/apps/output"

usage() {
  cat <<'USAGE'
SysAdminSuite — Remote App Installer Orchestrator

Usage:
  ./bash/apps/sas-install-apps.sh --targets HOST1,HOST2,... --list LIST_NAME [options]

Options:
  --targets HOSTS     Comma-separated list of target hostnames
  --list NAME         Named app list from sources.yaml
  --yaml PATH         Path to sources.yaml (default: Config/sources.yaml)
  --repo-root PATH    Remote path to software repo on targets (default: C:\SoftwareRepo)
  --share NAME        Admin share name (default: C$)
  --remote-base PATH  Remote base path for worker scripts (default: C:\ProgramData\SysAdminSuite\AppInstall)
  --remote-pwsh PATH  Path to powershell.exe on remote hosts
  --task-name NAME    Scheduled task name (default: SysAdminSuite_AppInstall)
  --smb-user USER     SMB username (or set SAS_SMB_USER)
  --smb-pass PASS     SMB password (or set SAS_SMB_PASS)
  --smb-domain DOM    SMB domain (or set SAS_SMB_DOMAIN)
  --timeout SEC       SMB timeout seconds (default: 10)
  --dry-run           Generate worker script and print schtasks commands without executing
  --log-dir PATH      Output log directory (default: bash/apps/output)
  -h, --help          Show help

Environment variables:
  SAS_SMB_USER, SAS_SMB_PASS, SAS_SMB_DOMAIN, SAS_REPO_ROOT

Notes:
  - Requires smbclient for admin share operations.
  - The generated worker script (sas-install-worker.ps1) is dropped via admin share,
    then a one-time scheduled task runs it as SYSTEM on each target.
  - Result files are written to \\TARGET\C$\ProgramData\SysAdminSuite\AppInstall\results\
USAGE
}

fail() { printf '[sas-install] ERROR: %s\n' "$*" >&2; exit 1; }
log()  { printf '[sas-install] %s\n' "$*" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)     TARGETS_RAW="${2:?missing value for --targets}"; shift 2 ;;
    --list)        LIST_NAME="${2:?missing value for --list}"; shift 2 ;;
    --yaml)        SOURCES_YAML="${2:?missing value for --yaml}"; shift 2 ;;
    --repo-root)   REPO_ROOT="${2:?missing value for --repo-root}"; shift 2 ;;
    --share)       SHARE="${2:?missing value for --share}"; shift 2 ;;
    --remote-base) REMOTE_BASE="${2:?missing value for --remote-base}"; shift 2 ;;
    --remote-pwsh) REMOTE_PWSH="${2:?missing value for --remote-pwsh}"; shift 2 ;;
    --task-name)   TASK_NAME="${2:?missing value for --task-name}"; shift 2 ;;
    --smb-user)    SMB_USER="${2:?missing value for --smb-user}"; shift 2 ;;
    --smb-pass)    SMB_PASS="${2:?missing value for --smb-pass}"; shift 2 ;;
    --smb-domain)  SMB_DOMAIN="${2:?missing value for --smb-domain}"; shift 2 ;;
    --timeout)     TIMEOUT="${2:?missing value for --timeout}"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --log-dir)     LOG_DIR="${2:?missing value for --log-dir}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    --) shift; break ;;
    -*) fail "Unknown option: $1" ;;
    *) fail "Unexpected argument: $1" ;;
  esac
done

[[ -n "$TARGETS_RAW" ]] || fail "--targets is required"
[[ -n "$LIST_NAME" ]]   || fail "--list is required"
has_cmd python3           || fail "python3 is required"
[[ -f "$SOURCES_YAML" ]] || fail "sources.yaml not found: $SOURCES_YAML"

# Input validation — reject shell metacharacters in user-supplied values
[[ "$LIST_NAME" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "--list contains invalid characters: $LIST_NAME"
[[ "$TASK_NAME" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "--task-name contains invalid characters: $TASK_NAME"
[[ "$SHARE"     =~ ^[A-Za-z0-9_\$]+$  ]] || fail "--share contains invalid characters: $SHARE"

IFS=',' read -r -a TARGETS_UNSANITIZED <<< "$TARGETS_RAW"
TARGETS=()
for _t in "${TARGETS_UNSANITIZED[@]}"; do
  _t="$(echo "$_t" | tr -d ' ')"
  [[ -z "$_t" ]] && continue
  [[ "$_t" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "Target hostname contains invalid characters: $_t"
  TARGETS+=("$_t")
done
[[ "${#TARGETS[@]}" -gt 0 ]] || fail "No valid targets after sanitizing --targets"

mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y%m%d_%H%M%S')"
WORKER_SCRIPT_PATH="$LOG_DIR/sas-install-worker-${LIST_NAME}-${STAMP}.ps1"

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
  param($Name, $InstallerPattern, $AssetRegex, $Type, $SilentArgs, $DetectType, $DetectValue)
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
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList ("/i `"$installer`" $SilentArgs") -Wait -PassThru -NoNewWindow
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

for a in apps:
    name       = a.get('name', '').replace('"', '`"')
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
    sargs      = (a.get('silent_args', '') or '').replace('"', '`"')
    detype     = a.get('detect_type', '') or ''
    deval      = (a.get('detect_value', '') or '').replace('"', '`"')
    display_name = a.get('name', '')
    print(f'$Results += Install-App -Name "{name}" -InstallerPattern "{ft_r}" -AssetRegex "{asset_rx}" -Type "{dtype}" -SilentArgs "{sargs}" -DetectType "{detype}" -DetectValue "{deval}"')
    print(f'Write-Host "  [$($Results[-1].Status)] {display_name}"')
    print()

print("""
$Results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $ResultsFile
Write-Host "Results written: $ResultsFile" -ForegroundColor Green
$failed = $Results | Where-Object { $_.Status -notin @("Installed","ExitOK_NotDetected") }
if ($failed) { Write-Warning "Failed installs: $($failed.Count)"; $failed | Format-Table Name,Status,Error -Auto }
""")
PYEOF

# ---------------------------------------------------------------------------
# Generate the PowerShell worker script from sources.yaml
# ---------------------------------------------------------------------------
log "Generating worker script for list: $LIST_NAME"

python3 "$_PY_WORKER_GEN" \
  "$SOURCES_YAML" "$LIST_NAME" "$REPO_ROOT" "$REMOTE_BASE" \
  > "$WORKER_SCRIPT_PATH"

# Check that python succeeded and the worker doesn't start with an error comment
if head -1 "$WORKER_SCRIPT_PATH" | grep -q '^# ERROR:'; then
  ERR="$(head -1 "$WORKER_SCRIPT_PATH")"
  rm -f "$WORKER_SCRIPT_PATH"
  fail "$ERR"
fi

log "Worker script written: $WORKER_SCRIPT_PATH"

# ---------------------------------------------------------------------------
# SMB helper
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

# ---------------------------------------------------------------------------
# Per-host orchestration
# ---------------------------------------------------------------------------
REMOTE_BASE_UNIX="${REMOTE_BASE//\\//}"
REMOTE_WORKER_REMOTE="${REMOTE_BASE}\\sas-install-worker.ps1"
REMOTE_LAUNCHER_REMOTE="${REMOTE_BASE}\\Start-Installer.ps1"
# SMB-relative path: strip drive letter prefix (C:/ProgramData/... -> ProgramData/...)
# so smbclient resolves correctly under \\HOST\C$ without doubling the drive letter.
REMOTE_BASE_SMB="${REMOTE_BASE_UNIX#*/}"

SUCCESS_COUNT=0
FAIL_COUNT=0

for TARGET in "${TARGETS[@]}"; do
  LOG_HOST="$LOG_DIR/sas-install-${TARGET}-${LIST_NAME}-${STAMP}.log"
  log "=== Processing target: $TARGET ==="

  _host_ok=0
  {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $TARGET list=$LIST_NAME"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY-RUN] Would copy worker to \\\\${TARGET}\\${SHARE}\\${REMOTE_BASE_SMB}\\sas-install-worker.ps1"
      echo "[DRY-RUN] schtasks /Create /S ${TARGET} /RU SYSTEM /SC ONCE /ST HH:MM /TN ${TASK_NAME} /TR \"${REMOTE_PWSH} -File ${REMOTE_WORKER_REMOTE}\" /RL HIGHEST /F"
      echo "[DRY-RUN] schtasks /Run /S ${TARGET} /TN ${TASK_NAME}"
      echo "DRY_RUN_OK"
    elif ! has_cmd smbclient; then
      echo "ERROR: smbclient not found — cannot push to $TARGET"
    else
      # Check admin share reachability
      RECON_OUT="$(run_smb_cmd "$TARGET" "pwd")"
      if echo "$RECON_OUT" | grep -Eiq 'NT_STATUS_ACCESS_DENIED|LOGON_FAILURE'; then
        echo "ERROR: Access denied on \\\\${TARGET}\\${SHARE}"
      elif echo "$RECON_OUT" | grep -Eiq 'NT_STATUS_HOST_UNREACHABLE|Connection.*failed|timed out'; then
        echo "ERROR: Host unreachable: $TARGET"
      else
        echo "Share reachable: \\\\${TARGET}\\${SHARE}"
        _deploy_ok=1

        # Copy worker script — use SMB-relative path (no drive letter prefix)
        REMOTE_WORKER_PATH="${REMOTE_BASE_SMB}/sas-install-worker.ps1"
        if ! smb_put "$TARGET" "$WORKER_SCRIPT_PATH" "$REMOTE_WORKER_PATH"; then
          echo "ERROR: Failed to copy worker script to $TARGET"
          _deploy_ok=0
        fi

        if [[ "$_deploy_ok" -eq 1 ]]; then
          echo "Copied worker -> \\\\${TARGET}\\${SHARE}\\${REMOTE_WORKER_PATH}"

          # Generate and copy launcher script — use SMB-relative path for smbclient,
          # Windows path (REMOTE_LAUNCHER_REMOTE) for the scheduled task /TR argument.
          LAUNCHER_TMP="$LOG_DIR/launcher-${TARGET}-${STAMP}.ps1"
          printf '\$ErrorActionPreference = "Stop"\n& "%s"\n' "$REMOTE_WORKER_REMOTE" > "$LAUNCHER_TMP"
          REMOTE_LAUNCHER_PATH="${REMOTE_BASE_SMB}/Start-Installer.ps1"
          if ! smb_put "$TARGET" "$LAUNCHER_TMP" "$REMOTE_LAUNCHER_PATH"; then
            echo "WARN: Failed to copy launcher to $TARGET — task may still run via worker directly"
          else
            echo "Copied launcher -> \\\\${TARGET}\\${SHARE}\\${REMOTE_LAUNCHER_PATH}"
          fi
          rm -f "$LAUNCHER_TMP"

          # Schedule and run task
          WHEN="$(date -d '+1 minute' '+%H:%M' 2>/dev/null || date -v+1M '+%H:%M' 2>/dev/null || echo '00:01')"
          TASK_CMD="\"${REMOTE_PWSH}\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"${REMOTE_LAUNCHER_REMOTE}\""
          CREATE_CMD="schtasks /Create /S ${TARGET} /RU SYSTEM /SC ONCE /ST ${WHEN} /TN ${TASK_NAME} /TR ${TASK_CMD} /RL HIGHEST /F"
          RUN_CMD="schtasks /Run /S ${TARGET} /TN ${TASK_NAME}"

          echo "Scheduling task: $TASK_NAME on $TARGET at $WHEN"
          if ! has_cmd cmd.exe; then
            echo "ERROR: cmd.exe not available — cannot schedule task on $TARGET; must run on a Windows host"
          else
            _sched_ok=0
            if cmd.exe /c "$CREATE_CMD" 2>&1; then
              echo "Task created."
              if cmd.exe /c "$RUN_CMD" 2>&1; then
                echo "Task triggered."
                _sched_ok=1
              else
                echo "ERROR: schtasks /Run failed on $TARGET"
              fi
            else
              echo "ERROR: schtasks /Create failed on $TARGET"
            fi
            if [[ "$_sched_ok" -eq 1 ]]; then
              echo "Results will appear at: \\\\${TARGET}\\${SHARE}\\ProgramData\\SysAdminSuite\\AppInstall\\results\\"
              echo "HOST_OK"
            fi
          fi
        fi
      fi
    fi
  } 2>&1 | tee "$LOG_HOST" | grep -q 'DRY_RUN_OK\|HOST_OK' && _host_ok=1 || true

  if [[ "$_host_ok" -eq 1 ]]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

log "=== Complete: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed ==="
log "Worker script: $WORKER_SCRIPT_PATH"
[[ "$FAIL_COUNT" -gt 0 ]] && exit 1 || exit 0
