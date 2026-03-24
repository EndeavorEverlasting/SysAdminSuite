<#
  Map-Remote-MachineWide-Printers.ps1
  Machine-wide printer mapping worker (runs LOCALLY on the endpoint).

  Supports:
    - Snapshot-only (ListOnly) -> writes artifacts for recon/triage
    - Machine-wide ADD (/ga) and REMOVE (/gd) of UNC queues
    - Optional one-shot default-printer at next user logon
    - PlanOnly (no changes), Preflight checks, optional Spooler restart
    - PruneNotInList: remove machine-wide UNC connections NOT in provided list

  Artifacts (when I/O is enabled: ListOnly, PlanOnly, or real run):
    C:\ProgramData\SysAdminSuite\Mapping\logs\<yyyyMMdd-HHmmss>\
      Run.log, Preflight.csv, Results.csv, Results.html

  Quick examples (run as admin on the endpoint):
    # Snapshot existing mappings ONLY (what recon uses)
    .\Map-Remote-MachineWide-Printers.ps1 -ListOnly -Preflight

    # Add a couple of machine-wide queues and set default at next logon
    .\Map-Remote-MachineWide-Printers.ps1 `
      -Queues '\\PRINTSRV\Q67','\\PRINTSRV\Q62' `
      -DefaultQueue '\\PRINTSRV\Q67' -RestartSpoolerIfNeeded

    # Remove a queue machine-wide
    .\Map-Remote-MachineWide-Printers.ps1 -RemoveQueues '\\PRINTSRV\Q67'

    # Keep only the queues listed (prune everything else)
    .\Map-Remote-MachineWide-Printers.ps1 `
      -Queues '\\PRINTSRV\Q67','\\PRINTSRV\Q62' -PruneNotInList
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
  # OPTIONAL: CSV of desired state (future extension; UNC-only today)
  [string]$InputPath,

  # Direct parameters (UNC queues). These are honored immediately.
  [string[]]$Queues        = @(),  # to ADD (machine-wide)
  [string[]]$RemoveQueues  = @(),  # to REMOVE (machine-wide)
  [string]$DefaultQueue,

  # Behaviors / modes
  [switch]$ListOnly,
  [switch]$PlanOnly,
  [switch]$Preflight,
  [switch]$PruneNotInList,
  [switch]$RestartSpoolerIfNeeded,
  [switch]$EnableUndoRedo,
  [string]$UndoRedoLogPath,
  [string]$StopSignalPath,
  [string]$StatusPath,

  # Output root for artifacts
  [string]$OutputRoot = 'C:\ProgramData\SysAdminSuite\Mapping'
)

$ErrorActionPreference = 'Stop'
$script:undoRedoEnabled = $false
$script:undoRedoSession = $null
$script:undoRedoLogPath = $null
$script:runControlUtilityPath = $null
$script:stopSignalPath = $null
$script:statusPath = $null
$script:stopRequested = $false
$script:undoRedoLogPath = $null
$script:runControlUtilityPath = $null
$script:stopSignalPath = $null
$script:statusPath = $null
$script:stopRequested = $false
$script:TranscriptActive = $false
# ----------------- Utilities -----------------
function New-StampedDir([string]$root){
  if (!(Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $dir   = Join-Path $root $stamp
  New-Item -ItemType Directory -Path (Join-Path $root 'logs') -Force | Out-Null
  $dir = Join-Path (Join-Path $root 'logs') $stamp
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  return $dir
}
function W([string]$m){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[{0}] {1}" -f $ts,$m
  Write-Host $line
  # When Start-Transcript is active it already captures Write-Host output to Run.log.
  # Using Add-Content on the same file would fail with a sharing-violation lock error.
  if ($script:doIO -and $script:logPath -and -not $script:TranscriptActive) {
    Add-Content -LiteralPath $script:logPath -Value $line
  }
}
function Get-GlobalUNCs {
  $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
  if (!(Test-Path $key)) { return @() }
  Get-ChildItem $key | ForEach-Object {
    try {
      $p = Get-ItemProperty $_.PSPath
      if ($p.Server -and $p.Printer) { "\\$($p.Server)\$($p.Printer)".ToLower() }
    } catch {}
  } | Sort-Object -Unique
}
function Get-LocalPrinters { try { Get-Printer -ErrorAction Stop } catch { @() } }

function Initialize-RunControl {
  $candidatePaths = @(
    (Join-Path $PSScriptRoot 'Invoke-RunControl.ps1'),
    (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Utilities\Invoke-RunControl.ps1')
  ) | Select-Object -Unique

  $script:runControlUtilityPath = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $script:runControlUtilityPath) {
    throw 'Invoke-RunControl.ps1 could not be located.'
  }

  . $script:runControlUtilityPath
  $script:stopSignalPath = if ($StopSignalPath) { $StopSignalPath } else { Join-Path $OutputRoot 'Stop.json' }
  $script:statusPath = if ($StatusPath) { $StatusPath } else { Join-Path $OutputRoot 'status.json' }
}

function Export-WorkerStatus {
  param(
    [string]$State = 'Running',
    [string]$Stage = 'Worker',
    [string]$Message = ''
  )

  if (-not $script:statusPath) { return }

  try {
    Export-RunStatusSnapshot -Path $script:statusPath -State $State -Stage $Stage -Message $Message -Data @{
      ComputerName     = $env:COMPUTERNAME
      OutputRoot       = $OutputRoot
      OutputDirectory  = $script:outDir
      LogPath          = $script:logPath
      ResultsPath      = $script:resultsCsv
      HtmlPath         = $script:htmlPath
      PreflightPath    = $script:preflightCsv
      StopSignalPath   = $script:stopSignalPath
      StopRequested    = [bool]$script:stopRequested
      EnableUndoRedo   = [bool]$script:undoRedoEnabled
      UndoRedoLogPath  = $script:undoRedoLogPath
      DesiredQueues    = @($Queues)
      RemoveQueues     = @($RemoveQueues)
      ListOnly         = [bool]$ListOnly
      PlanOnly         = [bool]$PlanOnly
    } | Out-Null
  } catch {
    W "WARN: Failed to export worker status: $($_.Exception.Message)"
  }
}

function Test-WorkerStopRequested {
  param([string]$Stage = 'WorkerLoop')

  $signal = $null
  if ($script:stopRequested) {
    $signal = [pscustomobject]@{ RequestedAt = Get-Date; Reason = 'Stop already requested.' }
  } elseif ($script:stopSignalPath) {
    $signal = Test-RunStopRequested -Path $script:stopSignalPath
  }

  if (-not $signal) { return $false }

  if (-not $script:stopRequested) {
    $script:stopRequested = $true
    W "Stop requested during $Stage. Flushing current artifacts and status."
  }

  Export-WorkerStatus -State 'Stopping' -Stage $Stage -Message 'Stop requested; skipping remaining queued operations.'
  return $true
}

function New-ResultRows {
  param(
    [string[]]$BeforeUNC,
    [string[]]$AfterUNC,
    [string[]]$DesiredUNC,
    [string[]]$RemoveQueueList,
    [object[]]$AfterLocalPrinters
  )

  $rows = New-Object System.Collections.Generic.List[object]
  $now  = (Get-Date).ToString('s')
  $universeUNC = ($BeforeUNC + $AfterUNC + $DesiredUNC + $RemoveQueueList) | Where-Object { $_ } | Sort-Object -Unique

  foreach($u in $universeUNC){
    $status = if ($PlanOnly) {
      if ($DesiredUNC -contains $u -and $BeforeUNC -notcontains $u) { 'PlannedAdd' }
      elseif ($RemoveQueueList -contains $u -or ($PruneNotInList -and $DesiredUNC -notcontains $u -and $BeforeUNC -contains $u)) { 'PlannedRemove' }
      elseif ($AfterUNC -contains $u) { 'PresentAfter' }
      elseif ($BeforeUNC -contains $u) { 'GoneAfter' } else { 'NotPresent' }
    } else {
      if (($AfterUNC -contains $u) -and ($BeforeUNC -notcontains $u)) { 'AddedNow' }
      elseif (($AfterUNC -notcontains $u) -and ($BeforeUNC -contains $u)) { 'RemovedNow' }
      elseif ($AfterUNC -contains $u) { 'PresentAfter' } else { 'NotPresent' }
    }

    $rows.Add([pscustomobject]@{ Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='UNC'; Target=$u; Driver=''; Port=''; Status=$status })
  }

  foreach($p in ($AfterLocalPrinters | Sort-Object Name)){
    $rows.Add([pscustomobject]@{ Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='LOCAL'; Target=$p.Name; Driver=$p.DriverName; Port=$p.PortName; Status='PresentAfter' })
  }

  return $rows
}

function Write-ResultArtifacts {
  param(
    [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Rows,
    [switch]$ListOnlyMode
  )

  if (-not $script:doIO) { return }

  $Rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $script:resultsCsv
  $table = $Rows | Select-Object Timestamp,Type,Target,Driver,Port,Status |
    ConvertTo-Html -Fragment -PreContent ($(if ($ListOnlyMode) { '<h3>Current Printers (UNC + Local)</h3>' } else { '<h3>Per-Target Detail</h3>' }))
  $logFrag = if ($script:logPath -and (Test-Path -LiteralPath $script:logPath)) { "<h3>Run Log</h3><pre>" + [System.Net.WebUtility]::HtmlEncode((Get-Content -Raw -LiteralPath $script:logPath)) + "</pre>" } else { '' }
  $heading = if ($ListOnlyMode) { "Printer Mappings - $env:COMPUTERNAME (ListOnly)" } else { "Printer Mapping Results - $env:COMPUTERNAME" }
  $doc = @"
<!DOCTYPE html><html><head><meta charset="utf-8"/><title>$heading</title>
<style>body{font-family:Segoe UI,Arial;background:#101014;color:#ececf1;padding:20px}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #2a2a33;padding:6px 8px;font-size:12px}
th{background:#171720}tr:nth-child(even){background:#0f0f16}</style></head><body>
<h2>$heading</h2>$table$logFrag</body></html>
"@
  Set-Content -LiteralPath $script:htmlPath -Value $doc -Encoding UTF8
  W "Artifacts:`n  $script:preflightCsv`n  $script:resultsCsv`n  $script:htmlPath`n  $script:logPath"
}

function Initialize-UndoRedo {
  if (-not $EnableUndoRedo) { return }

  $candidatePaths = @(
    (Join-Path $PSScriptRoot 'Invoke-UndoRedo.ps1'),
    (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Utilities\Invoke-UndoRedo.ps1')
  ) | Select-Object -Unique

  $utilityPath = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $utilityPath) {
    throw 'EnableUndoRedo was requested, but Invoke-UndoRedo.ps1 could not be located.'
  }

  . $utilityPath
  $script:undoRedoSession = New-UndoRedoSession
  $script:undoRedoEnabled = $true
  $script:undoRedoLogPath = if ($UndoRedoLogPath) {
    $UndoRedoLogPath
  } elseif ($outDir) {
    Join-Path $outDir 'UndoRedo.json'
  } else {
    Join-Path $OutputRoot ('UndoRedo-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))
  }
}

function Export-UndoRedoArtifacts {
  if (-not $script:undoRedoEnabled -or -not $script:undoRedoSession -or -not $script:undoRedoLogPath) { return }

  try {
    Export-UndoRedoSessionSummary -Session $script:undoRedoSession -Path $script:undoRedoLogPath | Out-Null
    W "Undo/redo summary -> $script:undoRedoLogPath"
  } catch {
    W "WARN: Failed to export undo/redo summary: $($_.Exception.Message)"
  }
}

function Invoke-UNCAction {
  param(
    [Parameter(Mandatory)][ValidateSet('Add','Remove')][string]$Operation,
    [Parameter(Mandatory)][string]$Queue,
    [string]$Source = 'Direct'
  )

  $normalizedQueue = $Queue.Trim().ToLower()
  if (-not $script:undoRedoEnabled) {
    return $false
  }

  $probe = {
    param($ctx)
    [pscustomobject]@{
      Target  = $ctx.Target
      Present = ((Get-GlobalUNCs) -contains $ctx.Target)
    }
  }

  if ($Operation -eq 'Add') {
    $do = {
      param($ctx)
      Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/ga','/n',$ctx.Target) -NoNewWindow -Wait
      W "ADD (/ga) -> $($ctx.Target)"
    }
    $undo = {
      param($ctx)
      Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/gd','/n',$ctx.Target) -NoNewWindow -Wait
      W "UNDO REMOVE (/gd) -> $($ctx.Target)"
    }
  } else {
    $do = {
      param($ctx)
      Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/gd','/n',$ctx.Target) -NoNewWindow -Wait
      W "REMOVE (/gd) -> $($ctx.Target)"
    }
    $undo = {
      param($ctx)
      Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/ga','/n',$ctx.Target) -NoNewWindow -Wait
      W "UNDO ADD (/ga) -> $($ctx.Target)"
    }
  }

  $action = New-UndoRedoActionRecord -Name "$Operation machine-wide printer" -Target $normalizedQueue -Do $do -Undo $undo -Probe $probe -Metadata @{
    Kind      = 'Printer'
    Mode      = 'MachineWide'
    Operation = $Operation
    Source    = $Source
  }

  Invoke-UndoRedo -Session $script:undoRedoSession -Action $action -WhatIf:$WhatIfPreference | Out-Null
  return $true
}

function Add-UNC([string]$unc){
  if (Invoke-UNCAction -Operation Add -Queue $unc -Source 'DesiredQueue') { return }
  $printArgs = @('printui.dll,PrintUIEntry','/ga','/n',"$unc")
  if ($PSCmdlet.ShouldProcess($unc,"Add machine-wide (/ga)")) {
    Start-Process rundll32.exe -ArgumentList $printArgs -NoNewWindow -Wait
    W "ADD (/ga) -> $unc"
  }
}
function Remove-UNC([string]$unc){
  if (Invoke-UNCAction -Operation Remove -Queue $unc -Source 'RemovalQueue') { return }
  $removeArgs = @('printui.dll,PrintUIEntry','/gd','/n',"$unc")
  if ($PSCmdlet.ShouldProcess($unc,"Remove machine-wide (/gd)")) {
    Start-Process rundll32.exe -ArgumentList $removeArgs -NoNewWindow -Wait
    W "REMOVE (/gd) -> $unc"
  }
}
function Force-GPUpdateComputer {
  try {
    Start-Process gpupdate.exe -ArgumentList @('/target:computer','/force') -NoNewWindow -Wait
    W "gpupdate /target:computer /force completed"
  } catch {
    W "WARN: gpupdate failed: $($_.Exception.Message)"
  }
}
function Register-SetDefaultPrinterOnce([string]$queue){
  # One-shot SYSTEM task: add connection if missing, set default at next logon
  $quoted = $queue.Replace("'","''")
  $escaped = $queue.Replace('\','\\')
  $cmd = @"
try {
  Add-Printer -ConnectionName '$quoted' -ErrorAction SilentlyContinue | Out-Null
  \$p = Get-CimInstance Win32_Printer -Filter "Name='$escaped'"
  if (\$p) { \$null = \$p | Invoke-CimMethod -MethodName SetDefaultPrinter }
  Unregister-ScheduledTask -TaskName 'SetDefaultPrinterOnce' -Confirm:\$false -ErrorAction SilentlyContinue
} catch {}
"@
  try {
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command $cmd"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    # BUG-FIX: SYSTEM cannot set per-user default printer; run as interactive user instead
    $principal = New-ScheduledTaskPrincipal -UserId 'BUILTIN\Users' -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName 'SetDefaultPrinterOnce' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    W "Registered one-shot default printer task for '$queue'"
  } catch {
    W "ERROR: Failed to register default-printer task: $($_.Exception.Message)"
  }
}

# ----------------- Artifact wiring -----------------
$script:doIO = $ListOnly -or $PlanOnly -or $Queues.Count -or $RemoveQueues.Count -or $DefaultQueue
$doIO = $script:doIO
$outDir=$null; $logPath=$null; $preflightCsv=$null; $resultsCsv=$null; $htmlPath=$null
$TranscriptStarted=$false
if ($doIO) {
  $outDir       = New-StampedDir $OutputRoot
  $logPath      = Join-Path $outDir 'Run.log'
  $preflightCsv = Join-Path $outDir 'Preflight.csv'
  $resultsCsv   = Join-Path $outDir 'Results.csv'
  $htmlPath     = Join-Path $outDir 'Results.html'
  try { Start-Transcript -Path $logPath -Force | Out-Null; $TranscriptStarted=$true; $script:TranscriptActive=$true } catch {}
}

Initialize-RunControl
$script:outDir = $outDir
$script:logPath = $logPath
$script:preflightCsv = $preflightCsv
$script:resultsCsv = $resultsCsv
$script:htmlPath = $htmlPath
Initialize-UndoRedo

$null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -SourceIdentifier 'Worker.CancelKeyPress' -Action {
  $Event.SourceEventArgs.Cancel = $true
  $script:stopRequested = $true
}

W "=== Printer Map start @ $env:COMPUTERNAME as $([Security.Principal.WindowsIdentity]::GetCurrent().Name) ==="
if ($doIO) { W "Artifacts -> $outDir" }
if ($script:undoRedoEnabled) { W "Undo/redo capture enabled -> $script:undoRedoLogPath" }
Export-WorkerStatus -State 'Running' -Stage 'Startup' -Message 'Worker initialized.'

# ----------------- Preflight -----------------
if ($Preflight) {
  $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
  if (-not $svc) { if($TranscriptStarted){Stop-Transcript|Out-Null; $script:TranscriptActive=$false}; throw "Spooler service not found." }
  W "Spooler: $($svc.Status)"
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { W "WARN: Not elevated; machine-wide actions may fail." }
}

# ----------------- Current state (BEFORE) -----------------
$beforeUNC = Get-GlobalUNCs
$beforeLP  = Get-LocalPrinters

# Preflight.csv (what exists now)
if ($doIO) {
  $pf = New-Object System.Collections.Generic.List[object]
  $now = (Get-Date).ToString('s')
  foreach($u in $beforeUNC){
    $pf.Add([pscustomobject]@{
      SnapshotTime=$now; ComputerName=$env:COMPUTERNAME; Type='UNC'; Target=$u;
      PresentNow=$true; InDesired=($Queues -contains $u); Notes=''
    })
  }
  foreach($q in $Queues){
    if ($beforeUNC -notcontains $q) {
      $pf.Add([pscustomobject]@{
        SnapshotTime=$now; ComputerName=$env:COMPUTERNAME; Type='UNC'; Target=$q;
        PresentNow=$false; InDesired=$true; Notes='(planned add)'
      })
    }
  }
  $pf | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $preflightCsv
}

Export-WorkerStatus -State 'Running' -Stage 'Preflight' -Message 'Preflight snapshot captured.'

# Short-circuit: ListOnly -> write Results + HTML and exit
if ($ListOnly) {
  $rows = New-Object System.Collections.Generic.List[object]
  $now = (Get-Date).ToString('s')
  foreach($u in $beforeUNC){
    $rows.Add([pscustomobject]@{ Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='UNC';   Target=$u; Driver='';               Port='';        Status='PresentNow' })
  }
  foreach($p in $beforeLP){
    $rows.Add([pscustomobject]@{ Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='LOCAL'; Target=$p.Name; Driver=$p.DriverName; Port=$p.PortName; Status='PresentNow' })
  }
  if ($doIO) { Write-ResultArtifacts -Rows $rows -ListOnlyMode }
  Export-UndoRedoArtifacts
  Export-WorkerStatus -State 'Completed' -Stage 'ListOnly' -Message 'ListOnly inventory completed.'
  if ($TranscriptStarted) { try { Stop-Transcript | Out-Null; $script:TranscriptActive=$false } catch {} }
  Unregister-Event -SourceIdentifier 'Worker.CancelKeyPress' -ErrorAction SilentlyContinue
  W "=== Completed (ListOnly) ==="
  return
}

# ----------------- Desired set & actions ----------------------------------
$desiredUNC = @()
if ($Queues -and $Queues.Count) { $desiredUNC = $Queues | ForEach-Object { $_.Trim().ToLower() } }

$changed = $false

# PlanOnly just reports intent; real run executes
if ($PlanOnly) {
  W "PLAN-ONLY: Adds => $($desiredUNC.Count); Removes => $($RemoveQueues.Count); PruneNotInList => $PruneNotInList"
  Export-WorkerStatus -State 'Running' -Stage 'PlanOnly' -Message 'Plan-only mode; no changes executed.'
} else {
  foreach($u in $desiredUNC){
    if (Test-WorkerStopRequested -Stage 'AddQueue') { break }
    if ($beforeUNC -notcontains $u) { Add-UNC $u; $changed = $true } else { W "SKIP add; already present -> $u" }
    Export-WorkerStatus -State 'Running' -Stage 'AddQueue' -Message "Processed add candidate $u"
  }
  foreach($u in $RemoveQueues){
    if (Test-WorkerStopRequested -Stage 'RemoveQueue') { break }
    Remove-UNC $u; $changed = $true
    Export-WorkerStatus -State 'Running' -Stage 'RemoveQueue' -Message "Processed removal candidate $u"
  }
  if (-not $script:stopRequested -and $PruneNotInList -and $desiredUNC.Count -gt 0) {
    foreach($u in $beforeUNC){
      if (Test-WorkerStopRequested -Stage 'PruneQueue') { break }
      if ($desiredUNC -notcontains $u) {
        if ($script:undoRedoEnabled) { Invoke-UNCAction -Operation Remove -Queue $u -Source 'PruneNotInList' | Out-Null } else { Remove-UNC $u }
        $changed = $true
        Export-WorkerStatus -State 'Running' -Stage 'PruneQueue' -Message "Pruned queue $u"
      }
    }
  }
  if (-not $script:stopRequested -and $DefaultQueue) {
    Register-SetDefaultPrinterOnce -queue $DefaultQueue
    Export-WorkerStatus -State 'Running' -Stage 'DefaultQueue' -Message "Registered default queue task for $DefaultQueue"
  }
  if (-not $script:stopRequested) {
    Force-GPUpdateComputer
    Export-WorkerStatus -State 'Running' -Stage 'GPUpdate' -Message 'gpupdate completed.'
  }
  if (-not $script:stopRequested -and $changed -and $RestartSpoolerIfNeeded) {
    try { Restart-Service Spooler -Force -ErrorAction Stop; W "Spooler restarted." } catch { W "WARN: Spooler restart failed: $($_.Exception.Message)" }
  }
}

# ----------------- AFTER + Results ----------------------------------------
$afterUNC = Get-GlobalUNCs
$afterLP  = Get-LocalPrinters

$rows = New-ResultRows -BeforeUNC $beforeUNC -AfterUNC $afterUNC -DesiredUNC $desiredUNC -RemoveQueueList $RemoveQueues -AfterLocalPrinters $afterLP
if ($doIO) { Write-ResultArtifacts -Rows $rows }

Export-UndoRedoArtifacts
Export-WorkerStatus -State ($(if ($script:stopRequested) { 'Stopped' } else { 'Completed' })) -Stage 'Complete' -Message ($(if ($script:stopRequested) { 'Stop requested; partial artifacts emitted.' } else { 'Worker completed successfully.' }))

if ($TranscriptStarted) { try { Stop-Transcript | Out-Null; $script:TranscriptActive=$false } catch {} }
Unregister-Event -SourceIdentifier 'Worker.CancelKeyPress' -ErrorAction SilentlyContinue
W "=== Completed ==="
