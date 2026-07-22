#Requires -Version 5.1
<#
.SYNOPSIS
Harmless Kerberos SMB/Remote Task Scheduler transport certification primitives.
.DESCRIPTION
Stages one run-scoped PowerShell worker, runs it noninteractively as LocalSystem,
retrieves and validates its nonce-bound result, and verifies task and staging
teardown. No function accepts credentials, installers, package paths, command
payloads, or transport fallback choices.
#>

Set-StrictMode -Version 2.0

function Test-SasLiveCertFqdn {
    param([Parameter(Mandatory = $true)][string]$ComputerName)
    return ($ComputerName -match '^(?=.{1,253}$)(?=.{1,63}\.)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$')
}

function Assert-SasLiveCertClosedPropertySet {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Role
    )

    if ($null -eq $Value -or $Value -isnot [pscustomobject]) { throw "$Role must be a JSON object." }
    $unknown = @($Value.PSObject.Properties.Name | Where-Object { $Allowed -notcontains $_ })
    if ($unknown.Count -gt 0) { throw "$Role contains unknown properties: $($unknown -join ', ')" }
    $missing = @($Allowed | Where-Object { $Value.PSObject.Properties.Name -notcontains $_ })
    if ($missing.Count -gt 0) { throw "$Role is missing required properties: $($missing -join ', ')" }
}

function Invoke-SasLiveCertSchtasks {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = @(& "$env:WINDIR\System32\schtasks.exe" @Arguments 2>&1 | ForEach-Object { [string]$_ })
    return [pscustomobject]@{
        exit_code = [int]$LASTEXITCODE
        output = ($output -join [Environment]::NewLine)
    }
}

function Test-SasLiveCertTaskAbsentText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot find|does not exist|not exist|cannot find the file')
}

function Test-SasLiveCertTaskNotRunningText {
    param([string]$Text)
    return ([string]$Text -match '(?i)not currently running|is not running|has not yet run|cannot find|does not exist|not exist|cannot find the file')
}

function New-SasLiveCertWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$Nonce,
        [Parameter(Mandatory = $true)][string]$ResultPath
    )

    if ($RunId -notmatch '^transport-live-cert-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { throw 'Live-cert run ID is invalid.' }
    if ($Nonce -notmatch '^[0-9a-f]{32}$') { throw 'Live-cert nonce is invalid.' }

    $configuration = [ordered]@{
        run_id = $RunId
        nonce = $Nonce
        result_path = $ResultPath
    }
    $configurationJson = $configuration | ConvertTo-Json -Depth 4 -Compress
    $configurationBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configurationJson))

    $worker = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$config = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CONFIG_BASE64__'))) | ConvertFrom-Json
$result = [ordered]@{
    schema_version = 'sas-software-deployment-transport-live-cert-worker-result/v1'
    run_id = [string]$config.run_id
    nonce = [string]$config.nonce
    execution_identity_sid = $null
    executed_as_system = $false
    harmless_payload_only = $true
    software_installation_performed = $false
    completed = $false
    error = $null
}
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $result.execution_identity_sid = [string]$identity.User.Value
    $result.executed_as_system = ($result.execution_identity_sid -eq 'S-1-5-18')
    if (-not $result.executed_as_system) { throw 'Harmless certification task did not execute as LocalSystem.' }
    $result.completed = $true
}
catch {
    $result.error = $_.Exception.Message
}
finally {
    $parent = Split-Path -Parent ([string]$config.result_path)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temporary = [string]$config.result_path + '.tmp'
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination ([string]$config.result_path) -Force
}
'@

    $worker.Replace('__CONFIG_BASE64__', $configurationBase64) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-SasLiveCertWorkerResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$Nonce
    )

    Assert-SasLiveCertClosedPropertySet -Value $Result -Allowed @(
        'schema_version','run_id','nonce','execution_identity_sid','executed_as_system',
        'harmless_payload_only','software_installation_performed','completed','error'
    ) -Role 'Live-cert worker result'
    if ([string]$Result.schema_version -ne 'sas-software-deployment-transport-live-cert-worker-result/v1') { throw 'Live-cert worker result schema is unsupported.' }
    if ([string]$Result.run_id -ne $RunId -or [string]$Result.nonce -ne $Nonce) { throw 'Live-cert worker result identity binding is invalid.' }
    if ([string]$Result.execution_identity_sid -notmatch '^S-[0-9-]+$') { throw 'Live-cert worker execution SID is invalid.' }
    foreach ($booleanName in @('executed_as_system','harmless_payload_only','software_installation_performed','completed')) {
        if ($Result.$booleanName -isnot [bool]) { throw "Live-cert worker field $booleanName must be Boolean." }
    }
    $identityIsSystem = ([string]$Result.execution_identity_sid -eq 'S-1-5-18')
    if ([bool]$Result.executed_as_system -ne $identityIsSystem) { throw 'Live-cert worker SYSTEM identity claim is inconsistent with its SID.' }
    if ([bool]$Result.completed -and -not $identityIsSystem) { throw 'Live-cert worker cannot claim completion outside LocalSystem.' }
    if (-not [bool]$Result.harmless_payload_only -or [bool]$Result.software_installation_performed) { throw 'Live-cert worker violated the harmless-payload boundary.' }
    return $true
}

