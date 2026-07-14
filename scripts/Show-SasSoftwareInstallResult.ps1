#Requires -Version 5.1
<#
.SYNOPSIS
Finds, validates, and presents a SysAdminSuite software-install result.

.DESCRIPTION
Reads one explicit software-install run or the latest run beneath an approved local output root.
It validates the summary, JSONL event stream, handoff, recomputed counts, cleanup state, and
repo-owned target-remnant state. It writes software_install_review.json and prints a concise
operator classification and per-target table.

This inspector proves installer execution and SysAdminSuite cleanup evidence only. It never
promotes an installer exit code to application-level deployment, launch, service, version, or
business acceptance proof.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string]$RunRoot,

    [Parameter(Mandatory = $false)]
    [switch]$RequireCompleted,

    [Parameter(Mandatory = $false)]
    [switch]$OpenEvidence,

    [Parameter(Mandatory = $false)]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$approvedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output')).TrimEnd('\')

function Resolve-SasApprovedInspectionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Role
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }

    if (-not (
        $candidate.Equals($approvedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith($approvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)
    )) {
        throw "$Role must remain under the approved local evidence root '$approvedRoot'. Received: $candidate"
    }

    return $candidate
}

function Convert-SasJsonLineFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Collections.Generic.List[string]]$Errors
    )

    $records = [Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $records.Add(($line | ConvertFrom-Json -ErrorAction Stop))
        }
        catch {
            $Errors.Add("invalid JSONL at line $lineNumber in '$Path': $($_.Exception.Message)")
        }
    }
    return @($records)
}

if (-not [string]::IsNullOrWhiteSpace($OutputRoot) -and
    -not [string]::IsNullOrWhiteSpace($RunRoot)) {
    throw 'Use either -OutputRoot or -RunRoot, not both.'
}

if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Join-Path $repoRoot 'survey/output/software_install'
    }
    $OutputRoot = Resolve-SasApprovedInspectionPath -Path $OutputRoot -Role 'Software-install output root'

    if (-not [IO.Directory]::Exists($OutputRoot)) {
        Write-Host 'SYSADMINSUITE SOFTWARE INSTALL RESULT'
        Write-Host 'Classification: NO_RUN_FOUND'
        Write-Host "No software-install output directory exists at: $OutputRoot"
        exit 23
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $OutputRoot -Directory -Filter 'software-install-*' |
            Sort-Object LastWriteTimeUtc, Name -Descending
    )
    if ($candidates.Count -eq 0) {
        Write-Host 'SYSADMINSUITE SOFTWARE INSTALL RESULT'
        Write-Host 'Classification: NO_RUN_FOUND'
        Write-Host "No software-install run directories were found under: $OutputRoot"
        exit 23
    }
    $RunRoot = $candidates[0].FullName
}

$RunRoot = Resolve-SasApprovedInspectionPath -Path $RunRoot -Role 'Software-install run root'
if (-not [IO.Directory]::Exists($RunRoot)) {
    Write-Host 'SYSADMINSUITE SOFTWARE INSTALL RESULT'
    Write-Host 'Classification: NO_RUN_FOUND'
    Write-Host "Run directory does not exist: $RunRoot"
    exit 23
}

$summaryPath = Join-Path $RunRoot 'software_install_summary.json'
$eventsPath = Join-Path $RunRoot 'software_install_events.jsonl'
$handoffPath = Join-Path $RunRoot 'operator_handoff.txt'
$reviewPath = Join-Path $RunRoot 'software_install_review.json'
$errors = [Collections.Generic.List[string]]::new()

foreach ($required in @($summaryPath, $eventsPath, $handoffPath)) {
    if (-not [IO.File]::Exists($required)) {
        $errors.Add("missing required evidence: $required")
    }
    elseif ((Get-Item -LiteralPath $required).Length -eq 0) {
        $errors.Add("required evidence is empty: $required")
    }
}

$summary = $null
if ([IO.File]::Exists($summaryPath)) {
    try {
        $summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $errors.Add("software_install_summary.json is invalid: $($_.Exception.Message)")
    }
}

$events = @()
if ([IO.File]::Exists($eventsPath)) {
    $events = @(Convert-SasJsonLineFile -Path $eventsPath -Errors $errors)
}
$eventNames = @($events | ForEach-Object { [string]$_.event })
foreach ($requiredEvent in @('run_started', 'run_completed')) {
    if ($requiredEvent -notin $eventNames) {
        $errors.Add("software_install_events.jsonl is missing event '$requiredEvent'")
    }
}

$results = @()
$targetCount = 0
$completedCount = 0
$plannedCount = 0
$failedCount = 0
$cleanupFailureCount = 0
$remnantCount = 0
$runId = Split-Path -Leaf $RunRoot
$packageName = $null
$installMode = $null

