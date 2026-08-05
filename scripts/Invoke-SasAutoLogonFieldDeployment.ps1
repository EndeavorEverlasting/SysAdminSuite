#Requires -Version 5.1
<#
.SYNOPSIS
Run the supported AutoLogon-only field transaction for one authorized Cybernet.

.DESCRIPTION
Owns the normal product path behind `sas autologon Remote HOST` and the recovery-only
path behind `sas autologon Recover HOST`.

The transaction proves the protected network before DNS/target contact, canonicalizes
the requested target before exact host eligibility inside the apply engine, acquires one
atomic per-target operator lock, converges any safely recorded unfinished probe-only
recovery, refuses to downgrade or repeat durable terminal completion, invokes the
restart-complete S4U deployment exactly once, and persists a terminal field result.
It never deploys the clinical-core package set and never reads DefaultPassword data.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Remote','Recover')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [ValidateRange(5,60)]
    [int]$RecoveryTimeoutSeconds = 20,

    [string]$OutputRoot,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$networkGate = Join-Path -Path $PSScriptRoot -ChildPath 'Confirm-SasNorthwellNetwork.ps1'
$targetModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetNameResolution.psm1'
$sessionModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasOperatorSession.psm1'
$stateModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasAutoLogonOperatorState.psm1'
$recoveryScript = Join-Path -Path $PSScriptRoot -ChildPath 'Recover-SasLatestInterruptedAutoLogonS4U.ps1'
$deploymentScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SasAutoLogonS4URestartDeployment.ps1'

foreach ($required in @($networkGate,$targetModule,$sessionModule,$stateModule,$recoveryScript,$deploymentScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing AutoLogon field-deployment dependency: $required"
    }
}

Import-Module $targetModule -Force
Import-Module $sessionModule -Force
Import-Module $stateModule -Force

