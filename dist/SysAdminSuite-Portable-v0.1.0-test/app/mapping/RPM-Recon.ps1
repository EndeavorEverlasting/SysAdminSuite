# mapping\RPM-Recon.ps1
<#
.SYNOPSIS
Zero-risk, controller-driven printer mapping recon (ListOnly + Preflight).

.DESCRIPTION
Stages the worker on each target, schedules a SYSTEM task to run Windows PowerShell
(PS5) with -ListOnly -Preflight, polls for artifacts over ADMIN$ (UNC), collects
whatever landed, and always finalizes an index + CentralResults.csv.

.Run from repo root or mapping (PowerShell 7+, elevated):
.\mapping\RPM-Recon.ps1 -HostsPath .\mapping\csv\hosts.txt

.PARAMETER HostsPath
Path to a text file of hosts; one host per line; lines starting with # ignored.

.PARAMETER MaxParallel
Max parallel fan-out from the controller (runspace workers).

.PARAMETER MaxWaitSeconds
Polling window for artifacts to appear on the remote logs directory.

.PARAMETER PollSeconds
Polling interval inside the wait window.

.NOTES
- Avoids $host collisions (PowerShell reserved).
- Clients run PS5; controller runs PS7+.
- Creates a hosts template if missing/empty, never overwrites real content.
#>

