<#
  Enforce-Mapping-SingleHost.ps1
  One-off enforcer: WLS111WCC094 -> \\SWBPNHPHPS01V\LS111-WCC65

  Usage (run from mapping\ as admin):
    .\Enforce-Mapping-SingleHost.ps1 -MaxWaitSeconds 180
#>

[CmdletBinding()]
param(
  [int]$MaxWaitSeconds = 180,
  [int]$PollSeconds = 3
)

$ErrorActionPreference = 'Stop'

$target     = 'WLS111WCC094'
$queue      = '\\SWBPNHPHPS01V\LS111-WCC65'
$taskName   = 'SysAdminSuite_PrinterMap_Enforce_Single'
$shareName  = "$target.nslijhs.net"
$remoteRoot = "\\$shareName\C$\ProgramData\SysAdminSuite\Mapping"
$remoteLogs = Join-Path $remoteRoot "logs"

Write-Host "[ENF] Target: $target -> $queue"

# Drop worker+runner on remote
New-Item -ItemType Directory -Path $remoteRoot -Force | Out-Null

# Prepare a tiny runner that imports the worker and enforces mapping if missing; always ListOnly afterward for artifacts
$runner = @"
`$ErrorActionPreference = 'Stop'
Import-Module PrintManagement -ErrorAction SilentlyContinue
`$outRoot = 'C:\ProgramData\SysAdminSuite\Mapping'
`$logDir  = Join-Path `$outRoot ('logs\\{0:yyyyMMdd-HHmmss}' -f (Get-Date))

# Ensure log dir exists early to signal controller
New-Item -ItemType Directory -Path `$logDir -Force | Out-Null

# Add machine-wide if missing
try {
  `$present = Get-Printer -Name '*LS111-WCC65*' -ErrorAction SilentlyContinue | Where-Object { `$_.Name -eq 'LS111-WCC65' }
} catch { `$present = `$null }

if (-not `$present) {
  Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/ga','/n','$queue') -NoNewWindow -Wait
}

# Snapshot artifacts (ListOnly)
# BUG-FIX: Escape $src so it is evaluated at runner time, not controller time
`$src = Join-Path `$PSScriptRoot 'Map-Remote-MachineWide-Printers.ps1'
powershell.exe -NoProfile -File `$src -ListOnly -OutputRoot `$outRoot | Out-Null
"@

$runnerPath = Join-Path $remoteRoot 'enforce-runner.ps1'
Set-Content -LiteralPath $runnerPath -Value $runner -Encoding UTF8

# Copy worker script alongside
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Map-Remote-MachineWide-Printers.ps1') -Destination $remoteRoot -Force

# Schedule as SYSTEM in the next whole minute (+1 or +2 min if seconds>=50)
$now    = Get-Date
$when   = if ($now.Second -ge 50) { $now.AddMinutes(2) } else { $now.AddMinutes(1) }
$stTime = $when.ToString('HH:mm')
$stDate = $when.ToString('yyyy-MM-dd')
$tr     = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerPath`""
# BUG-FIX: Call schtasks.exe directly and check exit codes
$create = & schtasks.exe /Create /S $shareName /RU SYSTEM /SC ONCE /SD $stDate /ST $stTime /TN $taskName /TR $tr /RL HIGHEST /F 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Error "schtasks /Create failed (exit $LASTEXITCODE): $create"
  exit 1
}
$run = & schtasks.exe /Run /S $shareName /TN $taskName 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Error "schtasks /Run failed (exit $LASTEXITCODE): $run"
  exit 1
}

Write-Host "[ENF] TASK CREATED ($stDate $stTime)"
Write-Host "[ENF] POLLING for artifacts..."

# Poll and collect latest stamped folder
$latest = $null; $elapsed = 0
while ($elapsed -lt $MaxWaitSeconds) {
  if (Test-Path $remoteLogs) {
    $latest = Get-ChildItem -Path $remoteLogs -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { break }
  }
  Start-Sleep -Seconds $PollSeconds
  $elapsed += $PollSeconds
}

if ($latest) {
  $session = Join-Path $PSScriptRoot ('logs\enforce-{0:yyyyMMdd-HHmmss}' -f (Get-Date))
  New-Item -ItemType Directory -Path $session -Force | Out-Null
  $hostOut = Join-Path $session $target
  New-Item -ItemType Directory -Path $hostOut -Force | Out-Null
  Copy-Item -Path (Join-Path $latest.FullName '*') -Destination $hostOut -Force -ErrorAction SilentlyContinue
  Write-Host "[ENF] COLLECTED -> $hostOut"
} else {
  Write-Host "[ENF] NO ARTIFACTS (${MaxWaitSeconds}s)"
}

# Cleanup task (best-effort)
& schtasks.exe /Delete /S $shareName /TN $taskName /F 2>&1 | Out-Null