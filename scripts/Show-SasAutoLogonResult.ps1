#Requires -Version 5.1
<#
.SYNOPSIS
Validate and present a public-safe AutoLogon result summary.

.DESCRIPTION
Reads only operator-local AutoLogon artifacts under survey/output, validates their
closed classifications and continuity, and prints no target, account, package, run,
or evidence paths. The presenter is read-only and performs no network or target work.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string]$RunRoot,
    [switch]$RequireDeploymentSucceeded,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$approvedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey\output')).TrimEnd('\')

function Resolve-SasAutoLogonResultPath {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Role)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }
    if (-not ($candidate.Equals($approvedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith($approvedRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Role must remain under the ignored survey/output root."
    }
    return $candidate
}

function Get-SasAutoLogonProperty {
    param($Value, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Value) { return $Default }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Read-SasAutoLogonJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Role,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][Collections.Generic.List[string]]$Errors
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $Errors.Add("missing required $Role")
        return $null
    }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch {
        $Errors.Add("invalid $Role JSON")
        return $null
    }
}

function Find-SasAutoLogonOptionalArtifact {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Name)
    $matches = @(Get-ChildItem -LiteralPath $Root -Filter $Name -File -Recurse -ErrorAction SilentlyContinue)
    if ($matches.Count -eq 1) { return $matches[0].FullName }
    if ($matches.Count -gt 1) { return '__AMBIGUOUS__' }
    return $null
}

if ($OutputRoot -and $RunRoot) { throw 'Use either -OutputRoot or -RunRoot.' }
if (-not $RunRoot) {
    if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'survey\output\runs\autologon-proof' }
    $OutputRoot = Resolve-SasAutoLogonResultPath -Path $OutputRoot -Role 'AutoLogon output root'
    $candidates = @()
    if (Test-Path -LiteralPath $OutputRoot -PathType Container) {
        $candidates = @(Get-ChildItem -LiteralPath $OutputRoot -Directory -Filter 'autologon-deploy-*' |
            Sort-Object LastWriteTimeUtc, Name -Descending)
    }
    if ($candidates.Count -eq 0) {
        Write-Host 'SYSADMINSUITE AUTOLOGON PUBLIC-SAFE RESULT'
        Write-Host 'Classification: NO_RUN_FOUND'
        exit 23
    }
    $RunRoot = $candidates[0].FullName
}
$RunRoot = Resolve-SasAutoLogonResultPath -Path $RunRoot -Role 'AutoLogon run root'

$errors = New-Object Collections.Generic.List[string]
$summaryPath = Join-Path $RunRoot 'summary.json'
$deploymentPath = Join-Path $RunRoot 'artifacts\autologon_deployment_result.json'
$gatePath = Join-Path $RunRoot 'artifacts\autologon_final_step_gate_result.json'
$statePath = Join-Path $RunRoot 'artifacts\autologon_state_proof_result.json'
$summary = Read-SasAutoLogonJson -Path $summaryPath -Role 'summary' -Errors $errors
$deployment = Read-SasAutoLogonJson -Path $deploymentPath -Role 'deployment result' -Errors $errors
$gate = if (Test-Path -LiteralPath $gatePath -PathType Leaf) {
    Read-SasAutoLogonJson -Path $gatePath -Role 'final-step gate result' -Errors $errors
} else { $null }
$state = if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    Read-SasAutoLogonJson -Path $statePath -Role 'state result' -Errors $errors
} else { $null }

