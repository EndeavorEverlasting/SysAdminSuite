#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EvidencePath,

    [ValidateRange(1, 2147483647)]
    [int]$SourcePr = 222,

    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$ValidationDate = (Get-Date).ToString('yyyy-MM-dd'),

    [ValidateSet('production_corporate_network', 'production_isolated', 'authorized_pilot')]
    [string]$EnvironmentClass = 'production_corporate_network',

    [switch]$OperatorConfirmed,
    [switch]$ContractFixture,
    [string]$OutputRoot,
    [string]$RunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runContextModule = Join-Path $PSScriptRoot 'SasRunContext.psm1'
$intakeScript = Join-Path $repoRoot 'tools/production-install-proof/ingest_production_install_proof.py'

Import-Module $runContextModule -Force

if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) {
    throw "Evidence file not found: $EvidencePath"
}
if (-not (Test-Path -LiteralPath $intakeScript -PathType Leaf)) {
    throw "Production proof intake script not found: $intakeScript"
}

$resolvedEvidence = (Resolve-Path -LiteralPath $EvidencePath).Path
$context = New-SasRunContext `
    -WorkflowId 'production-install-proof-ingest' `
    -RunId $RunId `
    -RepoRoot $repoRoot `
    -OutputRoot $OutputRoot `
    -RequestSummary 'Validate operator-local production software installation evidence and emit a sanitized proof receipt.' `
    -SourceArtifact $resolvedEvidence `
    -CreatedBy 'Import-SasProductionInstallProof'

$arguments = @(
    $intakeScript,
    '--evidence', $resolvedEvidence,
    '--output-dir', $context.directories.artifacts,
    '--source-pr', [string]$SourcePr,
    '--validation-date', $ValidationDate,
    '--environment-class', $EnvironmentClass
)
if ($OperatorConfirmed) { $arguments += '--operator-confirmed' }
if ($ContractFixture) { $arguments += '--contract-fixture' }

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
    if (-not $python) { throw 'Python 3 is required for production proof intake.' }
    $arguments = @('-3') + $arguments
}

$output = & $python.Source @arguments 2>&1
$exitCode = $LASTEXITCODE
$rawOutput = ($output | Out-String).Trim()
if ($exitCode -ne 0) {
    $handoff = @(
        'PRODUCTION SOFTWARE INSTALL PROOF: BLOCKED',
        "Evidence remains operator-local: $resolvedEvidence",
        "Intake exit code: $exitCode",
        $rawOutput
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $context.operator_handoff_path -Value $handoff -Encoding UTF8
    throw "Production proof intake failed with exit code $exitCode. $rawOutput"
}

try {
    $result = $rawOutput | ConvertFrom-Json
} catch {
    throw "Production proof intake returned malformed JSON: $rawOutput"
}

$receiptPath = [string]$result.receipt
$summaryPath = [string]$result.summary
if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "Receipt missing: $receiptPath" }
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Receipt summary missing: $summaryPath" }

Register-SasArtifact `
    -RegistryPath $context.artifact_registry_path `
    -Role 'production-install-source-evidence' `
    -Path $resolvedEvidence `
    -Tracked:$false `
    -LiveData:$true `
    -Generated:$false `
    -Description 'Operator-local source evidence; hashed in place and never copied.' `
    -SourceArtifact $resolvedEvidence `
    -CreatedBy 'Import-SasProductionInstallProof' | Out-Null

Register-SasArtifact `
    -RegistryPath $context.artifact_registry_path `
    -Role 'production-install-proof-receipt' `
    -Path $receiptPath `
    -Tracked:$false `
    -LiveData:$false `
    -Generated:$true `
    -Description 'Sanitized schema-backed receipt derived from the operator-local live evidence.' `
    -SourceArtifact $resolvedEvidence `
    -CreatedBy 'Import-SasProductionInstallProof' | Out-Null

Register-SasArtifact `
    -RegistryPath $context.artifact_registry_path `
    -Role 'production-install-proof-english' `
    -Path $summaryPath `
    -Tracked:$false `
    -LiveData:$false `
    -Generated:$true `
    -Description 'Public-safe English summary of the production installation proof receipt.' `
    -SourceArtifact $resolvedEvidence `
    -CreatedBy 'Import-SasProductionInstallProof' | Out-Null

$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$registry = Get-Content -LiteralPath $context.artifact_registry_path -Raw | ConvertFrom-Json
$summary = [ordered]@{
    schema_version = 'sas-run-summary/v1'
    workflow_id = 'production-install-proof-ingest'
    run_id = $context.run_id
    network_activity = 'No network activity performed during evidence ingestion.'
    artifact_count = @($registry.artifacts).Count
    review_required = ($receipt.outcome -ne 'validated')
    outcome = $receipt.outcome
    proof_level = $receipt.proof.proof_level
    source_pr = $receipt.source.source_pr
    source_evidence_sha256 = $receipt.source.source_evidence_sha256
    production_install_accepted = $receipt.proof.production_install_accepted
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $context.summary_path -Encoding UTF8

$handoff = @(
    "Production installation proof intake: $($receipt.outcome.ToUpperInvariant())",
    "Proof level: $($receipt.proof.proof_level)",
    "Source PR: #$($receipt.source.source_pr)",
    "Evidence SHA-256: $($receipt.source.source_evidence_sha256)",
    'Source evidence remained operator-local and was not copied.',
    "Receipt: $receiptPath",
    "Summary: $summaryPath"
) -join [Environment]::NewLine
Set-Content -LiteralPath $context.operator_handoff_path -Value $handoff -Encoding UTF8

[pscustomobject]@{
    workflow_id = 'production-install-proof-ingest'
    run_id = $context.run_id
    run_root = $context.run_root
    outcome = $receipt.outcome
    proof_level = $receipt.proof.proof_level
    receipt = $receiptPath
    summary = $summaryPath
    artifact_registry = $context.artifact_registry_path
    operator_handoff = $context.operator_handoff_path
}
