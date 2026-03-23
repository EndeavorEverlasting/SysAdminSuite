∩╗┐<#
Map-Remote-MachineWide-Printers.NoWinRM.ps1  (v1.1)
Controller: PS7 (your box). Targets: Win10/11 PS5. No WinRM required.
Transport: SMB (\\HOST\C$) + SCHTASKS (/S HOST). Optional remote REG verify.

What it does per host
  1) Creates C:\ProgramData\SysAdminSuite\Mapping via \\HOST\C$
  2) Drops Map-Agent.ps1 and config.json
  3) Creates a SYSTEM scheduled task and RUNs it now
  4) Polls for status.json, pulls agent-log.txt back to .\logs\<run>\<host>
  5) (Optional) reg.exe QUERY remote HKLM\...\Print\Connections to list machine-wide mappings

Example (single line; no backticks):
  & ".\Map-Remote-MachineWide-Printers.NoWinRM.ps1" -HostsPath ".\csv\hosts_smoke.txt" -Queues '\\SWBPNHPHPS01V\LS111-WCC67','\\SWBPNSXPS01V\LS111-WCC62' -Verify -MaxParallel 24 -Verbose
#>

[CmdletBinding(PositionalBinding=$false, SupportsShouldProcess, ConfirmImpact='High')]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$HostsPath,

  # Queues to ADD machine-wide (/ga)
  [string[]]$Queues = @(),

  # Queues to REMOVE machine-wide (/gd)
  [string[]]$RemoveQueues = @(),

  # Optional: set default for users at next logon (via one-shot scheduled task on target)
  [string]$DefaultQueue,

  # Append this DNS suffix when a hostname has no dot
  [string]$DnsSuffix = 'nslijhs.net',

  # Concurrency for our local fan-out (SMB + SCHTASKS RPC)
  [int]$MaxParallel = 24,

  # Per-host wait for the agent to finish (seconds)
  [int]$TimeoutSeconds = 180,

  # Also list HKLM machine-wide connections via reg.exe \\host\HKLM ... at the end
  [switch]$Verify
)

$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$ErrorActionPreference = 'Stop'

# ---------------- helpers ----------------

function Get-HostList {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Hosts file not found: $Path" }
  Get-Content -LiteralPath $Path |
    Where-Object { $_ -and $_.Trim() -ne '' -and $_ -notmatch '^\s*#' } |
    ForEach-Object { $_.Trim() } |
    Sort-Object -Unique
}

function Resolve-Fqdn {
  param([string]$Name,[string]$Suffix)
  if ($Name -match '\.') { return $Name }
  if ([string]::IsNullOrWhiteSpace($Suffix)) { return $Name }
  return "$Name.$Suffix"
}

# Agent code (runs under SYSTEM on the target via Scheduled Task)
$AgentCode = @'
param(
  [string]$CfgPath = "C:\ProgramData\SysAdminSuite\Mapping\config.json",
  [string]$WorkDir = "C:\ProgramData\SysAdminSuite\Mapping"
)

$ErrorActionPreference = "Stop"
$log = Join-Path $WorkDir "agent-log.txt"
$status = Join-Path $WorkDir "status.json"

function Write-Log([string]$m) {
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  "$ts  $m" | Add-Content -LiteralPath $log
}