$deploymentClassification = [string](Get-SasAutoLogonProperty -Value $deployment -Name 'classification' -Default 'unavailable')
$stateClassification = [string](Get-SasAutoLogonProperty -Value $state -Name 'classification' -Default 'not_emitted')
$gateClassification = [string](Get-SasAutoLogonProperty -Value $gate -Name 'classification' -Default 'not_emitted')
$deploymentEvidence = Get-SasAutoLogonProperty -Value $deployment -Name 'deployment'
$targetScope = Get-SasAutoLogonProperty -Value $deployment -Name 'target_scope'
$targetCount = [int](Get-SasAutoLogonProperty -Value $targetScope -Name 'target_count' -Default 0)
$identifiersEmitted = [bool](Get-SasAutoLogonProperty -Value $targetScope -Name 'identifiers_emitted' -Default $true)
$cleanupVerified = [bool](Get-SasAutoLogonProperty -Value $deploymentEvidence -Name 'cleanup_verified' -Default $false)
$zeroRemnantsVerified = [bool](Get-SasAutoLogonProperty -Value $deploymentEvidence -Name 'zero_remnants_verified' -Default $false)
$cleanupFailureCount = [int](Get-SasAutoLogonProperty -Value $summary -Name 'cleanup_failure_count' -Default 0)
$remnantCount = [int](Get-SasAutoLogonProperty -Value $summary -Name 'repo_artifact_remaining_count' -Default 0)
$proofLevel = [string](Get-SasAutoLogonProperty -Value $deployment -Name 'proof_level' -Default 'insufficient')
$proofCeiling = [string](Get-SasAutoLogonProperty -Value $deployment -Name 'proof_ceiling' -Default 'Evidence is unavailable or invalid; no deployment or runtime claim is supported.')

if ($deployment -and [string](Get-SasAutoLogonProperty -Value $deployment -Name 'schema_version') -ne 'sas-autologon-deployment-result/v1') {
    $errors.Add('unsupported deployment result schema')
}
if ($deployment -and [string](Get-SasAutoLogonProperty -Value $deployment -Name 'operation_id') -ne 'autologon.admin_deploy') {
    $errors.Add('unexpected deployment operation')
}
if ($identifiersEmitted) { $errors.Add('deployment result is not identifier-free') }
if ($summary -and [string](Get-SasAutoLogonProperty -Value $summary -Name 'deployment_result_classification') -ne $deploymentClassification) {
    $errors.Add('summary and deployment classifications disagree')
}
if ($cleanupFailureCount -lt 0 -or $remnantCount -lt 0) { $errors.Add('negative cleanup or remnant count') }

$receiptPath = Find-SasAutoLogonOptionalArtifact -Root $RunRoot -Name 'autologon_proof_receipt.json'
$sourcePath = Find-SasAutoLogonOptionalArtifact -Root $RunRoot -Name 'autologon_proof_source_evidence.json'
$digestContinuity = 'NOT_AVAILABLE'
$receiptClassification = 'not_emitted'
if ($receiptPath -eq '__AMBIGUOUS__' -or $sourcePath -eq '__AMBIGUOUS__') {
    $digestContinuity = 'INCOMPLETE'
    $errors.Add('ambiguous proof receipt or source evidence')
} elseif (($receiptPath -and -not $sourcePath) -or ($sourcePath -and -not $receiptPath)) {
    $digestContinuity = 'INCOMPLETE'
    $errors.Add('proof receipt continuity pair is incomplete')
} elseif ($receiptPath -and $sourcePath) {
    $receipt = Read-SasAutoLogonJson -Path $receiptPath -Role 'proof receipt' -Errors $errors
    if ($receipt) {
        $receiptClassification = [string](Get-SasAutoLogonProperty -Value $receipt -Name 'classification' -Default 'invalid')
        $expectedDigest = [string](Get-SasAutoLogonProperty -Value $receipt -Name 'source_evidence_sha256' -Default '')
        $expectedSize = [long](Get-SasAutoLogonProperty -Value $receipt -Name 'source_evidence_size_bytes' -Default 0)
        $actualDigest = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $actualSize = (Get-Item -LiteralPath $sourcePath).Length
        if ($expectedDigest -eq $actualDigest -and $expectedSize -eq $actualSize) {
            $digestContinuity = 'VERIFIED'
        } else {
            $digestContinuity = 'FAILED'
            $errors.Add('proof receipt digest continuity failed')
        }
    }
}

