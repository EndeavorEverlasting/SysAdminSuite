#Requires -Version 5.1
<#
.SYNOPSIS
Close one exact interrupted AutoLogon S4U probe run without launching AutoLogon.

.DESCRIPTION
Uses only recorded exact run/task identity. Re-proves the protected network, retrieves an exact
probe result when one exists, queries/deletes/verifies only the recorded probe task through bounded
schtasks, proves local evidence never entered installer phase, inventories/removes only the exact
recorded remote S4U run root under the ProbeOnly artifact profile, verifies absence, and writes a
terminal recovery result into the preserved local run evidence.

A terminal pilot result is accepted only when it is the exact same run/target/task, classified
S4U_PROBE_CREATE_TIMEOUT, contains no installer/after-state/reboot proof, and records verified
outer staging cleanup. Any other terminal result fails closed.

This command never launches the AutoLogon installer and never broadens cleanup beyond the recorded
task name and recorded run root.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ComputerName,
    [Parameter(Mandatory = $true)][ValidatePattern('^autologon-kerberos-s4u-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$')][string]$RunId,
    [Parameter(Mandatory = $true)][ValidatePattern('^SysAdminSuite-AutoLogonS4UProbe-[0-9a-f]{32}$')][string]$TaskName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$LocalS4URoot,
    [Parameter(Mandatory = $true)][switch]$ConfirmRecovery,
    [ValidateRange(5,60)][int]$TimeoutSeconds = 20
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmRecovery) { throw 'Exact interrupted S4U recovery requires -ConfirmRecovery.' }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$networkGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasNetworkGuard.psm1'
$boundedNativeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasBoundedNative.psm1'
$cleanupScript = Join-Path -Path $PSScriptRoot -ChildPath 'Remove-SasExactRemoteAutoLogonRunRoot.ps1'
foreach ($required in @($networkGuardModule,$boundedNativeModule,$cleanupScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing interrupted S4U recovery dependency: $required" }
}
Import-Module $networkGuardModule -Force
Import-Module $boundedNativeModule -Force

function Get-SasOptionalJsonString {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $Object) { return '' }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return [string]$property.Value
}

function Test-SasExactTerminalProbeCreateTimeoutRecoverable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedTaskName,
        [Parameter(Mandatory = $true)][string]$ExpectedTarget,
        [Parameter(Mandatory = $true)][ref]$Classification
    )

    $Classification.Value = ''
    try {
        $terminal = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $schema = Get-SasOptionalJsonString -Object $terminal -Name 'schema_version'
        $classification = Get-SasOptionalJsonString -Object $terminal -Name 'classification'
        $terminalRunId = Get-SasOptionalJsonString -Object $terminal -Name 'run_id'
        $terminalTarget = (Get-SasOptionalJsonString -Object $terminal -Name 'target').Trim().TrimEnd('.')
        $expectedTargetNormalized = $ExpectedTarget.Trim().TrimEnd('.')
        $probeProperty = $terminal.PSObject.Properties['probe']
        $installProperty = $terminal.PSObject.Properties['install']
        $installerExitProperty = $terminal.PSObject.Properties['installer_exit_code']
        $afterPathProperty = $terminal.PSObject.Properties['after_snapshot_path']
        $preRebootProperty = $terminal.PSObject.Properties['pre_reboot_autologon_ready']
        $cleanupProperty = $terminal.PSObject.Properties['staging_cleanup_verified']
        $rebootProperty = $terminal.PSObject.Properties['automatic_reboot_performed']
        $signInProperty = $terminal.PSObject.Properties['automatic_sign_in_observed']

        if ($schema -ne 'sas-autologon-kerberos-s4u-pilot-result/v2' -or
            $classification -ne 'S4U_PROBE_CREATE_TIMEOUT' -or
            $terminalRunId -ne $ExpectedRunId -or
            -not $terminalTarget.Equals($expectedTargetNormalized, [StringComparison]::OrdinalIgnoreCase) -or
            $null -eq $probeProperty -or $null -eq $probeProperty.Value -or
            $null -eq $installProperty -or $null -ne $installProperty.Value -or
            $null -eq $installerExitProperty -or $null -ne $installerExitProperty.Value -or
            $null -eq $afterPathProperty -or -not [string]::IsNullOrWhiteSpace([string]$afterPathProperty.Value) -or
            $null -eq $preRebootProperty -or [bool]$preRebootProperty.Value -or
            $null -eq $cleanupProperty -or -not [bool]$cleanupProperty.Value -or
            $null -eq $rebootProperty -or [bool]$rebootProperty.Value -or
            $null -eq $signInProperty -or [bool]$signInProperty.Value) {
            return $false
        }

        $probe = $probeProperty.Value
        if ((Get-SasOptionalJsonString -Object $probe -Name 'classification') -ne 'S4U_PROBE_CREATE_TIMEOUT' -or
            (Get-SasOptionalJsonString -Object $probe -Name 'run_id') -ne $ExpectedRunId -or
            (Get-SasOptionalJsonString -Object $probe -Name 'task_name') -ne $ExpectedTaskName) {
            return $false
        }

        $Classification.Value = $classification
        return $true
    }
    catch {
        return $false
    }
}

