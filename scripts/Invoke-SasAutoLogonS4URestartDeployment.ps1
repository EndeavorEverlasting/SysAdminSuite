#Requires -Version 5.1
<#
.SYNOPSIS
Apply AutoLogon through Kerberos/S4U and complete deployment by restarting the authorized target.

.DESCRIPTION
The existing Kerberos/S4U pilot is the apply engine. This wrapper requires its positive clean
pre-reboot state, then creates one bounded SYSTEM restart task on the same authorized target and
waits for the previously proven SMB service to leave and return. AutoLogon deployment is therefore
not reported complete before the required restart cycle occurs.

No fixture, transport live-cert, or technician runtime-proof loop is required for deployment
completion. Automatic sign-in is not claimed unless separately observed.
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

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$s4uScript = Join-Path $PSScriptRoot 'Invoke-SasAutoLogonKerberosS4UPilot.ps1'
if (-not (Test-Path -LiteralPath $s4uScript -PathType Leaf)) {
    throw "Missing AutoLogon S4U dependency: $s4uScript"
}

$target = $ComputerName.Trim()
if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw "Invalid Cybernet hostname or FQDN: $target"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey\output\runs\autologon-s4u-deployment'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$runId = 'autologon-s4u-deployment-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultPath = Join-Path $runRoot 'autologon_s4u_deployment_result.json'

