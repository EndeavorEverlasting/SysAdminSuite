#Requires -Version 5.1
<#
.SYNOPSIS
  Launch ScanSnap Home silent install exactly once using PID-delta routing.

.DESCRIPTION
  - Serializes launches with a named mutex.
  - Refuses duplicate installer processes.
  - Treats an already-detected installation as idempotent success without launching.
  - Snapshots before/after process state and records the selected installer PID.
  - Waits for the launched/selected process tree to finish.
  - Requires both an acceptable launcher exit code and executable detection.
  - Writes runtime evidence only beneath the ignored ScanSnap evidence directory.

  SilentArgs are measured vendor InstallShield arguments and the response file is
  staged beside the EXE.
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
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Installer missing: $exe" }
if (-not (Test-Path -LiteralPath $iss -PathType Leaf)) { throw "Response file missing: $iss" }
if (-not (Test-Path -LiteralPath $routePath -PathType Leaf)) { throw "Route manifest missing: $routePath" }

$route = Get-Content -LiteralPath $routePath -Raw -Encoding UTF8 | ConvertFrom-Json
$privateEvidenceRoot = [IO.Path]::GetFullPath((Join-Path $PackageRoot 'evidence'))
if (-not $EvidencePath) {
  $EvidencePath = Join-Path $privateEvidenceRoot ("silent-install_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))
}
$EvidencePath = [IO.Path]::GetFullPath($EvidencePath)
$rootWithSep = $privateEvidenceRoot.TrimEnd('\') + '\'
if (-not $EvidencePath.StartsWith($rootWithSep, [StringComparison]::OrdinalIgnoreCase)) {
  throw "EvidencePath must remain under ignored private evidence root: $privateEvidenceRoot"
}

function Get-SsDetectionHit {
  param($Route)
  foreach ($cand in @($Route.detection_seed.DetectValueCandidates)) {
    $p = [string]$cand
    if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
  }
  return $null
}

function Get-SsProcessRows {
  @(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
    $gp = Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue
    [pscustomobject]@{
      pid = [int]$_.ProcessId
      parent_pid = [int]$_.ParentProcessId
      name = [string]$_.Name
      path = [string]$_.ExecutablePath
      command_line = [string]$_.CommandLine
      window_title = $(if ($gp) { [string]$gp.MainWindowTitle } else { '' })
    }
  })
}

function Test-SsInstallerRow {
  param($Row, $Route)
  $nameBase = [IO.Path]::GetFileNameWithoutExtension([string]$Row.name)
  foreach ($excluded in @($Route.exclude_process_names)) {
    if ($nameBase -ieq [string]$excluded) { return $false }
  }
  $nameHit = @($Route.process_name_candidates | Where-Object { $nameBase -ieq [string]$_ }).Count -gt 0
  $titleHit = -not [string]::IsNullOrWhiteSpace([string]$Row.window_title) -and
    [string]$Row.window_title -match [string]$Route.window_title_pattern
  $pathText = ("{0} {1}" -f [string]$Row.path, [string]$Row.command_line)
  $pathHit = @($Route.path_fragment_candidates | Where-Object {
    $pathText -match [regex]::Escape([string]$_)
  }).Count -gt 0
  return $nameHit -or ($pathHit -and $titleHit)
}

function Get-SsActiveProcessTree {
  param([int[]]$RootPids)
  $rows = @(Get-SsProcessRows)
  $ids = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($id in @($RootPids)) {
    if ($id -gt 0) { [void]$ids.Add([int]$id) }
  }
  do {
    $changed = $false
    foreach ($row in $rows) {
      if ($ids.Contains([int]$row.parent_pid) -and -not $ids.Contains([int]$row.pid)) {
        [void]$ids.Add([int]$row.pid)
        $changed = $true
      }
    }
  } while ($changed)
  @($rows | Where-Object { $ids.Contains([int]$_.pid) })
}

function Write-SsReceipt {
  param($Receipt, [string]$Path)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  ($Receipt | ConvertTo-Json -Depth 7) | Set-Content -LiteralPath $Path -Encoding UTF8
  Write-Host ("Silent install final_class={0} evidence={1}" -f $Receipt.final_class, $Path)
  [pscustomobject]$Receipt | ConvertTo-Json -Depth 7
}

$mutex = [System.Threading.Mutex]::new($false, 'Global\SysAdminSuite_ScanSnap_SilentInstall_v1')
$lockAcquired = $false
$scriptExit = 2

try {
  try {
    $lockAcquired = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $lockAcquired = $true
  }
  if (-not $lockAcquired) {
    throw 'Another ScanSnap silent-install run owns the single-launch mutex.'
  }

  $existingDetect = Get-SsDetectionHit -Route $route
  if ($existingDetect) {
    $receipt = [ordered]@{
      schema_version = 'scansnap-silent-install-receipt/v1'
      controller = [string]$env:COMPUTERNAME
      finished_at_utc = (Get-Date).ToUniversalTime().ToString('o')
      launched_pid = $null
      selected_pid = $null
      selected_name = $null
      installer_exit_code = $null
      silent_args = $SilentArgs
      detect_hit = $existingDetect
      final_class = 'ALREADY_INSTALLED'
    }
    Write-SsReceipt -Receipt $receipt -Path $EvidencePath
    $scriptExit = 0
  }
  else {
    $already = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
      ($_.MainWindowTitle -and $_.MainWindowTitle -match [string]$route.window_title_pattern) -or
      ([IO.Path]::GetFileNameWithoutExtension([string]$_.ProcessName) -in @($route.process_name_candidates))
    })
    if ($already.Count -gt 0) {
      $ids = ($already | ForEach-Object { $_.Id }) -join ','
      throw "Refusing silent launch; installer already open (pids=$ids). AttachExisting instead."
    }

    $before = @(Get-SsProcessRows)
    $beforeIds = @($before | ForEach-Object { [int]$_.pid })
    $launcherName = [IO.Path]::GetFileName($exe)
    $proc = Start-Process -FilePath $exe -ArgumentList $SilentArgs -WorkingDirectory $installers -PassThru -ErrorAction Stop
    $launchedPid = [int]$proc.Id

    Start-Sleep -Seconds 2
    $after = @(Get-SsProcessRows)
    $delta = @($after | Where-Object { $_.pid -notin $beforeIds -or $_.pid -eq $launchedPid })
    $selected = $delta | Where-Object { Test-SsInstallerRow -Row $_ -Route $route } |
      Sort-Object pid -Descending | Select-Object -First 1

    if (-not $selected) {
      $selected = [pscustomobject]@{
        pid = $launchedPid
        parent_pid = 0
        name = $launcherName
        path = $exe
        command_line = ''
        window_title = ''
      }
    }

    $roots = @($launchedPid, [int]$selected.pid) | Select-Object -Unique
    $deadline = [DateTime]::UtcNow.AddSeconds($MaxWaitSeconds)
    $activeTree = @()
    do {
      Start-Sleep -Seconds 3
      $activeTree = @(Get-SsActiveProcessTree -RootPids $roots)
      if ($activeTree.Count -eq 0) { break }
    } while ([DateTime]::UtcNow -lt $deadline)

    $timedOut = $activeTree.Count -gt 0 -and [DateTime]::UtcNow -ge $deadline
    $exitCode = $null
    try {
      $proc.Refresh()
      if ($proc.HasExited) { $exitCode = [int]$proc.ExitCode }
    } catch {}

    $detectHit = Get-SsDetectionHit -Route $route
    $acceptableExit = $null -ne $exitCode -and $exitCode -in @(0, 1641, 3010)

    if ($timedOut) {
      $finalClass = 'INSTALLER_TIMEOUT'
      $scriptExit = 3
    }
    elseif ($null -ne $exitCode -and -not $acceptableExit) {
      $finalClass = 'INSTALLER_EXIT_NONZERO'
      $scriptExit = 2
    }
    elseif ($acceptableExit -and $detectHit) {
      $finalClass = 'SOFTWARE_INSTALL_DETECTED'
      $scriptExit = 0
    }
    elseif ($detectHit) {
      $finalClass = 'DETECT_PRESENT_EXIT_UNPROVEN'
      $scriptExit = 2
    }
    else {
      $finalClass = 'INSTALLER_FINISHED_NO_DETECT'
      $scriptExit = 2
    }

    $receipt = [ordered]@{
      schema_version = 'scansnap-silent-install-receipt/v1'
      controller = [string]$env:COMPUTERNAME
      finished_at_utc = (Get-Date).ToUniversalTime().ToString('o')
      launched_pid = $launchedPid
      selected_pid = [int]$selected.pid
      selected_name = [string]$selected.name
      installer_exit_code = $exitCode
      silent_args = $SilentArgs
      detect_hit = $detectHit
      final_class = $finalClass
    }
    Write-SsReceipt -Receipt $receipt -Path $EvidencePath
  }
}
finally {
  if ($lockAcquired) {
    try { $mutex.ReleaseMutex() } catch {}
  }
  $mutex.Dispose()
}

exit $scriptExit
