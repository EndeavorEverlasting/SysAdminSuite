<#  RPM-Recon.ps1 - Zero-risk printer mapping recon (ListOnly + Preflight)
    Streams progress live to console + Controller.log, survives Ctrl+C and
    finalizes outputs with whatever results were collected so far.

    Run (PowerShell 7+, elevated) from repo root or mapping:
      .\mapping\RPM-Recon.ps1 -HostsPath .\mapping\csv\hosts.txt
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$HostsPath,

  [int]$MaxParallel    = 12,
  [int]$MaxWaitSeconds = 60,
  [int]$PollSeconds    = 3
)

$ErrorActionPreference = 'Stop'

# --- Resolve paths / prerequisites --------------------------------------------
# NOTE (Bug-Log): $PSScriptRoot is only valid when this file is run as a script
# (pwsh -File or & .\RPM-Recon.ps1). It is empty when dot-sourced from the console.
# Always invoke via: pwsh -File .\Mapping\Controllers\RPM-Recon.ps1 -HostsPath ...
$HostsPath   = (Resolve-Path -LiteralPath $HostsPath).Path
$workerLeaf  = 'Map-MachineWide.ps1'
$localWorker = Join-Path $PSScriptRoot "..\Workers\$workerLeaf"
if (-not (Test-Path -LiteralPath $localWorker)) {
  # Fallback: look in same directory (legacy layout)
  $localWorker = Join-Path $PSScriptRoot $workerLeaf
}
if (-not (Test-Path -LiteralPath $localWorker)) {
  throw "Worker not found. Expected: $localWorker`nRun from repo root or pass full -HostsPath."
}

# Load host list (skip blanks and # comments)
$Targets = Get-Content -LiteralPath $HostsPath |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and $_ -notlike '#*' } |
  Sort-Object -Unique
if (!$Targets) { throw "No hosts found in: $HostsPath" }