function New-SasLiveCertLifecycleResult {
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$TaskName
    )

    return [ordered]@{
        schema_version = 'sas-software-deployment-transport-live-cert-lifecycle/v1'
        run_id = $RunId
        target = $Target
        selected_transport = 'kerberos_smb_task'
        fallback_attempted = $false
        network_activity_performed = $false
        target_mutation_performed = $false
        worker_integrity = [ordered]@{
            source_sha256 = $null
            staged_sha256 = $null
            verified_before_task_creation = $false
        }
        task = [ordered]@{
            name = $TaskName
            create_attempted = $false
            created = $false
            run_attempted = $false
            started = $false
            end_attempted = $false
            ended_or_not_running = $false
            delete_attempted = $false
            deleted = $false
            absent_verified = $false
        }
        result_retrieval = [ordered]@{
            attempted = $false
            succeeded = $false
            malformed = $false
            nonce_verified = $false
            retrieved_before_teardown = $false
        }
        execution = [ordered]@{
            identity_sid = $null
            as_system = $false
            harmless_payload_only = $true
            software_installation_performed = $false
        }
        cleanup = [ordered]@{
            attempted = $false
            task_deletion_succeeded = $false
            staging_deletion_succeeded = $false
            task_remaining = $false
            staging_remaining = $false
            zero_remnants_verified = $false
        }
        status = 'failed_before_staging'
        error_category = $null
    }
}

