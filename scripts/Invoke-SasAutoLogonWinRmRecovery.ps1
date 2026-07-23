#Requires -Version 5.1
<#
.SYNOPSIS
Recover one interrupted AutoLogon deployment whose state proof was blocked by unavailable WinRM.
.DESCRIPTION
Preserves the original run, reuses its closed validated deployment request, proves the canonical
Kerberos SMB scheduled-task boundary with a fresh P02 preflight and harmless live certification,
captures a new baseline through a transient read-only SYSTEM task, re-runs the canonical AutoLogon
final-step gate, and only then resumes the canonical validated deployment. After-state is captured
through the same transport and all transient tasks and staging roots must be absent before success
is reported.

This script never enables WinRM, opens a port, accepts credentials, reboots the target, or reads
DefaultPassword data. It refuses automatic recovery when the interrupted run already contains
software-install or SMB adapter evidence because duplicate-install risk then requires manual review.
#>

[CmdletBinding(DefaultParameterSetName = 'Live')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [string]$RunRoot,

    [Parameter(Mandatory = $false, ParameterSetName = 'Live')]
    [string]$ComputerName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [switch]$AllowNetworkActivity,

    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [switch]$AllowTargetMutation,

    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [switch]$ConfirmRecovery,

    [Parameter(Mandatory = $true, ParameterSetName = 'Fixture')]
    [switch]$FixtureMode,

    [Parameter(Mandatory = $false, ParameterSetName = 'Fixture')]
    [ValidateSet('success','already_configured','capture_failure','cleanup_failure','deployment_failure')]
    [string]$FixtureScenario = 'success',

    [string]$HostEligibilityPolicyPath,

    [ValidateRange(1, 1440)]
    [int]$PreflightMaxAgeMinutes = 15,

    [ValidateRange(10, 600)]
    [int]$StateResultTimeoutSeconds = 120,

    [ValidateRange(10, 7200)]
    [int]$DeploymentResultTimeoutSeconds = 1800,

    [string]$OutputRoot,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasRecoveryProperty {
    param($Value, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Value) { return $Default }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Write-SasRecoveryJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-SasRecoveryRunRoot {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$RepoRoot)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
    }
    $approved = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'survey\output\runs\autologon-proof')).TrimEnd('\')
    if (-not ($candidate.Equals($approved, [StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith($approved + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Interrupted AutoLogon RunRoot must remain under survey/output/runs/autologon-proof.'
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Interrupted AutoLogon run not found: $candidate" }
    return $candidate
}

function Get-SasRecoveryRequest {
    param([Parameter(Mandatory = $true)][string]$Root)
    $requests = @(Get-ChildItem -LiteralPath $Root -Filter 'validated_deployment_request_*.json' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]recovery[\\/]' } |
        Sort-Object FullName)
    if ($requests.Count -ne 1) {
        throw "Recovery requires exactly one preserved validated deployment request; found $($requests.Count)."
    }
    try { $request = Get-Content -LiteralPath $requests[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Preserved validated request is malformed: $($_.Exception.Message)" }
    if ([string]$request.schema_version -ne 'sas-validated-software-deployment-request/v1') {
        throw 'Preserved validated request schema is unsupported.'
    }
    if ([string]$request.package_name -ne 'NW AutoLogon Setup x64') {
        throw 'Preserved request is not the approved AutoLogon package.'
    }
    $targets = @($request.targets | ForEach-Object { [string]$_ })
    if ($targets.Count -ne 1) { throw 'WinRM-blocker recovery is intentionally limited to one target.' }
    return [pscustomobject]@{ path = $requests[0].FullName; request = $request; target = $targets[0] }
}

function Get-SasExistingDeploymentEvidence {
    param([Parameter(Mandatory = $true)][string]$Root)
    $files = @()
    foreach ($pattern in @('software_install_summary.json','smb_task_transport_result_*.json','validated_deployment_result.json','software_install_finalization.json')) {
        $files += @(Get-ChildItem -LiteralPath $Root -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue)
    }
    return @($files | Sort-Object FullName -Unique)
}

function Get-SasSoftwareKeySet {
    param([object[]]$Rows)
    $keys = @{}
    foreach ($row in @($Rows)) {
        $name = ([string](Get-SasRecoveryProperty -Value $row -Name 'name' -Default '')).Trim().ToLowerInvariant()
        $publisher = ([string](Get-SasRecoveryProperty -Value $row -Name 'publisher' -Default '')).Trim().ToLowerInvariant()
        if ($name) { $keys["$name|$publisher"] = $true }
    }
    return $keys
}

function Get-SasSoftwareAddedCount {
    param($Before, $After)
    $beforeKeys = Get-SasSoftwareKeySet -Rows @(Get-SasRecoveryProperty -Value $Before -Name 'installed_software' -Default @())
    $afterKeys = Get-SasSoftwareKeySet -Rows @(Get-SasRecoveryProperty -Value $After -Name 'installed_software' -Default @())
    return @($afterKeys.Keys | Where-Object { -not $beforeKeys.ContainsKey($_) }).Count
}

function Test-SasCaptureLifecycleComplete {
    param($Lifecycle)
    return ([string]$Lifecycle.status -eq 'completed' -and
        [bool]$Lifecycle.result_retrieval.succeeded -and
        [bool]$Lifecycle.worker.executed_as_system -and
        [bool]$Lifecycle.worker.hash_verified -and
        [bool]$Lifecycle.cleanup.task_deletion_succeeded -and
        [bool]$Lifecycle.cleanup.run_root_deletion_succeeded -and
        -not [bool]$Lifecycle.cleanup.task_remaining -and
        -not [bool]$Lifecycle.cleanup.run_root_remaining)
}

function New-SasRecoveryGateInput {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$BaselineSnapshotPath
    )
    $input = [pscustomobject][ordered]@{
        run_id = $RunId
        phase = 'before_complete'
        targets = @([pscustomobject][ordered]@{ computer_name = $Target; hostname = $Target })
        baseline_snapshot_path = $BaselineSnapshotPath
        baseline_snapshot_sha256 = (Get-FileHash -LiteralPath $BaselineSnapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
        collection_transport = 'kerberos_smb_task'
    }
    Write-SasRecoveryJson -Path $Path -Value $input
    return $Path
}

function New-SasRecoveryFixtureHostPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )
    $policy = [pscustomobject][ordered]@{
        schema_version = 'sas-host-eligibility-policy/v1'
        policy_id = 'autologon-winrm-recovery-fixture'
        policy_version = '1.0.0'
        patterns = @([pscustomobject][ordered]@{
            name = 'fixture-autologon-target'
            match_type = 'regex'
            regex = ('^{0}$' -f [regex]::Escape($Target))
            actions = @('fixture')
        })
    }
    Write-SasRecoveryJson -Path $Path -Value $policy
    return $Path
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$stateModulePath = Join-Path $PSScriptRoot 'SasAutoLogonSmbStateRecovery.psm1'
$preflightScript = Join-Path $PSScriptRoot 'Test-SasSoftwareDeploymentTransport.ps1'
$liveCertScript = Join-Path $PSScriptRoot 'Invoke-SasSoftwareDeploymentTransportLiveCert.ps1'
$finalGateScript = Join-Path $PSScriptRoot 'Invoke-SasAutoLogonFinalStepGate.ps1'
$validatedDeploymentScript = Join-Path $PSScriptRoot 'Invoke-SasValidatedSoftwareDeployment.ps1'
$networkGuardModule = Join-Path $PSScriptRoot 'SasNetworkGuard.psm1'
$approvedAppsPath = Join-Path $repoRoot 'configs\software-packages\approved-apps.json'
foreach ($required in @($stateModulePath,$preflightScript,$liveCertScript,$finalGateScript,$validatedDeploymentScript,$networkGuardModule,$approvedAppsPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing AutoLogon recovery dependency: $required" }
}
Import-Module $stateModulePath -Force

$recoveryRunId = 'autologon-recovery-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$gateRunId = 'autologon-delta-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$classification = 'RECOVERY_FAILED'
$errorMessage = $null
$target = $null
$requestPath = $null
$preflightPath = $null
$liveCertPath = $null
$finalGatePath = $null
$finalGatePassed = $false
$deploymentResultPath = $null
$installSummaryPath = $null
$baselinePath = $null
$afterPath = $null
$baselineStatus = 'unknown'
$afterStatus = 'unknown'
$softwareAddedCount = 0
$deploymentComplete = $false
$networkActivityPerformed = $false
$targetMutationPerformed = $false
$configurationMutationPerformed = $false
$collectorCleanupVerified = $false
$deploymentCleanupVerified = $false
$runtimeProofPending = $false
$baselineLifecycle = $null
$afterLifecycle = $null
$deployment = $null

if ($FixtureMode) {
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Join-Path $repoRoot 'survey\output\fixtures\autologon-winrm-recovery'
    }
    $recoveryRoot = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $recoveryRunId
}
else {
    if (-not $AllowNetworkActivity) { throw 'Live recovery requires explicit -AllowNetworkActivity acknowledgement.' }
    if (-not $AllowTargetMutation) { throw 'Live recovery requires explicit -AllowTargetMutation acknowledgement.' }
    if (-not $ConfirmRecovery) { throw 'Live recovery requires explicit -ConfirmRecovery acknowledgement.' }
    $RunRoot = Resolve-SasRecoveryRunRoot -Path $RunRoot -RepoRoot $repoRoot
    $requestInfo = Get-SasRecoveryRequest -Root $RunRoot
    $requestPath = $requestInfo.path
    $target = [string]$requestInfo.target
    if (-not [string]::IsNullOrWhiteSpace($ComputerName) -and
        -not $ComputerName.Equals($target, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ComputerName does not match the preserved validated deployment request.'
    }
    if (-not (Test-SasAutoLogonRecoveryFqdn -ComputerName $target)) { throw 'Preserved request target is not an exact FQDN.' }
    $existing = @(Get-SasExistingDeploymentEvidence -Root $RunRoot)
    if ($existing.Count -gt 0) {
        $names = @($existing | ForEach-Object { $_.Name }) -join ', '
        throw "Automatic recovery is blocked because deployment evidence already exists: $names. Preserve the run for manual classification to avoid a duplicate install."
    }
    $recoveryRoot = Join-Path $RunRoot (Join-Path 'recovery' $recoveryRunId)
}

New-Item -ItemType Directory -Path $recoveryRoot -Force | Out-Null
$artifactsRoot = Join-Path $recoveryRoot 'artifacts'
$actionsRoot = Join-Path $recoveryRoot 'actions'
$evidenceRoot = Join-Path $recoveryRoot 'evidence'
$reportsRoot = Join-Path $recoveryRoot 'reports'
New-Item -ItemType Directory -Path $artifactsRoot,$actionsRoot,$evidenceRoot,$reportsRoot -Force | Out-Null
$resultPath = Join-Path $artifactsRoot 'autologon_winrm_recovery_result.json'
$summaryPath = Join-Path $reportsRoot 'english_summary.txt'

try {
    if ($FixtureMode) {
        $target = 'fixture-autologon.example.invalid'
        $requestPath = '[fixture request]'
        $baselineScenario = if ($FixtureScenario -eq 'already_configured') { 'already_configured' }
            elseif ($FixtureScenario -eq 'capture_failure') { 'capture_failure' }
            elseif ($FixtureScenario -eq 'cleanup_failure') { 'cleanup_failure' }
            else { 'success' }
        $baselineLifecycle = Invoke-SasAutoLogonSmbStateCaptureFixture -FixtureRoot (Join-Path $evidenceRoot 'baseline') -Phase baseline -Scenario $baselineScenario
        $baselinePath = Join-Path $evidenceRoot 'baseline_snapshot.json'
        if ($baselineLifecycle.snapshot) { Write-SasRecoveryJson -Path $baselinePath -Value $baselineLifecycle.snapshot }
        if (-not (Test-SasCaptureLifecycleComplete -Lifecycle $baselineLifecycle)) {
            throw "Fixture baseline capture did not complete: $($baselineLifecycle.status)"
        }
        $baselineStatus = [string]$baselineLifecycle.snapshot.autologon.status
        $collectorCleanupVerified = $true
        if ($baselineStatus -eq 'autologon_ready') {
            $classification = 'ALREADY_CONFIGURED_RUNTIME_PENDING'
            $runtimeProofPending = $true
        }
        else {
            $gateInputPath = New-SasRecoveryGateInput -Path (Join-Path $actionsRoot 'autologon_final_step_gate_input.json') `
                -RunId $gateRunId -Target $target -BaselineSnapshotPath $baselinePath
            $fixturePolicyPath = New-SasRecoveryFixtureHostPolicy -Path (Join-Path $actionsRoot 'fixture_host_eligibility_policy.json') -Target $target
            $gateResult = & $finalGateScript -Target $target -RunId $gateRunId -BeforeSnapshotPath $gateInputPath `
                -ApprovedAppsPath $approvedAppsPath -HostEligibilityPolicyPath $fixturePolicyPath `
                -OutputRoot (Join-Path $actionsRoot 'final-gate') -ExecContext fixture -FixtureMode
            $finalGatePassed = [bool]$gateResult.overall_pass
            $finalGatePath = Join-Path (Join-Path (Join-Path $actionsRoot 'final-gate') $gateRunId) 'autologon_final_step_gate.json'
            if (-not $finalGatePassed) { throw "AutoLogon final-step gate blocked recovery: $($gateResult.blocked_reason)" }

            $deploymentComplete = ($FixtureScenario -ne 'deployment_failure')
            if (-not $deploymentComplete) { throw 'Synthetic validated deployment failure.' }
            $afterLifecycle = Invoke-SasAutoLogonSmbStateCaptureFixture -FixtureRoot (Join-Path $evidenceRoot 'after') -Phase after -Scenario success
            $afterPath = Join-Path $evidenceRoot 'after_snapshot.json'
            Write-SasRecoveryJson -Path $afterPath -Value $afterLifecycle.snapshot
            if (-not (Test-SasCaptureLifecycleComplete -Lifecycle $afterLifecycle)) { throw 'Fixture after capture did not complete.' }
            $afterStatus = [string]$afterLifecycle.snapshot.autologon.status
            $softwareAddedCount = Get-SasSoftwareAddedCount -Before $baselineLifecycle.snapshot -After $afterLifecycle.snapshot
            $deploymentCleanupVerified = $true
            $collectorCleanupVerified = $true
            if ($afterStatus -eq 'autologon_ready') {
                $classification = 'RECOVERED_DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING'
                $runtimeProofPending = $true
            }
            else {
                $classification = 'RECOVERED_DEPLOYMENT_STATE_REVIEW'
            }
        }
    }
    else {
        Import-Module $networkGuardModule -Force
        Assert-SasNorthwellWifi
        $networkActivityPerformed = $true

        $preflight = & $preflightScript -ComputerName $target -AllowNetworkActivity `
            -TransportIntent kerberos_smb_task -OutputRoot (Join-Path $recoveryRoot 'preflight') -PassThru
        $preflightPath = [string]$preflight.result_path
        if ([string]$preflight.result.decision.classification -ne 'kerberos_smb_task_ready') {
            throw "SMB recovery preflight did not pass: $($preflight.result.decision.classification)"
        }

        $liveCert = & $liveCertScript -ComputerName $target -PreflightResultPath $preflightPath `
            -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
            -OutputRoot (Join-Path $recoveryRoot 'live-cert') -PassThru
        $liveCertPath = [string]$liveCert.result_path
        $targetMutationPerformed = $true
        if ([string]$liveCert.disposition -ne 'LIVE CERT PASS' -or [string]$liveCert.lifecycle_status -ne 'completed') {
            throw "Harmless SMB live certification failed: $($liveCert.disposition) / $($liveCert.lifecycle_status)"
        }

        $baselineLifecycle = Invoke-SasAutoLogonSmbStateCapture -ComputerName $target -RunId $recoveryRunId -Phase baseline `
            -PreflightResultPath $preflightPath -LocalRunRoot (Join-Path $evidenceRoot 'baseline') `
            -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
            -ResultTimeoutSeconds $StateResultTimeoutSeconds
        Write-SasRecoveryJson -Path (Join-Path $evidenceRoot 'baseline_lifecycle.json') -Value $baselineLifecycle
        if ($baselineLifecycle.snapshot) {
            $baselinePath = Join-Path $evidenceRoot 'baseline_snapshot.json'
            Write-SasRecoveryJson -Path $baselinePath -Value $baselineLifecycle.snapshot
        }
        if (-not (Test-SasCaptureLifecycleComplete -Lifecycle $baselineLifecycle)) {
            throw "SMB baseline capture failed or left remnants: $($baselineLifecycle.status). $($baselineLifecycle.error)"
        }
        $collectorCleanupVerified = $true
        $baselineStatus = [string]$baselineLifecycle.snapshot.autologon.status

        if ($baselineStatus -eq 'autologon_ready') {
            $classification = 'ALREADY_CONFIGURED_RUNTIME_PENDING'
            $runtimeProofPending = $true
        }
        else {
            $gateInputPath = New-SasRecoveryGateInput -Path (Join-Path $actionsRoot 'autologon_final_step_gate_input.json') `
                -RunId $gateRunId -Target $target -BaselineSnapshotPath $baselinePath
            $gateParameters = @{
                Target = $target
                RunId = $gateRunId
                BeforeSnapshotPath = $gateInputPath
                ApprovedAppsPath = $approvedAppsPath
                OutputRoot = (Join-Path $actionsRoot 'final-gate')
                ExecContext = 'remote'
            }
            if (-not [string]::IsNullOrWhiteSpace($HostEligibilityPolicyPath)) {
                $gateParameters.HostEligibilityPolicyPath = $HostEligibilityPolicyPath
            }
            $gateResult = & $finalGateScript @gateParameters
            $finalGatePassed = [bool]$gateResult.overall_pass
            $finalGatePath = Join-Path (Join-Path (Join-Path $actionsRoot 'final-gate') $gateRunId) 'autologon_final_step_gate.json'
            if (-not $finalGatePassed) { throw "AutoLogon final-step gate blocked recovery: $($gateResult.blocked_reason)" }

            try {
                $deployment = & $validatedDeploymentScript -RequestPath $requestPath `
                    -OutputRoot (Join-Path $recoveryRoot 'deployment') -Transport SmbScheduledTask `
                    -TransportPreflightPath @($preflightPath) -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
                    -ResultTimeoutSeconds $DeploymentResultTimeoutSeconds -AllowTargetMutation -Confirm:$false
            }
            catch {
                $candidate = @(Get-ChildItem -LiteralPath (Join-Path $recoveryRoot 'deployment') -Filter 'validated_deployment_result.json' -File -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
                if ($candidate.Count -gt 0) {
                    $deployment = Get-Content -LiteralPath $candidate[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                }
                throw
            }
            $configurationMutationPerformed = $true
            $targetMutationPerformed = $true
            $deploymentComplete = [bool]$deployment.deployment_complete
            $deploymentResultFile = @(Get-ChildItem -LiteralPath (Join-Path $recoveryRoot 'deployment') -Filter 'validated_deployment_result.json' -File -Recurse |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
            if ($deploymentResultFile.Count -gt 0) { $deploymentResultPath = $deploymentResultFile[0].FullName }
            $installSummaryPath = [string]$deployment.install_summary_path
            if (-not $deploymentComplete) { throw "Validated recovery deployment did not complete: $($deployment.classification)" }
            if (-not (Test-Path -LiteralPath $installSummaryPath -PathType Leaf)) { throw 'Recovery install summary is missing.' }
            $installSummary = Get-Content -LiteralPath $installSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $deploymentCleanupVerified = ([int]$installSummary.cleanup_failure_count -eq 0 -and [int]$installSummary.repo_artifact_remaining_count -eq 0)
            if (-not $deploymentCleanupVerified) { throw 'Recovery deployment did not prove complete run-scoped teardown.' }

            $afterLifecycle = Invoke-SasAutoLogonSmbStateCapture -ComputerName $target -RunId $recoveryRunId -Phase after `
                -PreflightResultPath $preflightPath -LocalRunRoot (Join-Path $evidenceRoot 'after') `
                -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
                -ResultTimeoutSeconds $StateResultTimeoutSeconds
            Write-SasRecoveryJson -Path (Join-Path $evidenceRoot 'after_lifecycle.json') -Value $afterLifecycle
            if ($afterLifecycle.snapshot) {
                $afterPath = Join-Path $evidenceRoot 'after_snapshot.json'
                Write-SasRecoveryJson -Path $afterPath -Value $afterLifecycle.snapshot
            }
            if (-not (Test-SasCaptureLifecycleComplete -Lifecycle $afterLifecycle)) {
                throw "SMB after capture failed or left remnants: $($afterLifecycle.status). $($afterLifecycle.error)"
            }
            $collectorCleanupVerified = $true
            $afterStatus = [string]$afterLifecycle.snapshot.autologon.status
            $softwareAddedCount = Get-SasSoftwareAddedCount -Before $baselineLifecycle.snapshot -After $afterLifecycle.snapshot
            if ($afterStatus -eq 'autologon_ready') {
                $classification = 'RECOVERED_DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING'
                $runtimeProofPending = $true
            }
            else {
                $classification = 'RECOVERED_DEPLOYMENT_STATE_REVIEW'
            }
        }
    }
}
catch {
    $errorMessage = $_.Exception.Message
    if ($classification -notin @('ALREADY_CONFIGURED_RUNTIME_PENDING','RECOVERED_DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING','RECOVERED_DEPLOYMENT_STATE_REVIEW')) {
        $classification = if ($errorMessage -match 'deployment evidence already exists') { 'RECOVERY_BLOCKED_EXISTING_DEPLOYMENT_EVIDENCE' }
            elseif ($errorMessage -match 'final-step gate') { 'RECOVERY_FINAL_GATE_BLOCKED' }
            elseif ($errorMessage -match 'cleanup|remnant|teardown') { 'RECOVERY_CLEANUP_REVIEW_REQUIRED' }
            elseif ($errorMessage -match 'preflight|live certification') { 'RECOVERY_TRANSPORT_BLOCKED' }
            else { 'RECOVERY_FAILED' }
    }
}

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-winrm-recovery-result/v1'
    recovery_run_id = $recoveryRunId
    final_gate_run_id = $gateRunId
    classification = $classification
    reason = $errorMessage
    fixture_mode = [bool]$FixtureMode
    original_run_root = $(if ($FixtureMode) { $null } else { $RunRoot })
    target = $target
    request_path = $requestPath
    preflight_result_path = $preflightPath
    live_cert_result_path = $liveCertPath
    final_gate_result_path = $finalGatePath
    final_gate_passed = $finalGatePassed
    deployment_result_path = $deploymentResultPath
    install_summary_path = $installSummaryPath
    baseline_snapshot_path = $baselinePath
    after_snapshot_path = $afterPath
    baseline_status = $baselineStatus
    after_status = $afterStatus
    software_added_count = $softwareAddedCount
    deployment_complete = $deploymentComplete
    collector_cleanup_verified = $collectorCleanupVerified
    deployment_cleanup_verified = $deploymentCleanupVerified
    runtime_proof_pending = $runtimeProofPending
    network_activity_performed = $networkActivityPerformed
    target_mutation_performed = $targetMutationPerformed
    configuration_mutation_performed = $configurationMutationPerformed
    default_password_value_collected = $false
    automatic_reboot_performed = $false
    winrm_enabled_or_modified = $false
    proof_level = $(if ($FixtureMode) { 'sanitized_fixture_contract' }
        elseif ($classification -eq 'RECOVERED_DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING') { 'final_gate_deployment_execution_and_post_install_state' }
        elseif ($classification -eq 'ALREADY_CONFIGURED_RUNTIME_PENDING') { 'current_state_capture' }
        else { 'insufficient_or_review_required' })
    proof_ceiling = 'Recovery can prove canonical SMB transport, transient collector cleanup, final-step gate disposition, validated deployment execution, and post-install registry posture. Reboot, automatic sign-in, current-token access, application behavior, and technician acceptance remain unproven.'
}
Write-SasRecoveryJson -Path $resultPath -Value $result

$summary = @(
    'SysAdminSuite AutoLogon WinRM-blocker recovery'
    "Classification: $classification"
    "Recovery run: $recoveryRunId"
    "Final-step gate passed: $finalGatePassed"
    "Baseline status: $baselineStatus"
    "After status: $afterStatus"
    "Software added: $softwareAddedCount"
    "Deployment complete: $deploymentComplete"
    "Collector cleanup verified: $collectorCleanupVerified"
    "Deployment cleanup verified: $deploymentCleanupVerified"
    "Runtime proof pending: $runtimeProofPending"
    "WinRM enabled or modified: False"
    "Automatic reboot performed: False"
    "Result: $resultPath"
    "Proof ceiling: $($result.proof_ceiling)"
)
if ($errorMessage) { $summary += "Blocker: $errorMessage" }
$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ForEach-Object { Write-Host $_ }

$output = [pscustomobject]@{
    classification = $classification
    recovery_run_id = $recoveryRunId
    recovery_root = $recoveryRoot
    result_path = $resultPath
    summary_path = $summaryPath
    result = $result
}
if ($PassThru) { Write-Output $output }

if ($classification -notin @('ALREADY_CONFIGURED_RUNTIME_PENDING','RECOVERED_DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING')) {
    throw "AutoLogon recovery did not reach a successful terminal classification: $classification"
}
