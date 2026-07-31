#Requires -Version 5.1
<#
.SYNOPSIS
Apply AutoLogon through Kerberos/S4U and complete deployment by restarting the authorized target.

.DESCRIPTION
The hardened Kerberos/S4U pilot is the apply engine. This wrapper requires its positive clean
pre-reboot state, then creates one bounded SYSTEM restart task on the same authorized target and
waits for the previously proven SMB service to leave and return. All Task Scheduler operations are
bounded and checkpointed. Automatic sign-in is not claimed unless separately observed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [ValidateRange(5,120)]
    [int]$RestartDelaySeconds = 15,

    [ValidateRange(60,900)]
    [int]$RestartTimeoutSeconds = 300,

    [ValidateRange(5,120)]
    [int]$NativeTaskTimeoutSeconds = 30,

    [string]$OutputRoot,
    [switch]$AllowTargetMutation,
    [switch]$ConfirmDeployment,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $AllowTargetMutation -or -not $ConfirmDeployment) {
    throw 'AutoLogon deployment requires both -AllowTargetMutation and -ConfirmDeployment. Use sas autologon Remote HOST.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$s4uScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SasAutoLogonKerberosS4UPilot.ps1'
$boundedNativeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasBoundedNative.psm1'
foreach ($required in @($s4uScript,$boundedNativeModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing AutoLogon S4U dependency: $required"
    }
}
Import-Module $boundedNativeModule -Force

$target = $ComputerName.Trim()
if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw "Invalid Cybernet hostname or FQDN: $target"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey\output\runs\autologon-s4u-deployment'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$runId = 'autologon-s4u-deployment-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path -Path $OutputRoot -ChildPath $runId
$evidenceRoot = Join-Path -Path $runRoot -ChildPath 'evidence'
New-Item -ItemType Directory -Path $runRoot,$evidenceRoot -Force | Out-Null
$resultPath = Join-Path -Path $runRoot -ChildPath 'autologon_s4u_deployment_result.json'

function Save-SasAutoLogonDeploymentResult {
    param([Parameter(Mandatory = $true)]$Value)
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

function Write-SasAutoLogonRestartStage {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(19,22)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('START','PASS','FAIL','INFO')][string]$Status,
        [string]$Detail
    )
    $record = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-s4u-progress/v1'
        run_id = $runId
        stage_number = $Number
        stage_name = $Name
        status = $Status
        detail = $Detail
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path -Path $evidenceRoot -ChildPath 'progress_checkpoint.json') -Encoding UTF8
    ($record | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath (Join-Path -Path $evidenceRoot -ChildPath 'progress_history.jsonl') -Encoding UTF8
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " - $Detail" }
    Write-Host ("[{0}/22] {1}: {2}{3}" -f $Number,$Name,$Status,$suffix) -ForegroundColor Cyan
}

function Test-SasAutoLogonRestartTaskAbsentText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot find|does not exist|not exist|cannot find the file|the system cannot find')
}

function Invoke-SasAutoLogonBoundedTask {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )
    $schtasks = Join-Path -Path $env:WINDIR -ChildPath 'System32\schtasks.exe'
    $native = Invoke-SasBoundedNative -FilePath $schtasks -Arguments $Arguments -TimeoutSeconds $NativeTaskTimeoutSeconds
    if ([bool]$native.timed_out) {
        throw "AutoLogon restart Task Scheduler $Operation timed out after $NativeTaskTimeoutSeconds seconds."
    }
    return $native
}

function Test-SasAutoLogonTcp445 {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [ValidateRange(250,5000)][int]$TimeoutMilliseconds = 1500
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($Target, 445, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) { return $false }
        $client.EndConnect($async)
        return [bool]$client.Connected
    }
    catch { return $false }
    finally { $client.Close() }
}

