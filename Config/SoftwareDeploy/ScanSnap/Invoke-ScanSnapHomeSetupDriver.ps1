#Requires -Version 5.1
<#
.SYNOPSIS
  Drive ScanSnap Home Setup through the recommended Typical path for one exact PID.

.DESCRIPTION
  Binds exclusively to a resolved installer PID (from Resolve-ScanSnapInstallerProcess.ps1).
  Advances the wizard with focused-window keystrokes. Does not launch installers.
  Post-install scanner model setup is closed/skipped for unattended qualification.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [int]$ProcessId,

  [int]$MaxSteps = 40,

  [int]$StepDelayMs = 1500,

  [int]$InstallWaitSeconds = 1200,

  [string]$RouteManifestPath,

  [string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RouteManifestPath) {
  $RouteManifestPath = Join-Path $packageRoot 'installer-process-route.v1.json'
}
$route = Get-Content -LiteralPath $RouteManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$titlePattern = [string]$route.window_title_pattern

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SsFocus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  public const int SW_RESTORE = 9;
}
"@

function Get-SsLiveProcess {
  param([int]$Id)
  $p = Get-Process -Id $Id -ErrorAction SilentlyContinue
  if (-not $p) { return $null }
  $title = ''
  try { $title = [string]$p.MainWindowTitle } catch { $title = '' }
  return [pscustomobject]@{
    pid = $p.Id
    name = $p.ProcessName
    title = $title
    handle = $p.MainWindowHandle
    has_exited = $p.HasExited
    responding = $(try { [bool]$p.Responding } catch { $true })
  }
}

function Focus-SsWindow {
  param($Live)
  if (-not $Live -or $Live.handle -eq [IntPtr]::Zero) { return $false }
  if ([SsFocus]::IsIconic($Live.handle)) {
    [void][SsFocus]::ShowWindow($Live.handle, [SsFocus]::SW_RESTORE)
  }
  return [SsFocus]::SetForegroundWindow($Live.handle)
}

function Send-SsKeys {
  param([string]$Keys)
  [System.Windows.Forms.SendKeys]::SendWait($Keys)
}

$steps = New-Object System.Collections.Generic.List[object]
$startedUtc = (Get-Date).ToUniversalTime()
$installPhaseEntered = $false
$completed = $false
$finalClass = 'IN_PROGRESS'

