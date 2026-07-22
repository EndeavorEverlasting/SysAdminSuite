#Requires -Version 5.1
<#
.SYNOPSIS
Ingests an operator-local transport live-cert result and emits a public-safe receipt.

.DESCRIPTION
Reads an operator-local transport live-cert result, hashes the source evidence in
place (never copying it), and produces a sanitized public-safe receipt conforming
to sas-software-deployment-transport-receipt/v1.  The receipt binds source evidence
by SHA-256 without copying private fields such as hostnames, usernames, ticket
bytes, credentials, package paths, machine-local paths, or raw evidence.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourcePath,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [switch]$ContractFixture,
    [switch]$OperatorConfirmed,
    [string]$RunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runContextModule = Join-Path $PSScriptRoot 'SasRunContext.psm1'
$ingestScript = Join-Path $repoRoot 'tools/production-install-proof/ingest_transport_proof.py'

Import-Module $runContextModule -Force

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Source live-cert result not found: $SourcePath"
}
if (-not (Test-Path -LiteralPath $ingestScript -PathType Leaf)) {
    throw "Transport proof ingest script not found: $ingestScript"
}

$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$context = New-SasRunContext `
    -WorkflowId 'software-deployment-transport-proof-ingest' `
    -RunId $RunId `
    -RepoRoot $repoRoot `
    -OutputRoot $OutputRoot `
    -RequestSummary 'Hash operator-local transport live-cert evidence and emit a public-safe receipt.' `
    -SourceArtifact $resolvedSource `
    -CreatedBy 'Invoke-SasTransportProofIngest'

$arguments = @(
    $ingestScript,
    '--source', $resolvedSource,
    '--output-dir', $context.directories.artifacts
)
if ($ContractFixture) { $arguments += '--contract-fixture' }
if ($OperatorConfirmed) { $arguments += '--operator-confirmed' }

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
    if (-not $python) { throw 'Python 3 is required for transport proof ingest.' }
    $arguments = @('-3') + $arguments
}

$output = & $python.Source @arguments 2>&1
$exitCode = $LASTEXITCODE
$rawOutput = ($output | Out-String).Trim()
if ($exitCode -ne 0) {
    $handoff = @(
        'TRANSPORT PROOF INGEST: BLOCKED',
        "Source evidence remains operator-local: $resolvedSource",
        "Ingest exit code: $exitCode",
        $rawOutput
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $context.operator_handoff_path -Value $handoff -Encoding UTF8
    throw "Transport proof ingest failed with exit code $exitCode. $rawOutput"
}

try {
    $result = $rawOutput | ConvertFrom-Json
} catch {
    throw "Transport proof ingest returned malformed JSON: $rawOutput"
}

$receiptPath = [string]$result.receipt
$summaryPath = [string]$result.summary
if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "Receipt missing: $receiptPath" }
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Receipt summary missing: $summaryPath" }

Register-SasArtifact `
    -RegistryPath $context.artifact_registry_path `
    -Role 'transport-live-cert-source' `
    -Path $resolvedSource `
    -Tracked:$false `
    -LiveData:$true `
    -Generated:$false `
    -Description 'Operator-local live-cert source evidence; hashed in place and never copied.' `
    -SourceArtifact $resolvedSource `
    -CreatedBy 'Invoke-SasTransportProofIngest' | Out-Null

Register-SasArtifact `
    -RegistryPath $context.artifact_registry_path `
    -Role 'transport-proof-receipt' `
    -Path $receiptPath `
    -Tracked:$false `
    -LiveData:$false `
    -Generated:$true `
    -Description 'Public-safe receipt derived from the operator-local live-cert evidence.' `
    -SourceArtifact $resolvedSource `
    -CreatedBy 'Invoke-SasTransportProofIngest' | Out-Null

Register-SasArtifact `
    -RegistryPath $context.artifact_registry_path `
    -Role 'transport-proof-english' `
    -Path $summaryPath `
    -Tracked:$false `
    -LiveData:$false `
    -Generated:$true `
    -Description 'Public-safe English summary of the transport proof receipt.' `
    -SourceArtifact $resolvedSource `
    -CreatedBy 'Invoke-SasTransportProofIngest' | Out-Null

$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$registry = Get-Content -LiteralPath $context.artifact_registry_path -Raw | ConvertFrom-Json
$summary = [ordered]@{
    schema_version = 'sas-run-summary/v1'
    workflow_id = 'software-deployment-transport-proof-ingest'
    run_id = $context.run_id
    network_activity = 'No network activity performed during evidence ingestion.'
    artifact_count = @($registry.artifacts).Count
    review_required = ($receipt.outcome -ne 'live_cert_pass')
    outcome = $receipt.outcome
    proof_level = $receipt.proof_level
    source_evidence_sha256 = $receipt.source.source_evidence_sha256
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $context.summary_path -Encoding UTF8

$handoff = @(
    "Transport proof ingest: $($receipt.outcome.ToUpperInvariant())",
    "Proof level: $($receipt.proof_level)",
    "Source evidence SHA-256: $($receipt.source.source_evidence_sha256)",
    'Source evidence remained operator-local and was not copied.',
    "Receipt: $receiptPath",
    "Summary: $summaryPath"
) -join [Environment]::NewLine
Set-Content -LiteralPath $context.operator_handoff_path -Value $handoff -Encoding UTF8

[pscustomobject]@{
    workflow_id = 'software-deployment-transport-proof-ingest'
    run_id = $context.run_id
    run_root = $context.run_root
    outcome = $receipt.outcome
    proof_level = $receipt.proof_level
    receipt = $receiptPath
    summary = $summaryPath
    artifact_registry = $context.artifact_registry_path
    operator_handoff = $context.operator_handoff_path
}
