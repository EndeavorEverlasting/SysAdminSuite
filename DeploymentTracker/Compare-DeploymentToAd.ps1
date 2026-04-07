#Requires -Version 5.1
<#
.SYNOPSIS
  Reconcile Active Deployment Tracker rows with the ticket workbook and optionally Active Directory (Cybernets only).

.DESCRIPTION
  Reads the Deployments sheet (or CSV), filters Deployed = Yes, optional Device Type filter, applies duplicate rules
  aligned with the workbook, flags peripherals rows outside the LIJ four-site allowlist, joins ticket Hostname Used
  for Cybernet attribution, and optionally runs Get-ADComputer for Cybernet hostnames only. Neuron hostnames are
  not queried in AD.

  Excel input requires the ImportExcel module (Install-Module ImportExcel) unless you pass -DeploymentCsv / -TicketCsv.

.PARAMETER DeploymentWorkbook
  Path to the Active Deployment Tracker .xlsx

.PARAMETER TicketWorkbook
  Path to the Active Ticket Tracker .xlsx

.PARAMETER DeploymentCsv
  Optional CSV export of Deployments (same headers). Used instead of DeploymentWorkbook when set.

.PARAMETER TicketCsv
  Optional CSV export of General sheet. Used instead of TicketWorkbook when set.

.PARAMETER DeploymentsSheet
  Worksheet name (default Deployments)

.PARAMETER TicketSheet
  Worksheet name (default General)

.PARAMETER DeviceType
  If set, only rows whose Device Type equals this string (case-insensitive trim)

.PARAMETER SkipAd
  Do not load ActiveDirectory or call Get-ADComputer

.PARAMETER Server
  Optional domain controller FQDN for Get-ADComputer -Server

.PARAMETER OutputDirectory
  Where to write CSV and HTML (default: DeploymentTracker\Output under repo root)

.PARAMETER PassThru
  Return enriched row objects to the pipeline

.EXAMPLE
  .\Compare-DeploymentToAd.ps1 -DeploymentWorkbook 'C:\data\tracker.xlsx' -TicketWorkbook 'C:\data\tickets.xlsx' -SkipAd

.EXAMPLE
  .\Compare-DeploymentToAd.ps1 -DeploymentCsv .\Tests\Fixtures\DeploymentTracker\deployments.csv -TicketCsv .\Tests\Fixtures\DeploymentTracker\tickets.csv -SkipAd
#>

