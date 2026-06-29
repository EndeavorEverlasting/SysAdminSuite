<#
.SYNOPSIS
  Resolve approved serial lists to probe-ready hostnames/IPs, then run SysAdminSuite network preflight.

.DESCRIPTION
  Users often ask to "ping the network for these serials." A serial number is identity evidence,
  not a network address. This wrapper keeps that boundary explicit:

  1. Load a serial-first CSV/TXT from approved local intake roots.
  2. Attach hostnames/IPs from the serial file itself or optional enrichment CSVs.
  3. Stage only serials that resolve to exactly one probe-ready hostname/IP.
  4. Write review-required rows for serial-only, ambiguous, or invalid-host cases.
  5. Invoke survey/sas-network-preflight.ps1 against the staged hostname/IP file unless -PlanOnly is used.

  The wrapper performs no direct ping/TCP/DNS checks itself. Network activity, when requested, is
  delegated to the existing read-only network preflight script.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SerialFile,

  [Parameter(Mandatory = $false)]
  [string[]]$EnrichmentCsv = @(),

  [Parameter(Mandatory = $false)]
  [int[]]$Ports = @(135, 445, 3389, 9100),

  [Parameter(Mandatory = $false)]
  [string]$OutputDirectory,

  [Parameter(Mandatory = $false)]
  [string]$StagingDirectory,

  [Parameter(Mandatory = $false)]
  [switch]$PlanOnly,

  [Parameter(Mandatory = $false)]
  [switch]$AllowNonstandardInput
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoGuess = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path $repoGuess 'scripts/SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $targetIntakeModule -PathType Leaf)) {
  throw "Missing shared target intake module: $targetIntakeModule"
}
Import-Module $targetIntakeModule -Force

function Get-RepoRoot {
  Get-SasRepoRoot -StartPath $PSScriptRoot
}

function ConvertTo-FullPathSafe {
  param([Parameter(Mandatory = $true)][string]$Path)
  ConvertTo-SasFullPath -Path $Path
}

function Get-RowValue {
  param(
    [Parameter(Mandatory = $true)]$Row,
    [Parameter(Mandatory = $true)][string[]]$Names
  )

  foreach ($name in $Names) {
    $prop = $Row.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
    if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
      return ([string]$prop.Value).Trim()
    }
  }
  return ''
}

function Normalize-Serial {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  return (($Value.Trim() -replace '\s+', '')).ToUpperInvariant()
}

function Test-IsIpAddress {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  $ip = $null
  return [System.Net.IPAddress]::TryParse($Value.Trim(), [ref]$ip)
}

function Test-ProbeReadyTargetValue {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  $v = $Value.Trim()
  if (Test-IsIpAddress -Value $v) { return $true }
  if ($v -match '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$') { return $true }
  if ($v -match '^[A-Za-z0-9]+[-_][A-Za-z0-9_-]+$') { return $true }
  if ($v -match '^[A-Za-z]{2,6}[0-9]{2,}[A-Za-z0-9_-]*$') { return $true }
  return $false
}

function Get-SerialFromRow {
  param($Row)
  Get-RowValue -Row $Row -Names @(
    'Serial','ExpectedSerial','Cybernet Serial','Cybernet S/N','Cybernet SN','CybernetSerial',
    'Neuron Serial','Neuron S/N','Neuron SN','NeuronSerial','S/N','SN','AssetSerial','DeviceSerial'
  )
}

function Get-HostFromRow {
  param($Row)
  Get-RowValue -Row $Row -Names @(
    'HostName','Hostname','ComputerName','ExpectedHostname','ResolvedHostName','ResolvedHostname',
    'Cybernet Hostname','Neuron Hostname','DeviceName','Name','DnsName','DNSName','FQDN','IPAddress','IP','IPv4'
  )
}

function Get-IdentifierTypeFromRow {
  param($Row)
  Get-RowValue -Row $Row -Names @('IdentifierType','TargetType','Type','ValueType')
}