$LocalS4URoot = [IO.Path]::GetFullPath($LocalS4URoot)
if (-not (Test-Path -LiteralPath $LocalS4URoot -PathType Container)) { throw "Recorded local S4U run root does not exist: $LocalS4URoot" }
if ((Split-Path -Leaf $LocalS4URoot) -ne $RunId) { throw "Local S4U run-root leaf does not match the exact RunId: $RunId" }

$evidenceRoot = Join-Path -Path $LocalS4URoot -ChildPath 'evidence'
$actionsRoot = Join-Path -Path $LocalS4URoot -ChildPath 'actions'
$resultPath = Join-Path -Path $LocalS4URoot -ChildPath 's4u_probe_hang_recovery_result.json'
$probeWorker = Join-Path -Path $actionsRoot -ChildPath 's4u-probe-worker.ps1'
$probeResult = Join-Path -Path $evidenceRoot -ChildPath 's4u_probe_result.json'
$installWorker = Join-Path -Path $actionsRoot -ChildPath 's4u-install-worker.ps1'
$installResult = Join-Path -Path $evidenceRoot -ChildPath 's4u_install_result.json'
$installLifecycle = Join-Path -Path $evidenceRoot -ChildPath 's4u_install_lifecycle.json'
$afterSnapshot = Join-Path -Path $evidenceRoot -ChildPath 'after_snapshot.json'
$terminalResult = Join-Path -Path $LocalS4URoot -ChildPath 'autologon_kerberos_s4u_pilot_result.json'

if (-not (Test-Path -LiteralPath $probeWorker -PathType Leaf)) { throw 'Recorded interrupted run does not contain the expected local probe worker.' }
$forbiddenLocal = @($installWorker,$installResult,$installLifecycle,$afterSnapshot)
$presentForbidden = @($forbiddenLocal | Where-Object { Test-Path -LiteralPath $_ })
if ($presentForbidden.Count -gt 0) { throw "Installer/after-state evidence exists; refusing probe-run recovery: $($presentForbidden -join ', ')" }

$terminalPilotResultPresent = (Test-Path -LiteralPath $terminalResult -PathType Leaf)
$terminalPilotClassification = ''
$terminalProbeTimeoutAccepted = $false
if ($terminalPilotResultPresent) {
    $terminalProbeTimeoutAccepted = Test-SasExactTerminalProbeCreateTimeoutRecoverable -Path $terminalResult `
        -ExpectedRunId $RunId -ExpectedTaskName $TaskName -ExpectedTarget $ComputerName `
        -Classification ([ref]$terminalPilotClassification)
    if (-not $terminalProbeTimeoutAccepted) {
        throw 'A terminal S4U pilot result exists but is not the exact safe probe-create-timeout shape; use that result instead of interrupted recovery.'
    }
    Write-Host "Terminal probe-timeout result accepted for exact recovery: $terminalPilotClassification" -ForegroundColor Yellow
}