function Save-SasAutoLogonDeploymentResult {
    param([Parameter(Mandatory = $true)]$Value)
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

function Invoke-SasAutoLogonDeploymentNative {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $lines = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    [pscustomobject]@{
        exit_code = [int]$LASTEXITCODE
        output = ($lines -join [Environment]::NewLine)
    }
}

function Test-SasAutoLogonRestartTaskAbsentText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot find|does not exist|not exist|cannot find the file|the system cannot find')
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

function Wait-SasAutoLogonRestartCycle {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $offlineObserved = $false
    $offlineDeadline = (Get-Date).AddSeconds([Math]::Min(120, $TimeoutSeconds))
    while ((Get-Date) -lt $offlineDeadline) {
        if (-not (Test-SasAutoLogonTcp445 -Target $Target)) {
            $offlineObserved = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $offlineObserved) {
        throw 'Restart task started, but the target did not leave the previously proven SMB service within the bounded observation window.'
    }

    $onlineObserved = $false
    $onlineDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $onlineDeadline) {
        if (Test-SasAutoLogonTcp445 -Target $Target) {
            $onlineObserved = $true
            break
        }
        Start-Sleep -Seconds 3
    }
    if (-not $onlineObserved) {
        throw 'Target left for restart but did not return on the previously proven SMB service within the bounded observation window.'
    }

    [pscustomobject][ordered]@{
        offline_observed = $offlineObserved
        online_observed = $onlineObserved
        observation = 'tcp_445_restart_cycle'
    }
}

function Confirm-SasAutoLogonRestartTaskCleanup {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$SchtasksPath,
        [ValidateRange(10,120)][int]$TimeoutSeconds = 60
    )

    # SMB often becomes reachable before Task Scheduler RPC is fully ready after boot.
    # Retry bounded queries rather than misclassifying that transient recovery window as cleanup failure.
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $taskSeen = $false
    while ((Get-Date) -lt $deadline) {
        $query = Invoke-SasAutoLogonDeploymentNative -FilePath $SchtasksPath -Arguments @('/Query','/S',$Target,'/TN',$TaskName)
        if ($query.exit_code -ne 0 -and (Test-SasAutoLogonRestartTaskAbsentText -Text $query.output)) {
            return $true
        }
        if ($query.exit_code -eq 0) {
            $taskSeen = $true
            break
        }
        Start-Sleep -Seconds 3
    }

    if (-not $taskSeen) { return $false }

    $delete = Invoke-SasAutoLogonDeploymentNative -FilePath $SchtasksPath -Arguments @('/Delete','/S',$Target,'/TN',$TaskName,'/F')
    if ($delete.exit_code -ne 0 -and -not (Test-SasAutoLogonRestartTaskAbsentText -Text $delete.output)) {
        return $false
    }

    $verifyDeadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $verifyDeadline) {
        $verify = Invoke-SasAutoLogonDeploymentNative -FilePath $SchtasksPath -Arguments @('/Query','/S',$Target,'/TN',$TaskName)
        if ($verify.exit_code -ne 0 -and (Test-SasAutoLogonRestartTaskAbsentText -Text $verify.output)) {
            return $true
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

$result = [ordered]@{
    schema_version = 'sas-autologon-s4u-deployment-result/v1'
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
    status = 'STARTED'
    reason = $null
    result_path = $resultPath
}
Save-SasAutoLogonDeploymentResult -Value $result

$taskCreated = $false
$resolvedTarget = $target
$restartTask = $null
$schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'

try {
    Write-Host "`n=== AUTOLOGON APPLY: $target ===" -ForegroundColor Cyan
    $s4u = & $s4uScript -ComputerName $target -OutputRoot (Join-Path $runRoot 's4u') `
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

    $restartTask = 'SysAdminSuite-AutoLogonRestart-{0}' -f ([guid]::NewGuid().ToString('N'))
    $result.restart_task_name = $restartTask
    $startTime = (Get-Date).AddMinutes(2).ToString('HH:mm')
    $restartCommand = 'C:\Windows\System32\shutdown.exe /r /t {0} /f /d p:4:1' -f $RestartDelaySeconds

    Write-Host "`n=== AUTOLOGON RESTART: $resolvedTarget ===" -ForegroundColor Cyan
    $create = Invoke-SasAutoLogonDeploymentNative -FilePath $schtasks -Arguments @(
        '/Create','/S',$resolvedTarget,'/RU','SYSTEM','/SC','ONCE','/ST',$startTime,
        '/TN',$restartTask,'/TR',$restartCommand,'/RL','HIGHEST','/F','/Z'
    )
    if ($create.exit_code -ne 0) {
        throw "Could not create the one-time AutoLogon restart task: $($create.output)"
    }
    $taskCreated = $true
    $result.restart_task_created = $true
    Save-SasAutoLogonDeploymentResult -Value $result

    $run = Invoke-SasAutoLogonDeploymentNative -FilePath $schtasks -Arguments @('/Run','/S',$resolvedTarget,'/TN',$restartTask)
    if ($run.exit_code -ne 0) {
        throw "Could not start the one-time AutoLogon restart task: $($run.output)"
    }
    $result.restart_task_started = $true
    $result.classification = 'AUTOLOGON_RESTART_INITIATED'
    Save-SasAutoLogonDeploymentResult -Value $result

    $cycle = Wait-SasAutoLogonRestartCycle -Target $resolvedTarget -TimeoutSeconds $RestartTimeoutSeconds
    $result.restart_offline_observed = [bool]$cycle.offline_observed
    $result.restart_online_observed = [bool]$cycle.online_observed
    $result.automatic_reboot_performed = ($result.restart_offline_observed -and $result.restart_online_observed)
    Save-SasAutoLogonDeploymentResult -Value $result

    $result.restart_task_cleanup_verified = Confirm-SasAutoLogonRestartTaskCleanup `
        -Target $resolvedTarget -TaskName $restartTask -SchtasksPath $schtasks -TimeoutSeconds 60
    if (-not $result.restart_task_cleanup_verified) {
        throw 'AutoLogon restart completed, but cleanup of the one-time restart task could not be verified after the bounded post-boot Task Scheduler recovery window.'
    }

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
        try { [void](Invoke-SasAutoLogonDeploymentNative -FilePath $schtasks -Arguments @('/Delete','/S',$resolvedTarget,'/TN',$restartTask,'/F')) }
        catch {}
    }
}

if ($PassThru) { return [pscustomobject]$result }
exit 0