function Get-SourceFromRow {
  param($Row,[string]$DefaultSource)
  $source = Get-RowValue -Row $Row -Names @('Source','InputSource','Workbook','Sheet','EvidenceSource')
  if ($source) { return $source }
  return $DefaultSource
}

function New-SerialRequestRow {
  param(
    [string]$Serial,
    [string]$HostName,
    [string]$Source,
    [int]$InputRow
  )

  [pscustomobject]@{
    InputRow = $InputRow
    Serial = $Serial
    NormalizedSerial = Normalize-Serial $Serial
    DirectHostName = $HostName
    Source = $Source
  }
}

function Read-SerialRequestRows {
  param([Parameter(Mandatory = $true)][string]$Path)

  $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  $rows = New-Object System.Collections.Generic.List[object]
  $source = [System.IO.Path]::GetFileName($Path)

  if ($extension -eq '.txt') {
    $i = 0
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
      $i++
      $trimmed = ([string]$line).Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
      if ($trimmed.StartsWith('#')) { continue }
      $rows.Add((New-SerialRequestRow -Serial $trimmed -HostName '' -Source $source -InputRow $i)) | Out-Null
    }
    return $rows
  }

  if ($extension -ne '.csv') { throw "Unsupported serial file extension '$extension'. Use .csv or .txt." }

  $csvRows = @(Import-Csv -LiteralPath $Path)
  for ($i = 0; $i -lt $csvRows.Count; $i++) {
    $row = $csvRows[$i]
    $serial = Get-SerialFromRow -Row $row
    $host = Get-HostFromRow -Row $row
    $identifier = Get-RowValue -Row $row -Names @('Identifier','Target')
    $identifierType = Get-IdentifierTypeFromRow -Row $row

    if (-not $serial -and $identifier -and $identifierType -match '(?i)serial|asset') {
      $serial = $identifier
    }

    if (-not $host -and $identifier -and $identifierType -match '(?i)host|computer|dns|fqdn|ip') {
      $host = $identifier
    }

    if (-not $serial -and -not $host) { continue }
    $rows.Add((New-SerialRequestRow -Serial $serial -HostName $host -Source (Get-SourceFromRow -Row $row -DefaultSource $source) -InputRow ($i + 1))) | Out-Null
  }
  return $rows
}

function Add-SerialHostCandidate {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Map,
    [string]$Serial,
    [string]$HostName,
    [string]$Source
  )

  $normalized = Normalize-Serial $Serial
  if ([string]::IsNullOrWhiteSpace($normalized) -or [string]::IsNullOrWhiteSpace($HostName)) { return }
  if (-not $Map.ContainsKey($normalized)) {
    $Map[$normalized] = New-Object System.Collections.Generic.List[object]
  }
  $Map[$normalized].Add([pscustomobject]@{ HostName = $HostName.Trim(); Source = $Source }) | Out-Null
}

function Read-EnrichmentMap {
  param([string[]]$Paths)

  $map = @{}
  foreach ($path in $Paths) {
    $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($extension -ne '.csv') { throw "Unsupported enrichment file extension '$extension'. Use .csv: $path" }
    $rows = @(Import-Csv -LiteralPath $path)
    $source = [System.IO.Path]::GetFileName($path)
    foreach ($row in $rows) {
      $serial = Get-SerialFromRow -Row $row
      $host = Get-HostFromRow -Row $row
      Add-SerialHostCandidate -Map $map -Serial $serial -HostName $host -Source (Get-SourceFromRow -Row $row -DefaultSource $source)
    }
  }
  return $map
}

function Select-UniqueProbeCandidateRecords {
  param(
    [object[]]$Candidates
  )

  $records = New-Object System.Collections.Generic.List[object]
  $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($candidate in $Candidates) {
    $host = ([string]$candidate.HostName).Trim()
    if ([string]::IsNullOrWhiteSpace($host)) { continue }
    if ($seen.Add($host)) {
      $records.Add([pscustomobject]@{
        HostName = $host
        Source = ([string]$candidate.Source)
      }) | Out-Null
    }
  }
  return @($records)
}

