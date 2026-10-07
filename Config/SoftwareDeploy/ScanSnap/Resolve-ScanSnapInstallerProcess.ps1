#Requires -Version 5.1
<#
.SYNOPSIS
  Resolve the exact ScanSnap Home installer PID using before/after process delta.

.DESCRIPTION
  SysAdminSuite-aligned PID routing for ScanSnap package qualification:
    1) snapshot process IDs
    2) optionally launch the installer once
    3) snapshot again and compute the PID delta
    4) filter delta by durable process-name / window-title / path metadata
    5) persist the selected PID metadata for future agent runs

  Attach mode binds an already-open wizard without launching another copy.
#>
[CmdletBinding()]
param(
  [ValidateSet('Snapshot', 'LaunchAndResolve', 'AttachExisting')]
  [string]$Mode = 'AttachExisting',

  [string]$InstallerPath,

  [int]$AttachPid = 0,

  [int]$ReadyTimeoutSeconds = 90,

  [string]$RouteManifestPath,

  [string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RouteManifestPath) {
  $RouteManifestPath = Join-Path $packageRoot 'installer-process-route.v1.json'
}
if (-not (Test-Path -LiteralPath $RouteManifestPath)) {
  throw "Installer process route manifest missing: $RouteManifestPath"
}

$route = Get-Content -LiteralPath $RouteManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$route.schema_version -ne 'scansnap-installer-process-route/v1') {
  throw "Unsupported route schema: $($route.schema_version)"
}

function Get-SsProcessSnapshot {
  $rows = @(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
    $proc = $null
    try { $proc = Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue } catch { $proc = $null }
    $title = ''
    if ($proc) {
      try { $title = [string]$proc.MainWindowTitle } catch { $title = '' }
    }
    [pscustomobject]@{
      pid           = [int]$_.ProcessId
      parent_pid    = [int]$_.ParentProcessId
      name          = [string]$_.Name
      path          = [string]$_.ExecutablePath
      command_line  = [string]$_.CommandLine
      window_title  = $title
    }
  })
  return $rows
}

function Test-SsInstallerCandidate {
  param($Row, $Route)
  $nameBase = [IO.Path]::GetFileNameWithoutExtension([string]$Row.name)
  foreach ($excluded in @($Route.exclude_process_names)) {
    if ($nameBase -ieq [string]$excluded) { return $false }
  }
  $nameHit = $false
  foreach ($cand in @($Route.process_name_candidates)) {
    if ($nameBase -ieq [string]$cand -or [string]$Row.name -like ("{0}*" -f $cand)) {
      $nameHit = $true
      break
    }
  }
  $pathHit = $false
  $pathText = ("{0} {1}" -f [string]$Row.path, [string]$Row.command_line)
  foreach ($frag in @($Route.path_fragment_candidates)) {
    if ($pathText -match [regex]::Escape([string]$frag)) {
      $pathHit = $true
      break
    }
  }
  $titleHit = $false
  if (-not [string]::IsNullOrWhiteSpace([string]$Row.window_title) -and
      [string]$Row.window_title -match [string]$Route.window_title_pattern) {
    $titleHit = $true
  }
  return ($nameHit -or $pathHit) -and ($titleHit -or $nameHit -or $pathHit)
}

function Select-SsInstallerFromRows {
  param([object[]]$Rows, $Route, [int[]]$DeltaPids)
  $scoped = @($Rows)
  if ($DeltaPids -and $DeltaPids.Count -gt 0) {
    $deltaSet = @{}
    foreach ($d in $DeltaPids) { $deltaSet[[int]$d] = $true }
    $scoped = @($Rows | Where-Object { $deltaSet.ContainsKey([int]$_.pid) })
  }
  $candidates = @($scoped | Where-Object { Test-SsInstallerCandidate -Row $_ -Route $Route })
  if ($candidates.Count -eq 0) { return $null }
  # Prefer exact window-title match, then newest PID.
  $titled = @($candidates | Where-Object { $_.window_title -match [string]$Route.window_title_pattern })
  if ($titled.Count -gt 0) {
    return ($titled | Sort-Object pid -Descending | Select-Object -First 1)
  }
  return ($candidates | Sort-Object pid -Descending | Select-Object -First 1)
}

function Wait-SsInstallerSurface {
  param([int]$ProcessId, [string]$TitlePattern, [int]$TimeoutSeconds)
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) {
      return [pscustomobject]@{ ready = $false; detail = 'process_exited'; window_title = '' }
    }
    $title = ''
    try { $title = [string]$proc.MainWindowTitle } catch { $title = '' }
    $handleReady = $proc.MainWindowHandle -ne [IntPtr]::Zero
    if ($handleReady -and $title -match $TitlePattern) {
      return [pscustomobject]@{ ready = $true; detail = 'window_title_matched'; window_title = $title }
    }
    Start-Sleep -Milliseconds 500
  } while ([DateTime]::UtcNow -lt $deadline)
  return [pscustomobject]@{ ready = $false; detail = 'timeout_waiting_for_window'; window_title = '' }
}