$classification = 'EVIDENCE_INVALID'
$exitCode = 22
$runtimePending = $false
$nextAction = 'Preserve the evidence and repair the identified continuity or contract error before retrying.'
if ($errors.Count -eq 0) {
    switch ($deploymentClassification) {
        'deployment_succeeded' {
            if ($cleanupVerified -and $zeroRemnantsVerified -and $cleanupFailureCount -eq 0 -and $remnantCount -eq 0) {
                $classification = 'DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING'
                $exitCode = 0
                $runtimePending = $true
                $nextAction = 'Observe the controlled reboot and automatic sign-in, then run signed-in session and application proof.'
            } else {
                $classification = 'CLEANUP_REVIEW_REQUIRED'
                $exitCode = 21
                $nextAction = 'Preserve evidence and resolve only the identified run-scoped cleanup issue; do not expand or blindly retry.'
            }
        }
        'fixture_contract_pass' {
            $classification = 'FIXTURE_CONTRACT_PASS_ONLY'
            $exitCode = 0
            $nextAction = 'Use a fresh one-target transport preflight and approved change inputs before any live pilot.'
        }
        'deployment_planned' {
            $classification = 'PLAN_ONLY_NO_DEPLOYMENT'
            $exitCode = 0
            $nextAction = 'Review the closed request, fresh preflight, final-step prerequisites, and change approval before the pilot.'
        }
        'deployment_blocked' { $classification = 'DEPLOYMENT_BLOCKED'; $exitCode = 20; $nextAction = 'Resolve the recorded gate or preflight blocker; do not retry unchanged.' }
        'deployment_failed' { $classification = 'DEPLOYMENT_FAILED'; $exitCode = 20; $nextAction = 'Preserve evidence, review the failed stage, and do not expand or blindly retry.' }
        'fixture_contract_failed' { $classification = 'FIXTURE_CONTRACT_FAILED'; $exitCode = 20; $nextAction = 'Repair the fixture contract before any pilot.' }
        default { $classification = 'REVIEW_REQUIRED'; $exitCode = 20; $nextAction = 'Preserve evidence and reconcile the unrecognized terminal state.' }
    }
}
if ($RequireDeploymentSucceeded -and $classification -ne 'DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING') { $exitCode = 20 }

$review = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-public-safe-review/v1'
    classification = $classification
    deployment_classification = $deploymentClassification
    final_gate_classification = $gateClassification
    state_classification = $stateClassification
    target_count = $targetCount
    cleanup_verified = $cleanupVerified
    zero_remnants_verified = $zeroRemnantsVerified
    cleanup_failure_count = $cleanupFailureCount
    repo_owned_remnant_count = $remnantCount
    receipt_classification = $receiptClassification
    digest_continuity = $digestContinuity
    proof_level = $proofLevel
    runtime_proof_pending = $runtimePending
    proof_ceiling = $proofCeiling
    evidence_errors = @($errors.ToArray())
    next_action = $nextAction
}

Write-Host 'SYSADMINSUITE AUTOLOGON PUBLIC-SAFE RESULT'
Write-Host "Classification: $classification"
Write-Host "Deployment: $deploymentClassification | Final gate: $gateClassification | State: $stateClassification"
Write-Host "Targets: $targetCount"
Write-Host "Cleanup verified: $cleanupVerified | Zero remnants verified: $zeroRemnantsVerified"
Write-Host "Cleanup failures: $cleanupFailureCount | Repo-owned remnants: $remnantCount"
Write-Host "Receipt: $receiptClassification | Digest continuity: $digestContinuity"
Write-Host "Proof level: $proofLevel | Runtime proof pending: $runtimePending"
Write-Host "Proof ceiling: $proofCeiling"
Write-Host "Next action: $nextAction"
if ($errors.Count -gt 0) {
    Write-Host 'Evidence errors:'
    foreach ($message in $errors) { Write-Host "- $message" }
}
if ($PassThru) { Write-Output $review }
exit $exitCode
