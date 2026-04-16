<# ========================================================================
 RPM-Recon.ps1 — Annotated Edition (v1.1, single-parameter-set hardening)
 Purpose: fan out a read-only recon of printer mappings across hosts.
 Outputs: logs\recon-YYYYMMDD-HHmmss\ per-host artifacts + index.html
 Notes:
  - Requires PowerShell 7+ for ForEach-Object -Parallel
  - SYSTEM context on targets via schtasks (no /Z EndBoundary bug)
  - Uses FQDNs to dodge Kerberos “target account name is incorrect”
========================================================================= #>

[CmdletBinding(DefaultParameterSetName='Default')]  # single set = no ambiguity
param(
  [Parameter(Mandatory=$true, ParameterSetName='Default')]
  [string]$HostsPath,

  [Parameter(ParameterSetName='Default')]
  [int]$MaxParallel = 12,

  [Parameter(ParameterSetName='Default')]
  [int]$MaxWaitSeconds = 180,

  [Parameter(ParameterSetName='Default')]
  [int]$PollSeconds = 3
)


# Optional: seed CentralResults/index when nothing returns
[switch]$SeedIfEmpty
)
$ErrorActionPreference = 'Stop'

# --- Resolve paths / prerequisites ----------------------------------------
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

# --- Session folder + logging ---------------------------------------------
$sessionRoot = Join-Path $PSScriptRoot ("logs\recon-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
$ctrlLog = Join-Path $sessionRoot 'Controller.log'

# Streaming log queue → console + Controller.log
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
function Enq([string]$msg,[string]$tag='CTL'){ $queue.Enqueue([pscustomobject]@{Tag=$tag;Msg=$msg}) }

Enq "Recon session: $sessionRoot"
Enq ("Hosts: {0}" -f $Targets.Count)
Enq ("Open: {0}" -f (Join-Path $sessionRoot 'index.html'))

# --- Remote constants ------------------------------------------------------
$remoteRootRel = "C$\ProgramData\SysAdminSuite\Mapping"
$remoteRoot    = "C:\ProgramData\SysAdminSuite\Mapping"
$remoteLogsRel = "C$\ProgramData\SysAdminSuite\Mapping\logs"
$pwshWin       = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$taskName      = 'SysAdminSuite_PrinterMap_Recon'

# --- Helper to infer scope in CSV rows (for HTML + Central CSV) ------------
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
  # --- Fan-out (no common params inside -Parallel) -------------------------
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
    function EnqRun([string]$m){ $q.Enqueue([pscustomobject]@{Tag='RUN';Msg=$m}) }

    $target = $_
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
      EnqRun "[$target] START"

      # Prefer FQDN to keep Kerberos happy
      try { $fqdn = ([System.Net.Dns]::GetHostEntry($target)).HostName } catch { $fqdn = $target }
      $schedTarget = $fqdn
      $shareName   = $fqdn
      $dstShare    = "\\$shareName\$remoteRootRel"
      $remoteLogs  = "\\$shareName\$remoteLogsRel"

      # Reachability
      if (-not (Test-Connection -ComputerName $target -Quiet -Count 1)) {
        EnqRun "[$target] OFFLINE"; return
      }
      EnqRun "[$target] PING OK ($shareName)"

      # Stage worker
      New-Item -ItemType Directory -Path $dstShare -Force -ErrorAction Stop | Out-Null
      Copy-Item -LiteralPath $localWorker -Destination $dstShare -Force -ErrorAction Stop
      EnqRun "[$target] COPY OK → $dstShare"

      # Schedule ONCE (no /Z)
      $remoteWorker = Join-Path $remoteRoot ([IO.Path]::GetFileName($localWorker))
      $psArgs       = "`"$remoteWorker`" -ListOnly -Preflight"
      $tr           = "$pwshWin -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $psArgs"
      $now    = Get-Date
$when   = if ($now.Second -ge 50) { $now.AddMinutes(2) } else { $now.AddMinutes(1) }
      $stTime = $when.ToString('HH:mm')
      $stDate = $when.ToString('MM/dd/yyyy')

      $createOut = (cmd /c "schtasks /Create /S $schedTarget /RU SYSTEM /SC ONCE /SD $stDate /ST $stTime /TN $taskName /TR `"$tr`" /RL HIGHEST /F") 2>&1
      EnqRun "[$target] TASK CREATED ($stDate $stTime)"
      $runOut    = (cmd /c "schtasks /Run /S $schedTarget /TN $taskName") 2>&1

      # Poll for artifacts
      EnqRun "[$target] POLLING …"
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

  # --- Roll-up CentralResults.csv (with Scope) ----------------------------
  $centralCsv = Join-Path $sessionRoot 'CentralResults.csv'
  $union = New-Object System.Collections.Generic.List[Object]
  $centralCsvExists = $false

  Get-ChildItem -Path $sessionRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $r = Get-ChildItem -Path $_.FullName -Filter 'Results.csv' -File -ErrorAction SilentlyContinue
    if ($r) {
      try {
        foreach($row in (Import-Csv -LiteralPath $r.FullName)){
          $row | Add-Member -NotePropertyName Scope -NotePropertyValue (Get-RowScope $row) -Force
          $union.Add($row)
        }
      } catch {
        Enq "CSV parse error [$($_.FullName)] — $($_.Exception.Message)" "CTL"
      }
    }
  }
  if ($union.Count -gt 0) {
    $union | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $centralCsv
    $centralCsvExists = $true
  }

  if (-not $centralCsvExists -and $SeedIfEmpty) {
    $seed = @(
      @{ Timestamp=(Get-Date).ToString('s'); ComputerName='WLS111WCC001'; Type='UNC'; Target='(no data)'; Driver=''; Port=''; Status='Seed'; Scope='UNKNOWN' },
      @{ Timestamp=(Get-Date).ToString('s'); ComputerName='WLS111WCC002'; Type='UNC'; Target='(no data)'; Driver=''; Port=''; Status='Seed'; Scope='UNKNOWN' },
      @{ Timestamp=(Get-Date).ToString('s'); ComputerName='WLS111WCC003'; Type='UNC'; Target='(no data)'; Driver=''; Port=''; Status='Seed'; Scope='UNKNOWN' }
    ) | ForEach-Object { [pscustomobject]$_ }
    $seed | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $centralCsv
    $centralCsvExists = $true
  }

  # --- index.html (controller log + per-host file list + tables) ----------
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

  # Per-host mini tables if Results.csv exists
  Get-ChildItem -Path $sessionRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    $host = $_.Name
    $index += "<div class='host'><h2>$host</h2>"
    $results = Get-ChildItem -Path $_.FullName -Filter 'Results.csv' -File -ErrorAction SilentlyContinue
    if ($results) {
      try {
        $rows = Import-Csv -LiteralPath $results.FullName
        if ($rows) {
          $index += "<table><tr>"
          foreach ($col in $rows[0].PSObject.Properties.Name) { $index += "<th>$col</th>" }
          $index += "<th>Scope</th></tr>"
          foreach ($row in $rows) {
            $scope = Get-RowScope $row
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
    # Also list files
    $index += "<ul>"
    foreach ($f in Get-ChildItem -Path $_.FullName -File -ErrorAction SilentlyContinue | Sort-Object Name) {
      $rel = $f.FullName.Replace($sessionRoot,'').TrimStart('\').Replace('\','/')
      $index += "<li><a href='$rel'>$($f.Name)</a></li>"
    }
    $index += "</ul></div><hr/>"
  }

  $index += "</body></html>"
  Set-Content -LiteralPath (Join-Path $sessionRoot 'index.html') -Value $index -Encoding UTF8

  # final drain
  & $drain $queue $ctrlLog
}
