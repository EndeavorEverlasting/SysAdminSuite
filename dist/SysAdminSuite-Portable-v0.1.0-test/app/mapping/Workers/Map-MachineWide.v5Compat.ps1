<#
Map-Remote-MachineWide-Printers.v5Compat.ps1
PS7 admin -> PS5 endpoints (200+ boxes) via WSMan, no agent installs.
Machine-wide adds (/ga), removals (/gd), optional per-user default via one-shot task, and verify.
Creates a pooled set of PS5 sessions (-ConfigurationName Microsoft.PowerShell) and fans out in parallel.

Examples
--------
# Smoke (3 hosts, two queues, verify)
pwsh ./Map-Remote-MachineWide-Printers.v5Compat.ps1 `
  -HostsPath .\csv\hosts_smoke.txt `
  -Queues '\\PRINTSRV\Q67','\\PRINTSRV\Q62' `
  -Verify -MaxParallel 16 -Verbose

# Commit (full list, set default for users at next logon)
pwsh ./Map-Remote-MachineWide-Printers.v5Compat.ps1 `
  -HostsPath .\csv\hosts.txt `
  -Queues '\\PRINTSRV\WCC-67','\\PRINTSRV\WCC-62' `
  -DefaultQueue '\\PRINTSRV\WCC-67' `
  -MaxParallel 32 -Verbose

# Rollback a bad queue
pwsh ./Map-Remote-MachineWide-Printers.v5Compat.ps1 `
  -HostsPath .\csv\hosts.txt `
  -RemoveQueues '\\PRINTSRV\WCC-67' -Verify
#>

[CmdletBinding(SupportsShouldProcess, PositionalBinding=$false)]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$HostsPath,

  [string[]]$Queues = @(),          # queues to ADD (machine-wide)
  [string[]]$RemoveQueues = @(),     # queues to REMOVE (machine-wide)
  [string]$DefaultQueue,            # optional default per-user at next logon

  [int]$MaxParallel = 32,           # fan-out (tune to your network)
  [int]$TimeoutSeconds = 120,       # per-command timeout on each box

  [switch]$Verify,                  # list HKLM machine-wide connections after
  [pscredential]$Credential         # optional domain creds; else current token
)

# ---- Utilities ---------------------------------------------------------------

function Get-HostList {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Hosts file not found: $Path" }
  Get-Content -LiteralPath $Path |
    Where-Object { $_ -and $_.Trim() -ne '' -and $_ -notmatch '^\s*#' } |
    ForEach-Object { $_.Trim() } |
    Sort-Object -Unique
}

function New-CompatSessions {
  [CmdletBinding()]
  param(
    [string[]]$Computers,
    [int]$Throttle = 64,
    [pscredential]$Cred
  )

  $opt = New-PSSessionOption -OperationTimeout (1000 * 90) -IdleTimeout 7200000
  $sessionArgs = @{
    ComputerName      = $Computers
    ConfigurationName = 'Microsoft.PowerShell'   # <-- PS5 endpoint
    Authentication    = 'Negotiate'
    UseSSL            = $false
    SessionOption     = $opt
    ErrorAction       = 'SilentlyContinue'
    ThrottleLimit     = $Throttle
  }
  if ($Cred) { $sessionArgs.Credential = $Cred }

  Write-Verbose "Opening sessions to $($Computers.Count) endpoints (PS5) ..."
  $sessions = New-PSSession @sessionArgs

  # Report failures explicitly
  $failed = $Computers | Where-Object { $c = $_; -not ($sessions.ComputerName -contains $c) }
  if ($failed) {
    Write-Warning ("No session to: {0}" -f ($failed -join ', '))
  }
  $sessions
}

# Remote scriptblocks (run inside PS5 on the client)
$sbAdd = {
  param([string[]]$Queues)
  $added = @()
  foreach ($q in $Queues) {
    try {
      $p = Start-Process -FilePath 'rundll32.exe' -ArgumentList @('printui.dll,PrintUIEntry','/ga',"/n$q") -Wait -WindowStyle Hidden -PassThru
      if ($p.ExitCode -eq 0) { $added += $q } else { Write-Error "Add failed: $q :: exit code $($p.ExitCode)" }
    } catch { Write-Error "Add failed: $q :: $($_.Exception.Message)" }
  }
  try { Start-Process gpupdate.exe -ArgumentList '/target:computer','/force' -WindowStyle Hidden -Wait } catch {}
  [pscustomobject]@{ Added = $added }
}

$sbRemove = {
  param([string[]]$Queues)
  $removed = @()
  foreach ($q in $Queues) {
    try {
      $p = Start-Process -FilePath 'rundll32.exe' -ArgumentList @('printui.dll,PrintUIEntry','/gd',"/n$q") -Wait -WindowStyle Hidden -PassThru
      if ($p.ExitCode -eq 0) { $removed += $q } else { Write-Error "Remove failed: $q :: exit code $($p.ExitCode)" }
    } catch { Write-Error "Remove failed: $q :: $($_.Exception.Message)" }
  }
  try { Start-Process gpupdate.exe -ArgumentList '/target:computer','/force' -WindowStyle Hidden -Wait } catch {}
  [pscustomobject]@{ Removed = $removed }
}

$sbDefaultOnce = {
  param([string]$Queue)
  if ($Queue -notmatch "^[A-Za-z0-9 _\-\\]+$") {
    throw "Queue contains unsupported characters: $Queue"
  }
  $connEsc = $Queue.Replace("'","''")
  $filterEsc = $Queue.Replace("'","''").Replace('\','\\')
  $ps = @"
Add-Printer -ConnectionName '$connEsc' -ErrorAction SilentlyContinue
\$p = Get-CimInstance Win32_Printer -Filter "Name='$filterEsc'"
if (\$p) { \$null = \$p | Invoke-CimMethod -MethodName SetDefaultPrinter }
"@
  try {
    $act  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command $ps"
    $trg  = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId 'BUILTIN\Users' -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName 'SetDefaultPrinterOnce' -Action $act -Trigger $trg -Principal $principal -Force | Out-Null
    'DEFAULT_TASK_REGISTERED'
  } catch { Write-Error $_ }
}

$sbVerify = {
  $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
  if (Test-Path $k) { (Get-ChildItem $k | Select-Object -ExpandProperty PSChildName) } else { @() }
}

# ---- Main --------------------------------------------------------------------

$hosts = @(Get-HostList -Path $HostsPath)
if (-not $hosts.Count) { throw "No hosts in $HostsPath" }

# Open a session pool to PS5 endpoints once, reuse for all actions
$sessions = New-CompatSessions -Computers $hosts -Throttle ([math]::Min($hosts.Count, 128)) -Cred $Credential
if (-not $sessions) { throw "No usable sessions opened. Check WinRM/ACLs/Firewall." }

# Helper to fan-out a command across existing sessions
function Invoke-Pool {
  param(
    [System.Management.Automation.Runspaces.PSSession[]]$Sess,
    [scriptblock]$ScriptBlock,
    [object[]]$InvokeArgs = @(),
    [int]$Max = 32,
    [int]$Timeout = 120,
    [string]$Action = 'RUN'
  )
  $bag = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
  $null = $Sess | ForEach-Object -ThrottleLimit $Max -Parallel {
    $sb      = $using:ScriptBlock
    $argList = $using:InvokeArgs
    $timeout = $using:Timeout
    $act     = $using:Action
    try {
      $job = Invoke-Command -Session $_ -ScriptBlock $sb -ArgumentList $argList -AsJob -ErrorAction Stop
      if (-not ($job | Wait-Job -Timeout $timeout)) {
        try { $job | Stop-Job -Force | Out-Null } catch {}
        $using:bag.Add([pscustomobject]@{ Computer=$_.ComputerName; Action=$act; Ok=$false; Message="Timeout ${timeout}s" })
      } else {
        $out = $job | Receive-Job -ErrorAction SilentlyContinue
        $job | Remove-Job | Out-Null
        $using:bag.Add([pscustomobject]@{ Computer=$_.ComputerName; Action=$act; Ok=$true;  Message=($out | Out-String).Trim() })
      }
    } catch {
      $using:bag.Add([pscustomobject]@{ Computer=$_.ComputerName; Action=$act; Ok=$false; Message=$_.Exception.Message })
    }
  }
  $bag.ToArray()
}

$results = @()

if ($Queues.Count) {
  $results += Invoke-Pool -Sess $sessions -ScriptBlock $sbAdd -InvokeArgs @($Queues) -Max $MaxParallel -Timeout $TimeoutSeconds -Action 'ADD'
}

if ($RemoveQueues.Count) {
  $results += Invoke-Pool -Sess $sessions -ScriptBlock $sbRemove -InvokeArgs @($RemoveQueues) -Max $MaxParallel -Timeout $TimeoutSeconds -Action 'REMOVE'
}

if ($DefaultQueue) {
  $results += Invoke-Pool -Sess $sessions -ScriptBlock $sbDefaultOnce -InvokeArgs @($DefaultQueue) -Max $MaxParallel -Timeout $TimeoutSeconds -Action 'DEFAULT'
}

if ($Verify) {
  $results += Invoke-Pool -Sess $sessions -ScriptBlock $sbVerify -Max $MaxParallel -Timeout $TimeoutSeconds -Action 'VERIFY'
}

# Close sessions
$sessions | Remove-PSSession -ErrorAction SilentlyContinue

# Output tidy
$results | Sort-Object Computer, Action | Format-Table -AutoSize

$failed = $results | Where-Object { -not $_.Ok }
if ($failed) {
  Write-Host "`n--- FAILURES ---" -ForegroundColor Red
  $failed | Format-Table -AutoSize
  exit 1
} else {
  Write-Host "`nDone." -ForegroundColor Green
}