function Save-SsRouteObservation {
  param($Route, $Selected, [string]$Path)
  $Route.last_observed.controller = [string]$env:COMPUTERNAME
  $Route.last_observed.process_name = [IO.Path]::GetFileNameWithoutExtension([string]$Selected.name)
  $Route.last_observed.window_title = [string]$Selected.window_title
  $Route.last_observed.pid = [int]$Selected.pid
  $Route.last_observed.observed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  $pathText = ("{0}" -f [string]$Selected.path)
  foreach ($frag in @($Route.path_fragment_candidates)) {
    if ($pathText -match [regex]::Escape([string]$frag)) {
      $Route.last_observed.path_fragment = [string]$frag
      break
    }
  }
  ($Route | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $Path -Encoding UTF8
}

$before = @(Get-SsProcessSnapshot)
$beforeIds = @($before | ForEach-Object { [int]$_.pid })
$launchedPid = $null
$selected = $null

switch ($Mode) {
  'Snapshot' {
    $selected = Select-SsInstallerFromRows -Rows $before -Route $route -DeltaPids @()
  }
  'AttachExisting' {
    if ($AttachPid -gt 0) {
      $selected = @($before | Where-Object { [int]$_.pid -eq $AttachPid } | Select-Object -First 1)
      if (-not $selected) { throw "AttachPid $AttachPid is not running." }
      if (-not (Test-SsInstallerCandidate -Row $selected -Route $route)) {
        throw "AttachPid $AttachPid does not match ScanSnap installer route metadata."
      }
    }
    else {
      $selected = Select-SsInstallerFromRows -Rows $before -Route $route -DeltaPids @()
      if (-not $selected) {
        throw 'No existing ScanSnap installer wizard matched route metadata. Use -Mode LaunchAndResolve with -InstallerPath, or pass -AttachPid.'
      }
    }
  }
  'LaunchAndResolve' {
    if ([string]::IsNullOrWhiteSpace($InstallerPath) -or -not (Test-Path -LiteralPath $InstallerPath)) {
      throw "InstallerPath required for LaunchAndResolve: $InstallerPath"
    }
    # Refuse second launch when a matching wizard already exists.
    $existing = Select-SsInstallerFromRows -Rows $before -Route $route -DeltaPids @()
    if ($existing) {
      throw ("Refusing LaunchAndResolve: installer already open pid={0} title='{1}'. AttachExisting instead." -f $existing.pid, $existing.window_title)
    }
    $p = Start-Process -FilePath $InstallerPath -PassThru -ErrorAction Stop
    $launchedPid = [int]$p.Id
    $deadline = [DateTime]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
    do {
      Start-Sleep -Milliseconds 750
      $after = @(Get-SsProcessSnapshot)
      $afterIds = @($after | ForEach-Object { [int]$_.pid })
      $delta = @($afterIds | Where-Object { $_ -notin $beforeIds })
      $selected = Select-SsInstallerFromRows -Rows $after -Route $route -DeltaPids $delta
      if (-not $selected -and $launchedPid -gt 0) {
        $selected = Select-SsInstallerFromRows -Rows @($after | Where-Object { [int]$_.pid -eq $launchedPid -or [int]$_.parent_pid -eq $launchedPid }) -Route $route -DeltaPids @()
      }
      if ($selected) {
        $ready = Wait-SsInstallerSurface -ProcessId ([int]$selected.pid) -TitlePattern ([string]$route.window_title_pattern) -TimeoutSeconds 5
        if ($ready.ready) {
          $selected.window_title = $ready.window_title
          break
        }
      }
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $selected) {
      throw 'LaunchAndResolve failed: no installer PID matched the delta + route metadata.'
    }
  }
}

if (-not $selected) {
  throw 'No ScanSnap installer process selected.'
}

# Refresh title from live process
$live = Get-Process -Id ([int]$selected.pid) -ErrorAction SilentlyContinue
if ($live) {
  try { $selected.window_title = [string]$live.MainWindowTitle } catch {}
}

Save-SsRouteObservation -Route $route -Selected $selected -Path $RouteManifestPath

$result = [ordered]@{
  schema_version     = 'scansnap-installer-process-resolve/v1'
  mode               = $Mode
  controller         = [string]$env:COMPUTERNAME
  captured_at_utc    = (Get-Date).ToUniversalTime().ToString('o')
  before_pid_count   = $beforeIds.Count
  launched_pid       = $launchedPid
  selected_pid       = [int]$selected.pid
  selected_parent    = [int]$selected.parent_pid
  selected_name      = [string]$selected.name
  selected_path      = [string]$selected.path
  selected_title     = [string]$selected.window_title
  route_manifest     = $RouteManifestPath
  strategy           = [string]$route.strategy.name
}

if ($EvidencePath) {
  $dir = Split-Path -Parent $EvidencePath
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  ($result | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}

[pscustomobject]$result | ConvertTo-Json -Depth 6
exit 0
