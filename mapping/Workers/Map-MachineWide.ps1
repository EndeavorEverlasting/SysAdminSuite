∩╗┐<#
  Map-Remote-MachineWide-Printers.ps1
  Machine-wide printer mapping worker (runs LOCALLY on the endpoint).

  Supports:
    ΓÇó Snapshot-only (ListOnly) ΓåÆ writes artifacts for recon/triage
    ΓÇó Machine-wide ADD (/ga) & REMOVE (/gd) of UNC queues
    ΓÇó Optional one-shot default-printer at next user logon (SYSTEM task)
    ΓÇó PlanOnly (no changes), Preflight checks, optional Spooler restart
    ΓÇó PruneNotInList: remove machine-wide UNC connections NOT in provided list

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

  # Output root for artifacts
  [string]$OutputRoot = 'C:\ProgramData\SysAdminSuite\Mapping'
)

$ErrorActionPreference = 'Stop'

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
  if ($script:doIO -and $script:logPath) { Add-Content -LiteralPath $script:logPath -Value $line }
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

function Add-UNC([string]$unc){
  $args = @('printui.dll,PrintUIEntry','/ga','/n',"$unc")
  if ($PSCmdlet.ShouldProcess($unc,"Add machine-wide (/ga)")) {
    Start-Process rundll32.exe -ArgumentList $args -NoNewWindow -Wait
    W "ADD (/ga) ΓåÆ $unc"
  }
}
function Remove-UNC([string]$unc){
  $args = @('printui.dll,PrintUIEntry','/gd','/n',"$unc")
  if ($PSCmdlet.ShouldProcess($unc,"Remove machine-wide (/gd)")) {
    Start-Process rundll32.exe -ArgumentList $args -NoNewWindow -Wait
    W "REMOVE (/gd) ΓåÆ $unc"
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
} catch {}
"@
  try {
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command $cmd"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    Register-ScheduledTask -TaskName 'SetDefaultPrinterOnce' -Action $action -Trigger $trigger -RunLevel Highest -User 'NT AUTHORITY\SYSTEM' -Force | Out-Null
    W "Registered one-shot default printer task for '$queue'"
  } catch {
    W "ERROR: Failed to register default-printer task: $($_.Exception.Message)"
  }
}

# ----------------- Artifact wiring -----------------
$doIO = $ListOnly -or $PlanOnly -or $Queues.Count -or $RemoveQueues.Count -or $DefaultQueue
$outDir=$null; $logPath=$null; $preflightCsv=$null; $resultsCsv=$null; $htmlPath=$null
$TranscriptStarted=$false
if ($doIO) {
  $outDir       = New-StampedDir $OutputRoot
  $logPath      = Join-Path $outDir 'Run.log'
  $preflightCsv = Join-Path $outDir 'Preflight.csv'
  $resultsCsv   = Join-Path $outDir 'Results.csv'
  $htmlPath     = Join-Path $outDir 'Results.html'
  try { Start-Transcript -Path $logPath -Force | Out-Null; $TranscriptStarted=$true } catch {}
}

W "=== Printer Map start @ $env:COMPUTERNAME as $([Security.Principal.WindowsIdentity]::GetCurrent().Name) ==="
if ($doIO) { W "Artifacts ΓåÆ $outDir" }