# Session folder + logging ------------------------------------------------------
$sessionRoot = Join-Path $PSScriptRoot ("logs\recon-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
$ctrlLog = Join-Path $sessionRoot 'Controller.log'

# Streaming log queue + timer consumer (drains as messages arrive)
$queue = [System.Collections.Concurrent.ConcurrentQueue[pscustomobject]]::new()
$drain = {
  param($q,$logPath)
  $obj = $null
  while ($q.TryDequeue([ref]$obj)) {
    $line = "[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $obj.Tag, $obj.Msg
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line
  }
}
$timer = New-Object System.Timers.Timer 500
$timer.AutoReset = $true
$null = Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier 'RPMRecon.TimerElapsed' -Action {
  & $using:drain $using:queue $using:ctrlLog
}
$timer.Start()

function Enq([string]$msg,[string]$tag='CTL') { $queue.Enqueue([pscustomobject]@{Tag=$tag;Msg=$msg}) }

Enq "Recon session: $sessionRoot"
Enq ("Hosts: {0}" -f $Targets.Count)
Enq ("Open: {0}" -f (Join-Path $sessionRoot 'index.html'))

# --- Remote scheduling constants ----------------------------------------------
$remoteRootRel = "C$\ProgramData\SysAdminSuite\Mapping"
$remoteRoot    = "C:\ProgramData\SysAdminSuite\Mapping"
$remoteLogsRel = "C$\ProgramData\SysAdminSuite\Mapping\logs"
$pwshWin       = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$taskName      = 'SysAdminSuite_PrinterMap_Recon'

try {
  # --- Fan-out (uses $using:, no -ArgumentList; no global common params) -------
  $Targets | ForEach-Object -Parallel {
    $q              = $using:queue
    $localWorker    = $using:localWorker
    $remoteRootRel  = $using:remoteRootRel
    $remoteRoot     = $using:remoteRoot
    $remoteLogsRel  = $using:remoteLogsRel
    $pwshWin        = $using:pwshWin
    $taskName       = $using:taskName
    $sessionRoot    = $using:sessionRoot
    $MaxWaitSeconds = $using:MaxWaitSeconds
    $PollSeconds    = $using:PollSeconds

    function EnqRun([string]$msg){ $q.Enqueue([pscustomobject]@{Tag='RUN';Msg=$msg}) }

    $target = $_
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
      EnqRun "[$target] START"

      # Prefer FQDN for SMB/Kerberos
      try { $fqdn = ([System.Net.Dns]::GetHostEntry($target)).HostName } catch { $fqdn = $target }
      $schedTarget = $fqdn
      $shareName   = $fqdn
      $dstShare    = "\\$shareName\$remoteRootRel"
      $remoteLogs  = "\\$shareName\$remoteLogsRel"

      # Ping
      if (-not (Test-Connection -ComputerName $target -Quiet -Count 1)) {
        EnqRun "[$target] OFFLINE"
        return
      }
      EnqRun "[$target] PING OK ($shareName)"

      # Stage worker (terminating errors)
      New-Item -ItemType Directory -Path $dstShare -Force -ErrorAction Stop | Out-Null
      Copy-Item -LiteralPath $localWorker -Destination $dstShare -Force -ErrorAction Stop
      EnqRun "[$target] COPY OK -> $dstShare"

      # Schedule ONCE
      $remoteWorker = Join-Path $remoteRoot ([IO.Path]::GetFileName($localWorker))
      $psArgs       = '"{0}" -ListOnly -Preflight' -f $remoteWorker
      $pshWin       = 'powershell.exe'
      $tr           = '{0} -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File {1}' -f $pshWin, $psArgs

      $when   = (Get-Date).AddMinutes(1)
      $stTime = $when.ToString('HH:mm')
      $dateFmt = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern
      $stDate = $when.ToString($dateFmt)

      $createOut = & schtasks.exe /Create /S $schedTarget /RU SYSTEM /SC ONCE /SD $stDate /ST $stTime /TN $taskName /TR $tr /RL HIGHEST /F 2>&1
      if ($LASTEXITCODE -ne 0) {
        EnqRun "[$target] ERROR schtasks /Create failed (exit $LASTEXITCODE): $createOut"
        $status = "Create failed"; throw "schtasks /Create failed"
      }
      EnqRun "[${target}] TASK CREATED ($stDate $stTime)"

      $runOut = & schtasks.exe /Run /S $schedTarget /TN $taskName 2>&1
      if ($LASTEXITCODE -ne 0) {
        EnqRun "[$target] ERROR schtasks /Run failed (exit $LASTEXITCODE): $runOut"
        $status = "Run failed"; throw "schtasks /Run failed"
      }
      EnqRun "[${target}] TASK STARTED"


      # Poll for artifacts
      EnqRun "[$target] POLLING ..."
      $latest = $null
      $elapsed = 0
      while ($elapsed -lt $MaxWaitSeconds) {
        if (Test-Path $remoteLogs) {
          $latest = Get-ChildItem -Path $remoteLogs -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending | Select-Object -First 1
          if ($latest) { break }
        }
        Start-Sleep -Seconds $PollSeconds
        $elapsed += $PollSeconds
      }

      # Collect
      if ($latest) {
        $hostOut = Join-Path $sessionRoot $target
        New-Item -ItemType Directory -Path $hostOut -Force | Out-Null
        Copy-Item -Path (Join-Path $latest.FullName '*') -Destination $hostOut -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $latest.FullName -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $latest.FullName -Force -ErrorAction SilentlyContinue
        EnqRun "[$target] COLLECTED"
        $status = "Collected -> $hostOut"
      } else {
        EnqRun "[$target] NO ARTIFACTS (${MaxWaitSeconds}s)"
        $status = "No artifacts after ${MaxWaitSeconds}s"
      }

      # Cleanup (best-effort)
      & schtasks.exe /Delete /S $schedTarget /TN $taskName /F 2>&1 | Out-Null
      Remove-Item -LiteralPath "\\$shareName\C$\ProgramData\SysAdminSuite\Mapping" -Recurse -Force -ErrorAction SilentlyContinue

      $sw.Stop()
      EnqRun "[$target] SUMMARY | Create: $createOut | Run: $runOut | $status | $($sw.Elapsed)"

    } catch {
      $sw.Stop()
      EnqRun "[$target] ERROR: $($_.Exception.Message) | $($sw.Elapsed)"
    }
  } -ThrottleLimit $MaxParallel

} catch [System.Management.Automation.PipelineStoppedException] {
  Enq "Ctrl+C detected - finalizing with partial results..." "CTL"
} finally {
  # Stop timer, drain queue
  $timer.Stop()
  Unregister-Event -SourceIdentifier 'RPMRecon.TimerElapsed' -ErrorAction SilentlyContinue
  & $drain $queue $ctrlLog

  # Roll-up CentralResults.csv (whatever we have)
  $centralCsv = Join-Path $sessionRoot 'CentralResults.csv'
  $rows = New-Object System.Collections.Generic.List[Object]
  Get-ChildItem -Path $sessionRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $r = Get-ChildItem -Path $_.FullName -Filter 'Results.csv' -File -ErrorAction SilentlyContinue
    if ($r) { try { (Import-Csv -LiteralPath $r.FullName) | ForEach-Object { $rows.Add($_) } } catch {} }
  }
  if ($rows.Count -gt 0) { $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $centralCsv }

  # index.html (always)
  $index = @"
<!DOCTYPE html><html><head><meta charset="utf-8">
<title>RPM Recon</title>
<style>
  body{font-family:Segoe UI,Arial;background:#0b0b0f;color:#eaeaf0;padding:24px}
  a{color:#8ed0ff;text-decoration:none}
  .host{margin:10px 0 18px 0}
  .chip{display:inline-block;background:#1a1a22;border:1px solid #2a2a34;padding:3px 8px;border-radius:999px;margin-right:6px;font-size:12px}
  pre{white-space:pre-wrap;background:#13131a;border:1px solid #232330;border-radius:8px;padding:8px}
</style></head><body>
<h1>RPM Recon @ $(Get-Date)</h1>
<p><span class="chip">Hosts: $($Targets.Count)</span>
   <span class="chip">Central CSV: $(Split-Path $centralCsv -Leaf)</span></p>
<p><a href="./$(Split-Path $centralCsv -Leaf)">Download CentralResults.csv</a></p>
<h2>Controller Log</h2>
<pre>$(Get-Content $ctrlLog -Raw)</pre>
<hr/>
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

  # Final drain to ensure last line hits
  & $drain $queue $ctrlLog
}