function Invoke-SasSoftwareDeploymentTransportLiveCert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$LocalRunRoot,
        [ValidateRange(10, 600)][int]$ResultTimeoutSeconds = 120
    )

    if (-not (Test-SasLiveCertFqdn -ComputerName $ComputerName)) { throw 'Live cert requires the exact authorized FQDN.' }
    if ($RunId -notmatch '^transport-live-cert-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { throw 'Live-cert run ID is invalid.' }
    if (-not (Test-Path -LiteralPath $LocalRunRoot -PathType Container)) { New-Item -ItemType Directory -Path $LocalRunRoot -Force | Out-Null }

    $nonce = [guid]::NewGuid().ToString('N')
    $taskName = 'SysAdminSuite-TransportLiveCert-{0}' -f ([guid]::NewGuid().ToString('N'))
    $result = New-SasLiveCertLifecycleResult -RunId $RunId -Target $ComputerName -TaskName $taskName
    $adminRoot = "\\$ComputerName\ADMIN$"
    $cRoot = "\\$ComputerName\C$"
    $remoteWindowsRoot = "C:\ProgramData\SysAdminSuite\TransportLiveCert\$RunId"
    $remoteUncRoot = Join-Path $cRoot "ProgramData\SysAdminSuite\TransportLiveCert\$RunId"
    $remoteWorker = Join-Path $remoteWindowsRoot 'Invoke-HarmlessTransportCert.ps1'
    $remoteWorkerUnc = Join-Path $remoteUncRoot 'Invoke-HarmlessTransportCert.ps1'
    $remoteResultUnc = Join-Path $remoteUncRoot 'worker-result.json'
    $remoteResult = Join-Path $remoteWindowsRoot 'worker-result.json'
    $localWorker = Join-Path $LocalRunRoot 'harmless-worker.ps1'
    $localResult = Join-Path $LocalRunRoot 'retrieved-worker-result.json'
    $stagingBegan = $false

    try {
        $result.network_activity_performed = $true
        if (-not (Test-Path -LiteralPath $adminRoot -PathType Container)) { throw 'admin_share_unavailable' }
        if (-not (Test-Path -LiteralPath $cRoot -PathType Container)) { throw 'staging_share_unavailable' }

        New-SasLiveCertWorker -Path $localWorker -RunId $RunId -Nonce $nonce -ResultPath $remoteResult
        $result.worker_integrity.source_sha256 = (Get-FileHash -LiteralPath $localWorker -Algorithm SHA256).Hash.ToLowerInvariant()
        New-Item -ItemType Directory -Path $remoteUncRoot -Force -ErrorAction Stop | Out-Null
        $stagingBegan = $true
        $result.target_mutation_performed = $true
        $result.cleanup.staging_remaining = $true
        Copy-Item -LiteralPath $localWorker -Destination $remoteWorkerUnc -Force -ErrorAction Stop
        $result.worker_integrity.staged_sha256 = (Get-FileHash -LiteralPath $remoteWorkerUnc -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.worker_integrity.verified_before_task_creation = ($result.worker_integrity.source_sha256 -eq $result.worker_integrity.staged_sha256)
        if (-not $result.worker_integrity.verified_before_task_creation) { throw 'worker_hash_mismatch' }

        $when = (Get-Date).AddMinutes(1).ToString('HH:mm')
        $taskCommand = ('{0} -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}"' -f "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe", $remoteWorker)
        $result.task.create_attempted = $true
        $create = Invoke-SasLiveCertSchtasks -Arguments @('/Create','/S',$ComputerName,'/RU','SYSTEM','/SC','ONCE','/ST',$when,'/TN',$taskName,'/TR',$taskCommand,'/RL','HIGHEST','/F')
        if ($create.exit_code -ne 0) { throw 'task_creation_failed' }
        $result.task.created = $true
        $result.cleanup.task_remaining = $true

        $result.task.run_attempted = $true
        $run = Invoke-SasLiveCertSchtasks -Arguments @('/Run','/S',$ComputerName,'/TN',$taskName)
        if ($run.exit_code -ne 0) { throw 'task_run_failed' }
        $result.task.started = $true
        $result.status = 'task_started'

        $result.result_retrieval.attempted = $true
        $deadline = (Get-Date).AddSeconds($ResultTimeoutSeconds)
        while (-not (Test-Path -LiteralPath $remoteResultUnc -PathType Leaf)) {
            if ((Get-Date) -ge $deadline) { throw 'result_timeout' }
            Start-Sleep -Seconds 2
        }
        Copy-Item -LiteralPath $remoteResultUnc -Destination $localResult -Force -ErrorAction Stop
        try {
            $workerResult = Get-Content -LiteralPath $localResult -Raw -Encoding UTF8 | ConvertFrom-Json
            $null = Test-SasLiveCertWorkerResult -Result $workerResult -RunId $RunId -Nonce $nonce
        }
        catch {
            $result.result_retrieval.malformed = $true
            throw 'worker_result_invalid'
        }
        $result.result_retrieval.succeeded = $true
        $result.result_retrieval.nonce_verified = $true
        $result.result_retrieval.retrieved_before_teardown = $true
        $result.execution.identity_sid = [string]$workerResult.execution_identity_sid
        $result.execution.as_system = [bool]$workerResult.executed_as_system
        $result.execution.harmless_payload_only = [bool]$workerResult.harmless_payload_only
        $result.execution.software_installation_performed = [bool]$workerResult.software_installation_performed
        if (-not [bool]$workerResult.completed -or -not $result.execution.as_system) { throw 'system_execution_not_proven' }
        $result.status = 'completed_pending_cleanup'
    }
    catch {
        $category = [string]$_.Exception.Message
        if ($category -notmatch '^[a-z0-9_]+$') { $category = 'live_cert_operation_failed' }
        $result.error_category = $category
        if ($result.status -ne 'completed_pending_cleanup') { $result.status = 'certification_failed_pending_cleanup' }
    }
    finally {
        if (Test-Path -LiteralPath $localWorker -PathType Leaf) { Remove-Item -LiteralPath $localWorker -Force -ErrorAction SilentlyContinue }
        if ($stagingBegan -or $result.task.create_attempted) {
            $result.cleanup.attempted = $true
            if ($result.task.create_attempted) {
                $result.task.end_attempted = $true
                $end = Invoke-SasLiveCertSchtasks -Arguments @('/End','/S',$ComputerName,'/TN',$taskName)
                $result.task.ended_or_not_running = ($end.exit_code -eq 0 -or (Test-SasLiveCertTaskNotRunningText -Text $end.output))
                $result.task.delete_attempted = $true
                $delete = Invoke-SasLiveCertSchtasks -Arguments @('/Delete','/S',$ComputerName,'/TN',$taskName,'/F')
                $deleteAccepted = ($delete.exit_code -eq 0 -or (Test-SasLiveCertTaskAbsentText -Text $delete.output))
                $query = Invoke-SasLiveCertSchtasks -Arguments @('/Query','/S',$ComputerName,'/TN',$taskName)
                $result.task.absent_verified = ($query.exit_code -ne 0 -and (Test-SasLiveCertTaskAbsentText -Text $query.output))
                $result.task.deleted = ($result.task.created -and $deleteAccepted -and $result.task.absent_verified)
                $result.cleanup.task_deletion_succeeded = $result.task.deleted
                $result.cleanup.task_remaining = (-not $result.task.absent_verified)
            }

            try {
                if (Test-Path -LiteralPath $remoteUncRoot) { Remove-Item -LiteralPath $remoteUncRoot -Recurse -Force -ErrorAction Stop }
                $result.cleanup.staging_remaining = Test-Path -LiteralPath $remoteUncRoot
                $result.cleanup.staging_deletion_succeeded = (-not $result.cleanup.staging_remaining)
            }
            catch {
                $result.cleanup.staging_remaining = $true
                $result.cleanup.staging_deletion_succeeded = $false
                $result.error_category = 'staging_teardown_failed'
            }
            $taskStoppedForCleanup = ((-not $result.task.create_attempted) -or $result.task.ended_or_not_running)
            $taskAbsentForCleanup = ((-not $result.task.create_attempted) -or $result.task.absent_verified)
            $result.cleanup.zero_remnants_verified = ($taskStoppedForCleanup -and $taskAbsentForCleanup -and -not $result.cleanup.task_remaining -and -not $result.cleanup.staging_remaining)
        }
    }

    $certificationComplete = ($result.task.created -and $result.result_retrieval.succeeded -and
        $result.result_retrieval.nonce_verified -and $result.result_retrieval.retrieved_before_teardown -and
        $result.worker_integrity.verified_before_task_creation -and $result.execution.as_system -and $result.execution.harmless_payload_only -and
        -not $result.execution.software_installation_performed)
    $requiredDeletionComplete = ($result.task.deleted -and $result.cleanup.task_deletion_succeeded)
    $teardownClean = ($result.cleanup.staging_deletion_succeeded -and $result.cleanup.zero_remnants_verified)
    if ($certificationComplete -and $requiredDeletionComplete -and $teardownClean) {
        $result.status = 'certified'
        $result.error_category = $null
    }
    elseif (-not $teardownClean -and ($stagingBegan -or $result.task.create_attempted)) {
        $result.status = 'teardown_failed'
        if (-not $result.error_category) { $result.error_category = 'zero_remnants_not_verified' }
    }
    elseif ($result.status -ne 'failed_before_staging') {
        $result.status = 'certification_failed_cleaned'
    }

    return [pscustomobject]$result
}

function Invoke-SasSoftwareDeploymentTransportLiveCertFixture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)]
        [ValidateSet('success','worker_hash_mismatch','task_creation_failure','task_run_failure','result_timeout','malformed_result','not_system','wrong_nonce','task_deletion_failure','staging_deletion_failure')]
        [string]$Scenario,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    if (-not [IO.Path]::IsPathRooted($FixtureRoot)) { throw 'FixtureRoot must be absolute.' }
    if ($RunId -notmatch '^transport-live-cert-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { throw 'Live-cert run ID is invalid.' }
    New-Item -ItemType Directory -Path $FixtureRoot -Force | Out-Null
    $taskName = 'SysAdminSuite-TransportLiveCert-00000000000000000000000000000000'
    $result = New-SasLiveCertLifecycleResult -RunId $RunId -Target 'fixture-target.example.test' -TaskName $taskName
    $stagingMarker = Join-Path $FixtureRoot 'staging.marker'
    $taskMarker = Join-Path $FixtureRoot 'task.marker'
    $result.task.create_attempted = $true
    [IO.File]::WriteAllText($stagingMarker, 'harmless fixture staging')
    $result.cleanup.attempted = $true
    $result.cleanup.staging_remaining = $true

    $result.worker_integrity.source_sha256 = ('a' * 64)
    $result.worker_integrity.staged_sha256 = if ($Scenario -eq 'worker_hash_mismatch') { ('b' * 64) } else { ('a' * 64) }
    $result.worker_integrity.verified_before_task_creation = ($Scenario -ne 'worker_hash_mismatch')

    if ($Scenario -eq 'worker_hash_mismatch') {
        $result.error_category = 'worker_hash_mismatch'
        $result.task.create_attempted = $false
        $result.task.absent_verified = $true
        Remove-Item -LiteralPath $stagingMarker -Force
        $result.cleanup.staging_deletion_succeeded = $true
        $result.cleanup.staging_remaining = $false
        $result.cleanup.zero_remnants_verified = $true
        $result.status = 'certification_failed_cleaned'
        return [pscustomobject]$result
    }

    if ($Scenario -eq 'task_creation_failure') {
        $result.error_category = 'task_creation_failed'
        $result.task.absent_verified = $true
        $result.task.end_attempted = $true
        $result.task.ended_or_not_running = $true
        Remove-Item -LiteralPath $stagingMarker -Force
        $result.cleanup.staging_deletion_succeeded = $true
        $result.cleanup.staging_remaining = $false
        $result.cleanup.zero_remnants_verified = $true
        $result.status = 'certification_failed_cleaned'
        return [pscustomobject]$result
    }

    [IO.File]::WriteAllText($taskMarker, $taskName)
    $result.task.created = $true
    $result.task.run_attempted = $true
    $result.task.started = ($Scenario -ne 'task_run_failure')
    $result.cleanup.task_remaining = $true

    if ($Scenario -eq 'task_run_failure') { $result.error_category = 'task_run_failed' }
    elseif ($Scenario -eq 'result_timeout') {
        $result.result_retrieval.attempted = $true
        $result.error_category = 'result_timeout'
    }
    elseif ($Scenario -eq 'malformed_result') {
        $result.result_retrieval.attempted = $true
        $result.result_retrieval.malformed = $true
        $result.error_category = 'worker_result_invalid'
    }
    elseif ($Scenario -eq 'wrong_nonce') {
        $result.result_retrieval.attempted = $true
        $result.result_retrieval.malformed = $true
        $result.error_category = 'worker_result_invalid'
    }
    else {
        $result.result_retrieval.attempted = $true
        $result.result_retrieval.succeeded = $true
        $result.result_retrieval.nonce_verified = $true
        $result.result_retrieval.retrieved_before_teardown = $true
        $result.execution.identity_sid = if ($Scenario -eq 'not_system') { 'S-1-5-21-1' } else { 'S-1-5-18' }
        $result.execution.as_system = ($Scenario -ne 'not_system')
        if ($Scenario -eq 'not_system') { $result.error_category = 'system_execution_not_proven' }
    }

    $result.task.delete_attempted = $true
    $result.task.end_attempted = $true
    $result.task.ended_or_not_running = $true
    if ($Scenario -ne 'task_deletion_failure') {
        Remove-Item -LiteralPath $taskMarker -Force
        $result.task.absent_verified = $true
        $result.task.deleted = $true
        $result.cleanup.task_deletion_succeeded = $true
        $result.cleanup.task_remaining = $false
    }
    else { $result.error_category = 'task_teardown_failed' }

    if ($Scenario -ne 'staging_deletion_failure') {
        Remove-Item -LiteralPath $stagingMarker -Force
        $result.cleanup.staging_deletion_succeeded = $true
        $result.cleanup.staging_remaining = $false
    }
    else { $result.error_category = 'staging_teardown_failed' }

    $result.cleanup.zero_remnants_verified = ($result.task.ended_or_not_running -and $result.task.absent_verified -and -not $result.cleanup.task_remaining -and -not $result.cleanup.staging_remaining)
    $certificationComplete = ($result.task.created -and $result.worker_integrity.verified_before_task_creation -and $result.result_retrieval.succeeded -and $result.result_retrieval.nonce_verified -and $result.execution.as_system)
    $teardownComplete = ($result.task.deleted -and $result.cleanup.staging_deletion_succeeded -and $result.cleanup.zero_remnants_verified)
    if ($certificationComplete -and $teardownComplete) {
        $result.status = 'certified'
        $result.error_category = $null
    }
    elseif (-not $teardownComplete) { $result.status = 'teardown_failed' }
    else { $result.status = 'certification_failed_cleaned' }
    return [pscustomobject]$result
}