# ---------- 1) HEADER (must be first) ----------
[CmdletBinding(SupportsShouldProcess = $false, PositionalBinding = $false)]
param(
  [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
  [ValidateNotNullOrEmpty()]
  [Alias('HostsFile','HostList')]
  [string]$HostsPath,

  [ValidateRange(1,128)]
  [int]$MaxParallel    = 12,

  [ValidateRange(10,600)]
  [int]$MaxWaitSeconds = 60,

  [ValidateRange(1,30)]
  [int]$PollSeconds    = 3
)

# --- Normalize early: accept PathInfo or string, end up with string ---
if ($HostsPath -isnot [string]) { $HostsPath = $HostsPath.ToString() }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

# ---------- 2) CONSTANTS (before any use) ----------
$workerLeaf     = 'Map-Remote-MachineWide-Printers.ps1'
$remoteRootRel  = 'C$\ProgramData\SysAdminSuite\Mapping'
$remoteRoot     = 'C:\ProgramData\SysAdminSuite\Mapping'
$remoteLogsRel  = 'C$\ProgramData\SysAdminSuite\Mapping\logs'
$taskName       = 'SysAdminSuite_PrinterMap_Recon'

# ---------- 3) BOOTSTRAP (after header) ----------
function New-HostsTemplate {
  param([Parameter(Mandatory)][string]$Path)
  $parent = Split-Path -Parent $Path
  if ($parent) { $null = New-Item -ItemType Directory -Force -Path $parent }
@"
# hosts.txt — one host per line. Lines starting with # are ignored.
# Place short names or FQDNs; FQDN preferred if Kerberos/SPN issues.
WGH003STR001
WGH003STR002
WGH003STR003
"@ | Set-Content -Encoding UTF8 -NoNewline -Path $Path
}

try {
  $ResolvedHosts = Resolve-Path -Path $HostsPath -ErrorAction Stop
} catch {
  New-HostsTemplate -Path $HostsPath
  Write-Warning "Created hosts template at: $HostsPath"
  throw "No hosts found. Populate and rerun."
}

$Targets = Get-Content -Path $ResolvedHosts |
           Where-Object { $_ -and $_ -notmatch '^\s*#' } |
           ForEach-Object { $_.Trim() } |
           Sort-Object -Unique

if (-not $Targets) {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  Copy-Item -LiteralPath $ResolvedHosts -Destination "$ResolvedHosts.$ts.bak" -Force
  New-HostsTemplate -Path $ResolvedHosts
  Write-Warning "Existing hosts had no usable entries; backed up."
  throw "Populate $ResolvedHosts and rerun."
}

# ---------- 4) PATHS, LOGGING & HELPERS ----------
$HostsPath   = (Resolve-Path -LiteralPath $HostsPath).Path
$localWorker = Join-Path $PSScriptRoot $workerLeaf
if (-not (Test-Path -LiteralPath $localWorker)) {
  throw "Worker not found next to this script: $localWorker"
}

$sessionRoot = Join-Path $PSScriptRoot ("logs\recon-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
$null = New-Item -ItemType Directory -Path $sessionRoot -Force
$ctrlLog = Join-Path $sessionRoot 'Controller.log'
# QoL: guard parent path explicitly (redundant but explicit)
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $ctrlLog) -Force

$queue = [System.Collections.Concurrent.ConcurrentQueue[pscustomobject]]::new()
function Enq([string]$msg,[string]$tag='CTL'){ $queue.Enqueue([pscustomobject]@{Tag=$tag;Msg=$msg}) }
function Drain($q,$logPath){
  $obj=$null
  while($q.TryDequeue([ref]$obj)){
    $line = "[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $obj.Tag, $obj.Msg
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line
  }
}
$timer = New-Object System.Timers.Timer 500
$timer.AutoReset = $true
$timer.add_Elapsed({ Drain $queue $ctrlLog })
$timer.Start()

Enq "Recon session: $sessionRoot"
Enq ("Hosts: {0}" -f $Targets.Count)
Enq ("Open: {0}" -f (Join-Path $sessionRoot 'index.html'))

# ---------- 5) FAN-OUT ----------
try {
  $Targets | ForEach-Object -Parallel {
    # --- Strict + stop inside runspace ---
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $q              = $using:queue
    $localWorker    = $using:localWorker
    $remoteRootRel  = $using:remoteRootRel
    $remoteRoot     = $using:remoteRoot
    $remoteLogsRel  = $using:remoteLogsRel
    $taskName       = $using:taskName
    $sessionRoot    = $using:sessionRoot
    $MaxWaitSeconds = $using:MaxWaitSeconds
    $PollSeconds    = $using:PollSeconds

    function EnqRun([string]$m){ $q.Enqueue([pscustomobject]@{Tag='RUN';Msg=$m}) }

    $target = $_
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
      EnqRun "[$target] START"

      # --------- SPN-RESILIENT NAME RESOLUTION (FQDN → short → IP) ----------
      try { $fqdn = ([System.Net.Dns]::GetHostEntry($target)).HostName } catch { $fqdn = $target }
      $short = $target -replace '\..*$',''
      try { $ip = (Resolve-DnsName $fqdn -Type A -ErrorAction Stop).IPAddress | Select-Object -First 1 } catch { $ip = $null }

      $namesToTry = @($fqdn, $short) + @(if ($ip) { $ip } else { $null }) | Where-Object { $_ }
      $shareName = $null
      foreach ($n in $namesToTry) {
        if (Test-Path "\\$n\ADMIN$") { $shareName = $n; break }
      }
      if (-not $shareName) { EnqRun "[$target] ADMIN$ unavailable on all name variants"; return }

      EnqRun "[$target] USING NAME VARIANT: $shareName"

      # Use the chosen variant for BOTH file stage and scheduler /S target
      $schedTarget = $shareName
      $dstShare    = "\\$shareName\$remoteRootRel"
      $remoteLogs  = "\\$shareName\$remoteLogsRel"

      # ----------------------------------------------------------------------

      if (-not (Test-Connection -ComputerName $target -Quiet -Count 1)) { EnqRun "[$target] OFFLINE"; return }
      EnqRun "[$target] PING OK ($shareName)"

      New-Item -ItemType Directory -Path $dstShare -Force -ErrorAction Stop | Out-Null
      Copy-Item -LiteralPath $localWorker -Destination $dstShare -Force -ErrorAction Stop
      EnqRun "[$target] COPY OK → $dstShare"

      $remoteWorker = Join-Path $remoteRoot ([IO.Path]::GetFileName($localWorker))

      # Hardened quoting for schtasks /TR
      $psArgs = '"{0}" -ListOnly -Preflight' -f $remoteWorker
      $tr     = '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" ' +
                '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + $psArgs
      $when   = (Get-Date).AddMinutes(1)
      $stTime = $when.ToString('HH:mm')
      $stDate = $when.ToString('MM/dd/yyyy')
      $trEsc  = '"' + $tr.Replace('"','\"') + '"'

      $createCmd = 'schtasks /Create /S {0} /RU SYSTEM /SC ONCE /SD {1} /ST {2} /TN {3} /TR {4} /RL HIGHEST' -f $schedTarget,$stDate,$stTime,$taskName,$trEsc
      $null = (cmd /c $createCmd) 2>&1
      EnqRun "[$target] TASK CREATED ($stDate $stTime)"

      $null = (cmd /c "schtasks /Run /S $schedTarget /TN $taskName") 2>&1
      EnqRun "[$target] TASK STARTED"

      EnqRun "[$target] POLLING …"
      $latest=$null; $elapsed=0
      while ($elapsed -lt $MaxWaitSeconds) {
        if (Test-Path $remoteLogs) {
          $latest = Get-ChildItem -Path $remoteLogs -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending | Select-Object -First 1
          if ($latest) { break }
        }
        Start-Sleep -Seconds $PollSeconds; $elapsed += $PollSeconds
      }

      if ($latest) {
        $hostOut = Join-Path $sessionRoot $target
        New-Item -ItemType Directory -Path $hostOut -Force | Out-Null
        Copy-Item -Path (Join-Path $latest.FullName '*.*') -Destination $hostOut -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $latest.FullName -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $latest.FullName -Force -ErrorAction SilentlyContinue
        EnqRun "[$target] COLLECTED"
        $status = "Collected → $hostOut"
      } else {
        EnqRun "[$target] NO ARTIFACTS (${MaxWaitSeconds}s)"
        $status = "No artifacts after ${MaxWaitSeconds}s"
      }

      cmd /c "schtasks /Delete /S $schedTarget /TN $taskName /F" | Out-Null
      Remove-Item -LiteralPath "\\$shareName\C$\ProgramData\SysAdminSuite\Mapping" -Recurse -Force -ErrorAction SilentlyContinue

      $sw.Stop()
      EnqRun "[$target] SUMMARY | $status | $($sw.Elapsed)"
    } catch {
      $sw.Stop(); EnqRun "[$target] ERROR: $($_.Exception.Message) | $($sw.Elapsed)"
    }
  } -ThrottleLimit $MaxParallel

} catch [System.Management.Automation.PipelineStoppedException] {
  Enq "Ctrl+C detected — finalizing with partial results…"
} finally {
  $timer.Stop()
  try { $timer.Dispose() } catch {}
  Drain $queue $ctrlLog

  $centralCsv = Join-Path $sessionRoot 'CentralResults.csv'
  $rows = New-Object System.Collections.Generic.List[Object]
  Get-ChildItem -Path $sessionRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $r = Get-ChildItem -Path $_.FullName -Filter 'Results.csv' -File -ErrorAction SilentlyContinue
    if ($r) { try { (Import-Csv -LiteralPath $r.FullName) | ForEach-Object { $rows.Add($_) } } catch {} }
  }
  if ($rows.Count -gt 0) { $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $centralCsv }

  $index = @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>RPM Recon</title>