Write-Host "`n=== EXACT S4U INTERRUPTED-RUN RECOVERY ===" -ForegroundColor Cyan
Assert-SasNorthwellWifi
Write-Host 'Protected network posture: PASS' -ForegroundColor Green

function Test-SasRecoveryTaskAbsentText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot find|does not exist|not exist|cannot find the file|the system cannot find')
}

# Preserve any exact probe result that reached disk before the old transaction was interrupted.
$remoteRunRoot = '\\{0}\C$\ProgramData\SysAdminSuite\AutoLogonKerberosS4U\{1}' -f $ComputerName,$RunId
$remoteProbeResult = Join-Path -Path $remoteRunRoot -ChildPath 's4u-probe-result.json'
$probeEvidenceRecovered = (Test-Path -LiteralPath $probeResult -PathType Leaf)
if (-not $probeEvidenceRecovered) {
    $probePresence = Test-SasBoundedPath -Path $remoteProbeResult -PathType Leaf -TimeoutSeconds $TimeoutSeconds
    if ($probePresence.timed_out) { throw 'Timed out checking the exact remote probe result. No cleanup was attempted.' }
    if (-not $probePresence.succeeded) { throw "Exact remote probe-result check failed: $($probePresence.error)" }
    if ($probePresence.exists) {
        $copy = Copy-SasBoundedFile -Source $remoteProbeResult -Destination $probeResult -TimeoutSeconds $TimeoutSeconds
        if ($copy.timed_out -or -not $copy.succeeded) { throw "Exact probe-result retrieval failed or timed out: $($copy.error)" }
        $probeEvidenceRecovered = $true
        Write-Host "Recovered exact probe result: $probeResult" -ForegroundColor Green
    }
}

$schtasks = Join-Path -Path $env:WINDIR -ChildPath 'System32\schtasks.exe'
$query = Invoke-SasBoundedNative -FilePath $schtasks -Arguments @('/Query','/S',$ComputerName,'/TN',$TaskName) -TimeoutSeconds $TimeoutSeconds
if ([bool]$query.timed_out) { throw "Timed out querying the exact recorded probe task after $TimeoutSeconds seconds." }
$queryText = ([string]$query.output) + "`n" + ([string]$query.error)
$taskInitiallyAbsent = ([int]$query.exit_code -ne 0 -and (Test-SasRecoveryTaskAbsentText -Text $queryText))
$taskInitiallyPresent = ([int]$query.exit_code -eq 0)
if (-not $taskInitiallyAbsent -and -not $taskInitiallyPresent) {
    throw "Exact recorded probe-task query failed unexpectedly. Exit=$($query.exit_code)"
}

$taskDeleteAttempted = $false
$taskDeleteSucceeded = $false
if ($taskInitiallyPresent) {
    Write-Host 'Exact recorded probe task is present; removing only that task.' -ForegroundColor Yellow
    $taskDeleteAttempted = $true
    $delete = Invoke-SasBoundedNative -FilePath $schtasks -Arguments @('/Delete','/S',$ComputerName,'/TN',$TaskName,'/F') -TimeoutSeconds $TimeoutSeconds
    if ([bool]$delete.timed_out) { throw "Timed out deleting the exact recorded probe task after $TimeoutSeconds seconds. Run-root cleanup was not attempted." }
    $deleteText = ([string]$delete.output) + "`n" + ([string]$delete.error)
    $taskDeleteSucceeded = ([int]$delete.exit_code -eq 0 -or (Test-SasRecoveryTaskAbsentText -Text $deleteText))
    if (-not $taskDeleteSucceeded) { throw "Exact recorded probe-task deletion failed. Exit=$($delete.exit_code)" }
}
else {
    Write-Host 'Exact recorded probe task is already absent.' -ForegroundColor Green
}

