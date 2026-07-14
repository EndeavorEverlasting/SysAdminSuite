#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$EvidenceRoot = 'C:\Temp\CybernetCOM'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
  throw "No AutoFix evidence root exists at $EvidenceRoot. Run the dry-run launcher first."
}

$run = Get-ChildItem -LiteralPath $EvidenceRoot -Directory |
  Where-Object { $_.Name -like 'autofix_*' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $run) {
  throw "No autofix_* run directory exists under $EvidenceRoot."
}

Write-Output "Inspecting: $($run.FullName)"

$summaryPath = Join-Path -Path $run.FullName -ChildPath 'autofix-summary.json'
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
  throw "This run did not produce autofix-summary.json. Review autofix-transcript.txt for the failure point."
}
if ((Get-Item -LiteralPath $summaryPath).Length -le 0) {
  throw 'autofix-summary.json exists but is empty.'
}

$summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$summary.status)) {
  throw 'AutoFix summary does not contain a status.'
}

Write-Output "Status: $($summary.status)"

if ($summary.status -eq 'already-correct') {
  if ($null -ne $summary.registry_backups) {
    throw 'Already-correct summary unexpectedly contains registry backup data.'
  }
  Write-Output 'ALREADY CORRECT - COM1-COM4 detected; no registry backup or mutation was required.'
  return
}

if ($null -eq $summary.registry_backups) {
  throw 'AutoFix summary does not contain registry_backups.'
}

$requiredBackups = @(
  'COMNameArbiter-before.reg',
  'device-parameters-before-01.reg',
  'device-parameters-before-02.reg',
  'device-parameters-before-03.reg',
  'device-parameters-before-04.reg'
)

$results = foreach ($name in $requiredBackups) {
  $artifactPath = Join-Path -Path $run.FullName -ChildPath $name
  $exists = Test-Path -LiteralPath $artifactPath -PathType Leaf
  [pscustomobject]@{
    File = $name
    Exists = $exists
    Bytes = if ($exists) { (Get-Item -LiteralPath $artifactPath).Length } else { 0 }
  }
}

$results | Format-Table -AutoSize

$invalidArtifacts = @($results | Where-Object { -not $_.Exists -or $_.Bytes -le 0 })
if ($invalidArtifacts.Count -gt 0) {
  throw "AutoFix backup proof is incomplete or empty: $($invalidArtifacts.File -join ', ')"
}

$summary.registry_backups | Format-List
if ($summary.registry_backups.validated -ne $true) {
  throw 'AutoFix summary does not report registry_backups.validated as true.'
}

Write-Output 'REGISTRY BACKUPS VALIDATED'