try {
  $cfg = Get-Content -Raw -LiteralPath $CfgPath | ConvertFrom-Json
  $queuesAdd    = @($cfg.Queues) | Where-Object {$_}
  $queuesRemove = @($cfg.RemoveQueues) | Where-Object {$_}
  $defaultQ     = $cfg.DefaultQueue

  Write-Log "Agent start. Add: $($queuesAdd -join ', '); Remove: $($queuesRemove -join ', '); Default: $defaultQ"

  foreach ($q in $queuesRemove) {
    try {
      Write-Log "REMOVE $q"
      Start-Process -FilePath 'rundll32.exe' -ArgumentList @('printui.dll,PrintUIEntry','/gd',"/n$q") -Wait -WindowStyle Hidden
    } catch { Write-Log "REMOVE FAIL $q :: $($_.Exception.Message)" }
  }

  foreach ($q in $queuesAdd) {
    try {
      Write-Log "ADD $q"
      Start-Process -FilePath 'rundll32.exe' -ArgumentList @('printui.dll,PrintUIEntry','/ga',"/n$q") -Wait -WindowStyle Hidden
    } catch { Write-Log "ADD FAIL $q :: $($_.Exception.Message)" }
  }

  try {
    Write-Log "gpupdate /target:computer /force"
    Start-Process -FilePath 'gpupdate.exe' -ArgumentList @('/target:computer','/force') -Wait -WindowStyle Hidden
  } catch { Write-Log "gpupdate FAIL :: $($_.Exception.Message)" }

  if ($defaultQ) {
    try {
      Write-Log "Schedule default at next logon: $defaultQ"
      $ps = @"
Add-Printer -ConnectionName '$defaultQ' -ErrorAction SilentlyContinue
\$p = Get-CimInstance Win32_Printer -Filter "Name='$($defaultQ.Replace('\','\\'))'"
if (\$p) { \$null = \$p | Invoke-CimMethod -MethodName SetDefaultPrinter }
"@
      $act  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command $ps"
      $trg  = New-ScheduledTaskTrigger -AtLogOn
      Register-ScheduledTask -TaskName 'SetDefaultPrinterOnce' -Action $act -Trigger $trg -RunLevel Highest -User 'NT AUTHORITY\SYSTEM' -Force | Out-Null
    } catch { Write-Log "DEFAULT TASK FAIL :: $($_.Exception.Message)" }
  }

  $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
  $mw = @()
  if (Test-Path $k) { $mw = Get-ChildItem $k | Select-Object -ExpandProperty PSChildName }
  @{
    Host = $env:COMPUTERNAME
    Added = $queuesAdd
    Removed = $queuesRemove
    MachineWide = $mw
    Success = $true
    Finished = (Get-Date)
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $status -Encoding UTF8

  Write-Log "Agent done."
} catch {
  Write-Log "FATAL :: $($_.Exception.Message)"
  @{
    Host = $env:COMPUTERNAME
    Success = $false
    Error = $_.Exception.Message
    Finished = (Get-Date)
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $status -Encoding UTF8
  exit 1
}
'@

# ---------------- main ----------------

$hosts = Get-HostList -Path $HostsPath
if (-not $hosts.Count) { throw "No hosts in $HostsPath" }

$logsRoot = Join-Path (Get-Location) "logs"
$null = New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null

$runToken = Get-Date -Format 'yyyyMMdd-HHmmss'
$taskName = "SysAdminSuite_PrinterMap_$runToken"   # unique per run
$start    = (Get-Date).AddMinutes(2).ToString('HH:mm')   # SCHTASKS needs future time

Write-Host "=== Printer Map (NoWinRM) v1.1 ===" -ForegroundColor Cyan
Write-Host ("Hosts file : {0}" -f (Resolve-Path $HostsPath)) 
Write-Host ("Hosts count: {0}" -f $hosts.Count)
Write-Host ("ADD        : {0}" -f ($Queues -join ', ')) 
Write-Host ("REMOVE     : {0}" -f ($RemoveQueues -join ', ')) 
if ($DefaultQueue) { Write-Host ("Default    : {0}" -f $DefaultQueue) }
Write-Host ("Verify     : {0}" -f ($Verify.IsPresent)) 
Write-Host ("MaxParallel: {0}" -f $MaxParallel)
Write-Host ""

# quick preflight against the first host (C$ + SCHTASKS)
$first = $hosts[0]
$fqdn0 = Resolve-Fqdn -Name $first -Suffix $DnsSuffix
if (-not (Test-Path "\\$fqdn0\C$")) {
  Write-Warning "Admin share not reachable: \\$fqdn0\C$  (check creds/firewall/VPN)"
}
try {
  $q = & schtasks.exe /Query /S $fqdn0 /FO LIST 2>$null
} catch {
  Write-Warning "SCHTASKS RPC may be blocked to $fqdn0 (135/445). Script will attempt anyway."
}

$bag = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

$hosts | ForEach-Object -ThrottleLimit $MaxParallel -Parallel {
  $hostRaw   = $_
  $suffix    = $using:DnsSuffix
  $fqdn      = if ($hostRaw -match '\.') { $hostRaw } else { "$hostRaw.$suffix" }
  $relDir    = 'ProgramData\SysAdminSuite\Mapping'
  $uncDir    = "\\$fqdn\C$\$relDir"
  $agentPath = Join-Path $uncDir 'Map-Agent.ps1'
  $cfgPath   = Join-Path $uncDir 'config.json'
  $statusUNC = Join-Path $uncDir 'status.json'
  $logUNC    = Join-Path $uncDir 'agent-log.txt'
  $localDir  = Join-Path (Join-Path $using:logsRoot $using:runToken) $hostRaw
  New-Item -ItemType Directory -Force -Path $localDir | Out-Null

  $result = [ordered]@{
    Host = $hostRaw
    Fqdn = $fqdn
    Step = 'INIT'
    Ok = $false
    Message = ''
    Verify = @()
  }

  try {
    if (-not (Test-Path "\\$fqdn\C$")) { throw "Cannot reach \\$fqdn\C$ (admin share). Check network/ACL." }

    # 1) Ensure remote dir
    New-Item -ItemType Directory -Force -Path $uncDir -ErrorAction Stop | Out-Null

    # 2) Drop agent + config
    Set-Content -LiteralPath $agentPath -Value $using:AgentCode -Encoding UTF8 -ErrorAction Stop

    $cfgObj = [ordered]@{
      Queues       = @($using:Queues)
      RemoveQueues = @($using:RemoveQueues)
      DefaultQueue = $using:DefaultQueue
    }
    $cfgObj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $cfgPath -Encoding UTF8 -ErrorAction Stop

    # 3) Create task (as SYSTEM, runs once) and run it now
    $tn = $using:taskName
    $st = $using:start
    $createArgs = @(
      '/Create','/F',
      '/S',$fqdn,
      '/RU','SYSTEM',
      '/SC','ONCE',
      '/ST',$st,
      '/TN',$tn,
      '/TR','powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\SysAdminSuite\Mapping\Map-Agent.ps1"'
    )
    $runArgs = @('/Run','/S',$fqdn,'/TN',$tn)

    $p = Start-Process -FilePath schtasks.exe -ArgumentList $createArgs -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "SCHTASKS /Create failed ($($p.ExitCode))" }

    $p = Start-Process -FilePath schtasks.exe -ArgumentList $runArgs -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "SCHTASKS /Run failed ($($p.ExitCode))" }

    # 4) Poll for status.json up to TimeoutSeconds
    $deadline = (Get-Date).AddSeconds($using:TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
      if (Test-Path -LiteralPath $statusUNC) { break }
      Start-Sleep -Seconds 3
    }
    if (-not (Test-Path -LiteralPath $statusUNC)) { throw "Timed out waiting for agent status ($($using:TimeoutSeconds)s)" }

    # Pull back artifacts
    Copy-Item -LiteralPath $statusUNC -Destination (Join-Path $localDir 'status.json') -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $logUNC) {
      Copy-Item -LiteralPath $logUNC -Destination (Join-Path $localDir 'agent-log.txt') -Force -ErrorAction SilentlyContinue
    }

    $result.Step = 'AGENT'
    $result.Ok = $true
    $result.Message = 'Completed'
  }
  catch {
    $result.Ok = $false
    $result.Step = 'ERROR'
    $result.Message = $_.Exception.Message
  }

  if ($using:Verify) {
    try {
      $keyPath = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
      $regOut = & reg.exe QUERY "\\$fqdn\$keyPath" 2>$null
      if ($LASTEXITCODE -eq 0 -and $regOut) {
        $leafs = @()
        foreach ($line in $regOut) {
          if ($line -match 'HKEY_LOCAL_MACHINE\\.*\\Connections\\(.+)$') { $leafs += $Matches[1].Trim() }
        }
        $result.Verify = $leafs
      } else {
        $result.Verify = @()
      }
    } catch {
      $result.Verify = @("verify-error: $($_.Exception.Message)")
    }
  }

  $using:bag.Add([pscustomobject]$result)
}

# Emit results
$rows = $bag.ToArray() | Sort-Object Host
$rows | Select-Object Host,Ok,Step,Message,Verify | Format-Table -AutoSize

$fail = $rows | Where-Object { -not $_.Ok }
if ($fail) {
  Write-Host "`n--- FAILURES ---" -ForegroundColor Red
  $fail | Select-Object Host,Step,Message | Format-Table -AutoSize
  Write-Host ("Logs: {0}" -f (Join-Path $logsRoot $runToken)) -ForegroundColor Yellow
  exit 1
} else {
  Write-Host ("`nSuccess. Logs: {0}" -f (Join-Path $logsRoot $runToken)) -ForegroundColor Green
}