function New-ReviewRow {
  param(
    $Request,
    [string]$Status,
    [string]$Reason,
    [string[]]$CandidateHostnames
  )

  [pscustomobject]@{
    InputRow = $Request.InputRow
    Serial = $Request.Serial
    NormalizedSerial = $Request.NormalizedSerial
    DirectHostName = $Request.DirectHostName
    CandidateHostnames = ($CandidateHostnames -join ';')
    Status = $Status
    Reason = $Reason
    Source = $Request.Source
  }
}

$repoRoot = Get-RepoRoot
$roots = Get-SasTargetIntakeRoots -RepoRoot $repoRoot

Assert-SasApprovedInputPath -Path $SerialFile -RepoRoot $repoRoot -Role 'serial network preflight input' -AllowStaging -AllowGenerated -AllowNonstandard:$AllowNonstandardInput
foreach ($path in $EnrichmentCsv) {
  Assert-SasApprovedInputPath -Path $path -RepoRoot $repoRoot -Role 'serial hostname enrichment input' -AllowStaging -AllowGenerated -AllowNonstandard:$AllowNonstandardInput
}

$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path (Join-Path $roots.OutputRoots[0] 'serial_network_preflight') $runId
}
if ([string]::IsNullOrWhiteSpace($StagingDirectory)) {
  $StagingDirectory = Join-Path (Join-Path $roots.StagingRoot 'serial_network_preflight') $runId
}

$outputDirectoryFull = ConvertTo-FullPathSafe -Path $OutputDirectory
$stagingDirectoryFull = ConvertTo-FullPathSafe -Path $StagingDirectory
Assert-SasApprovedOutputPath -Path $outputDirectoryFull -RepoRoot $repoRoot -Role 'serial network preflight output directory'
if (-not (Test-SasPathUnderRoot -Path $stagingDirectoryFull -Root $roots.StagingRoot)) {
  throw "Staging directory must be under survey/input. Refusing: $stagingDirectoryFull"
}

New-Item -ItemType Directory -Force -Path $outputDirectoryFull | Out-Null
New-Item -ItemType Directory -Force -Path $stagingDirectoryFull | Out-Null

$requests = @(Read-SerialRequestRows -Path $SerialFile)
$enrichmentMap = Read-EnrichmentMap -Paths $EnrichmentCsv

$toProbe = New-Object System.Collections.Generic.List[object]
$review = New-Object System.Collections.Generic.List[object]
$seenTargets = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($request in $requests) {
  if ([string]::IsNullOrWhiteSpace($request.NormalizedSerial)) {
    $review.Add((New-ReviewRow -Request $request -Status 'REVIEW_REQUIRED_MISSING_SERIAL' -Reason 'Row does not contain a serial; cannot maintain serial-first accountability.' -CandidateHostnames @($request.DirectHostName))) | Out-Null
    continue
  }

  $candidates = New-Object System.Collections.Generic.List[object]
  # Duplicate serial direct hostnames are included in the same candidate set so one serial cannot stage multiple machines.
  foreach ($peer in $requests | Where-Object { $_.NormalizedSerial -eq $request.NormalizedSerial -and $_.DirectHostName }) {
    $candidates.Add([pscustomobject]@{ HostName = $peer.DirectHostName; Source = $peer.Source }) | Out-Null
  }
  if ($enrichmentMap.ContainsKey($request.NormalizedSerial)) {
    foreach ($candidate in $enrichmentMap[$request.NormalizedSerial]) { $candidates.Add($candidate) | Out-Null }
  }

  $candidateRecords = @(Select-UniqueProbeCandidateRecords -Candidates @($candidates))
  $candidateValues = @($candidateRecords | Select-Object -ExpandProperty HostName)
  if ($candidateValues.Count -eq 0) {
    $review.Add((New-ReviewRow -Request $request -Status 'REVIEW_REQUIRED_SERIAL_ONLY' -Reason 'Serial-only rows are review-required; a serial cannot be pinged until resolved to one hostname or IP.' -CandidateHostnames @())) | Out-Null
    continue
  }

  $probeReadyRecords = @($candidateRecords | Where-Object { Test-ProbeReadyTargetValue -Value $_.HostName })
  $probeReady = @($probeReadyRecords | Select-Object -ExpandProperty HostName)
  if ($probeReady.Count -eq 0) {
    $review.Add((New-ReviewRow -Request $request -Status 'REVIEW_REQUIRED_NO_PROBE_READY_HOST' -Reason 'Candidate host values exist but none are valid probe-ready hostnames or IP addresses.' -CandidateHostnames $candidateValues)) | Out-Null
    continue
  }

  if ($probeReady.Count -gt 1) {
    $review.Add((New-ReviewRow -Request $request -Status 'REVIEW_REQUIRED_MULTIPLE_HOSTNAMES' -Reason 'Serial resolved to multiple probe-ready hostnames/IPs; the wrapper will not arbitrarily pick one.' -CandidateHostnames $probeReady)) | Out-Null
    continue
  }

  $selected = $probeReadyRecords[0]
  $target = [string]$selected.HostName
  if ($seenTargets.Add($target)) {
    $toProbe.Add([pscustomobject]@{
      HostName = $target
      Serial = $request.NormalizedSerial
      IdentifierType = if (Test-IsIpAddress -Value $target) { 'IPAddress' } else { 'HostName' }
      Source = [string]$selected.Source
      RequestSource = $request.Source
    }) | Out-Null
  }
}

