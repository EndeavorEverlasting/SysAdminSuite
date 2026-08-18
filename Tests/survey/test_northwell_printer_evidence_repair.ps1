#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repairPath = Join-Path $repoRoot 'scripts\Repair-SasNorthwellPrinterQueueEvidence.ps1'
if (-not (Test-Path -LiteralPath $repairPath)) {
    throw "Missing evidence repair engine: $repairPath"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-printer-evidence-repair-' + [Guid]::NewGuid().ToString('N'))
$sourceDir = Join-Path $tempRoot '20260818-180648-758'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null

try {
    $sourcePath = Join-Path $sourceDir 'printer-queue-proof-result.json'
    [ordered]@{
        schema_version = 'sas-northwell-printer-queue-proof/v1'
        status = 'FAIL'
        classification = 'PRINT_RPC_DYNAMIC_PORT_STALLED'
        printer = '\\SYKPNHPHPS01V\LS001-EMS01'
        physical_output_observed = $true
        completed_utc = '2026-08-18T22:09:33.3527227Z'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sourcePath -Encoding UTF8

    & $repairPath -Printer '\\SYKPNHPHPS01V\LS001-EMS01' -EvidenceRoot $tempRoot | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Evidence repair returned exit code $LASTEXITCODE."
    }

    $latestJson = Join-Path $tempRoot 'latest.json'
    $latestText = Join-Path $tempRoot 'latest.txt'
    $pointer = Join-Path $tempRoot 'LATEST-PATH.txt'
    foreach ($path in @($latestJson,$latestText,$pointer)) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing durable repair artifact: $path" }
    }

    $result = Get-Content -LiteralPath $latestJson -Raw | ConvertFrom-Json
    if ($result.status -ne 'PASS') { throw "Expected repaired PASS, got $($result.status)." }
    if ($result.classification -ne 'DURABLE_PHYSICAL_PRINT_EVIDENCE_PASS') {
        throw "Unexpected repair classification: $($result.classification)"
    }
    if ($result.physical_output_observed -ne $true) { throw 'Physical output proof was not preserved.' }
    if ($result.source_preserved_unchanged -ne $true) { throw 'Original artifact preservation was not recorded.' }
    if ($result.test_page_requested_by_repair -ne $false) { throw 'Repair must never request a test page.' }
    if ($result.network_activity -ne 'NONE' -or $result.target_contact -ne 'NONE' -or $result.target_mutation -ne 'NONE') {
        throw 'Evidence repair must be local-only with no target/network activity.'
    }
    if ($result.source_result_path -ne $sourcePath) { throw 'Repair did not point back to the original proof artifact.' }

    $sourceAfter = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    if ($sourceAfter.status -ne 'FAIL' -or $sourceAfter.classification -ne 'PRINT_RPC_DYNAMIC_PORT_STALLED') {
        throw 'Original raw artifact was mutated instead of preserved.'
    }

    $repairText = Get-Content -LiteralPath $repairPath -Raw
    foreach ($forbidden in @('Resolve-DnsName','Get-Printer','Test-NetConnection','PrintTestPage','Add-Printer')) {
        if ($repairText -match [regex]::Escape($forbidden)) {
            throw "Evidence repair contains forbidden live-operation token: $forbidden"
        }
    }

    Write-Host 'PASS: existing physical-print evidence reclassifies to PASS without reprinting.'
    Write-Host 'PASS: original raw evidence remains unchanged.'
    Write-Host 'PASS: stable latest summary/result aliases are created locally.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
