#Requires -Version 5.1
<#$
.SYNOPSIS
  Compares a Neuron software package snapshot against an offline software reference.

.DESCRIPTION
  Field-safe checker for Capsule Neuron software reference validation.

  The tool supports two practical modes:
    1) Baseline/report mode: emit the expected package set from a local JSON reference.
    2) Comparison mode: import observed packages from CSV or JSON and compare them to the reference.

  This intentionally avoids requiring direct login to the command console for basic survey work. If command-console scraping is later approved, keep that as a separate adapter that produces the same observed package schema.

.PARAMETER ReferenceId
  Software reference id to compare against. Defaults to 11.8.0.328.

.PARAMETER ReferencePath
  Explicit path to a reference JSON file.

.PARAMETER ObservedPath
  Optional CSV or JSON file containing observed software packages.

.PARAMETER OutputDirectory
  Folder for generated CSV, JSON, and HTML reports.

.PARAMETER NeuronHost
  Optional name/MAC/hostname label to stamp onto reports.

.PARAMETER NoHtml
  Suppress HTML output.

.EXAMPLE
  powershell.exe -File .\GetInfo\Get-NeuronSoftwareReference.ps1

.EXAMPLE
  powershell.exe -File .\GetInfo\Get-NeuronSoftwareReference.ps1 -ObservedPath .\observed.csv -NeuronHost A0F5097FE1C4

.OBSERVED CSV SCHEMA
  Category,Name,Version
  firmware,Application binaries packages,11.8.0.328
  ddi,AspectA,5.1.3.10
#>
[CmdletBinding()]
param(
  [string]$ReferenceId = '11.8.0.328',
  [string]$ReferencePath = '',
  [string]$ObservedPath = '',
  [string]$OutputDirectory = (Join-Path $PSScriptRoot 'Output/NeuronSoftwareReference'),
  [string]$NeuronHost = '',
  [switch]$NoHtml
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Normalize-PackageName {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  return (($Value.Trim() -replace '\s+', '')).ToUpperInvariant()
}

function Normalize-Version {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  return ($Value.Trim() -replace '\s+', '')
}

function New-PackageRow {
  param(
    [string]$Category,
    [string]$Name,
    [string]$Version,
    [string]$Source
  )
  [pscustomobject]@{
    Category = if ($Category) { $Category.ToLowerInvariant() } else { '' }
    Name = $Name
    Version = $Version
    NormalizedName = Normalize-PackageName $Name
    NormalizedVersion = Normalize-Version $Version
    Source = $Source
  }
}

function Resolve-ReferencePath {
  param([string]$ExplicitPath, [string]$Id)
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    if (-not (Test-Path -LiteralPath $ExplicitPath)) { throw "ReferencePath not found: $ExplicitPath" }
    return $ExplicitPath
  }

  $candidate = Join-Path $PSScriptRoot ("Config\NeuronSoftwareReferences\{0}.json" -f $Id)
  if (-not (Test-Path -LiteralPath $candidate)) { throw "Reference baseline not found: $candidate" }
  return $candidate
}

