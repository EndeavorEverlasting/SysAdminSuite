#Requires -Version 5.1
<#
.SYNOPSIS
  Launch ScanSnap Home silent install exactly once using PID-delta routing.

.DESCRIPTION
  1) Refuse if a matching wizard/installer is already open.
  2) Snapshot process IDs.
  3) Launch WinSSHomeInstaller with the measured InstallShield response file.
  4) Compute PID delta and persist selected PID metadata.
  5) Wait for completion and evaluate DetectValue candidates.

  Does not invent SilentArgs — uses the vendor ISS companion staged beside the EXE.
#>
[CmdletBinding()]
param(
  [string]$PackageRoot = $PSScriptRoot,
  [string]$InstallerFileName = 'WinSSHomeInstaller_4_1_0.exe',
  [string]$ResponseFileName = 'WinSSHomeInstaller_4_1_0.iss',
  [string]$SilentArgs = '-s -f1".\WinSSHomeInstaller_4_1_0.iss"',
  [int]$MaxWaitSeconds = 1200,
  [string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installers = Join-Path $PackageRoot 'installers'
$routePath = Join-Path $PackageRoot 'installer-process-route.v1.json'
$exe = Join-Path $installers $InstallerFileName
$iss = Join-Path $installers $ResponseFileName
if (-not (Test-Path -LiteralPath $exe)) { throw "Installer missing: $exe" }
if (-not (Test-Path -LiteralPath $iss)) { throw "Response file missing: $iss" }
if (-not (Test-Path -LiteralPath $routePath)) { throw "Route manifest missing: $routePath" }

$route = Get-Content -LiteralPath $routePath -Raw -Encoding UTF8 | ConvertFrom-Json

$already = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
  ($_.MainWindowTitle -and $_.MainWindowTitle -match [string]$route.window_title_pattern) -or
  ($_.ProcessName -in @($route.process_name_candidates))
})
if ($already.Count -gt 0) {
  $ids = ($already | ForEach-Object { $_.Id }) -join ','
  throw "Refusing silent launch; installer already open (pids=$ids). AttachExisting instead."
}

$before = @(Get-CimInstance Win32_Process | ForEach-Object { [int]$_.ProcessId })
$proc = Start-Process -FilePath $exe -ArgumentList $SilentArgs -WorkingDirectory $installers -PassThru
Start-Sleep -Seconds 2

$after = @(Get-CimInstance Win32_Process | ForEach-Object {
  $gp = Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue
  [pscustomobject]@{
    pid = [int]$_.ProcessId
    parent_pid = [int]$_.ParentProcessId
    name = [string]$_.Name
    path = [string]$_.ExecutablePath
    window_title = $(if ($gp) { [string]$gp.MainWindowTitle } else { '' })
  }
})
$delta = @($after | Where-Object { $_.pid -notin $before -or $_.pid -eq [int]$proc.Id })
$selected = @($delta | Where-Object {
  $base = [IO.Path]::GetFileNameWithoutExtension($_.name)
  ($base -in @($route.process_name_candidates)) -or
  ($_.path -match 'WinSSHomeInstaller|SSHome|ScanSnap') -or
  ($_.window_title -match [string]$route.window_title_pattern)
} | Sort-Object pid -Descending | Select-Object -First 1)
if (-not $selected) {
  $selected = $after | Where-Object { $_.pid -eq [int]$proc.Id } | Select-Object -First 1
}

$route.last_observed.controller = [string]$env:COMPUTERNAME
$route.last_observed.process_name = [IO.Path]::GetFileNameWithoutExtension([string]$selected.name)
$route.last_observed.window_title = [string]$selected.window_title
$route.last_observed.path_fragment = 'WinSSHomeInstaller'
$route.last_observed.pid = [int]$selected.pid
$route.last_observed.observed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
$route.last_observed.notes = "Silent launch via Invoke-ScanSnapSilentInstall.ps1 args=$SilentArgs"
($route | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $routePath -Encoding UTF8

$deadline = [DateTime]::UtcNow.AddSeconds($MaxWaitSeconds)
$detectHit = $null
do {
  Start-Sleep -Seconds 5
  foreach ($cand in @($route.detection_seed.DetectValueCandidates)) {
    if (Test-Path -LiteralPath ([string]$cand)) { $detectHit = [string]$cand; break }
  }
  $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
  if ($detectHit -and -not $alive) { break }
  if (-not $alive) {
    $kids = @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $proc.Id })
    if ($kids.Count -eq 0) { break }
  }
} while ([DateTime]::UtcNow -lt $deadline)

$exitCode = $null
try { $proc.Refresh(); if ($proc.HasExited) { $exitCode = [int]$proc.ExitCode } } catch {}
if (-not $detectHit) {
  foreach ($cand in @($route.detection_seed.DetectValueCandidates)) {
    if (Test-Path -LiteralPath ([string]$cand)) { $detectHit = [string]$cand; break }
  }
}

$result = [ordered]@{
  schema_version = 'scansnap-silent-install-receipt/v1'
  controller = [string]$env:COMPUTERNAME
  finished_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  launched_pid = [int]$proc.Id
  selected_pid = [int]$selected.pid
  selected_name = [string]$selected.name
  installer_exit_code = $exitCode
  silent_args = $SilentArgs
  detect_hit = $detectHit
  final_class = $(if ($detectHit) { 'SOFTWARE_INSTALL_DETECTED' } else { 'INSTALLER_FINISHED_NO_DETECT' })
}

if (-not $EvidencePath) {
  $EvidencePath = Join-Path $PackageRoot ("evidence\silent-install_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EvidencePath) | Out-Null
($result | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
Write-Host ("Silent install final_class={0} evidence={1}" -f $result.final_class, $EvidencePath)
[pscustomobject]$result | ConvertTo-Json -Depth 6
if ($detectHit) { exit 0 } else { exit 2 }