[CmdletBinding()]
param(
  [string]$DeploymentWorkbook,
  [string]$TicketWorkbook,
  [string]$DeploymentCsv,
  [string]$TicketCsv,
  [string]$DeploymentsSheet = 'Deployments',
  [string]$TicketSheet = 'General',
  [string]$DeviceType,
  [switch]$SkipAd,
  [string]$Server,
  [string]$OutputDirectory,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$core = Join-Path $PSScriptRoot 'DeploymentTracker.Core.psm1'
Import-Module -Name $core -Force

function Import-DeploymentRows {
  param([string]$Path, [string]$Sheet)
  if (-not (Get-Command -Name Import-Excel -ErrorAction SilentlyContinue)) {
    throw "Import-Excel not found. Install-Module ImportExcel -Scope CurrentUser, or use -DeploymentCsv with Export-Csv headers matching the workbook."
  }
  $p = Get-Item -LiteralPath $Path
  return @(Import-Excel -Path $p.FullName -WorksheetName $Sheet -ErrorAction Stop)
}

function Import-TicketRows {
  param([string]$Path, [string]$Sheet)
  if (-not (Get-Command -Name Import-Excel -ErrorAction SilentlyContinue)) {
    throw "Import-Excel not found. Install-Module ImportExcel -Scope CurrentUser, or use -TicketCsv."
  }
  $p = Get-Item -LiteralPath $Path
  return @(Import-Excel -Path $p.FullName -WorksheetName $Sheet -ErrorAction Stop)
}

function Get-AdComputerSummary {
  param(
    [string[]]$Hostnames,
    [string]$ServerName
  )
  $map = @{}
  foreach ($h in $Hostnames | Sort-Object -Unique) {
    if (-not $h) { continue }
    try {
      $p = @{ Identity = $h; Properties = @('DNSHostName', 'Enabled', 'DistinguishedName') }
      if ($ServerName) { $p.Server = $ServerName }
      $c = Get-ADComputer @p -ErrorAction Stop
      $ou = ($c.DistinguishedName -split '(?<!\\),', 2)[1]
      $map[$h] = "Enabled=$($c.Enabled); DNS=$($c.DNSHostName); OU=$ou"
    }
    catch {
      $map[$h] = 'NOT_FOUND'
    }
  }
  return $map
}

# --- Load deployment rows ---
$dep = $null
if ($DeploymentCsv) {
  $dep = @(Import-Csv -LiteralPath $DeploymentCsv)
}
elseif ($DeploymentWorkbook) {
  $dep = Import-DeploymentRows -Path $DeploymentWorkbook -Sheet $DeploymentsSheet
}
else {
  throw 'Provide -DeploymentWorkbook or -DeploymentCsv.'
}

# --- Load ticket rows ---
$ticketRows = @()
if ($TicketCsv) {
  $ticketRows = @(Import-Csv -LiteralPath $TicketCsv)
}
elseif ($TicketWorkbook) {
  $ticketRows = Import-TicketRows -Path $TicketWorkbook -Sheet $TicketSheet
}
else {
  Write-Warning 'No -TicketWorkbook or -TicketCsv: Cybernet_InTicketHostnameUsed will be false for all rows.'
}

$ticketSet = Get-TicketHostnameSet -TicketRows $ticketRows

# --- Filter ---
$filtered = [System.Collections.Generic.List[object]]::new()
foreach ($r in $dep) {
  if (-not (Test-IsDeployedYes -Row $r)) { continue }
  if ($DeviceType) {
    $dt = ('' + $r.'Device Type').Trim()
    if ($dt.ToUpperInvariant() -ne $DeviceType.Trim().ToUpperInvariant()) { continue }
  }
  $filtered.Add($r)
}

# Work on a copy for enrichment (preserve list reference for Add-Member)
$work = [System.Collections.Generic.List[object]]::new()
foreach ($x in $filtered) { $work.Add($x) }

Set-DeploymentDupMetadata -Rows $work

# --- AD: Cybernet hostnames only ---
$adMap = @{}
if (-not $SkipAd) {
  try { Import-Module ActiveDirectory -ErrorAction Stop }
  catch { throw "ActiveDirectory module required when -SkipAd is not set. Install RSAT or use -SkipAd. $_" }

  $cyberNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($t in $ticketSet) { [void]$cyberNames.Add($t) }
  foreach ($r in $work) {
    $ch = ConvertTo-HostnameCompareKey -Hostname ($r.'Cybernet Hostname')
    if ($ch) { [void]$cyberNames.Add($ch) }
  }
  $adMap = Get-AdComputerSummary -Hostnames @($cyberNames) -ServerName $Server
}

Set-CybernetReconcileMetadata -Rows $work -TicketHostSet $ticketSet -AdLookup $adMap

# --- Output ---
$outRoot = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $repoRoot 'DeploymentTracker\Output' }
if (-not (Test-Path -LiteralPath $outRoot)) {
  New-Item -ItemType Directory -Path $outRoot -Force | Out-Null
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath = Join-Path $outRoot "DeploymentAdReconcile-$stamp.csv"
$work | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath

$htmlHelper = Join-Path $repoRoot 'tools\ConvertTo-SuiteHtml.ps1'
$htmlPath = $null
$htmlPath = Join-Path $outRoot "DeploymentAdReconcile-$stamp.html"
if (Test-Path -LiteralPath $htmlHelper) {
  . $htmlHelper
  $deployedCount = $work.Count
  $dupYes = @($work | Where-Object { $_.DupDeployedCalculated -eq 'Yes' }).Count
  $periphBad = @($work | Where-Object { $_.'Device Type' -match '(?i)^peripherals$' -and $_.PeripheralsAllowedSite -eq $false }).Count
  $cyOnNet = @($work | Where-Object { $_.Cybernet_OnNetwork -eq $true }).Count
  $frag1 = $work | Select-Object -First 500 'Device Type', Deployed, 'Cybernet Hostname', 'Neuron Hostname', DupDeployedCalculated, DuplicateProblematicColumns, IsNeuronOnly, PeripheralsAllowedSite, Cybernet_Ours, Cybernet_InAd, Cybernet_OnNetwork | ConvertTo-Html -Fragment
  $dtPart = if ($DeviceType) { ", DeviceType=$DeviceType" } else { '' }
  $summary = @(
    "Rows (Deployed=Yes$dtPart): $deployedCount"
    "DupDeployedCalculated=Yes: $dupYes"
    "Peripherals not at allowlisted site: $periphBad"
    "Cybernet_OnNetwork (approx from rows): $cyOnNet"
  ) -join ' | '
  $body = @(
    "<h2>Summary</h2><pre>$([System.Net.WebUtility]::HtmlEncode($summary))</pre>"
    '<h2>Sample rows (first 500)</h2>'
    $frag1
    "<p>Full data: <code>$([System.Net.WebUtility]::HtmlEncode($csvPath))</code></p>"
  )
  ConvertTo-SuiteHtml -Title 'Deployment vs AD reconcile' -Subtitle $summary -BodyFragment $body -OutputPath $htmlPath
}
else {
  Write-Warning "ConvertTo-SuiteHtml.ps1 not found; skipped HTML. CSV: $csvPath"
}

Write-Host "Wrote $csvPath"
if ($htmlPath -and (Test-Path -LiteralPath $htmlPath)) { Write-Host "Wrote $htmlPath" }

if ($PassThru) {
  return $work
}
