#Requires -Version 5.1
<#
.SYNOPSIS
Close one exact interrupted AutoLogon S4U probe-create hang without launching AutoLogon.

.DESCRIPTION
Uses only recorded exact run/task identity. Re-proves the protected network, verifies the recorded
probe task is absent through bounded schtasks, proves local evidence never entered installer phase,
inventories/removes only the exact recorded remote S4U run root, verifies absence, and writes a
terminal recovery result into the preserved local run evidence.

This command never launches the AutoLogon installer.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^autologon-kerberos-s4u-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^SysAdminSuite-AutoLogonS4UProbe-[0-9a-f]{32}$')]
    [string]$TaskName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LocalS4URoot,

    [Parameter(Mandatory = $true)]
    [switch]$ConfirmRecovery,

    [ValidateRange(5,60)]
    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmRecovery) {
    throw 'Exact interrupted S4U recovery requires -ConfirmRecovery.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$networkGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasNetworkGuard.psm1'
$boundedNativeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasBoundedNative.psm1'
$cleanupScript = Join-Path -Path $PSScriptRoot -ChildPath 'Remove-SasExactRemoteAutoLogonRunRoot.ps1'
foreach ($required in @($networkGuardModule,$boundedNativeModule,$cleanupScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing interrupted S4U recovery dependency: $required"
    }
}
Import-Module $networkGuardModule -Force
Import-Module $boundedNativeModule -Force

$LocalS4URoot = [IO.Path]::GetFullPath($LocalS4URoot)
if (-not (Test-Path -LiteralPath $LocalS4URoot -PathType Container)) {
    throw "Recorded local S4U run root does not exist: $LocalS4URoot"
}
if ((Split-Path -Leaf $LocalS4URoot) -ne $RunId) {
    throw "Local S4U run-root leaf does not match the exact RunId: $RunId"
}

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

if (-not (Test-Path -LiteralPath $probeWorker -PathType Leaf)) {
    throw 'Recorded interrupted run does not contain the expected local probe worker.'
}
$forbiddenLocal = @($installWorker,$installResult,$installLifecycle,$afterSnapshot)
$presentForbidden = @($forbiddenLocal | Where-Object { Test-Path -LiteralPath $_ })
if ($presentForbidden.Count -gt 0) {
    throw "Installer/after-state evidence exists; refusing probe-create-hang recovery: $($presentForbidden -join ', ')"
}
if (Test-Path -LiteralPath $terminalResult -PathType Leaf) {
    throw 'A terminal S4U pilot result already exists; use that result instead of the interrupted probe-hang recovery helper.'
}

Write-Host "`n=== EXACT S4U PROBE-HANG RECOVERY ===" -ForegroundColor Cyan
Assert-SasNorthwellWifi
Write-Host 'Protected network posture: PASS' -ForegroundColor Green

function Test-SasRecoveryTaskAbsentText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot find|does not exist|not exist|cannot find the file|the system cannot find')
}

$schtasks = Join-Path -Path $env:WINDIR -ChildPath 'System32\schtasks.exe'
$query = Invoke-SasBoundedNative -FilePath $schtasks -Arguments @('/Query','/S',$ComputerName,'/TN',$TaskName) -TimeoutSeconds $TimeoutSeconds
if ([bool]$query.timed_out) {
    throw "Timed out querying the exact recorded probe task after $TimeoutSeconds seconds."
}
$taskAbsentBeforeCleanup = ([int]$query.exit_code -ne 0 -and
    (Test-SasRecoveryTaskAbsentText -Text (([string]$query.output) + "`n" + ([string]$query.error))))
if (-not $taskAbsentBeforeCleanup) {
    throw 'Exact recorded probe task is present or its absence could not be proven. Refusing staging cleanup.'
}
Write-Host 'Exact recorded probe task absent: PASS' -ForegroundColor Green

$cleanup = & $cleanupScript -ComputerName $ComputerName -RunId $RunId -ConfirmExactCleanup -TimeoutSeconds $TimeoutSeconds
if ([string]$cleanup.classification -ne 'EXACT_REMOTE_AUTOLOGON_RUN_ROOT_CLEANED' -or
    -not [bool]$cleanup.exact_run_root_absent) {
    throw 'Exact recorded remote S4U run-root cleanup did not prove absence.'
}
Write-Host 'Exact recorded remote S4U run root absent: PASS' -ForegroundColor Green

$verify = Invoke-SasBoundedNative -FilePath $schtasks -Arguments @('/Query','/S',$ComputerName,'/TN',$TaskName) -TimeoutSeconds $TimeoutSeconds
if ([bool]$verify.timed_out) {
    throw "Timed out verifying exact recorded probe-task absence after cleanup."
}
$taskAbsentAfterCleanup = ([int]$verify.exit_code -ne 0 -and
    (Test-SasRecoveryTaskAbsentText -Text (([string]$verify.output) + "`n" + ([string]$verify.error))))
if (-not $taskAbsentAfterCleanup) {
    throw 'Exact recorded probe-task absence was not preserved after cleanup.'
}

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-s4u-interrupted-recovery/v1'
    status = 'COMPLETED'
    classification = 'S4U_PROBE_CREATE_HANG_RECOVERED'
    target = $ComputerName
    run_id = $RunId
    task_name = $TaskName
    protected_network_verified = $true
    probe_worker_present = $true
    probe_result_present = (Test-Path -LiteralPath $probeResult -PathType Leaf)
    installer_worker_present = $false
    installer_result_present = $false
    installer_lifecycle_present = $false
    after_snapshot_present = $false
    terminal_pilot_result_present = $false
    installer_phase_entered = $false
    task_absent_before_cleanup = $taskAbsentBeforeCleanup
    task_absent_after_cleanup = $taskAbsentAfterCleanup
    exact_run_root_absent = [bool]$cleanup.exact_run_root_absent
    exact_remote_inventory = @($cleanup.inventory_names)
    cleanup_scope = [string]$cleanup.cleanup_scope
    autologon_installer_launched_by_recovered_transaction = $false
    next_action = 'Refresh to merged trusted head, re-read baseline/eligibility/network state, then run AutoLogon once through the supported hardened command.'
    completed_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resultPath -Encoding UTF8

Write-Host "`nS4U_PROBE_CREATE_HANG_RECOVERED" -ForegroundColor Green
Write-Host "Evidence: $resultPath"
$result
