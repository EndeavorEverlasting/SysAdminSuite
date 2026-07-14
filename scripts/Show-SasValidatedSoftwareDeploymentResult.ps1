#Requires -Version 5.1
<#
.SYNOPSIS
Validates and presents the final install, package-validation, teardown, and preservation result.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string]$RunRoot,
    [switch]$RequireCompleted,
    [switch]$OpenEvidence,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$approvedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output')).TrimEnd('\')

function Resolve-ApprovedPath {
    param([string]$Path, [string]$Role)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not ($candidate.Equals($approvedRoot, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith($approvedRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Role must remain under $approvedRoot"
    }
    return $candidate
}

if ($OutputRoot -and $RunRoot) { throw 'Use either -OutputRoot or -RunRoot.' }
if (-not $RunRoot) {
    if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'survey/output/software_install' }
    $OutputRoot = Resolve-ApprovedPath -Path $OutputRoot -Role 'Validated deployment output root'
    $candidates = @()
    if (Test-Path -LiteralPath $OutputRoot -PathType Container) {
        $candidates = @(
            Get-ChildItem -LiteralPath $OutputRoot -Directory -Filter 'software-install-*' |
                Sort-Object LastWriteTimeUtc, Name -Descending
        )
    }
    if ($candidates.Count -eq 0) {
        Write-Host 'SYSADMINSUITE VALIDATED SOFTWARE DEPLOYMENT RESULT'
        Write-Host 'Classification: NO_RUN_FOUND'
        exit 23
    }
    $RunRoot = $candidates[0].FullName
}
$RunRoot = Resolve-ApprovedPath -Path $RunRoot -Role 'Validated deployment run root'

$paths = [ordered]@{
    summary = Join-Path $RunRoot 'software_install_summary.json'
    events = Join-Path $RunRoot 'software_install_events.jsonl'
    handoff = Join-Path $RunRoot 'operator_handoff.txt'
    finalization = Join-Path $RunRoot 'software_install_finalization.json'
    deployment = Join-Path $RunRoot 'validated_deployment_result.json'
    review = Join-Path $RunRoot 'validated_deployment_review.json'
}
$errors = @()
foreach ($name in @('summary','events','handoff','finalization','deployment')) {
    $path = [string]$paths[$name]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors += "missing required evidence: $path" }
    elseif ((Get-Item -LiteralPath $path).Length -eq 0) { $errors += "required evidence is empty: $path" }
}

$summary = $null
$finalization = $null
$deployment = $null
$events = @()
if ($errors.Count -eq 0) {
    try { $summary = Get-Content -LiteralPath $paths.summary -Raw | ConvertFrom-Json } catch { $errors += "invalid summary JSON: $($_.Exception.Message)" }
    try { $finalization = Get-Content -LiteralPath $paths.finalization -Raw | ConvertFrom-Json } catch { $errors += "invalid finalization JSON: $($_.Exception.Message)" }
    try { $deployment = Get-Content -LiteralPath $paths.deployment -Raw | ConvertFrom-Json } catch { $errors += "invalid deployment JSON: $($_.Exception.Message)" }
    try {
        $events = @(
            Get-Content -LiteralPath $paths.events |
                Where-Object { $_.Trim() } |
                ForEach-Object { $_ | ConvertFrom-Json }
        )
    }
    catch { $errors += "invalid events JSONL: $($_.Exception.Message)" }
}

$results = @()
if ($finalization) {
    $results = @($finalization.results)
}
$targetCount = $results.Count
$completeCount = @($results | Where-Object { $_.finalization_status -eq 'COMPLETED_VALIDATED_FINALIZED' }).Count
$installFailureCount = @($results | Where-Object { $_.finalization_status -eq 'INSTALL_FAILED_TOOLS_REMOVED' }).Count
$validationFailureCount = @($results | Where-Object { $_.finalization_status -eq 'VALIDATION_FAILED_TOOLS_REMOVED' }).Count
$teardownFailureCount = @($results | Where-Object { $_.finalization_status -eq 'TEARDOWN_FAILED' }).Count
$preservationFailureCount = @($results | Where-Object { $_.finalization_status -eq 'REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN' }).Count
$remnantCount = @($results | Where-Object { $_.repo_artifact_remaining -eq $true }).Count

if ($summary -and $finalization -and $deployment) {
    if ([string]$summary.run_id -ne [string]$finalization.run_id -or [string]$summary.run_id -ne [string]$deployment.run_id) { $errors += 'run IDs disagree across evidence artifacts' }
    if ([string]$summary.package_name -ne [string]$finalization.package_name -or [string]$summary.package_name -ne [string]$deployment.package_name) { $errors += 'package names disagree across evidence artifacts' }
    if ([int]$finalization.target_count -ne $targetCount) { $errors += 'finalization target_count does not match results' }
    if ([int]$finalization.completed_validated_finalized_count -ne $completeCount) { $errors += 'finalization completed count mismatch' }
    if ([int]$finalization.install_failure_count -ne $installFailureCount) { $errors += 'finalization install failure count mismatch' }
    if ([int]$finalization.validation_failure_count -ne $validationFailureCount) { $errors += 'finalization validation failure count mismatch' }
    if ([int]$finalization.teardown_failure_count -ne $teardownFailureCount) { $errors += 'finalization teardown failure count mismatch' }
    if ([int]$finalization.preservation_failure_count -ne $preservationFailureCount) { $errors += 'finalization preservation failure count mismatch' }
    if ([bool]$deployment.deployment_complete -ne [bool]$finalization.deployment_complete) { $errors += 'deployment_complete disagrees across artifacts' }
    if (-not [bool]$deployment.installer_hash_verified) { $errors += 'installer hash was not verified' }
    if ([bool]$finalization.requested_software_uninstall_performed) { $errors += 'finalization claims requested software uninstall was performed' }
    $eventNames = @($events | ForEach-Object { [string]$_.event })
    foreach ($requiredEvent in @('run_started','run_completed','finalization_started','finalization_completed')) {
        if ($requiredEvent -notin $eventNames) { $errors += "event stream is missing '$requiredEvent'" }
    }
}

