#Requires -Version 5.1
<#
.SYNOPSIS
    Reclassifies existing Northwell printer evidence without network activity or printing.

.DESCRIPTION
    Finds the newest raw printer-queue proof artifact with physical_output_observed=true
    (optionally for one explicit shared queue), preserves the original artifact unchanged,
    and emits a derived PASS result plus stable latest aliases.
#>

[CmdletBinding()]
param(
    [string]$Printer,
    [string]$EvidenceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-runs\printer-queue-proof'
}
else {
    Join-Path ([System.IO.Path]::GetTempPath()) 'SysAdminSuite\field-runs\printer-queue-proof'
}

if (-not (Test-Path -LiteralPath $base)) {
    throw "Printer evidence root does not exist: $base"
}

$sourceArtifact = $null
$sourceValue = $null
$candidates = @(
    Get-ChildItem -LiteralPath $base -Filter 'printer-queue-proof-result.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending
)

foreach ($candidate in $candidates) {
    try {
        $value = Get-Content -LiteralPath $candidate.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $physicalProperty = $value.PSObject.Properties['physical_output_observed']
        $printerProperty = $value.PSObject.Properties['printer']
        if ($null -eq $physicalProperty -or $physicalProperty.Value -ne $true) { continue }
        if ($null -eq $printerProperty) { continue }
        if (-not [string]::IsNullOrWhiteSpace($Printer) -and [string]$printerProperty.Value -ne $Printer.Trim()) { continue }
        $sourceArtifact = $candidate
        $sourceValue = $value
        break
    }
    catch {
        continue
    }
}

if (-not $sourceArtifact) {
    if ([string]::IsNullOrWhiteSpace($Printer)) {
        throw 'No raw printer proof artifact with physical_output_observed=true was found.'
    }
    throw "No physical-print proof artifact was found for '$($Printer.Trim())'."
}

$resolvedPrinter = [string]$sourceValue.printer
$runRoot = Join-Path $base ('evidence-repair-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultPath = Join-Path $runRoot 'printer-queue-evidence-repair-result.json'
$summaryPath = Join-Path $runRoot 'printer-queue-evidence-repair-summary.txt'
$latestJson = Join-Path $base 'latest.json'
$latestText = Join-Path $base 'latest.txt'
$latestPointer = Join-Path $base 'LATEST-PATH.txt'

$completedProperty = $sourceValue.PSObject.Properties['completed_utc']
$sourceCompletedUtc = if ($null -ne $completedProperty) { [string]$completedProperty.Value } else { $null }
$statusProperty = $sourceValue.PSObject.Properties['status']
$classProperty = $sourceValue.PSObject.Properties['classification']

$result = [ordered]@{
    schema_version = 'sas-northwell-printer-evidence-reclassification/v1'
    status = 'PASS'
    classification = 'DURABLE_PHYSICAL_PRINT_EVIDENCE_PASS'
    proof_level = 'HISTORICAL_PHYSICAL_OUTPUT_OPERATOR_OBSERVED'
    printer = $resolvedPrinter
    physical_output_observed = $true
    source_result_path = $sourceArtifact.FullName
    source_completed_utc = $sourceCompletedUtc
    source_status = if ($null -ne $statusProperty) { [string]$statusProperty.Value } else { $null }
    source_classification = if ($null -ne $classProperty) { [string]$classProperty.Value } else { $null }
    source_preserved_unchanged = $true
    test_page_requested_by_repair = $false
    network_activity = 'NONE'
    target_contact = 'NONE'
    target_mutation = 'NONE'
    direct_ip_mapping_performed = $false
    evidence_path = $resultPath
    completed_utc = [DateTime]::UtcNow.ToString('o')
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Copy-Item -LiteralPath $resultPath -Destination $latestJson -Force

$summary = @(
    'SysAdminSuite Northwell Printer Evidence Reclassification'
    'Status: PASS'
    'Classification: DURABLE_PHYSICAL_PRINT_EVIDENCE_PASS'
    'Proof level: HISTORICAL_PHYSICAL_OUTPUT_OPERATOR_OBSERVED'
    ('Printer: ' + $resolvedPrinter)
    'New test page requested: NO'
    'Network activity: NONE'
    'Target mutation: NONE'
    ('Original physical-proof artifact: ' + $sourceArtifact.FullName)
    ('Original completed UTC: ' + $sourceCompletedUtc)
    ('Derived result: ' + $resultPath)
    ('Stable latest JSON: ' + $latestJson)
    ('Stable latest summary: ' + $latestText)
)
$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | Set-Content -LiteralPath $latestText -Encoding UTF8
@(
    ('Run directory: ' + $runRoot)
    ('Summary: ' + $summaryPath)
    ('Result: ' + $resultPath)
    ('Original physical-proof artifact: ' + $sourceArtifact.FullName)
) | Set-Content -LiteralPath $latestPointer -Encoding UTF8

Write-Host ''
Write-Host '=== NORTHWELL PRINTER EVIDENCE RECLASSIFICATION ===' -ForegroundColor Cyan
$summary | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host 'Existing physical proof counted. Nothing was printed and no target was contacted.' -ForegroundColor Green
Write-Host ''

[pscustomobject]$result
exit 0