function Import-ReferencePackages {
  param([string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  $rows = @()
  foreach ($pkg in @($raw.firmware)) {
    $rows += New-PackageRow -Category 'firmware' -Name ([string]$pkg.name) -Version ([string]$pkg.version) -Source 'Reference'
  }
  foreach ($pkg in @($raw.ddi)) {
    $rows += New-PackageRow -Category 'ddi' -Name ([string]$pkg.name) -Version ([string]$pkg.version) -Source 'Reference'
  }
  return [pscustomobject]@{
    Metadata = $raw
    Packages = @($rows)
  }
}

function Import-ObservedPackages {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return @() }
  if (-not (Test-Path -LiteralPath $Path)) { throw "ObservedPath not found: $Path" }

  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  $rows = @()

  if ($ext -eq '.json') {
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($raw.firmware -or $raw.ddi) {
      foreach ($pkg in @($raw.firmware)) {
        $rows += New-PackageRow -Category 'firmware' -Name ([string]$pkg.name) -Version ([string]$pkg.version) -Source 'Observed'
      }
      foreach ($pkg in @($raw.ddi)) {
        $rows += New-PackageRow -Category 'ddi' -Name ([string]$pkg.name) -Version ([string]$pkg.version) -Source 'Observed'
      }
      return @($rows)
    }

    foreach ($pkg in @($raw)) {
      $rows += New-PackageRow -Category ([string]$pkg.Category) -Name ([string]$pkg.Name) -Version ([string]$pkg.Version) -Source 'Observed'
    }
    return @($rows)
  }

  foreach ($pkg in @(Import-Csv -LiteralPath $Path)) {
    $category = if ($pkg.PSObject.Properties['Category']) { [string]$pkg.Category } else { '' }
    $name = if ($pkg.PSObject.Properties['Name']) { [string]$pkg.Name } elseif ($pkg.PSObject.Properties['Package']) { [string]$pkg.Package } else { '' }
    $version = if ($pkg.PSObject.Properties['Version']) { [string]$pkg.Version } else { '' }
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $rows += New-PackageRow -Category $category -Name $name -Version $version -Source 'Observed'
  }
  return @($rows)
}

function Compare-NeuronPackages {
  param([object[]]$ReferencePackages, [object[]]$ObservedPackages)

  $observedByKey = @{}
  foreach ($obs in $ObservedPackages) {
    $key = '{0}|{1}' -f $obs.Category, $obs.NormalizedName
    if (-not $observedByKey.ContainsKey($key)) { $observedByKey[$key] = @() }
    $observedByKey[$key] += $obs
  }

  $referenceKeys = @{}
  $results = @()

  foreach ($ref in $ReferencePackages) {
    $key = '{0}|{1}' -f $ref.Category, $ref.NormalizedName
    $referenceKeys[$key] = $true
    $matches = if ($observedByKey.ContainsKey($key)) { @($observedByKey[$key]) } else { @() }

    if ($matches.Count -eq 0) {
      $results += [pscustomobject]@{
        Category = $ref.Category
        Package = $ref.Name
        ExpectedVersion = $ref.Version
        ObservedVersion = ''
        Status = 'Missing'
        Detail = 'Package expected by reference was not found in observed snapshot.'
      }
      continue
    }

    $versionMatch = $false
    $observedVersions = @()
    foreach ($m in $matches) {
      $observedVersions += $m.Version
      if ($m.NormalizedVersion -eq $ref.NormalizedVersion) { $versionMatch = $true }
    }

    $results += [pscustomobject]@{
      Category = $ref.Category
      Package = $ref.Name
      ExpectedVersion = $ref.Version
      ObservedVersion = (($observedVersions | Sort-Object -Unique) -join ';')
      Status = if ($versionMatch) { 'OK' } else { 'VersionMismatch' }
      Detail = if ($versionMatch) { 'Observed package matches reference.' } else { 'Observed package exists but version differs from reference.' }
    }
  }

  foreach ($obs in $ObservedPackages) {
    $key = '{0}|{1}' -f $obs.Category, $obs.NormalizedName
    if ($referenceKeys.ContainsKey($key)) { continue }
    $results += [pscustomobject]@{
      Category = $obs.Category
      Package = $obs.Name
      ExpectedVersion = ''
      ObservedVersion = $obs.Version
      Status = 'Extra'
      Detail = 'Observed package is not in the selected reference baseline.'
    }
  }

  return @($results | Sort-Object Category, Package)
}

$referenceFile = Resolve-ReferencePath -ExplicitPath $ReferencePath -Id $ReferenceId
$reference = Import-ReferencePackages -Path $referenceFile
$observed = Import-ObservedPackages -Path $ObservedPath

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
  New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$hostToken = if ($NeuronHost) { ($NeuronHost -replace '[^A-Za-z0-9_.-]', '_') } else { 'Neuron' }
$prefix = '{0}_SoftwareReference_{1}_{2}' -f $hostToken, $ReferenceId, $runStamp
$expectedCsv = Join-Path $OutputDirectory ($prefix + '_expected.csv')
$comparisonCsv = Join-Path $OutputDirectory ($prefix + '_comparison.csv')
$jsonPath = Join-Path $OutputDirectory ($prefix + '_summary.json')
$htmlPath = Join-Path $OutputDirectory ($prefix + '.html')

$reference.Packages |
  Select-Object Category,Name,Version |
  Export-Csv -LiteralPath $expectedCsv -NoTypeInformation

if ($observed.Count -gt 0) {
  $comparison = Compare-NeuronPackages -ReferencePackages $reference.Packages -ObservedPackages $observed
} else {
  $comparison = @($reference.Packages | ForEach-Object {
    [pscustomobject]@{
      Category = $_.Category
      Package = $_.Name
      ExpectedVersion = $_.Version
      ObservedVersion = ''
      Status = 'ReferenceOnly'
      Detail = 'No observed snapshot supplied; use this row as the expected survey baseline.'
    }
  })
}

$comparison | Export-Csv -LiteralPath $comparisonCsv -NoTypeInformation

$summary = [pscustomobject]@{
  Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  NeuronHost = $NeuronHost
  ReferenceId = [string]$reference.Metadata.referenceId
  ReferencePath = $referenceFile
  ObservedPath = $ObservedPath
  ExpectedPackageCount = @($reference.Packages).Count
  ObservedPackageCount = @($observed).Count
  Missing = @($comparison | Where-Object Status -eq 'Missing').Count
  VersionMismatch = @($comparison | Where-Object Status -eq 'VersionMismatch').Count
  Extra = @($comparison | Where-Object Status -eq 'Extra').Count
  OK = @($comparison | Where-Object Status -eq 'OK').Count
  ExpectedCsv = $expectedCsv
  ComparisonCsv = $comparisonCsv
  HtmlPath = if (-not $NoHtml) { $htmlPath } else { '' }
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

if (-not $NoHtml) {
  $suiteHtmlHelper = Join-Path $PSScriptRoot '../tools/ConvertTo-SuiteHtml.ps1'
  if (Test-Path -LiteralPath $suiteHtmlHelper) {
    . $suiteHtmlHelper
    $body = @()
    $body += $summary | ConvertTo-Html -Fragment -PreContent '<h2>Summary</h2>'
    $body += $comparison | ConvertTo-Html -Fragment -PreContent '<h2>Software Reference Comparison</h2>'
    ($body -join "`n") |
      ConvertTo-SuiteHtml -Title 'Neuron Software Reference Check' -Subtitle ("Reference {0} | {1}" -f $ReferenceId, $hostToken) -OutputPath $htmlPath
  }
}

Write-Host ('Neuron software reference check complete. Reference: {0}' -f $reference.Metadata.referenceId) -ForegroundColor Green
Write-Host ('Expected CSV: {0}' -f $expectedCsv) -ForegroundColor Green
Write-Host ('Comparison CSV: {0}' -f $comparisonCsv) -ForegroundColor Green
Write-Host ('Summary JSON: {0}' -f $jsonPath) -ForegroundColor Green
if ((Test-Path -LiteralPath $htmlPath) -and -not $NoHtml) { Write-Host ('HTML: {0}' -f $htmlPath) -ForegroundColor Green }
$comparison
