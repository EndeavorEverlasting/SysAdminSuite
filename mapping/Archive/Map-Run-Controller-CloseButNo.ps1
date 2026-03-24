<# 
  Map-Run-Controller.ps1  — RPM Controller (per-host mappings)

  What it does:
    - Reads host scope from hosts.txt (or just derive from host-mappings.csv)
    - Reads per-host mappings from host-mappings.csv
    - For each host:
        * builds a tiny per-host CSV with ONLY that host’s rows
        * pushes RPM Worker + that per-host CSV
        * schedules the worker as SYSTEM
        * collects artifacts back to admin box and wipes remote traces
    - If a host has NO mappings, runs ListOnly (recon only).

  Typical runs:
    # Recon (just list current printers on listed hosts)
    .\Map-Run-Controller.ps1 -HostsPath .\mapping\csv\hosts.txt -ListOnly -Preflight

    # Plan (produce per-host worker inputs but don’t execute)
    .\Map-Run-Controller.ps1 -HostMappingsPath .\mapping\csv\host-mappings.csv -PlanOnly

    # Execute — commit mappings per host
    .\Map-Run-Controller.ps1 -HostMappingsPath .\mapping\csv\host-mappings.csv -Preflight -RestartSpoolerIfNeeded

  Notes:
    - If you pass BOTH HostsPath and HostMappingsPath, scope is intersection
      (i.e., only hosts in HostsPath are processed, and each gets its own subset).
    - If you pass ONLY HostMappingsPath, the set of distinct Host values drives the run.
    - If you pass ONLY HostsPath and no HostMappingsPath, you can still do ListOnly scans.