$requestedTarget = $ComputerName.Trim().TrimEnd('.')
if ([string]::IsNullOrWhiteSpace($requestedTarget)) {
    throw 'An explicit AutoLogon target is required.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey\output\runs\autologon-field-deployment'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$runId = 'autologon-field-deployment-{0}-{1}' -f (
    (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'),
    ([guid]::NewGuid().ToString('N').Substring(0,8))
)
$runRoot = Join-Path -Path $OutputRoot -ChildPath $runId
$evidenceRoot = Join-Path -Path $runRoot -ChildPath 'evidence'
New-Item -ItemType Directory -Path $runRoot,$evidenceRoot -Force | Out-Null
$resultPath = Join-Path -Path $runRoot -ChildPath 'autologon_field_deployment_result.json'

function Save-SasAutoLogonFieldResult {
    param([Parameter(Mandatory = $true)]$Value)
    $Value.updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    $temporary = $resultPath + '.tmp'
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $resultPath -Force
}

function Get-SasAutoLogonTargetMutexName {
    param([Parameter(Mandatory = $true)][string]$CanonicalTarget)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($CanonicalTarget.Trim().TrimEnd('.').ToLowerInvariant())
        $digest = $algorithm.ComputeHash($bytes)
    }
    finally { $algorithm.Dispose() }
    $token = ([BitConverter]::ToString($digest)).Replace('-','').Substring(0,32)
    return "Local\SysAdminSuite-AutoLogon-$token"
}

function Get-SasLatestInnerDeploymentResult {
    $files = @(
        Get-ChildItem -LiteralPath $runRoot -Filter 'autologon_s4u_deployment_result.json' `
            -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending
    )
    if ($files.Count -eq 0) { return $null }
    try {
        $value = Get-Content -LiteralPath $files[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        return [pscustomobject]@{ path=$files[0].FullName; value=$value }
    }
    catch { return $null }
}

function Copy-SasDeploymentState {
    param(
        [Parameter(Mandatory = $true)]$Destination,
        [AllowNull()]$Source
    )
    if ($null -eq $Source) { return }
    foreach ($name in @(
        'status','classification','target','autologon_applied','pre_reboot_autologon_ready',
        'automatic_reboot_performed','restart_offline_observed','restart_online_observed',
        'restart_task_cleanup_verified','target_mutation_performed','result_path'
    )) {
        $value = Get-SasObjectPropertyValue -Object $Source -Name $name -Default $null
        if ($null -ne $value) {
            switch ($name) {
                'status' { $Destination.deployment_status = $value }
                'classification' { $Destination.deployment_classification = $value }
                'target' { $Destination.final_target = $value }
                'result_path' { $Destination.deployment_result_path = $value }
                default { $Destination[$name] = $value }
            }
        }
    }
}

$result = [ordered]@{
    schema_version = 'sas-autologon-field-deployment-result/v1'
    run_id = $runId
    action = $Action
    requested_target = $requestedTarget
    requested_target_short_name = $requestedTarget.Split('.')[0].ToUpperInvariant()
    resolved_target_fqdn = $null
    resolved_addresses = @()
    resolution_sources = @()
    resolution_evidence_path = $null
    target_lock_name = $null
    target_lock_acquired = $false
    prior_field_result_path = $null
    existing_terminal_result_path = $null
    network_classification = 'UNPROVEN'
    network_gate_completed = $false
    historical_recovery_status = 'UNKNOWN'
    historical_recovery_classification = $null
    historical_recovery_result_path = $null
    recovery_status = $null
    recovery_classification = $null
    recovery_result = $null
    autologon_deployment_started = $false
    autologon_deployment_completed = $false
    apply_invocation_count = 0
    clinical_core_invoked = $false
    deployment_status = $null
    deployment_classification = $null
    deployment_result_path = $null
    final_target = $null
    autologon_applied = $false
    pre_reboot_autologon_ready = $false
    automatic_reboot_performed = $false
    restart_offline_observed = $false
    restart_online_observed = $false
    restart_task_cleanup_verified = $false
    target_mutation_performed = $false
    default_password_value_collected = $false
    status = 'STARTED'
    classification = 'AUTOLOGON_FIELD_DEPLOYMENT_STARTED'
    next_action = $null
    reason = $null
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    updated_at_utc = $null
    result_path = $resultPath
}
Save-SasAutoLogonFieldResult -Value $result

$targetMutex = $null
$targetMutexAcquired = $false
try {
    Write-Host "`n=== PROTECTED NETWORK GATE ===" -ForegroundColor Cyan
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGate `
        -Purpose "AutoLogon $Action for $requestedTarget"
    if ($LASTEXITCODE -ne 0) {
        throw "AutoLogon field deployment stopped by the network gate with exit code $LASTEXITCODE."
    }
    $network = Get-SasOperatorNetworkClassification -RepoRoot $repoRoot
    $result.network_classification = [string]$network.classification
    $result.network_gate_completed = $true
    Save-SasAutoLogonFieldResult -Value $result

    Write-Host "`n=== CANONICAL TARGET RESOLUTION ===" -ForegroundColor Cyan
    $resolution = Resolve-SasCanonicalTargetFqdn -TargetName $requestedTarget
    if (@($resolution.addresses).Count -lt 1) {
        throw 'Canonical target resolution returned no address.'
    }
    $resolvedTarget = [string]$resolution.fqdn
    $resolutionPath = Join-Path -Path $evidenceRoot -ChildPath 'target_resolution.json'
    $resolution | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resolutionPath -Encoding UTF8

    $result.resolved_target_fqdn = $resolvedTarget
    $result.resolved_addresses = @($resolution.addresses)
    $result.resolution_sources = @($resolution.resolution_sources)
    $result.resolution_evidence_path = $resolutionPath
    $result.final_target = $resolvedTarget
    Save-SasAutoLogonFieldResult -Value $result

    $lockName = Get-SasAutoLogonTargetMutexName -CanonicalTarget $resolvedTarget
    $result.target_lock_name = $lockName
    $targetMutex = [System.Threading.Mutex]::new($false, $lockName)
    try { $targetMutexAcquired = $targetMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $targetMutexAcquired = $true }
    if (-not $targetMutexAcquired) {
        throw "Another AutoLogon field transaction already owns canonical target $resolvedTarget."
    }
    $result.target_lock_acquired = $true
    Save-SasAutoLogonFieldResult -Value $result

    [void](Initialize-SasAutoLogonOperatorState -RepoRoot $repoRoot `
        -RequestedTarget $requestedTarget -ResolvedTargetFqdn $resolvedTarget `
        -ResolutionAddresses @($resolution.addresses) -ResolutionSources @($resolution.resolution_sources))

    $priorField = @(Find-SasLatestAutoLogonFieldResult -RepoRoot $repoRoot `
        -Target $resolvedTarget -ExcludePath $resultPath)
    if ($priorField.Count -gt 0) {
        $priorValue = $priorField[0].value
        $result.prior_field_result_path = [string]$priorField[0].path
        $priorStatus = [string](Get-SasObjectPropertyValue $priorValue 'status')
        $priorClassification = [string](Get-SasObjectPropertyValue $priorValue 'classification')
        $priorCompleted = ($priorStatus -eq 'COMPLETED' -and
            $priorClassification -eq 'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED')

        if ($Action -eq 'Remote' -and $priorCompleted) {
            $result.status = 'COMPLETED'
            $result.classification = 'AUTOLOGON_DEPLOYMENT_ALREADY_COMPLETED'
            $result.autologon_deployment_completed = $true
            $result.existing_terminal_result_path = [string]$priorField[0].path
            $result.next_action = 'STOP - durable terminal deployment evidence already exists; do not rerun.'
            Save-SasAutoLogonFieldResult -Value $result
            [void](Set-SasAutoLogonOperatorStateValues -Values @{
                autologon_deployment_started=$true
                autologon_deployment_completed=$true
                latest_status='COMPLETED'
                latest_phase='terminal'
                latest_checkpoint='AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED'
                evidence_path=[string]$priorField[0].path
                next_required_network='NONE'
                next_command='STOP - AutoLogon deployment completed; do not rerun.'
            })
            Write-Host 'AUTOLOGON_DEPLOYMENT_ALREADY_COMPLETED' -ForegroundColor Green
            Write-Host "Existing terminal evidence: $($priorField[0].path)"
            if ($PassThru) { return [pscustomobject]$result }
            return
        }

        $priorStarted = [bool](Get-SasObjectPropertyValue $priorValue 'autologon_deployment_started' $false)
        $priorPostApply = (
            [bool](Get-SasObjectPropertyValue $priorValue 'target_mutation_performed' $false) -or
            [bool](Get-SasObjectPropertyValue $priorValue 'autologon_applied' $false) -or
            [bool](Get-SasObjectPropertyValue $priorValue 'pre_reboot_autologon_ready' $false) -or
            [bool](Get-SasObjectPropertyValue $priorValue 'automatic_reboot_performed' $false) -or
            $priorClassification -eq 'AUTOLOGON_FIELD_POST_APPLY_REVIEW_REQUIRED'
        )
        $priorAmbiguousStarted = ($priorStatus -eq 'STARTED' -and $priorStarted)
        if ($Action -eq 'Remote' -and ($priorPostApply -or $priorAmbiguousStarted)) {
            throw "Prior AutoLogon field evidence requires evidence-led review before any new apply: $($priorField[0].path)"
        }
    }

    $historical = @(Find-SasLatestCompletedAutoLogonRecovery -RepoRoot $repoRoot -Target $resolvedTarget)
    if ($historical.Count -gt 0) {
        $historicalValue = $historical[0].value
        $result.historical_recovery_status = 'COMPLETED'
        $result.historical_recovery_classification = [string](
            Get-SasObjectPropertyValue $historicalValue 'classification'
        )
        $result.historical_recovery_result_path = [string]$historical[0].path
        Save-SasAutoLogonFieldResult -Value $result
    }

    Write-Host "Requested target: $requestedTarget"
    Write-Host "Canonical target: $resolvedTarget" -ForegroundColor Green

    Write-Host "`n=== INTERRUPTED PROBE RECOVERY GATE ===" -ForegroundColor Cyan
    $recovery = & $recoveryScript -ComputerName $resolvedTarget -ConfirmRecovery `
        -TimeoutSeconds $RecoveryTimeoutSeconds -PassThru
    if ($null -eq $recovery -or [string](Get-SasObjectPropertyValue $recovery 'status') -ne 'COMPLETED') {
        throw 'Interrupted-run gate did not return a completed result. AutoLogon apply was not started.'
    }

    $recoveryClassification = [string](Get-SasObjectPropertyValue $recovery 'classification')
    if ($recoveryClassification -notin @(
        'NO_INTERRUPTED_PROBE_RUN_FOUND',
        'INTERRUPTED_PROBE_RUNS_RECOVERED'
    )) {
        throw "Interrupted-run gate returned an unsupported classification: $recoveryClassification"
    }

    $result.recovery_status = 'COMPLETED'
    $result.recovery_classification = $recoveryClassification
    $result.recovery_result = $recovery
    if ($recoveryClassification -eq 'INTERRUPTED_PROBE_RUNS_RECOVERED') {
        $result.historical_recovery_status = 'COMPLETED'
        $result.historical_recovery_classification = $recoveryClassification
    }
    Save-SasAutoLogonFieldResult -Value $result

    [void](Set-SasAutoLogonOperatorStateValues -Values @{
        historical_recovery_status=[string]$result.historical_recovery_status
        historical_recovery_classification=[string]$result.historical_recovery_classification
        historical_recovery_result_path=[string]$result.historical_recovery_result_path
        latest_status='RECOVERY_GATE_COMPLETED'
        latest_phase='recovery_gate'
        latest_checkpoint=$recoveryClassification
        evidence_path=$resultPath
        next_required_network='PROTECTED NORTHWELL'
        next_command=$(if ($Action -eq 'Recover') {
            "sas autologon Remote $requestedTarget"
        } else {
            'STOP - AutoLogon deployment transaction is starting; do not launch a second transaction.'
        })
    })

    if ($Action -eq 'Recover') {
        $result.status = 'COMPLETED'
        $result.classification = $recoveryClassification
        $result.next_action = "sas autologon Remote $requestedTarget"
        Save-SasAutoLogonFieldResult -Value $result
        Write-Host $result.classification -ForegroundColor Green
        Write-Host "Evidence: $resultPath"
        if ($PassThru) { return [pscustomobject]$result }
        return
    }

    $result.autologon_deployment_started = $true
    $result.apply_invocation_count = 1
    $result.classification = 'AUTOLOGON_APPLY_INVOKED'
    $result.next_action = 'STOP - transaction in progress; do not start another AutoLogon deployment.'
    Save-SasAutoLogonFieldResult -Value $result

    [void](Set-SasAutoLogonOperatorStateValues -Values @{
        autologon_deployment_started=$true
        latest_status='STARTED'
        latest_phase='apply'
        latest_checkpoint='AUTOLOGON_APPLY_INVOKED'
        evidence_path=$resultPath
        next_required_network='PROTECTED NORTHWELL'
        next_command='STOP - AutoLogon deployment transaction is in progress; do not rerun.'
    })

    Write-Host "`n=== AUTOLOGON APPLY + BOUNDED RESTART ===" -ForegroundColor Cyan
    $deployment = & $deploymentScript -ComputerName $resolvedTarget `
        -OutputRoot (Join-Path -Path $runRoot -ChildPath 'deployment') `
        -AllowTargetMutation -ConfirmDeployment -PassThru
    if ($null -eq $deployment) {
        throw 'AutoLogon deployment engine returned no structured result.'
    }

    Copy-SasDeploymentState -Destination $result -Source $deployment
    if ([string]$result.deployment_status -ne 'COMPLETED' -or
        [string]$result.deployment_classification -ne 'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED' -or
        -not [bool]$result.autologon_applied -or
        -not [bool]$result.pre_reboot_autologon_ready -or
        -not [bool]$result.automatic_reboot_performed -or
        -not [bool]$result.restart_offline_observed -or
        -not [bool]$result.restart_online_observed -or
        -not [bool]$result.restart_task_cleanup_verified -or
        -not [bool]$result.target_mutation_performed) {
        throw 'AutoLogon deployment engine did not satisfy the restart-complete terminal contract.'
    }

    $result.status = 'COMPLETED'
    $result.classification = 'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED'
    $result.autologon_deployment_completed = $true
    $result.final_target = $resolvedTarget
    $result.next_action = 'STOP - deployment is complete. Do not run AutoLogon again.'
    Save-SasAutoLogonFieldResult -Value $result

    [void](Set-SasAutoLogonOperatorStateValues -Values @{
        autologon_deployment_started=$true
        autologon_deployment_completed=$true
        latest_status='COMPLETED'
        latest_phase='terminal'
        latest_checkpoint='AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED'
        latest_run_id=$runId
        target_mutation_performed=$true
        evidence_path=$resultPath
        next_required_network='NONE'
        next_command='STOP - AutoLogon deployment completed; do not rerun.'
    })

    Write-Host "`nAUTOLOGON_DEPLOYMENT_RESTART_COMPLETED" -ForegroundColor Green
    Write-Host "Requested target: $requestedTarget"
    Write-Host "Final target: $resolvedTarget"
    Write-Host "Evidence: $resultPath"
}
catch {
    $inner = Get-SasLatestInnerDeploymentResult
    if ($null -ne $inner) {
        Copy-SasDeploymentState -Destination $result -Source $inner.value
        $result.deployment_result_path = $inner.path
    }

    $result.status = 'ACTION_REQUIRED'
    $mustStop = ([bool]$result.target_mutation_performed -or
        [bool]$result.autologon_applied -or
        [bool]$result.pre_reboot_autologon_ready -or
        [bool]$result.automatic_reboot_performed -or
        [bool]$result.restart_offline_observed -or
        [bool]$result.restart_online_observed)
    if ($_.Exception.Message -like 'Another AutoLogon field transaction already owns canonical target*') {
        $result.classification = 'AUTOLOGON_FIELD_TARGET_LOCKED'
    }
    elseif ($mustStop) {
        $result.classification = 'AUTOLOGON_FIELD_POST_APPLY_REVIEW_REQUIRED'
    }
    elseif ([bool]$result.autologon_deployment_started) {
        $result.classification = 'AUTOLOGON_FIELD_PRE_APPLY_ENGINE_BLOCKED'
    }
    elseif ([string]$result.classification -eq 'AUTOLOGON_FIELD_DEPLOYMENT_STARTED') {
        $result.classification = 'AUTOLOGON_FIELD_PREFLIGHT_BLOCKED'
    }
    else {
        $result.classification = 'AUTOLOGON_FIELD_RECOVERY_GATE_BLOCKED'
    }
    $result.reason = $_.Exception.Message

    $result.next_action = if ($result.classification -eq 'AUTOLOGON_FIELD_TARGET_LOCKED') {
        'STOP - another AutoLogon transaction owns this canonical target; do not start a second transaction.'
    } elseif ($mustStop -or $result.reason -like 'Prior AutoLogon field evidence requires evidence-led review*') {
        "STOP - inspect durable evidence at $resultPath; do not rerun."
    } else {
        "Fix the pre-apply defect, then rerun once: sas autologon Remote $requestedTarget"
    }
    Save-SasAutoLogonFieldResult -Value $result

    [void](Set-SasAutoLogonOperatorStateValues -Values @{
        autologon_deployment_started=[bool]$result.autologon_deployment_started
        autologon_deployment_completed=$false
        latest_status='ACTION_REQUIRED'
        latest_phase=$(if ($mustStop) { 'post_apply_review' } else { 'pre_apply_blocked' })
        latest_checkpoint=[string]$result.classification
        target_mutation_performed=[bool]$result.target_mutation_performed
        evidence_path=$resultPath
        next_required_network=$(if ($mustStop -or $result.classification -eq 'AUTOLOGON_FIELD_TARGET_LOCKED') { 'NONE' } else { 'PROTECTED NORTHWELL' })
        next_command=[string]$result.next_action
    })

    Write-Host "`nACTION REQUIRED: $($result.reason)" -ForegroundColor Yellow
    Write-Host "Classification: $($result.classification)"
    Write-Host "Evidence: $resultPath"
    throw
}
finally {
    if ($targetMutexAcquired -and $null -ne $targetMutex) {
        try { $targetMutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $targetMutex) { $targetMutex.Dispose() }
}

if ($PassThru) { return [pscustomobject]$result }
return
