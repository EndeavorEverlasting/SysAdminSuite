<#
================================================================================
 RPM-Recon.ps1 — Annotated Edition (v1.1)      Generated: (now)
--------------------------------------------------------------------------------
Purpose
  Read-only "recon" for printer mappings across many Windows hosts, orchestrated
  from a controller box. This annotated edition keeps the working logic and adds
  commentary so future-you knows why choices were made.

High-level flow
  Resolve → Reachability → Stage → Schedule (SYSTEM) → Poll → Collect
  → Roll-up → Report (HTML) → Cleanup.

Outputs
  ./logs/recon-YYYYMMDD-HHmmss/
    - Controller.log (live breadcrumbs)
    - CentralResults.csv (if any Results.csv exist; includes Scope column)
    - index.html (renders Controller.log + per-host mapping tables with scope)
    - <HOST>\Results.csv, Results.html, Preflight.csv, Run.log (if produced)

Guarantees
  - Recon only (ListOnly + Preflight): no endpoint changes to mappings.
  - Partial credit: failures logged, partial successes preserved.
  - Ctrl+C: flushes logs and writes index.html/CentralResults.csv with whatever exists.

Important quirks
  - Use FQDN for \\share and /S target to avoid Kerberos "target account name is incorrect".
  - PowerShell 7 required for ForEach-Object -Parallel.
  - Do NOT use $host variable (reserved). Use $target.
================================================================================
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
$HostsPath   = (Resolve-Path -LiteralPath $HostsPath).Path
$workerLeaf  = 'Map-Remote-MachineWide-Printers.ps1'
$localWorker = Join-Path $PSScriptRoot $workerLeaf
if (-not (Test-Path -LiteralPath $localWorker)) {
  throw "Worker not found next to this script: $localWorker"
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

# Streaming log queue → console + Controller.log (every ~500ms)
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
$timer.add_Elapsed({ & $drain $queue $ctrlLog })
$timer.Start()

function Enq([string]$msg,[string]$tag='CTL') { $queue.Enqueue([pscustomobject]@{Tag=$tag;Msg=$msg}) }

Enq "Recon session: $sessionRoot"
Enq ("Hosts: {0}" -f $Targets.Count)
Enq ("Open: {0}" -f (Join-Path $sessionRoot 'index.html'))

# Remote constants --------------------------------------------------------------
$remoteRootRel = "C$\ProgramData\SysAdminSuite\Mapping"
$remoteRoot    = "C:\ProgramData\SysAdminSuite\Mapping"
$remoteLogsRel = "C$\ProgramData\SysAdminSuite\Mapping\logs"
$pwshWin       = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$taskName      = 'SysAdminSuite_PrinterMap_Recon'

# Helper: determine mapping scope for a CSV row (SYSTEM vs USER vs UNKNOWN)
function Get-RowScope {
  param([Parameter(Mandatory)][pscustomobject]$Row)
  $names = $Row.PSObject.Properties.Name

  if ($names -contains 'Scope' -and $Row.Scope) { return [string]$Row.Scope }

  if ($names -contains 'RegRoot') {
    if ($Row.RegRoot -match 'HKLM|HKEY_LOCAL_MACHINE') { return 'SYSTEM' }
    if ($Row.RegRoot -match 'HKCU|HKEY_CURRENT_USER') { return 'USER' }
  }
  if ($names -contains 'Hive') {
    if ($Row.Hive -match 'HKLM') { return 'SYSTEM' }
    if ($Row.Hive -match 'HKCU') { return 'USER' }
  }
  if ($names -contains 'UserSid') {
    if ($Row.UserSid -match '^S-1-5-18$|^S-1-5-19$|^S-1-5-20$') { return 'SYSTEM' }
    if ($Row.UserSid -match '^S-1-5-21-') { return 'USER' }
  }
  return 'UNKNOWN'
}

try {
  # Fan-out (PowerShell 7). Do not pass common params into -Parallel.
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

      # Reachability
      if (-not (Test-Connection -ComputerName $target -Quiet -Count 1)) {
        EnqRun "[$target] OFFLINE"
        return
      }
      EnqRun "[$target] PING OK ($shareName)"

      # Stage worker (terminating errors)
      New-Item -ItemType Directory -Path $dstShare -Force -ErrorAction Stop | Out-Null
      Copy-Item -LiteralPath $localWorker -Destination $dstShare -Force -ErrorAction Stop
      EnqRun "[$target] COPY OK → $dstShare"

      # Schedule ONCE (avoid EndBoundary XML bug; no /Z)
      $remoteWorker = Join-Path $remoteRoot ([IO.Path]::GetFileName($localWorker))
      $psArgs       = "`"$remoteWorker`" -ListOnly -Preflight"
      $tr           = "$pwshWin -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $psArgs"

      $when   = (Get-Date).AddMinutes(1)
      $stTime = $when.ToString('HH:mm')
      $stDate = $when.ToString('MM/dd/yyyy')
      $createOut = (cmd /c "schtasks /Create /S $schedTarget /RU SYSTEM /SC ONCE /SD $stDate /ST $stTime /TN $taskName /TR `"$tr`" /RL HIGHEST /F") 2>&1
      EnqRun "[$target] TASK CREATED ($stDate $stTime)"
      $runOut    = (cmd /c "schtasks /Run /S $schedTarget /TN $taskName") 2>&1

      # Poll for artifacts
      EnqRun "[$target] POLLING …"
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
        Copy-Item -Path (Join-Path $latest.FullName '*.*') -Destination $hostOut -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $latest.FullName -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $latest.FullName -Force -ErrorAction SilentlyContinue
        EnqRun "[$target] COLLECTED"
        $status = "Collected → $hostOut"
      } else {
        EnqRun "[$target] NO ARTIFACTS (${MaxWaitSeconds}s)"
        $status = "No artifacts after ${MaxWaitSeconds}s"
      }

      # Cleanup (best-effort)
      cmd /c "schtasks /Delete /S $schedTarget /TN $taskName /F" | Out-Null
      Remove-Item -LiteralPath "\\$shareName\C$\ProgramData\SysAdminSuite\Mapping" -Recurse -Force -ErrorAction SilentlyContinue

      $sw.Stop()
      EnqRun "[$target] SUMMARY | Create: $createOut | Run: $runOut | $status | ${($sw.Elapsed)}"

    } catch {
      $sw.Stop()
      EnqRun "[$target] ERROR: $($_.Exception.Message) | ${($sw.Elapsed)}"
    }
  } -ThrottleLimit $MaxParallel

} catch [System.Management.Automation.PipelineStoppedException] {
  Enq "Ctrl+C detected — finalizing with partial results…" "CTL"
} finally {
  # Stop timer, drain queue to Controller.log
  $timer.Stop()
  & $drain $queue $ctrlLog

  # Roll-up CentralResults.csv (add Scope column)
  $centralCsv = Join-Path $sessionRoot 'CentralResults.csv'
  $rows = New-Object System.Collections.Generic.List[Object]
  Get-ChildItem -Path $sessionRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $r = Get-ChildItem -Path $_.FullName -Filter 'Results.csv' -File -ErrorAction SilentlyContinue
    if ($r) {
      try {
        foreach ($row in (Import-Csv -LiteralPath $r.FullName)) {
          $scope = Get-RowScope -Row $row
          $row | Add-Member -NotePropertyName "Scope" -NotePropertyValue $scope -Force
          $rows.Add($row)
        }
      } catch {}
    }
  }
  $centralCsvExists = $false
  if ($rows.Count -gt 0) {
    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $centralCsv
    $centralCsvExists = $true
  }

  # Build index.html with per-host tables + scope column
  $index = @"