#>
[CmdletBinding()]
param(
  [string]$HostsPath,                           # optional (hosts.txt)
  [string]$HostMappingsPath,                    # optional for ListOnly; required for Plan/Execute

  [string]$LocalRoot = (Join-Path $PSScriptRoot "."),
  [string]$RemoteRootRel = "C$\ProgramData\SysAdminSuite\Mapping",

  [switch]$ListOnly,
  [switch]$PlanOnly,
  [switch]$Preflight,
  [switch]$PruneNotInList,
  [switch]$RestartSpoolerIfNeeded,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# --- Paths & prechecks ---
function Load-Hosts($path) {
  if (-not $path) { return @() }
  if (!(Test-Path -LiteralPath $path)) { throw "Hosts file not found: $path" }
  Get-Content -LiteralPath $path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' }
}

function Ensure-Dir($p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }

# Normalize input CSV & derive per-host rows
function Get-HostRows {
  param(
    # BUG-FIX: Renamed from $Host to $TargetHost to avoid shadowing the automatic $Host variable
    [Parameter(Mandatory=$true)][string]$TargetHost,
    [Parameter(Mandatory=$true)][System.Object[]]$MasterRows
  )

  $rows = $MasterRows | Where-Object { $_.Host -eq $TargetHost }
  $out  = New-Object System.Collections.Generic.List[object]

  foreach ($r in $rows) {
    $rowHost = $r.Host
    $unc  = $r.PrinterUNC
    $ip   = $r.IP
    $pname = $r.PrinterName
    $portname = $r.PortName
    $proto = $r.Protocol
    $port  = $r.Port
    $snmp  = $r.SNMP
    $lprq  = $r.LprQueueName
    $drv   = $r.DriverName

    if ($unc) {
      $obj = [pscustomobject]@{
        PrinterUNC   = $unc
        PrinterName  = $pname
        PortName     = $portname
        Protocol     = $proto
        Port         = $port
        SNMP         = $snmp
        LprQueueName = $lprq
      }
      if ($drv) { $obj | Add-Member -NotePropertyName DriverName -NotePropertyValue $drv }
      $out.Add($obj)
      continue
    }

    if ($ip) {
      $obj = [pscustomobject]@{
        IP           = $ip
        PrinterName  = $pname
        PortName     = $portname
        Protocol     = $proto
        Port         = $port
        SNMP         = $snmp
        LprQueueName = $lprq
      }
      if ($drv) { $obj | Add-Member -NotePropertyName DriverName -NotePropertyValue $drv }
      $out.Add($obj)
      continue
    }

    throw "Row for host '$rowHost' has neither UNC nor IP: $($r | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1)"
  }

  return $out
}

if ($HostMappingsPath) {
  if (!(Test-Path -LiteralPath $HostMappingsPath)) { throw "Host mappings CSV not found: $HostMappingsPath" }
  $master = Import-Csv -LiteralPath $HostMappingsPath
  if (-not $master -or $master.Count -eq 0) { throw "No rows in $HostMappingsPath" }
  # normalize column names (case-insensitive access)
  $cols = $master[0].PSObject.Properties.Name
  if (-not ($cols -contains 'Host')) { throw "Host mappings CSV must include a 'Host' column." }
}

# Determine run host list:
$hostsFromFile = Load-Hosts $HostsPath
$hostsFromMap  = if ($master) { ($master | ForEach-Object { $_.Host }) | Where-Object { $_ } | Sort-Object -Unique } else { @() }

$targets = @()
if ($hostsFromFile.Count -gt 0 -and $hostsFromMap.Count -gt 0) {
  $targets = $hostsFromFile | Where-Object { $hostsFromMap -contains $_ }
} elseif ($hostsFromFile.Count -gt 0) {
  $targets = $hostsFromFile
} elseif ($hostsFromMap.Count -gt 0) {
  $targets = $hostsFromMap
} else {
  throw "No hosts to process. Provide HostsPath and/or HostMappingsPath."
}

# --- Session dir on admin box ---
$sessionRoot = Join-Path $LocalRoot ("logs\controller-run-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null

Write-Host "Controller session: $sessionRoot"
Write-Host "Hosts: $($targets.Count)"
if ($ListOnly) { Write-Host "Mode: ListOnly" }
elseif ($PlanOnly) { Write-Host "Mode: PlanOnly" }
else { Write-Host "Mode: Execute" }

foreach ($c in $targets) {
  try {
    if (-not (Test-Connection -ComputerName $c -Quiet -Count 1)) { Write-Host "Skip $c (offline)"; continue }

    $dst        = "\\$c\$RemoteRootRel"
    $remoteLogs = "\\$c\C$\ProgramData\SysAdminSuite\Mapping\logs"

    if ($WhatIf) {
      Write-Host "[WhatIf] Would create $dst, copy worker$(if(-not $ListOnly) {' + per-host csv'} else {''}), schedule/run, collect from $remoteLogs, wipe."
      continue
    }

    # BUG-FIX: $PlanOnly was declared but never used; skip remote execution when set
    if ($PlanOnly) {
      $hostRows = if ($master) { Get-HostRows -TargetHost $c -MasterRows $master } else { @() }
      Write-Host "[PlanOnly] $c — would push worker, schedule task, map $($hostRows.Count) printer(s)."
      continue
    }

    # Ensure remote roots
    cmd /c "mkdir \\$c\C$\ProgramData\SysAdminSuite\Mapping" | Out-Null
    cmd /c "mkdir \\$c\C$\ProgramData\SysAdminSuite\Mapping\logs" | Out-Null
    cmd /c "mkdir \\$c\C$\ProgramData\SysAdminSuite\Mapping\worker" | Out-Null

    # Push worker + per-host CSV (or just worker for list-only)
    $workerSrc = Join-Path $PSScriptRoot "Map-Remote-MachineWide-Printers.ps1"
    if (!(Test-Path -LiteralPath $workerSrc)) { throw "Worker not found: $workerSrc" }
    Copy-Item -LiteralPath $workerSrc -Destination "\\$c\C$\ProgramData\SysAdminSuite\Mapping" -Force

    $hostRows = if ($master) { Get-HostRows -TargetHost $c -MasterRows $master } else { @() }
    if (-not $ListOnly -and $hostRows.Count -gt 0) {
      $tmpCsv = Join-Path $sessionRoot "$c.csv"
      $hostRows | Export-Csv -LiteralPath $tmpCsv -NoTypeInformation -Encoding UTF8
      Copy-Item -LiteralPath $tmpCsv -Destination "\\$c\C$\ProgramData\SysAdminSuite\Mapping\worker\$c.csv" -Force
    }

    # Build the remote command for the worker
    $parts = @(
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "Import-Module PrintManagement -ErrorAction SilentlyContinue",
      "cd C:\ProgramData\SysAdminSuite\Mapping"
    )
    
    if ($ListOnly) {
      $parts += "powershell -NoProfile -ExecutionPolicy Bypass -File .\Map-Remote-MachineWide-Printers.ps1 -ListOnly" +
                ($(if ($Preflight) {" -Preflight"} else {""})) +
                ($(if ($RestartSpoolerIfNeeded) {" -RestartSpoolerIfNeeded"} else {""}))
    } else {
      $parts += "powershell -NoProfile -ExecutionPolicy Bypass -File .\Map-Remote-MachineWide-Printers.ps1 -CsvPath .\worker\$c.csv" +
                ($(if ($Preflight) {" -Preflight"} else {""})) +
                ($(if ($PruneNotInList) {" -PruneNotInList"} else {""})) +
                ($(if ($RestartSpoolerIfNeeded) {" -RestartSpoolerIfNeeded"} else {""}))
    }
    
    $psCmd = $parts -join "; "
    

    # --- Robust schedule+run as SYSTEM (ONCE trigger with explicit start date) ---
    # BUG-FIX: Validate $c against a strict hostname pattern to prevent command injection
    if ($c -notmatch '^[A-Za-z0-9\-\.]+$') {
      Write-Error "[$c] Invalid hostname — skipping to prevent command injection."
      continue
    }

    $when   = (Get-Date).AddMinutes(1)
    $stTime = $when.ToString('HH:mm')          # 24h time
    # BUG-FIX: Use culture-aware short date format so schtasks receives the correct format on non-US locales
    $stDate = $when.ToShortDateString()
    $taskName = 'SysAdminSuite_PrinterMap'

    # Use full path to Windows PowerShell for broad compatibility on endpoints
    $pwsh = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

    # Create the task (drop /Z to avoid EndBoundary XML requirement)
    $create = cmd /c "schtasks /Create /S $c /RU SYSTEM /SC ONCE /SD $stDate /ST $stTime /TN $taskName /TR `"$pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command $psCmd`" /RL HIGHEST /F"
    Write-Host "[$c] schtasks /Create → $create"
    if ($LASTEXITCODE -ne 0) {
      Write-Error "[$c] schtasks /Create failed (exit $LASTEXITCODE). Skipping."
      continue
    }

    # Start it
    $run = cmd /c "schtasks /Run /S $c /TN $taskName"
    Write-Host "[$c] schtasks /Run → $run"
    if ($LASTEXITCODE -ne 0) {
      Write-Error "[$c] schtasks /Run failed (exit $LASTEXITCODE)."
    }

    # Poll for artifacts (move on as soon as we see output; max 45s)
    # BUG-FIX: Removed unused $found variable
    $maxWait = 45; $waited = 0
    while ($waited -lt $maxWait) {
      if (Test-Path $remoteLogs) {
        $latest = Get-ChildItem -Path $remoteLogs -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) { break }
      }
      Start-Sleep -Seconds 3; $waited += 3
    }

    # collect newest artifacts
    if (Test-Path $remoteLogs) {
      $latest = Get-ChildItem -Path $remoteLogs -Directory | Sort-Object Name -Descending |
                Select-Object -First 1
      if ($latest) {
        $hostOut = Join-Path $sessionRoot $c
        New-Item -ItemType Directory -Path $hostOut -Force | Out-Null
        # BUG-FIX: Changed '*.*' to '*' so files without extensions are also copied
        Copy-Item -Path (Join-Path $latest.FullName '*') -Destination $hostOut -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $latest.FullName -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $latest.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "Collected → $hostOut (wiped remote)."
      } else {
        Write-Host "No artifacts yet on $c."
      }
    } else {
      Write-Host "Remote logs path missing on $c."
    }
    # Best-effort cleanup of the scheduled task
    cmd /c "schtasks /Delete /S $c /TN $taskName /F" | Out-Null

  } catch {
    Write-Host "Error ${c}: $($_.Exception.Message)"
  }
}

# roll-up
$centralCsv = Join-Path $sessionRoot 'CentralResults.csv'
$all = Get-ChildItem -Path $sessionRoot -Directory | ForEach-Object {
  Get-ChildItem -Path $_.FullName -Filter *.csv -File -ErrorAction SilentlyContinue
} | ForEach-Object {
  try { Import-Csv -LiteralPath $_.FullName } catch { @() }
}
if ($all -and $all.Count -gt 0) { $all | Export-Csv -LiteralPath $centralCsv -NoTypeInformation -Encoding UTF8 }

# tiny index
$index = @"
<!doctype html><html>
<head>
<meta charset="utf-8">
<title>Controller ${sessionRoot}</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial}
.host{margin:12px 0;padding:8px;border:1px solid #ddd;border-radius:10px}
</style>
</head><body>
<h2>Controller run: $(Split-Path $sessionRoot -Leaf)</h2>
<p>Hosts: $($targets.Count)</p>
<p><a href="./$(Split-Path $centralCsv -Leaf)">Download CentralResults.csv</a></p>
"@
Get-ChildItem -Path $sessionRoot -Directory | Sort-Object Name | ForEach-Object {
  $index += "<div class='host'><h3>$($_.Name)</h3><ul>"
  foreach ($f in Get-ChildItem -Path $_.FullName -File | Sort-Object Name) {
    $rel = $f.FullName.Replace($sessionRoot,'').TrimStart('\').Replace('\','/')
    $index += "<li><a href='$rel'>$($f.Name)</a></li>"
  }
  $index += "</ul></div>"
}
$index += "</body></html>"
Set-Content -LiteralPath (Join-Path $sessionRoot 'index.html') -Value $index -Encoding UTF8

Write-Host "`nController complete. Open: $(Join-Path $sessionRoot 'index.html')"