function Wait-SasAutoLogonRestartOffline {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $deadline = (Get-Date).AddSeconds([Math]::Min(120, $TimeoutSeconds))
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-SasAutoLogonTcp445 -Target $Target)) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Wait-SasAutoLogonRestartOnline {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-SasAutoLogonTcp445 -Target $Target) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Confirm-SasAutoLogonRestartTaskCleanup {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [ValidateRange(10,120)][int]$TimeoutSeconds = 60
    )

    # SMB may return before Task Scheduler RPC is ready. Every individual query remains bounded.
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $taskSeen = $false
    while ((Get-Date) -lt $deadline) {
        $query = Invoke-SasAutoLogonBoundedTask -Operation 'query' -Arguments @('/Query','/S',$Target,'/TN',$TaskName)
        $queryText = ([string]$query.output) + "`n" + ([string]$query.error)
        if ([int]$query.exit_code -ne 0 -and (Test-SasAutoLogonRestartTaskAbsentText -Text $queryText)) {
            return $true
        }
        if ([int]$query.exit_code -eq 0) {
            $taskSeen = $true
            break
        }
        Start-Sleep -Seconds 3
    }

    if (-not $taskSeen) { return $false }

    $delete = Invoke-SasAutoLogonBoundedTask -Operation 'delete' -Arguments @('/Delete','/S',$Target,'/TN',$TaskName,'/F')
    $deleteText = ([string]$delete.output) + "`n" + ([string]$delete.error)
    if ([int]$delete.exit_code -ne 0 -and -not (Test-SasAutoLogonRestartTaskAbsentText -Text $deleteText)) {
        return $false
    }

    $verifyDeadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $verifyDeadline) {
        $verify = Invoke-SasAutoLogonBoundedTask -Operation 'query' -Arguments @('/Query','/S',$Target,'/TN',$TaskName)
        $verifyText = ([string]$verify.output) + "`n" + ([string]$verify.error)
        if ([int]$verify.exit_code -ne 0 -and (Test-SasAutoLogonRestartTaskAbsentText -Text $verifyText)) {
            return $true
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

$result = [ordered]@{
    schema_version = 'sas-autologon-s4u-deployment-result/v2'
    run_id = $runId
    target = $target
    classification = 'AUTOLOGON_DEPLOYMENT_STARTED'
    autologon_applied = $false
    autologon_was_last_software_step = $true
    s4u_result_path = $null
    s4u_classification = $null
    pre_reboot_autologon_ready = $false
    restart_task_name = $null
    restart_task_created = $false
    restart_task_started = $false
    restart_task_cleanup_verified = $false
    restart_delay_seconds = $RestartDelaySeconds
    restart_offline_observed = $false
    restart_online_observed = $false
    automatic_reboot_performed = $false
    automatic_sign_in_observed = $false
    runtime_proof_required_for_deployment_completion = $false
    target_mutation_performed = $false
    native_task_timeout_seconds = $NativeTaskTimeoutSeconds
    status = 'STARTED'
    reason = $null
    result_path = $resultPath
}
Save-SasAutoLogonDeploymentResult -Value $result

$taskCreated = $false
$resolvedTarget = $target
$restartTask = $null

try {
    Write-Host "`n=== AUTOLOGON APPLY: $target ===" -ForegroundColor Cyan
    $s4u = & $s4uScript -ComputerName $target -OutputRoot (Join-Path -Path $runRoot -ChildPath 's4u') `
        -AllowTargetMutation -ConfirmS4U -PassThru

    $result.s4u_result_path = [string]$s4u.result_path
    $result.s4u_classification = [string]$s4u.classification
    $result.pre_reboot_autologon_ready = [bool]$s4u.result.pre_reboot_autologon_ready
    $result.target_mutation_performed = [bool]$s4u.result.target_mutation_performed
    if (-not [string]::IsNullOrWhiteSpace([string]$s4u.result.target)) {
        $resolvedTarget = [string]$s4u.result.target
        $result.target = $resolvedTarget
    }
    Save-SasAutoLogonDeploymentResult -Value $result

    if ([string]$s4u.classification -ne 'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING' -or
        -not [bool]$s4u.result.pre_reboot_autologon_ready -or
        -not [bool]$s4u.result.staging_cleanup_verified) {
        throw "AutoLogon apply did not reach the required clean pre-reboot state: $($s4u.classification)"
    }

    $result.autologon_applied = $true
    $result.classification = 'AUTOLOGON_APPLIED_RESTART_REQUIRED'
    Save-SasAutoLogonDeploymentResult -Value $result

    Write-SasAutoLogonRestartStage -Number 19 -Name 'restart handoff' -Status START
    $restartTask = 'SysAdminSuite-AutoLogonRestart-{0}' -f ([guid]::NewGuid().ToString('N'))
    $result.restart_task_name = $restartTask
    Save-SasAutoLogonDeploymentResult -Value $result

    $startTime = (Get-Date).AddMinutes(2).ToString('HH:mm')
    $restartCommand = 'C:\Windows\System32\shutdown.exe /r /t {0} /f /d p:4:1' -f $RestartDelaySeconds

    Write-Host "`n=== AUTOLOGON RESTART: $resolvedTarget ===" -ForegroundColor Cyan
    $create = Invoke-SasAutoLogonBoundedTask -Operation 'create' -Arguments @(
        '/Create','/S',$resolvedTarget,'/RU','SYSTEM','/SC','ONCE','/ST',$startTime,
        '/TN',$restartTask,'/TR',$restartCommand,'/RL','HIGHEST','/F','/Z'
    )
    if ([int]$create.exit_code -ne 0) {
        throw "Could not create the one-time AutoLogon restart task: $($create.output) $($create.error)"
    }
    $taskCreated = $true
    $result.restart_task_created = $true
    Save-SasAutoLogonDeploymentResult -Value $result

    $run = Invoke-SasAutoLogonBoundedTask -Operation 'run' -Arguments @('/Run','/S',$resolvedTarget,'/TN',$restartTask)
    if ([int]$run.exit_code -ne 0) {
        throw "Could not start the one-time AutoLogon restart task: $($run.output) $($run.error)"
    }
    $result.restart_task_started = $true
    $result.classification = 'AUTOLOGON_RESTART_INITIATED'
    Save-SasAutoLogonDeploymentResult -Value $result
    Write-SasAutoLogonRestartStage -Number 19 -Name 'restart handoff' -Status PASS

    Write-SasAutoLogonRestartStage -Number 20 -Name 'offline observation' -Status START
    $result.restart_offline_observed = Wait-SasAutoLogonRestartOffline -Target $resolvedTarget -TimeoutSeconds $RestartTimeoutSeconds
    Save-SasAutoLogonDeploymentResult -Value $result
    if (-not $result.restart_offline_observed) {
        throw 'Restart task started, but the target did not leave the previously proven SMB service within the bounded observation window.'
    }
    Write-SasAutoLogonRestartStage -Number 20 -Name 'offline observation' -Status PASS

    Write-SasAutoLogonRestartStage -Number 21 -Name 'online observation' -Status START
    $result.restart_online_observed = Wait-SasAutoLogonRestartOnline -Target $resolvedTarget -TimeoutSeconds $RestartTimeoutSeconds
    $result.automatic_reboot_performed = ($result.restart_offline_observed -and $result.restart_online_observed)
    Save-SasAutoLogonDeploymentResult -Value $result
    if (-not $result.restart_online_observed) {
        throw 'Target left for restart but did not return on the previously proven SMB service within the bounded observation window.'
    }
    Write-SasAutoLogonRestartStage -Number 21 -Name 'online observation' -Status PASS

    Write-SasAutoLogonRestartStage -Number 22 -Name 'restart-task cleanup' -Status START
    $result.restart_task_cleanup_verified = Confirm-SasAutoLogonRestartTaskCleanup `
        -Target $resolvedTarget -TaskName $restartTask -TimeoutSeconds 60
    if (-not $result.restart_task_cleanup_verified) {
        throw 'AutoLogon restart completed, but cleanup of the one-time restart task could not be verified after the bounded post-boot Task Scheduler recovery window.'
    }
    Write-SasAutoLogonRestartStage -Number 22 -Name 'restart-task cleanup' -Status PASS

    $result.classification = 'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED'
    $result.status = 'COMPLETED'
    $result.reason = $null
    Save-SasAutoLogonDeploymentResult -Value $result

    Write-Host "`nAUTOLOGON DEPLOYMENT COMPLETED AND TARGET RESTARTED." -ForegroundColor Green
    Write-Host "Target: $resolvedTarget" -ForegroundColor Green
    Write-Host 'AutoLogon was the final software step and the restart cycle was observed.' -ForegroundColor Green
    Write-Host "Evidence: $resultPath"
    Write-Host 'Runtime proof remains available when explicitly requested, but it is not a prerequisite for deployment completion.' -ForegroundColor Cyan
}
catch {
    $result.status = 'ACTION_REQUIRED'
    $result.reason = $_.Exception.Message
    if ([string]$result.classification -eq 'AUTOLOGON_DEPLOYMENT_STARTED') {
        $result.classification = 'AUTOLOGON_DEPLOYMENT_FAILED'
    }
    elseif ([string]$result.classification -eq 'AUTOLOGON_APPLIED_RESTART_REQUIRED') {
        $result.classification = 'AUTOLOGON_RESTART_FAILED'
    }
    elseif ([string]$result.classification -eq 'AUTOLOGON_RESTART_INITIATED') {
        $result.classification = 'AUTOLOGON_RESTART_RECOVERY_UNCONFIRMED'
    }
    Save-SasAutoLogonDeploymentResult -Value $result
    Write-Host "`nACTION REQUIRED: $($result.reason)" -ForegroundColor Yellow
    Write-Host "Evidence: $resultPath"
    throw
}
finally {
    if ($taskCreated -and $restartTask -and -not [bool]$result.restart_task_cleanup_verified -and -not [bool]$result.restart_offline_observed) {
        try {
            [void](Invoke-SasAutoLogonBoundedTask -Operation 'delete' -Arguments @('/Delete','/S',$resolvedTarget,'/TN',$restartTask,'/F'))
        }
        catch { }
    }
}

if ($PassThru) { return [pscustomobject]$result }
exit 0