$toProbePath = Join-Path $stagingDirectoryFull 'to_probe_targets.csv'
$reviewPath = Join-Path $outputDirectoryFull 'review_required.csv'
$summaryPath = Join-Path $outputDirectoryFull 'serial_network_preflight_summary.json'
$networkOutputDirectory = Join-Path $outputDirectoryFull 'network_preflight'

$toProbe | Export-Csv -LiteralPath $toProbePath -NoTypeInformation -Encoding UTF8
$review | Export-Csv -LiteralPath $reviewPath -NoTypeInformation -Encoding UTF8

$networkActivityPerformed = $false
Write-Host 'SERIAL NETWORK PREFLIGHT PLAN:'
Write-Host ("- Serial input rows: {0}" -f $requests.Count)
Write-Host ("- Probe-ready unique targets: {0}" -f $toProbe.Count)
Write-Host ("- Review-required serial rows: {0}" -f $review.Count)
Write-Host ("- Staged target file: {0}" -f $toProbePath)
Write-Host ("- Review CSV: {0}" -f $reviewPath)

if ($toProbe.Count -eq 0) {
  Write-Host '- Network preflight skipped: no probe-ready hostnames/IPs were staged.'
} elseif ($PlanOnly) {
  Write-Host '- PlanOnly set: network preflight not invoked.'
} else {
  $networkPreflightScript = Join-Path $PSScriptRoot 'sas-network-preflight.ps1'
  if (-not (Test-Path -LiteralPath $networkPreflightScript -PathType Leaf)) {
    throw "Missing network preflight script: $networkPreflightScript"
  }
  New-Item -ItemType Directory -Force -Path $networkOutputDirectory | Out-Null
  $networkActivityPerformed = $true
  & $networkPreflightScript -TargetFile $toProbePath -Ports $Ports -OutputDirectory $networkOutputDirectory
}

[ordered]@{
  run_id = $runId
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  serial_file = (Resolve-Path -LiteralPath $SerialFile).Path
  enrichment_files = @($EnrichmentCsv | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
  input_serial_rows = $requests.Count
  probe_ready_targets = $toProbe.Count
  review_required_rows = $review.Count
  staged_target_file = $toProbePath
  review_required_csv = $reviewPath
  network_preflight_output_directory = $networkOutputDirectory
  ports = $Ports
  plan_only = [bool]$PlanOnly
  network_activity_performed = $networkActivityPerformed
  doctrine = 'serials_resolve_to_exactly_one_hostname_or_ip_before_network_preflight'
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host ("- Summary JSON: {0}" -f $summaryPath)