$verifyTask = Invoke-SasBoundedNative -FilePath $schtasks -Arguments @('/Query','/S',$ComputerName,'/TN',$TaskName) -TimeoutSeconds $TimeoutSeconds
if ([bool]$verifyTask.timed_out) { throw 'Timed out verifying exact recorded probe-task absence before run-root cleanup.' }
$verifyText = ([string]$verifyTask.output) + "`n" + ([string]$verifyTask.error)
$taskAbsentBeforeCleanup = ([int]$verifyTask.exit_code -ne 0 -and (Test-SasRecoveryTaskAbsentText -Text $verifyText))
if (-not $taskAbsentBeforeCleanup) { throw 'Exact recorded probe task still exists; refusing run-root cleanup.' }
Write-Host 'Exact recorded probe task absence: VERIFIED' -ForegroundColor Green

# Probe-only recovery must refuse remote installer artifacts before deletion. The generic cleanup
# helper also serves normal post-install teardown, so select the stricter profile explicitly here.
$cleanup = & $cleanupScript -ComputerName $ComputerName -RunId $RunId -ConfirmExactCleanup -AllowedArtifactProfile ProbeOnly -TimeoutSeconds $TimeoutSeconds
if ([string]$cleanup.classification -ne 'EXACT_REMOTE_AUTOLOGON_RUN_ROOT_CLEANED' -or -not [bool]$cleanup.exact_run_root_absent) {
    throw 'Exact recorded remote S4U probe-only run-root cleanup did not prove absence.'
}
if ([string]$cleanup.allowed_artifact_profile -ne 'ProbeOnly') {
    throw 'Interrupted S4U recovery did not use the required ProbeOnly cleanup profile.'
}
Write-Host 'Exact recorded remote S4U probe-only run root absent: PASS' -ForegroundColor Green

$verify = Invoke-SasBoundedNative -FilePath $schtasks -Arguments @('/Query','/S',$ComputerName,'/TN',$TaskName) -TimeoutSeconds $TimeoutSeconds
if ([bool]$verify.timed_out) { throw 'Timed out verifying exact recorded probe-task absence after cleanup.' }
$taskAbsentAfterCleanup = ([int]$verify.exit_code -ne 0 -and
    (Test-SasRecoveryTaskAbsentText -Text (([string]$verify.output) + "`n" + ([string]$verify.error))))
if (-not $taskAbsentAfterCleanup) { throw 'Exact recorded probe-task absence was not preserved after cleanup.' }

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-s4u-interrupted-recovery/v3'
    status = 'COMPLETED'
    classification = 'S4U_PROBE_CREATE_HANG_RECOVERED'
    target = $ComputerName
    run_id = $RunId
    task_name = $TaskName
    protected_network_verified = $true
    probe_worker_present = $true
    probe_result_present = (Test-Path -LiteralPath $probeResult -PathType Leaf)
    probe_result_recovered_before_cleanup = $probeEvidenceRecovered
    installer_worker_present = $false
    installer_result_present = $false
    installer_lifecycle_present = $false
    after_snapshot_present = $false
    terminal_pilot_result_present = $terminalPilotResultPresent
    terminal_pilot_classification = $terminalPilotClassification
    terminal_probe_timeout_accepted = $terminalProbeTimeoutAccepted
    installer_phase_entered = $false
    task_initially_present = $taskInitiallyPresent
    task_initially_absent = $taskInitiallyAbsent
    task_delete_attempted = $taskDeleteAttempted
    task_delete_succeeded = $taskDeleteSucceeded
    task_absent_before_cleanup = $taskAbsentBeforeCleanup
    task_absent_after_cleanup = $taskAbsentAfterCleanup
    allowed_artifact_profile = [string]$cleanup.allowed_artifact_profile
    exact_run_root_absent = [bool]$cleanup.exact_run_root_absent
    exact_remote_inventory = @($cleanup.inventory_names)
    cleanup_scope = [string]$cleanup.cleanup_scope
    autologon_installer_launched_by_recovered_transaction = $false
    next_action = 'Run AutoLogon once through the supported hardened command after refreshing the intended branch on Guest/Internet.'
    completed_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resultPath -Encoding UTF8

Write-Host "`nS4U_PROBE_CREATE_HANG_RECOVERED" -ForegroundColor Green
Write-Host "Evidence: $resultPath"
$result