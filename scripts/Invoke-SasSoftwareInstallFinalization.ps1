#Requires -Version 5.1
<#
.SYNOPSIS
Validates requested software, removes SysAdminSuite run-scoped target artifacts, and verifies requested software remains.

.DESCRIPTION
This is the mandatory finalization gate for validated software deployment. It consumes an existing canonical
software_install_summary.json and a closed validated-deployment request. For each target it performs bounded
read-only package checks, executes idempotent cleanup limited to ProgramData\SysAdminSuite\SoftwareInstall\<run_id>,
then repeats the package checks. Cleanup runs even when installation or validation failed. The script never
uninstalls the requested package, clears logs, suppresses monitoring, collects credentials, or removes installer-owned files.
Direct execution is fail-closed and requires both -AllowTargetMutation and ShouldProcess approval.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallSummaryPath,

    [Parameter(Mandatory = $true)]
    [string]$RequestPath,

    [Parameter(Mandatory = $false)]
    [switch]$AllowTargetMutation,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFixtures
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$modulePath = Join-Path $PSScriptRoot 'SasSoftwareInstallFinalization.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Missing finalization module: $modulePath" }
Import-Module $modulePath -Force

function Resolve-SasLocalEvidencePath {
    param([string]$Path, [string]$Role)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    $roots = @(
        [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output')).TrimEnd('\'),
        [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/input')).TrimEnd('\')
    )
    if ($AllowFixtures) { $roots += [IO.Path]::GetFullPath((Join-Path $repoRoot 'Tests/fixtures')).TrimEnd('\') }
    $approved = @($roots | Where-Object {
        $candidate.Equals($_, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0
    if (-not $approved) { throw "$Role must remain under an approved local evidence root. Received: $candidate" }
    return $candidate
}

$InstallSummaryPath = Resolve-SasLocalEvidencePath -Path $InstallSummaryPath -Role 'Install summary'
$RequestPath = Resolve-SasLocalEvidencePath -Path $RequestPath -Role 'Validated deployment request'
if (-not (Test-Path -LiteralPath $InstallSummaryPath -PathType Leaf)) { throw "Install summary not found: $InstallSummaryPath" }
if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) { throw "Validated deployment request not found: $RequestPath" }

$summary = Get-Content -LiteralPath $InstallSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$requestErrors = @(Test-SasValidatedDeploymentRequest -Request $request)
if ($requestErrors.Count -gt 0) { throw "Validated deployment request failed contract checks: $($requestErrors -join ', ')" }
if ([string]$summary.schema_version -ne 'sas-software-install-summary/v1') { throw "Unsupported install summary schema: $($summary.schema_version)" }
if ([string]$summary.run_id -notmatch '^software-install-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { throw "Install summary run ID is invalid: $($summary.run_id)" }
if ([string]$summary.package_name -ne [string]$request.package_name) { throw 'Install summary package does not match validated deployment request.' }

$summaryTargets = @($summary.results | ForEach-Object { [string]$_.computer_name } | Sort-Object -Unique)
$requestTargets = @($request.targets | ForEach-Object { [string]$_ } | Sort-Object -Unique)
if (@(Compare-Object -ReferenceObject $requestTargets -DifferenceObject $summaryTargets).Count -ne 0) {
    throw 'Install summary target set does not match validated deployment request.'
}

if (-not $AllowTargetMutation -and -not $WhatIfPreference) {
    throw 'Refusing software-install finalization without -AllowTargetMutation. Use -WhatIf to inspect the approved finalization scope without contacting targets.'
}
$targetDescription = $summaryTargets -join ', '
$actionDescription = "Validate package '$($request.package_name)', remove only run-scoped SysAdminSuite staging for '$($summary.run_id)', and validate package preservation"
if (-not $PSCmdlet.ShouldProcess($targetDescription, $actionDescription)) {
    Write-Host 'Software-install finalization was not executed.'
    return
}

$runRoot = Split-Path -Parent $InstallSummaryPath
$finalizationPath = Join-Path $runRoot 'software_install_finalization.json'
$eventPath = Join-Path $runRoot 'software_install_events.jsonl'
$validationScript = Get-SasSoftwareValidationScriptBlock
$cleanupScript = Get-SasSoftwareCleanupScriptBlock
$checksJson = @($request.validation.checks) | ConvertTo-Json -Depth 12 -Compress
$rows = @()

function Write-FinalizationEvent {
    param([string]$Name, [hashtable]$Data)
    $payload = [ordered]@{ timestamp_utc = (Get-Date).ToUniversalTime().ToString('o'); event = $Name; run_id = [string]$summary.run_id }
    foreach ($key in $Data.Keys) { $payload[$key] = $Data[$key] }
    $payload | ConvertTo-Json -Depth 12 -Compress | Add-Content -LiteralPath $eventPath -Encoding UTF8
}

Write-FinalizationEvent -Name 'finalization_started' -Data @{ request_id = [string]$request.request_id; target_count = $summaryTargets.Count }

foreach ($installRow in @($summary.results)) {
    $target = [string]$installRow.computer_name
    $session = $null
    $validationBefore = $null
    $validationAfter = $null
    $cleanup = $null
    $finalStatus = 'FINALIZATION_FAILED'
    $errorMessage = $null
    try {
        $sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 3600000
        $session = New-PSSession -ComputerName $target -SessionOption $sessionOption

        if ([string]$installRow.status -eq 'completed') {
            $validationBefore = Invoke-Command -Session $session -ScriptBlock $validationScript -ArgumentList $checksJson
        }

        $cleanup = Invoke-Command -Session $session -ScriptBlock $cleanupScript -ArgumentList ([string]$summary.run_id)

        if ([string]$installRow.status -eq 'completed' -and $validationBefore -and $validationBefore.succeeded) {
            $validationAfter = Invoke-Command -Session $session -ScriptBlock $validationScript -ArgumentList $checksJson
        }

        if (-not $cleanup -or -not $cleanup.cleanup_succeeded -or $cleanup.repo_artifact_remaining) {
            $finalStatus = 'TEARDOWN_FAILED'
        }
        elseif ([string]$installRow.status -ne 'completed') {
            $finalStatus = 'INSTALL_FAILED_TOOLS_REMOVED'
        }
        elseif (-not $validationBefore -or -not $validationBefore.succeeded) {
            $finalStatus = 'VALIDATION_FAILED_TOOLS_REMOVED'
        }
        elseif (-not $validationAfter -or -not $validationAfter.succeeded) {
            $finalStatus = 'REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN'
        }
        else {
            $finalStatus = 'COMPLETED_VALIDATED_FINALIZED'
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($session -and $null -eq $cleanup) {
            try { $cleanup = Invoke-Command -Session $session -ScriptBlock $cleanupScript -ArgumentList ([string]$summary.run_id) }
            catch { $errorMessage = "$errorMessage; final cleanup failed: $($_.Exception.Message)" }
        }
        if ($cleanup -and $cleanup.cleanup_succeeded -and -not $cleanup.repo_artifact_remaining) {
            if ([string]$installRow.status -eq 'completed') { $finalStatus = 'VALIDATION_FAILED_TOOLS_REMOVED' }
            else { $finalStatus = 'INSTALL_FAILED_TOOLS_REMOVED' }
        }
        else { $finalStatus = 'TEARDOWN_FAILED' }
    }
    finally {
        if ($session) { Remove-PSSession -Session $session }
    }

    $row = [pscustomobject][ordered]@{
        computer_name = $target
        install_status = [string]$installRow.status
        validation_before_cleanup_succeeded = [bool]($validationBefore -and $validationBefore.succeeded)
        validation_before_cleanup = if ($validationBefore) { @($validationBefore.checks) } else { @() }
        cleanup_attempted = [bool]($cleanup -and $cleanup.cleanup_attempted)
        cleanup_succeeded = [bool]($cleanup -and $cleanup.cleanup_succeeded)
        repo_artifact_remaining = [bool]($cleanup -and $cleanup.repo_artifact_remaining)
        removed_paths = if ($cleanup) { @($cleanup.removed_paths) } else { @() }
        pruned_empty_parent_dirs = if ($cleanup) { @($cleanup.pruned_empty_parent_dirs) } else { @() }
        requested_software_preserved_after_teardown = [bool]($validationAfter -and $validationAfter.succeeded)
        validation_after_cleanup = if ($validationAfter) { @($validationAfter.checks) } else { @() }
        finalization_status = $finalStatus
        error = if ($errorMessage) { $errorMessage } elseif ($cleanup -and $cleanup.error) { [string]$cleanup.error } else { $null }
    }
    $rows += $row
    Write-FinalizationEvent -Name 'target_finalization_completed' -Data @{
        computer_name = $target
        finalization_status = $finalStatus
        validation_before_cleanup_succeeded = $row.validation_before_cleanup_succeeded
        cleanup_succeeded = $row.cleanup_succeeded
        repo_artifact_remaining = $row.repo_artifact_remaining
        requested_software_preserved_after_teardown = $row.requested_software_preserved_after_teardown
    }
}

$completedCount = @($rows | Where-Object { $_.finalization_status -eq 'COMPLETED_VALIDATED_FINALIZED' }).Count
$validationFailureCount = @($rows | Where-Object { $_.finalization_status -eq 'VALIDATION_FAILED_TOOLS_REMOVED' }).Count
$teardownFailureCount = @($rows | Where-Object { $_.finalization_status -eq 'TEARDOWN_FAILED' }).Count
$preservationFailureCount = @($rows | Where-Object { $_.finalization_status -eq 'REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN' }).Count
$installFailureCount = @($rows | Where-Object { $_.finalization_status -eq 'INSTALL_FAILED_TOOLS_REMOVED' }).Count
$deploymentComplete = ($rows.Count -gt 0 -and $completedCount -eq $rows.Count)
$classification = if ($deploymentComplete) { 'DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED' }
elseif ($teardownFailureCount -gt 0) { 'TEARDOWN_FAILED' }
elseif ($preservationFailureCount -gt 0) { 'REQUESTED_SOFTWARE_NOT_PRESERVED' }
elseif ($validationFailureCount -gt 0) { 'POST_INSTALL_VALIDATION_FAILED_TOOLS_REMOVED' }
else { 'INSTALL_FAILED_TOOLS_REMOVED' }

$finalization = [ordered]@{
    schema_version = 'sas-software-install-finalization/v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    run_id = [string]$summary.run_id
    request_id = [string]$request.request_id
    package_name = [string]$request.package_name
    classification = $classification
    deployment_complete = $deploymentComplete
    target_count = $rows.Count
    completed_validated_finalized_count = $completedCount
    install_failure_count = $installFailureCount
    validation_failure_count = $validationFailureCount
    teardown_failure_count = $teardownFailureCount
    preservation_failure_count = $preservationFailureCount
    cleanup_policy = 'repo_owned_run_scoped_only'
    requested_software_uninstall_performed = $false
    management_transport_used = $true
    network_activity_performed = $true
    target_mutation_performed = $true
    proof_level = 'installer_exit_package_validation_run_scoped_teardown_and_post_teardown_preservation'
    results = @($rows)
}
$finalization | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $finalizationPath -Encoding UTF8

$summary | Add-Member -NotePropertyName finalization_path -NotePropertyValue $finalizationPath -Force
$summary | Add-Member -NotePropertyName deployment_complete -NotePropertyValue $deploymentComplete -Force
$summary | Add-Member -NotePropertyName finalization_classification -NotePropertyValue $classification -Force
$summary | Add-Member -NotePropertyName completed_validated_finalized_count -NotePropertyValue $completedCount -Force
$summary | Add-Member -NotePropertyName validation_failure_count -NotePropertyValue $validationFailureCount -Force
$summary | Add-Member -NotePropertyName teardown_failure_count -NotePropertyValue $teardownFailureCount -Force
$summary | Add-Member -NotePropertyName preservation_failure_count -NotePropertyValue $preservationFailureCount -Force
$summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $InstallSummaryPath -Encoding UTF8

Write-FinalizationEvent -Name 'finalization_completed' -Data @{
    classification = $classification
    deployment_complete = $deploymentComplete
    finalization_path = $finalizationPath
    completed_validated_finalized_count = $completedCount
    validation_failure_count = $validationFailureCount
    teardown_failure_count = $teardownFailureCount
    preservation_failure_count = $preservationFailureCount
}

Write-Host "Finalization classification: $classification"
Write-Host "Deployment complete: $deploymentComplete"
Write-Host "Finalization artifact: $finalizationPath"
Write-Output ([pscustomobject]$finalization)