for ($i = 1; $i -le $MaxSteps; $i++) {
  $live = Get-SsLiveProcess -Id $ProcessId
  if (-not $live) {
    # Parent bootstrap may exit after spawning child installer — search children/route candidates.
    $children = @(Get-CimInstance Win32_Process | Where-Object {
      $_.ParentProcessId -eq $ProcessId -or
      ([IO.Path]::GetFileNameWithoutExtension([string]$_.Name) -in @($route.process_name_candidates))
    })
    $replacement = $null
    foreach ($c in $children) {
      $cp = Get-Process -Id ([int]$c.ProcessId) -ErrorAction SilentlyContinue
      if ($cp -and $cp.MainWindowTitle -match $titlePattern) {
        $replacement = [int]$c.ProcessId
        break
      }
    }
    if ($replacement) {
      $steps.Add([pscustomobject]@{
        step = $i; event = 'PID_REBINDED'; from = $ProcessId; to = $replacement
        at_utc = (Get-Date).ToUniversalTime().ToString('o')
      })
      $ProcessId = $replacement
      $live = Get-SsLiveProcess -Id $ProcessId
    }
    else {
      $finalClass = 'PROCESS_EXITED'
      $steps.Add([pscustomobject]@{
        step = $i; event = 'PROCESS_EXITED'; pid = $ProcessId
        at_utc = (Get-Date).ToUniversalTime().ToString('o')
      })
      break
    }
  }

  $title = [string]$live.title
  $focused = Focus-SsWindow -Live $live
  $action = 'WAIT'
  $keys = $null

  if ($title -match '(?i)model|start setup|connection is complete|select a model') {
    $action = 'CLOSE_POST_INSTALL_SETUP'
    $keys = '%{F4}'
    $completed = $true
    $finalClass = 'SOFTWARE_INSTALL_COMPLETE_SETUP_DISMISSED'
  }
  elseif ($title -match $titlePattern) {
    # Setup Type / Welcome / Contents / Install share the same window title.
    # Prefer Next (Alt+N). If Install is the primary action, Enter/Alt+I also advance.
    if ($installPhaseEntered) {
      $action = 'WAIT_INSTALL'
      $keys = $null
    }
    else {
      $action = 'ADVANCE_TYPICAL'
      $keys = '%n'
    }
  }
  elseif ([string]::IsNullOrWhiteSpace($title)) {
    $action = 'WAIT_TITLE'
  }
  else {
    $action = 'UNKNOWN_TITLE'
  }

  $steps.Add([pscustomobject]@{
    step = $i
    pid = $ProcessId
    title = $title
    focused = [bool]$focused
    action = $action
    keys = $keys
    at_utc = (Get-Date).ToUniversalTime().ToString('o')
  })

  if ($keys) {
    Start-Sleep -Milliseconds 250
    Send-SsKeys -Keys $keys
  }

  if ($action -eq 'ADVANCE_TYPICAL') {
    # After a few Next presses we may enter long install; detect by child workers / unresponsive title churn.
    Start-Sleep -Milliseconds $StepDelayMs
    $after = Get-SsLiveProcess -Id $ProcessId
    if ($after -and $after.title -match $titlePattern) {
      # Probe for Install button via Alt+I once we may be on contents/install page.
      if ($i -ge 2) {
        Focus-SsWindow -Live $after | Out-Null
        Send-SsKeys -Keys '%i'
        $installPhaseEntered = $true
        $steps.Add([pscustomobject]@{
          step = $i; event = 'INSTALL_KEY_SENT'; pid = $ProcessId
          at_utc = (Get-Date).ToUniversalTime().ToString('o')
        })
      }
    }
  }
  elseif ($action -eq 'WAIT_INSTALL') {
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(30, $InstallWaitSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
      Start-Sleep -Seconds 5
      $probe = Get-SsLiveProcess -Id $ProcessId
      if (-not $probe) { break }
      if ($probe.title -match '(?i)model|start setup|complete') { break }
      # Keep window focused; do not spam keys during file copy.
    }
  }
  elseif ($action -eq 'CLOSE_POST_INSTALL_SETUP') {
    Start-Sleep -Milliseconds 800
    break
  }
  else {
    Start-Sleep -Milliseconds $StepDelayMs
  }

  if ($completed) { break }

  # Detection-based completion: ScanSnap Home binary appeared.
  foreach ($cand in @($route.detection_seed.DetectValueCandidates)) {
    if (Test-Path -LiteralPath ([string]$cand)) {
      $completed = $true
      $finalClass = 'SOFTWARE_INSTALL_DETECTED'
      $steps.Add([pscustomobject]@{
        step = $i; event = 'DETECT_HIT'; path = [string]$cand
        at_utc = (Get-Date).ToUniversalTime().ToString('o')
      })
      break
    }
  }
  if ($completed) { break }
}

# Final detection sweep
$detectHit = $null
foreach ($cand in @($route.detection_seed.DetectValueCandidates)) {
  if (Test-Path -LiteralPath ([string]$cand)) {
    $detectHit = [string]$cand
    if ($finalClass -eq 'IN_PROGRESS' -or $finalClass -eq 'PROCESS_EXITED') {
      $finalClass = 'SOFTWARE_INSTALL_DETECTED'
      $completed = $true
    }
    break
  }
}

$result = [ordered]@{
  schema_version   = 'scansnap-home-setup-driver/v1'
  controller       = [string]$env:COMPUTERNAME
  process_id       = $ProcessId
  started_at_utc   = $startedUtc.ToString('o')
  finished_at_utc  = (Get-Date).ToUniversalTime().ToString('o')
  final_class      = $finalClass
  completed        = [bool]$completed
  detect_hit       = $detectHit
  steps            = @($steps)
}

if (-not $EvidencePath) {
  $EvidencePath = Join-Path $packageRoot ("evidence\setup-driver_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))
}
$evidenceDir = Split-Path -Parent $EvidencePath
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
($result | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
Write-Host ("Setup driver final_class={0} evidence={1}" -f $finalClass, $EvidencePath)
[pscustomobject]$result | ConvertTo-Json -Depth 6
if ($completed) { exit 0 } else { exit 2 }
