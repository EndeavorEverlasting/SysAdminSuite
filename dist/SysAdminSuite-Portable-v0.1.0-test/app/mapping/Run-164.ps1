
<#
Run-164.ps1 — Orchestrator for RPM-Recon.ps1 across large host lists
Author: You (generated scaffolding)
Purpose: Drive RPM-Recon.ps1 in safe batches, generate per-batch host files, and
         create a simple session roll-up. No logic changes to RPM-Recon.ps1.
Usage:
  # From repo root or mapping folder (PowerShell 7, elevated)
  .\Run-164.ps1 -HostsPath .\mapping\csv\hosts.txt

Parameters:
  -HostsPath            Path to the master hosts list (txt; one host per line; '#' comments allowed)
  -BatchSize            Hosts per batch (default 24)
  -MaxParallel          Fan-out inside RPM-Recon.ps1 (default 12)
  -MaxWaitSeconds       Poll budget per host (default 45)
  -PollSeconds          Poll cadence (default 3)
  -DelayBetweenBatches  Seconds to rest between batches (default 20)
Outputs:
  - mapping\csv\hosts_batch-###.txt (per batch)
  - mapping\logs\recon-YYYYMMDD-HHmmss\... (from RPM-Recon.ps1)
  - mapping\logs\MasterResults.csv (roll-up of all CentralResults.csv from this orchestrated run)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$HostsPath,

  [int]$BatchSize = 24,
  [int]$MaxParallel = 12,
  [int]$MaxWaitSeconds = 45,
  [int]$PollSeconds = 3,
  [int]$DelayBetweenBatches = 20
)

# --- Prep --------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
if (-not (Test-Path $root)) { $root = (Get-Location).Path }

# Allow running from repo root *or* mapping folder
$mappingDir = if (Test-Path (Join-Path $root 'mapping')) { Join-Path $root 'mapping' } else { $root }

$recon = Join-Path $mappingDir 'RPM-Recon.ps1'
if (-not (Test-Path $recon)) {
  throw "Cannot find RPM-Recon.ps1 at $recon. Run from repo root or mapping folder."
}

$csvDir = Join-Path $mappingDir 'csv'
$null = New-Item -ItemType Directory -Force -Path $csvDir | Out-Null

# Load master host list, strip blanks and comments, normalize case (no DNS change here)
$all = Get-Content -LiteralPath $HostsPath -ErrorAction Stop |
          Where-Object { $_ -and $_ -notmatch '^\s*#' } |
          ForEach-Object { $_.Trim() } |
          Where-Object { $_ } |
          Select-Object -Unique

if ($all.Count -eq 0) { throw "No hosts found in $HostsPath after filtering." }

Write-Host "[ORCH] Total hosts: $($all.Count)  (source: $HostsPath)"

# --- Partition into batches ---------------------------------------------------
$groups = @()
$batch = @()
$counter = 0
$batchIndex = 1

foreach ($h in $all) {
  $batch += $h
  $counter++
  if ($counter -ge $BatchSize) {
    $groups += ,@($batch)
    $batch = @()
    $counter = 0
  }
}
if ($batch.Count -gt 0) { $groups += ,@($batch) }

Write-Host "[ORCH] Batches: $($groups.Count)  (BatchSize=$BatchSize)"

$sessionStamps = @()
$centralCsvs = New-Object System.Collections.Generic.List[Object]

# --- Execute batches ----------------------------------------------------------
$batchNo = 0
foreach ($g in $groups) {
  $batchNo++
  $batchFile = Join-Path $csvDir ("hosts_batch-{0:d3}.txt" -f $batchNo)
  $g | Set-Content -LiteralPath $batchFile -Encoding ASCII
  Write-Host "[ORCH] Batch $batchNo -> $($g.Count) hosts -> $batchFile"

  # Call the recon controller for this batch
  $before = Get-ChildItem -Path (Join-Path $mappingDir 'logs') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

  & $recon -HostsPath $batchFile -MaxParallel $MaxParallel -MaxWaitSeconds $MaxWaitSeconds -PollSeconds $PollSeconds

  # Grab the newest recon session folder (heuristic)
  $after = Get-ChildItem -Path (Join-Path $mappingDir 'logs') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($after -and ($before -eq $null -or $after.FullName -ne $before.FullName)) {
    $sessionStamps += $after.FullName
    $central = Join-Path $after.FullName 'CentralResults.csv'
    if (Test-Path $central) {
      try {
        Import-Csv -LiteralPath $central | ForEach-Object { $centralCsvs.Add($_) }
        Write-Host "[ORCH]  Collected central CSV from $($after.Name)"
      } catch {
        Write-Warning "[ORCH]  Failed to import CentralResults.csv from $($after.Name): $($_.Exception.Message)"
      }
    } else {
      Write-Host "[ORCH]  No CentralResults.csv for $($after.Name) — likely no hosts produced Results.csv in window."
    }
  } else {
    Write-Warning "[ORCH]  Could not determine recon session folder for this batch."
  }

  if ($batchNo -lt $groups.Count -and $DelayBetweenBatches -gt 0) {
    Write-Host "[ORCH] Resting $DelayBetweenBatches s before next batch..."
    Start-Sleep -Seconds $DelayBetweenBatches
  }
}

# --- Write master roll-up -----------------------------------------------------
$logsDir = Join-Path $mappingDir 'logs'
$null = New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$master = Join-Path $logsDir 'MasterResults.csv'
if ($centralCsvs.Count -gt 0) {
  $centralCsvs | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $master
  Write-Host "[ORCH] Wrote MasterResults.csv  (rows=$($centralCsvs.Count))"
} else {
  Write-Host "[ORCH] No rows to write to MasterResults.csv"
}

# --- Print a tiny summary -----------------------------------------------------
Write-Host ""
Write-Host "========= ORCHESTRATION SUMMARY ========="
Write-Host "Batches run    : $($groups.Count)"
Write-Host "Hosts total    : $($all.Count)"
Write-Host "Sessions       : $($sessionStamps.Count)"
Write-Host "Master CSV     : $master"
Write-Host "========================================="