# ----------------- Preflight -----------------
if ($Preflight) {
  $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
  if (-not $svc) { if($TranscriptStarted){Stop-Transcript|Out-Null}; throw "Spooler service not found." }
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

# Short-circuit: ListOnly ΓåÆ write Results + HTML and exit
if ($ListOnly) {
  $rows = New-Object System.Collections.Generic.List[object]
  $now = (Get-Date).ToString('s')
  foreach($u in $beforeUNC){
    $rows.Add([pscustomobject]@{ Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='UNC';   Target=$u; Driver='';               Port='';        Status='PresentNow' })
  }
  foreach($p in $beforeLP){
    $rows.Add([pscustomobject]@{ Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='LOCAL'; Target=$p.Name; Driver=$p.DriverName; Port=$p.PortName; Status='PresentNow' })
  }
  if ($doIO) {
    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $resultsCsv
    $table = $rows | Select-Object Timestamp,Type,Target,Driver,Port,Status |
      ConvertTo-Html -Fragment -PreContent '<h3>Current Printers (UNC + Local)</h3>'
    $logFrag = if (Test-Path $logPath) { "<h3>Run Log</h3><pre>" + [System.Web.HttpUtility]::HtmlEncode((Get-Content -Raw -LiteralPath $logPath)) + "</pre>" } else { '' }
    $doc = @"
<!DOCTYPE html><html><head><meta charset="utf-8"/><title>Printer Mappings ΓÇö $env:COMPUTERNAME (ListOnly)</title>
<style>body{font-family:Segoe UI,Arial;background:#101014;color:#ececf1;padding:20px}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #2a2a33;padding:6px 8px;font-size:12px}
th{background:#171720}tr:nth-child(even){background:#0f0f16}</style></head><body>
<h2>Printer Mappings ΓÇö $env:COMPUTERNAME (ListOnly)</h2>$table$logFrag</body></html>
"@
    Set-Content -LiteralPath $htmlPath -Value $doc -Encoding UTF8
    W "Artifacts:`n  $preflightCsv`n  $resultsCsv`n  $htmlPath`n  $logPath"
  }
  if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
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
} else {
  # Adds
  foreach($u in $desiredUNC){
    if ($beforeUNC -notcontains $u) { Add-UNC $u; $changed = $true }
    else { W "SKIP add; already present ΓåÆ $u" }
  }
  # Removes (explicit)
  foreach($u in $RemoveQueues){
    Remove-UNC $u; $changed = $true
  }
  # Prune anything not in the desired list (if requested)
  if ($PruneNotInList -and $desiredUNC.Count -gt 0) {
    foreach($u in $beforeUNC){
      if ($desiredUNC -notcontains $u) { Remove-UNC $u; $changed = $true }
    }
  }
  # Default printer at next logon
  if ($DefaultQueue) { Register-SetDefaultPrinterOnce -queue $DefaultQueue }
  # Group policy refresh helps machine-wide additions show up faster
  Force-GPUpdateComputer
  if ($changed -and $RestartSpoolerIfNeeded) {
    try { Restart-Service Spooler -Force -ErrorAction Stop; W "Spooler restarted." } catch { W "WARN: Spooler restart failed: $($_.Exception.Message)" }
  }
}

# ----------------- AFTER + Results ----------------------------------------
$afterUNC = Get-GlobalUNCs
$afterLP  = Get-LocalPrinters

$rows = New-Object System.Collections.Generic.List[object]
$now  = (Get-Date).ToString('s')

$universeUNC = ($beforeUNC + $afterUNC + $desiredUNC + $RemoveQueues) | Sort-Object -Unique
foreach($u in $universeUNC){
  $status = if ($PlanOnly) {
    if ($desiredUNC -contains $u -and $beforeUNC -notcontains $u) { 'PlannedAdd' }
    elseif ($RemoveQueues -contains $u -or ($PruneNotInList -and $desiredUNC -notcontains $u -and $beforeUNC -contains $u)) { 'PlannedRemove' }
    elseif ($afterUNC -contains $u) { 'PresentAfter' }
    elseif ($beforeUNC -contains $u) { 'GoneAfter' } else { 'NotPresent' }
  } else {
    if (($afterUNC -contains $u) -and ($beforeUNC -notcontains $u)) { 'AddedNow' }
    elseif (($afterUNC -notcontains $u) -and ($beforeUNC -contains $u)) { 'RemovedNow' }
    elseif ($afterUNC -contains $u) { 'PresentAfter' } else { 'NotPresent' }
  }
  $rows.Add([pscustomobject]@{
    Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='UNC'; Target=$u; Driver=''; Port=''; Status=$status
  })
}

# local printers table included for visibility (not changed by UNC ops)
foreach($p in ($afterLP | Sort-Object Name)){
  $rows.Add([pscustomobject]@{
    Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='LOCAL'; Target=$p.Name; Driver=$p.DriverName; Port=$p.PortName; Status='PresentAfter'
  })
}

if ($doIO) {
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $resultsCsv
  $table = $rows | Select-Object Timestamp,Type,Target,Driver,Port,Status |
    ConvertTo-Html -Fragment -PreContent '<h3>Per-Target Detail</h3>'

  $doc = @"
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Printer Mapping ΓÇö $env:COMPUTERNAME</title>
  <style>
    body{font-family:Segoe UI,Arial;background:#101014;color:#ececf1;padding:20px}
    table{border-collapse:collapse;width:100%}
    th,td{border:1px solid #2a2a33;padding:6px 8px;font-size:12px}
    th{background:#171720}
    tr:nth-child(even){background:#0f0f16}
  </style>
</head>
<body>
  <h2>Printer Mapping Results ΓÇö $env:COMPUTERNAME</h2>
  $table
</body>
</html>
"@
  Set-Content -LiteralPath $htmlPath -Value $doc -Encoding UTF8
  W "Artifacts:`n  $preflightCsv`n  $resultsCsv`n  $htmlPath`n  $logPath"
}

if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
W "=== Completed ==="