<!DOCTYPE html><html><head><meta charset="utf-8">
<title>RPM Recon</title>
<style>
  body{font-family:Segoe UI,Arial;background:#0b0b0f;color:#eaeaf0;padding:24px}
  a{color:#8ed0ff;text-decoration:none}
  .host{margin:10px 0 18px 0}
  .chip{display:inline-block;background:#1a1a22;border:1px solid #2a2a34;padding:3px 8px;border-radius:999px;margin-right:6px;font-size:12px}
  pre{white-space:pre-wrap;background:#13131a;border:1px solid #232330;border-radius:8px;padding:8px}
  table{border-collapse:collapse;width:100%;margin:12px 0}
  th,td{border:1px solid #444;padding:6px 10px;text-align:left;font-size:13px}
  th{background:#222;color:#ddd}
  .scope-user{color:#8ed0ff;font-weight:600}
  .scope-system{color:#90ee90;font-weight:600}
  .scope-unknown{color:#ffa07a;font-weight:600}
</style></head><body>
<h1>RPM Recon @ $(Get-Date)</h1>
<p><span class="chip">Hosts: $($Targets.Count)</span>
"@
  if ($centralCsvExists) {
    $index += "<span class='chip'>Central CSV: CentralResults.csv</span></p>
<p><a href='./CentralResults.csv'>Download CentralResults.csv</a></p>"
  } else {
    $index += "<span class='chip'>Central CSV: none</span></p>"
  }
  $index += "<h2>Controller Log</h2><pre>$(Get-Content $ctrlLog -Raw)</pre><hr/>"

  # Per-host mapping tables
  Get-ChildItem -Path $sessionRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    $host = $_.Name
    $index += "<div class='host'><h2>$host</h2>"
    $results = Get-ChildItem -Path $_.FullName -Filter 'Results.csv' -File -ErrorAction SilentlyContinue
    if ($results) {
      try {
        $rows = Import-Csv -LiteralPath $results.FullName
        if ($rows) {
          # Build header with existing columns + Scope
          $index += "<table><tr>"
          foreach ($col in $rows[0].PSObject.Properties.Name) { $index += "<th>$col</th>" }
          $index += "<th>Scope</th></tr>"

          # Body
          foreach ($row in $rows) {
            $scope = Get-RowScope -Row $row
            $scopeClass = switch ($scope) { 'SYSTEM' {'scope-system'} 'USER' {'scope-user'} default {'scope-unknown'} }
            $index += "<tr>"
            foreach ($col in $row.PSObject.Properties.Name) {
              $index += "<td>$([System.Web.HttpUtility]::HtmlEncode($row.$col))</td>"
            }
            $index += "<td class='$scopeClass'>$scope</td></tr>"
          }
          $index += "</table>"
        } else {
          $index += "<p><i>Results.csv was empty.</i></p>"
        }
      } catch {
        $index += "<p><i>Failed to parse Results.csv ($($_.Exception.Message)).</i></p>"
      }
    } else {
      $index += "<p><i>No Results.csv found.</i></p>"
    }

    # Also list any files present for quick downloads
    $index += "<ul>"
    foreach ($f in Get-ChildItem -Path $_.FullName -File -ErrorAction SilentlyContinue | Sort-Object Name) {
      $rel = $f.FullName.Replace($sessionRoot,'').TrimStart('\').Replace('\','/')
      $index += "<li><a href='$rel'>$($f.Name)</a></li>"
    }
    $index += "</ul></div><hr/>"
  }

  $index += "</body></html>"
  Set-Content -LiteralPath (Join-Path $sessionRoot 'index.html') -Value $index -Encoding UTF8

  # Final drain to ensure last messages land
  & $drain $queue $ctrlLog
}