$classification = 'EVIDENCE_INVALID'; $exitCode = 22; $nextAction = 'Repair the evidence package before making a deployment claim.'
if ($errors.Count -eq 0) {
    if ($teardownFailureCount -gt 0 -or $remnantCount -gt 0) { $classification = 'TEARDOWN_FAILED'; $exitCode = 21; $nextAction = 'Remove only the identified run-scoped SysAdminSuite remnants and re-run finalization.' }
    elseif ($preservationFailureCount -gt 0) { $classification = 'REQUESTED_SOFTWARE_NOT_PRESERVED'; $exitCode = 25; $nextAction = 'Stop. Reconcile the package state before retrying or expanding.' }
    elseif ($validationFailureCount -gt 0) { $classification = 'POST_INSTALL_VALIDATION_FAILED_TOOLS_REMOVED'; $exitCode = 24; $nextAction = 'Tools are removed; investigate package validation without claiming deployment completion.' }
    elseif ($installFailureCount -gt 0) { $classification = 'INSTALL_FAILED_TOOLS_REMOVED'; $exitCode = 20; $nextAction = 'Tools are removed; review installer failure evidence before retrying.' }
    elseif ($targetCount -gt 0 -and $completeCount -eq $targetCount) { $classification = 'DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED'; $exitCode = 0; $nextAction = 'Record package-specific runtime or client acceptance separately when required.' }
    else { $classification = 'PARTIAL_OR_MIXED_RESULT'; $exitCode = 20; $nextAction = 'Review every target row and do not expand.' }
}
if ($RequireCompleted -and $classification -ne 'DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED' -and $exitCode -eq 0) { $exitCode = 20 }

$review = [ordered]@{
    schema_version = 'sas-validated-software-deployment-review/v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    run_root = $RunRoot
    run_id = if ($summary) { [string]$summary.run_id } else { Split-Path -Leaf $RunRoot }
    package_name = if ($summary) { [string]$summary.package_name } else { $null }
    classification = $classification
    exit_code = $exitCode
    deployment_complete = ($classification -eq 'DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED')
    installer_hash_verified = [bool]($deployment -and $deployment.installer_hash_verified)
    requested_software_preserved = ($preservationFailureCount -eq 0 -and $completeCount -eq $targetCount -and $targetCount -gt 0)
    requested_software_uninstall_performed = $false
    proof_level = 'installer_hash_exit_package_validation_run_scoped_teardown_post_teardown_preservation'
    counts = [ordered]@{
        targets = $targetCount
        completed_validated_finalized = $completeCount
        install_failures = $installFailureCount
        validation_failures = $validationFailureCount
        teardown_failures = $teardownFailureCount
        preservation_failures = $preservationFailureCount
        repo_owned_target_remnants = $remnantCount
    }
    evidence = $paths
    evidence_errors = @($errors)
    results = @($results)
    next_action = $nextAction
}
$review | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $paths.review -Encoding UTF8

Write-Host 'SYSADMINSUITE VALIDATED SOFTWARE DEPLOYMENT RESULT'
Write-Host "Classification: $classification"
Write-Host "Run ID: $($review.run_id)"
Write-Host "Package: $($review.package_name)"
Write-Host "Targets: $targetCount | Validated/finalized: $completeCount | Install failures: $installFailureCount"
Write-Host "Validation failures: $validationFailureCount | Teardown failures: $teardownFailureCount | Preservation failures: $preservationFailureCount"
Write-Host "Repo-owned target remnants: $remnantCount"
Write-Host "Deployment complete: $($review.deployment_complete)"
Write-Host "Review artifact: $($paths.review)"
Write-Host "Next action: $nextAction"
if ($results.Count -gt 0) {
    Write-Host ''
    $results | Select-Object computer_name, finalization_status, validation_before_cleanup_succeeded, cleanup_succeeded, requested_software_preserved_after_teardown, repo_artifact_remaining, error | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }
}
if ($errors.Count -gt 0) { Write-Host ''; Write-Host 'Evidence errors:'; $errors | ForEach-Object { Write-Host "- $_" } }
if ($OpenEvidence) { Start-Process explorer.exe -ArgumentList @($RunRoot) | Out-Null }
if ($PassThru) { Write-Output ([pscustomobject]$review) }
exit $exitCode