<style>body{font-family:Segoe UI,Arial;background:#0b0b0f;color:#eaeaf0;padding:24px}a{color:#8ed0ff;text-decoration:none}.host{margin:10px 0 18px 0}.chip{display:inline-block;background:#1a1a22;border:1px solid #2a2a34;padding:3px 8px;border-radius:999px;margin-right:6px;font-size:12px}pre{white-space:pre-wrap;background:#13131a;border:1px solid #232330;border-radius:8px;padding:8px}</style></head><body>
<h1>RPM Recon @ $(Get-Date)</h1>
<p><span class="chip">Hosts: $($Targets.Count)</span><span class="chip">Central CSV: $(Split-Path $centralCsv -Leaf)</span></p>
<p><a href="./$(Split-Path $centralCsv -Leaf)">Download CentralResults.csv</a></p>
<h2>Controller Log</h2><pre>$(Get-Content $ctrlLog -Raw)</pre><hr/>
"@
  Get-ChildItem -Path $sessionRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    $index += "<div class='host'><h3>$($_.Name)</h3><ul>"
    foreach ($f in Get-ChildItem -Path $_.FullName -File -ErrorAction SilentlyContinue | Sort-Object Name) {
      $rel = $f.FullName.Replace($sessionRoot,'').TrimStart('\').Replace('\','/')
      $index += "<li><a href='$rel'>$($f.Name)</a></li>"
    }
    $index += "</ul></div>"
  }
  $index += "</body></html>"
  Set-Content -LiteralPath (Join-Path $sessionRoot 'index.html') -Value $index -Encoding UTF8

  Drain $queue $ctrlLog
}