function New-SasSoftwareDeploymentTransportLiveCertResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Lifecycle,
        [Parameter(Mandatory = $true)]$Preflight
    )

    return [pscustomobject][ordered]@{
        schema_version = 'sas-software-deployment-transport-live-cert-result/v1'
        workflow_id = 'software-deployment-transport-live-cert'
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        decision = [ordered]@{
            preflight_classification = [string]$Preflight.decision.classification
            selected_transport = [string]$Preflight.decision.selected_transport
        }
        certification = [ordered]@{
            task_created = [bool]$Lifecycle.task.created
            executed_as_system = [bool]$Lifecycle.execution.as_system
            result_retrieved = [bool]($Lifecycle.result_retrieval.succeeded -and $Lifecycle.result_retrieval.nonce_verified -and $Lifecycle.result_retrieval.retrieved_before_teardown)
            task_deleted = [bool]($Lifecycle.task.deleted -and $Lifecycle.task.absent_verified)
            staging_deleted = [bool]$Lifecycle.cleanup.staging_deletion_succeeded
            zero_remnants_verified = [bool]$Lifecycle.cleanup.zero_remnants_verified
            software_installation_performed = $false
            harmless_payload_only = $true
        }
        privacy = [ordered]@{
            hostnames_emitted = $false
            usernames_emitted = $false
            ticket_bytes_emitted = $false
            credentials_emitted = $false
            package_paths_emitted = $false
            machine_local_paths_emitted = $false
            raw_evidence_emitted = $false
        }
        network_activity_performed = [bool]$Lifecycle.network_activity_performed
        target_mutation_performed = [bool]$Lifecycle.target_mutation_performed
        proof_ceiling = 'This result certifies only one run-scoped harmless Kerberos SMB scheduled-task lifecycle; it does not prove software installation, WinRM, fleet readiness, or application acceptance.'
    }
}

Export-ModuleMember -Function Test-SasLiveCertFqdn, New-SasLiveCertWorker, Test-SasLiveCertWorkerResult, Invoke-SasSoftwareDeploymentTransportLiveCert, Invoke-SasSoftwareDeploymentTransportLiveCertFixture, New-SasSoftwareDeploymentTransportLiveCertResult