if ($summary) {
    foreach ($requiredProperty in @(
        'schema_version', 'run_id', 'package_name', 'install_mode', 'target_count',
        'completed_count', 'planned_count', 'failed_count', 'cleanup_failure_count',
        'repo_artifact_remaining_count', 'results'
    )) {
        if ($summary.PSObject.Properties.Name -notcontains $requiredProperty) {
            $errors.Add("summary is missing property '$requiredProperty'")
        }
    }

    if ($summary.PSObject.Properties.Name -contains 'schema_version' -and
        [string]$summary.schema_version -ne 'sas-software-install-summary/v1') {
        $errors.Add("unsupported summary schema: $($summary.schema_version)")
    }

    $runId = [string]$summary.run_id
    $packageName = [string]$summary.package_name
    $installMode = [string]$summary.install_mode
    $results = @($summary.results)
    $targetCount = [int]$summary.target_count
    $completedCount = @($results | Where-Object { $_.status -eq 'completed' }).Count
    $plannedCount = @($results | Where-Object { $_.status -eq 'planned_whatif' }).Count
    $failedCount = @($results | Where-Object { $_.status -notin @('completed', 'planned_whatif') }).Count
    $cleanupFailureCount = @(
        $results | Where-Object { $_.cleanup_attempted -and $_.cleanup_succeeded -eq $false }
    ).Count
    $remnantCount = @($results | Where-Object { $_.repo_artifact_remaining -eq $true }).Count

    $countChecks = @{
        target_count = $targetCount
        completed_count = $completedCount
        planned_count = $plannedCount
        failed_count = $failedCount
        cleanup_failure_count = $cleanupFailureCount
        repo_artifact_remaining_count = $remnantCount
    }
    foreach ($name in $countChecks.Keys) {
        if ([int]$summary.$name -ne [int]$countChecks[$name]) {
            $errors.Add("summary $name=$($summary.$name) does not match recomputed value $($countChecks[$name])")
        }
    }
    if ($targetCount -ne $results.Count) {
        $errors.Add("summary target_count=$targetCount does not match results count $($results.Count)")
    }
}

$classification = 'EVIDENCE_INVALID'
$exitCode = 22
$nextAction = 'Repair or recover the local evidence package before making an installation claim.'

if ($errors.Count -eq 0) {
    if ($cleanupFailureCount -gt 0 -or $remnantCount -gt 0) {
        $classification = 'CLEANUP_REVIEW_REQUIRED'
        $exitCode = 21
        $nextAction = 'Resolve cleanup failures or confirmed SysAdminSuite remnants before expansion.'
    }
    elseif ($failedCount -gt 0) {
        $classification = 'INSTALL_FAILED'
        $exitCode = 20
        $nextAction = 'Review the failed target rows and operator JSONL before retrying.'
    }
    elseif ($completedCount -eq 0 -and $plannedCount -eq $targetCount -and $targetCount -gt 0) {
        $classification = 'PLAN_ONLY_NO_INSTALL'
        $exitCode = 10
        $nextAction = 'Review the plan, then run the separately authorized mutation command.'
    }
    elseif ($completedCount -eq $targetCount -and $targetCount -gt 0 -and $plannedCount -eq 0) {
        $classification = 'INSTALLER_EXECUTION_COMPLETE_POST_INSTALL_VERIFICATION_REQUIRED'
        $exitCode = 0
        $nextAction = 'Run package-specific version, service, launch, or acceptance checks before reporting deployment completion.'
    }
    else {
        $classification = 'PARTIAL_OR_MIXED_RESULT'
        $exitCode = 20
        $nextAction = 'Review every target row; do not expand or report completion.'
    }
}

if ($RequireCompleted -and
    $classification -ne 'INSTALLER_EXECUTION_COMPLETE_POST_INSTALL_VERIFICATION_REQUIRED') {
    if ($exitCode -eq 0) {
        $exitCode = 20
    }
}

$review = [ordered]@{
    schema_version = 'sas-software-install-review/v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    run_root = $RunRoot
    run_id = $runId
    package_name = $packageName
    install_mode = $installMode
    classification = $classification
    exit_code = $exitCode
    installer_execution_complete = (
        $classification -eq 'INSTALLER_EXECUTION_COMPLETE_POST_INSTALL_VERIFICATION_REQUIRED'
    )
    deployment_complete = $false
    post_install_verification_required = (
        $classification -eq 'INSTALLER_EXECUTION_COMPLETE_POST_INSTALL_VERIFICATION_REQUIRED'
    )
    proof_level = 'installer_process_exit_and_sysadminsuite_cleanup_evidence'
    counts = [ordered]@{
        targets = $targetCount
        completed = $completedCount
        planned = $plannedCount
        failed = $failedCount
        cleanup_failures = $cleanupFailureCount
        repo_owned_target_remnants = $remnantCount
    }
    evidence = [ordered]@{
        summary = $summaryPath
        events = $eventsPath
        handoff = $handoffPath
        review = $reviewPath
    }
    evidence_errors = @($errors)
    results = @($results | ForEach-Object { $_ })
    next_action = $nextAction
}
$review | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $reviewPath -Encoding UTF8

Write-Host 'SYSADMINSUITE SOFTWARE INSTALL RESULT'
Write-Host "Classification: $classification"
Write-Host "Run ID: $runId"
Write-Host "Package: $packageName"
Write-Host "Mode: $installMode"
Write-Host "Targets: $targetCount | Completed: $completedCount | Planned: $plannedCount | Failed: $failedCount"
Write-Host "Cleanup failures: $cleanupFailureCount | Repo-owned target remnants: $remnantCount"
Write-Host 'Deployment complete: false'
Write-Host "Review artifact: $reviewPath"
Write-Host "Next action: $nextAction"

if ($results.Count -gt 0) {
    Write-Host ''
    $table = $results |
        Select-Object computer_name, status, exit_code, cleanup_succeeded, repo_artifact_remaining, error |
        Format-Table -AutoSize |
        Out-String
    Write-Host $table.TrimEnd()
}

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host 'Evidence errors:'
    foreach ($errorMessage in $errors) {
        Write-Host "- $errorMessage"
    }
}

if ($OpenEvidence) {
    Start-Process -FilePath explorer.exe -ArgumentList @($RunRoot) | Out-Null
}
if ($PassThru) {
    Write-Output ([pscustomobject]$review)
}
exit $exitCode
