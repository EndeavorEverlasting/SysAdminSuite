#Requires -Version 5.1
<#
.SYNOPSIS
Bounded transport selection and Kerberos SMB/Remote Task Scheduler deployment adapter.
.DESCRIPTION
Consumes the frozen P02 preflight result, stages one pinned installer plus one
transient worker, executes the worker once as SYSTEM, retrieves a closed result,
and removes the unique task and run root. The module has no credential parameters
and never falls back to another transport after selection.
#>

Set-StrictMode -Version 2.0

function Test-SasDeploymentFqdn {
    param([Parameter(Mandatory = $true)][string]$ComputerName)
    return ($ComputerName -match '^(?=.{1,253}$)(?=.{1,63}\.)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$')
}

function Assert-SasClosedPropertySet {
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

function Read-SasDeploymentTransportPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateRange(1, 1440)][int]$MaxAgeMinutes,
        [switch]$AllowFixture
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Transport preflight result not found: $Path" }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $age = (Get-Date).ToUniversalTime() - $item.LastWriteTimeUtc
    if ($age.TotalMinutes -lt -1 -or $age.TotalMinutes -gt $MaxAgeMinutes) {
        throw "Transport preflight result is stale or has an invalid timestamp; maximum age is $MaxAgeMinutes minutes."
    }

    try { $result = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Transport preflight result is malformed JSON: $($_.Exception.Message)" }

    Assert-SasClosedPropertySet -Value $result -Allowed @(
        'schema_version','workflow_id','evidence_class','target_scope','observations','decision','proof',
        'network_activity_performed','target_mutation_performed','proof_ceiling'
    ) -Role 'Transport preflight result'
    Assert-SasClosedPropertySet -Value $result.target_scope -Allowed @('target_count','identifier_emitted') -Role 'Transport target scope'
    Assert-SasClosedPropertySet -Value $result.observations -Allowed @('dns','identity','service_tickets','tcp','winrm_session','admin_share','schedule_service','scheduled_task_query') -Role 'Transport observations'
    Assert-SasClosedPropertySet -Value $result.observations.dns -Allowed @('attempted','resolved','address_count','timed_out') -Role 'DNS observation'
    Assert-SasClosedPropertySet -Value $result.observations.identity -Allowed @('domain_joined','tgt_present','ticket_bytes_emitted') -Role 'Identity observation'
    Assert-SasClosedPropertySet -Value $result.observations.service_tickets -Allowed @('http','host','cifs') -Role 'Service-ticket observations'
    foreach ($ticketName in @('http','host','cifs')) {
        Assert-SasClosedPropertySet -Value $result.observations.service_tickets.$ticketName -Allowed @('requested','issued','ticket_bytes_emitted') -Role "$ticketName ticket observation"
    }
    Assert-SasClosedPropertySet -Value $result.observations.tcp -Allowed @('port_5985','port_5986','port_445','port_135') -Role 'TCP observations'
    foreach ($portName in @('port_5985','port_5986','port_445','port_135')) {
        Assert-SasClosedPropertySet -Value $result.observations.tcp.$portName -Allowed @('tested','reachable','timed_out') -Role "$portName observation"
    }
    foreach ($authorizationName in @('winrm_session','admin_share')) {
        Assert-SasClosedPropertySet -Value $result.observations.$authorizationName -Allowed @('attempted','authorized','authorization_denied') -Role "$authorizationName observation"
    }
    Assert-SasClosedPropertySet -Value $result.observations.schedule_service -Allowed @('queried','running','authorization_denied') -Role 'Schedule service observation'
    Assert-SasClosedPropertySet -Value $result.observations.scheduled_task_query -Allowed @('queried','succeeded','authorization_denied') -Role 'Scheduled-task query observation'
    Assert-SasClosedPropertySet -Value $result.decision -Allowed @('classification','selected_transport','reason_codes','silent_fallback_permitted','fallback_after_mutation_permitted') -Role 'Transport decision'
    Assert-SasClosedPropertySet -Value $result.proof -Allowed @('preflight_complete','transport_authorization_proven','task_creation_proven','system_execution_proven','result_retrieval_proven','cleanup_proven','live_runtime') -Role 'Transport proof'
    if ([string]$result.schema_version -ne 'sas-software-deployment-transport-result/v1' -or
        [string]$result.workflow_id -ne 'software-deployment-transport') {
        throw 'Transport preflight result schema is unsupported.'
    }
    if ([string]$result.evidence_class -eq 'sanitized_fixture' -and -not $AllowFixture) {
        throw 'Sanitized fixture preflight cannot authorize live deployment.'
    }
    if ([string]$result.evidence_class -notin @('sanitized_fixture','operator_local_live')) { throw 'Transport preflight evidence class is invalid.' }
    if ([int]$result.target_scope.target_count -ne 1 -or [bool]$result.target_scope.identifier_emitted) {
        throw 'Each deployment target requires one identifier-free single-target P02 result.'
    }
    if ([bool]$result.target_mutation_performed -or
        [bool]$result.proof.task_creation_proven -or
        [bool]$result.proof.system_execution_proven -or
        [bool]$result.proof.result_retrieval_proven -or
        [bool]$result.proof.cleanup_proven) {
        throw 'P02 preflight result contains an impossible mutation or execution proof claim.'
    }
    if ([bool]$result.decision.silent_fallback_permitted -or [bool]$result.decision.fallback_after_mutation_permitted) {
        throw 'Transport preflight result permits forbidden fallback.'
    }

    $transportModule = Join-Path $PSScriptRoot 'SasSoftwareDeploymentTransport.psm1'
    Import-Module $transportModule -Force
    $reclassified = New-SasSoftwareDeploymentTransportResult `
        -Observations $result.observations `
        -EvidenceClass ([string]$result.evidence_class) `
        -NetworkActivityPerformed ([bool]$result.network_activity_performed)
    if ([string]$reclassified.decision.classification -ne [string]$result.decision.classification -or
        [string]$reclassified.decision.selected_transport -ne [string]$result.decision.selected_transport -or
        ((@($reclassified.decision.reason_codes) | Sort-Object) -join ',') -ne ((@($result.decision.reason_codes) | Sort-Object) -join ',') -or
        [bool]$reclassified.proof.preflight_complete -ne [bool]$result.proof.preflight_complete -or
        [bool]$reclassified.proof.transport_authorization_proven -ne [bool]$result.proof.transport_authorization_proven) {
        throw 'Transport preflight result is inconsistent with its observations.'
    }
    return $result
}

function Resolve-SasSoftwareDeploymentTransport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Auto','WinRM','SmbScheduledTask')][string]$Transport,
        [string]$PreflightResultPath,
        [ValidateRange(1, 1440)][int]$PreflightMaxAgeMinutes = 15,
        [switch]$AllowFixturePreflight
    )

    $preflight = $null
    if ($Transport -eq 'Auto' -or -not [string]::IsNullOrWhiteSpace($PreflightResultPath)) {
        if ([string]::IsNullOrWhiteSpace($PreflightResultPath)) { throw 'Auto transport requires a fresh schema-valid P02 result.' }
        $preflight = Read-SasDeploymentTransportPreflight -Path $PreflightResultPath -MaxAgeMinutes $PreflightMaxAgeMinutes -AllowFixture:$AllowFixturePreflight
    }

    $selected = $Transport
    if ($Transport -eq 'Auto') {
        switch ([string]$preflight.decision.selected_transport) {
            'winrm' { $selected = 'WinRM' }
            'kerberos_smb_task' { $selected = 'SmbScheduledTask' }
            default { throw "P02 did not select an executable transport: $($preflight.decision.classification)" }
        }
    }
    elseif ($preflight) {
        $expected = if ($Transport -eq 'WinRM') { 'winrm' } else { 'kerberos_smb_task' }
        if ([string]$preflight.decision.selected_transport -ne $expected -or
            -not [bool]$preflight.proof.preflight_complete -or
            -not [bool]$preflight.proof.transport_authorization_proven) {
            throw "Explicit transport $Transport conflicts with the supplied P02 decision."
        }
    }

    [pscustomobject][ordered]@{
        requested_transport = $Transport
        selected_transport = $selected
        preflight_consumed = ($null -ne $preflight)
        preflight_classification = if ($preflight) { [string]$preflight.decision.classification } else { $null }
        selected_before_mutation = $true
        silent_fallback_permitted = $false
        fallback_after_mutation_permitted = $false
    }
}

function Invoke-SasSchtasksCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = @(& "$env:WINDIR\System32\schtasks.exe" @Arguments 2>&1 | ForEach-Object { [string]$_ })
    [pscustomobject]@{ exit_code = [int]$LASTEXITCODE; output = ($output -join [Environment]::NewLine) }
}

function Test-SasTaskAbsentText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot find|does not exist|not exist|cannot find the file')
}

function New-SasSmbTaskWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string[]]$InstallerArguments,
        [Parameter(Mandatory = $true)]$ValidationChecks,
        [Parameter(Mandatory = $true)][string]$ResultPath,
        [ValidateRange(10, 7200)][int]$InstallerTimeoutSeconds = 1800
    )

    $finalizationModule = Join-Path $PSScriptRoot 'SasSoftwareInstallFinalization.psm1'
    Import-Module $finalizationModule -Force
    $validationBody = (Get-SasSoftwareValidationScriptBlock).ToString()
    $configuration = [ordered]@{
        run_id = $RunId
        package_name = $PackageName
        installer_path = $InstallerPath
        expected_sha256 = $ExpectedSha256.ToLowerInvariant()
        installer_arguments = @($InstallerArguments)
        validation_checks_json = (@($ValidationChecks) | ConvertTo-Json -Depth 16 -Compress)
        result_path = $ResultPath
        timeout_seconds = $InstallerTimeoutSeconds
    }
    $configJson = $configuration | ConvertTo-Json -Depth 20 -Compress
    $configBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configJson))

    $worker = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$config = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CONFIG_BASE64__'))) | ConvertFrom-Json
$validationScript = {
__VALIDATION_BODY__
}
$result = [ordered]@{
    schema_version = 'sas-smb-scheduled-task-worker-result/v1'
    run_id = [string]$config.run_id
    package_name = [string]$config.package_name
    execution_identity_sid = $null
    execution_as_system = $false
    source_sha256 = [string]$config.expected_sha256
    target_sha256 = $null
    target_hash_verified = $false
    installer_exit_code = $null
    reboot_required = $false
    installer_status = 'not_started'
    validation_before_payload_cleanup = $null
    payload_cleanup_succeeded = $false
    staged_installer_remaining = $true
    validation_after_payload_cleanup = $null
    result_complete = $false
    error = $null
}
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $result.execution_identity_sid = [string]$identity.User.Value
    $result.execution_as_system = ($result.execution_identity_sid -eq 'S-1-5-18')
    if (-not $result.execution_as_system) { throw 'Scheduled task did not execute as LocalSystem.' }

    if (-not (Test-Path -LiteralPath $config.installer_path -PathType Leaf)) { throw 'Staged installer is missing.' }
    $result.target_sha256 = (Get-FileHash -LiteralPath $config.installer_path -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.target_hash_verified = ($result.target_sha256 -eq [string]$config.expected_sha256)
    if (-not $result.target_hash_verified) { throw 'Target-side installer SHA-256 mismatch.' }

    $arguments = @($config.installer_arguments | ForEach-Object { [string]$_ })
    $extension = [IO.Path]::GetExtension([string]$config.installer_path).ToLowerInvariant()
    if ($extension -eq '.msi') {
        $processArguments = @('/i', ('"{0}"' -f [string]$config.installer_path)) + $arguments
        $process = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $processArguments -PassThru
    }
    elseif ($extension -eq '.exe') {
        $start = @{ FilePath = [string]$config.installer_path; PassThru = $true }
        if ($arguments.Count -gt 0) { $start.ArgumentList = $arguments }
        $process = Start-Process @start
    }
    else { throw "Unsupported staged installer extension: $extension" }

    if (-not $process.WaitForExit(([int]$config.timeout_seconds * 1000))) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "Installer timed out after $($config.timeout_seconds) seconds."
    }
    $result.installer_exit_code = [int]$process.ExitCode
    $result.reboot_required = ($process.ExitCode -eq 3010)
    if ($process.ExitCode -notin @(0,3010)) { throw "Installer returned exit code $($process.ExitCode)." }
    $result.installer_status = if ($result.reboot_required) { 'completed_reboot_required' } else { 'completed' }

    $result.validation_before_payload_cleanup = & $validationScript ([string]$config.validation_checks_json)
    if (-not $result.validation_before_payload_cleanup.succeeded) { throw 'Required package validation failed before payload cleanup.' }

    Remove-Item -LiteralPath $config.installer_path -Force -ErrorAction Stop
    $result.staged_installer_remaining = Test-Path -LiteralPath $config.installer_path
    $result.payload_cleanup_succeeded = (-not $result.staged_installer_remaining)
    if (-not $result.payload_cleanup_succeeded) { throw 'Staged installer remained after payload cleanup.' }

    $result.validation_after_payload_cleanup = & $validationScript ([string]$config.validation_checks_json)
    if (-not $result.validation_after_payload_cleanup.succeeded) { throw 'Requested software was not preserved after staged payload cleanup.' }
    $result.result_complete = $true
}
catch {
    $result.error = $_.Exception.Message
    if (Test-Path -LiteralPath $config.installer_path -PathType Leaf) {
        try { Remove-Item -LiteralPath $config.installer_path -Force -ErrorAction Stop } catch { $result.error = "$($result.error); payload cleanup failed: $($_.Exception.Message)" }
    }
    $result.staged_installer_remaining = Test-Path -LiteralPath $config.installer_path
    $result.payload_cleanup_succeeded = (-not $result.staged_installer_remaining)
}
finally {
    $parent = Split-Path -Parent ([string]$config.result_path)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = [string]$config.result_path + '.tmp'
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $config.result_path -Force
}
'@
    $worker = $worker.Replace('__CONFIG_BASE64__', $configBase64).Replace('__VALIDATION_BODY__', $validationBody)
    $worker | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-SasSmbTaskWorkerResult {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Result, [Parameter(Mandatory = $true)][string]$RunId)
    Assert-SasClosedPropertySet -Value $Result -Allowed @(
        'schema_version','run_id','package_name','execution_identity_sid','execution_as_system','source_sha256',
        'target_sha256','target_hash_verified','installer_exit_code','reboot_required','installer_status',
        'validation_before_payload_cleanup','payload_cleanup_succeeded','staged_installer_remaining',
        'validation_after_payload_cleanup','result_complete','error'
    ) -Role 'SMB scheduled-task worker result'
    if ([string]$Result.schema_version -ne 'sas-smb-scheduled-task-worker-result/v1' -or [string]$Result.run_id -ne $RunId) { throw 'Worker result identity is invalid.' }
    if ([string]$Result.source_sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Worker result source hash is invalid.' }
    if ($Result.target_sha256 -and [string]$Result.target_sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Worker result target hash is invalid.' }
    if ($Result.execution_identity_sid -and [string]$Result.execution_identity_sid -notmatch '^S-[0-9-]+$') { throw 'Worker execution SID is invalid.' }
    return $true
}

function New-SasSmbTaskResult {
    param([string]$RunId, [string]$Target, [string]$TaskName, [string]$SourceSha256)
    [ordered]@{
        schema_version = 'sas-smb-scheduled-task-deployment-result/v1'
        run_id = $RunId
        target = $Target
        transport = 'SmbScheduledTask'
        selected_before_mutation = $true
        fallback_attempted = $false
        source_sha256 = $SourceSha256
        target_sha256 = $null
        worker_source_sha256 = $null
        worker_target_sha256 = $null
        hashes_verified = $false
        task = [ordered]@{ name = $TaskName; create_attempted = $false; created = $false; run_attempted = $false; started = $false; delete_attempted = $false; deleted = $false; absent_verified = $false }
        execution = [ordered]@{ identity_sid = $null; as_system = $false; installer_exit_code = $null; reboot_required = $false; installer_status = 'not_started' }
        result_retrieval = [ordered]@{ attempted = $false; succeeded = $false; malformed = $false; local_path = $null }
        validation = [ordered]@{ before_payload_cleanup_succeeded = $false; after_payload_cleanup_succeeded = $false }
        cleanup = [ordered]@{ attempted = $false; task_deletion_succeeded = $false; run_root_deletion_succeeded = $false; task_remaining = $false; run_root_remaining = $false }
        status = 'failed_before_staging'
        network_activity_performed = $false
        target_mutation_performed = $false
        error = $null
    }
}

function Invoke-SasSmbScheduledTaskDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][string]$ExpectedSourceSha256,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string[]]$InstallerArguments,
        [Parameter(Mandatory = $true)]$ValidationChecks,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$LocalRunRoot,
        [ValidateRange(10, 7200)][int]$ResultTimeoutSeconds = 1800,
        [ValidateRange(10, 7200)][int]$InstallerTimeoutSeconds = 1800
    )

    if (-not (Test-SasDeploymentFqdn -ComputerName $ComputerName)) { throw 'SmbScheduledTask requires the exact authorized FQDN.' }
    if ($RunId -notmatch '^software-install-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { throw 'SmbScheduledTask run ID is invalid.' }
    if ([string]$ExpectedSourceSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Expected source SHA-256 is invalid.' }
    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw "Pinned installer not found: $InstallerPath" }
    if (-not (Test-Path -LiteralPath $LocalRunRoot -PathType Container)) { New-Item -ItemType Directory -Path $LocalRunRoot -Force | Out-Null }

    $taskName = 'SysAdminSuite-SoftwareInstall-{0}' -f ([guid]::NewGuid().ToString('N'))
    $sourceHash = $ExpectedSourceSha256.ToLowerInvariant()
    $result = New-SasSmbTaskResult -RunId $RunId -Target $ComputerName -TaskName $taskName -SourceSha256 $sourceHash
    $adminRoot = "\\$ComputerName\ADMIN$"
    $cRoot = "\\$ComputerName\C$"
    $remoteWindowsRoot = "C:\ProgramData\SysAdminSuite\SoftwareInstall\$RunId"
    $remoteUncRoot = Join-Path $cRoot "ProgramData\SysAdminSuite\SoftwareInstall\$RunId"
    $remoteInstaller = Join-Path $remoteWindowsRoot (Split-Path -Leaf $InstallerPath)
    $remoteInstallerUnc = Join-Path $remoteUncRoot (Split-Path -Leaf $InstallerPath)
    $remoteWorker = Join-Path $remoteWindowsRoot 'Invoke-InstallWorker.ps1'
    $remoteWorkerUnc = Join-Path $remoteUncRoot 'Invoke-InstallWorker.ps1'
    $remoteResult = Join-Path $remoteWindowsRoot 'worker-result.json'
    $remoteResultUnc = Join-Path $remoteUncRoot 'worker-result.json'
    $localWorker = Join-Path $LocalRunRoot ("worker-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    $localResult = Join-Path $LocalRunRoot ("target-result-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    $stagingBegan = $false

    try {
        $sourceHash = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.source_sha256 = $sourceHash
        if ($sourceHash -ne $ExpectedSourceSha256.ToLowerInvariant()) { throw 'Source SHA-256 changed before SMB staging.' }
        $result.network_activity_performed = $true
        if (-not (Test-Path -LiteralPath $adminRoot -PathType Container)) { throw 'ADMIN$ access denied or unavailable.' }
        if (-not (Test-Path -LiteralPath $cRoot -PathType Container)) { throw 'C$ access denied or unavailable for the canonical ProgramData staging root.' }

        New-SasSmbTaskWorker -Path $localWorker -RunId $RunId -PackageName $PackageName -InstallerPath $remoteInstaller `
            -ExpectedSha256 $sourceHash -InstallerArguments $InstallerArguments -ValidationChecks $ValidationChecks `
            -ResultPath $remoteResult -InstallerTimeoutSeconds $InstallerTimeoutSeconds
        $result.worker_source_sha256 = (Get-FileHash -LiteralPath $localWorker -Algorithm SHA256).Hash.ToLowerInvariant()

        New-Item -ItemType Directory -Path $remoteUncRoot -Force -ErrorAction Stop | Out-Null
        $stagingBegan = $true
        $result.target_mutation_performed = $true
        $result.cleanup.run_root_remaining = $true
        Copy-Item -LiteralPath $InstallerPath -Destination $remoteInstallerUnc -Force -ErrorAction Stop
        Copy-Item -LiteralPath $localWorker -Destination $remoteWorkerUnc -Force -ErrorAction Stop
        $result.target_sha256 = (Get-FileHash -LiteralPath $remoteInstallerUnc -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.worker_target_sha256 = (Get-FileHash -LiteralPath $remoteWorkerUnc -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.hashes_verified = ($result.target_sha256 -eq $sourceHash -and $result.worker_target_sha256 -eq $result.worker_source_sha256)
        if (-not $result.hashes_verified) { throw 'Target or transient worker SHA-256 mismatch before task creation.' }
        $result.status = 'staged_hash_verified'

        $when = (Get-Date).AddMinutes(1).ToString('HH:mm')
        $taskCommand = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $remoteWorker"
        $result.task.create_attempted = $true
        $create = Invoke-SasSchtasksCommand -Arguments @('/Create','/S',$ComputerName,'/RU','SYSTEM','/SC','ONCE','/ST',$when,'/TN',$taskName,'/TR',$taskCommand,'/RL','HIGHEST','/F')
        if ($create.exit_code -ne 0) { throw "Scheduled-task creation failed: $($create.output)" }
        $result.task.created = $true
        $result.cleanup.task_remaining = $true

        $result.task.run_attempted = $true
        $run = Invoke-SasSchtasksCommand -Arguments @('/Run','/S',$ComputerName,'/TN',$taskName)
        if ($run.exit_code -ne 0) { throw "Scheduled-task run failed: $($run.output)" }
        $result.task.started = $true
        $result.status = 'task_started'

        $result.result_retrieval.attempted = $true
        $deadline = (Get-Date).AddSeconds($ResultTimeoutSeconds)
        while (-not (Test-Path -LiteralPath $remoteResultUnc -PathType Leaf)) {
            if ((Get-Date) -ge $deadline) { throw "Timed out after $ResultTimeoutSeconds seconds waiting for the closed worker result." }
            Start-Sleep -Seconds 2
        }
        Copy-Item -LiteralPath $remoteResultUnc -Destination $localResult -Force -ErrorAction Stop
        $result.result_retrieval.local_path = $localResult
        try {
            $workerResult = Get-Content -LiteralPath $localResult -Raw -Encoding UTF8 | ConvertFrom-Json
            $null = Test-SasSmbTaskWorkerResult -Result $workerResult -RunId $RunId
        }
        catch {
            $result.result_retrieval.malformed = $true
            throw "Retrieved worker result is malformed: $($_.Exception.Message)"
        }
        $result.result_retrieval.succeeded = $true
        $result.target_sha256 = [string]$workerResult.target_sha256
        $result.execution.identity_sid = [string]$workerResult.execution_identity_sid
        $result.execution.as_system = [bool]$workerResult.execution_as_system
        $result.execution.installer_exit_code = $workerResult.installer_exit_code
        $result.execution.reboot_required = [bool]$workerResult.reboot_required
        $result.execution.installer_status = [string]$workerResult.installer_status
        $result.validation.before_payload_cleanup_succeeded = [bool]($workerResult.validation_before_payload_cleanup -and $workerResult.validation_before_payload_cleanup.succeeded)
        $result.validation.after_payload_cleanup_succeeded = [bool]($workerResult.validation_after_payload_cleanup -and $workerResult.validation_after_payload_cleanup.succeeded)
        if (-not [bool]$workerResult.result_complete -or -not [bool]$workerResult.target_hash_verified -or
            -not [bool]$workerResult.execution_as_system -or -not [bool]$workerResult.payload_cleanup_succeeded -or
            [bool]$workerResult.staged_installer_remaining) {
            throw "Worker did not complete the required hash, SYSTEM, validation, and payload-cleanup chain: $($workerResult.error)"
        }
        $result.status = if ([bool]$workerResult.reboot_required) { 'completed_reboot_required_pending_cleanup' } else { 'completed_pending_cleanup' }
    }
    catch {
        $result.error = $_.Exception.Message
        if ($result.status -notin @('completed_pending_cleanup','completed_reboot_required_pending_cleanup')) { $result.status = 'deployment_failed_pending_cleanup' }
    }
    finally {
        if (Test-Path -LiteralPath $localWorker -PathType Leaf) { Remove-Item -LiteralPath $localWorker -Force -ErrorAction SilentlyContinue }
        if ($stagingBegan -or $result.task.create_attempted) {
            $result.cleanup.attempted = $true
            $result.task.delete_attempted = $true
            $delete = Invoke-SasSchtasksCommand -Arguments @('/Delete','/S',$ComputerName,'/TN',$taskName,'/F')
            $result.task.deleted = ($delete.exit_code -eq 0 -or (Test-SasTaskAbsentText -Text $delete.output))
            $result.cleanup.task_deletion_succeeded = $result.task.deleted
            $query = Invoke-SasSchtasksCommand -Arguments @('/Query','/S',$ComputerName,'/TN',$taskName)
            $result.task.absent_verified = ($query.exit_code -ne 0 -and (Test-SasTaskAbsentText -Text $query.output))
            $result.cleanup.task_remaining = (-not $result.task.absent_verified)

            try {
                if (Test-Path -LiteralPath $remoteUncRoot) { Remove-Item -LiteralPath $remoteUncRoot -Recurse -Force -ErrorAction Stop }
                $result.cleanup.run_root_remaining = Test-Path -LiteralPath $remoteUncRoot
                $result.cleanup.run_root_deletion_succeeded = (-not $result.cleanup.run_root_remaining)
            }
            catch {
                $result.cleanup.run_root_remaining = $true
                $result.cleanup.run_root_deletion_succeeded = $false
                if ($result.error) { $result.error = "$($result.error); run-root cleanup failed: $($_.Exception.Message)" }
                else { $result.error = "Run-root cleanup failed: $($_.Exception.Message)" }
            }
        }
    }

    $cleanupComplete = ($result.cleanup.attempted -and $result.cleanup.task_deletion_succeeded -and
        $result.task.absent_verified -and $result.cleanup.run_root_deletion_succeeded -and
        -not $result.cleanup.task_remaining -and -not $result.cleanup.run_root_remaining)
    $executionComplete = ($result.result_retrieval.succeeded -and $result.execution.as_system -and
        $result.hashes_verified -and $result.validation.before_payload_cleanup_succeeded -and
        $result.validation.after_payload_cleanup_succeeded)
    if (-not $stagingBegan -and -not $result.task.create_attempted) {
        $result.status = 'failed_before_staging'
    }
    elseif (-not $cleanupComplete) {
        $result.status = 'cleanup_failed'
        if (-not $result.error) { $result.error = 'Task or run-root teardown was not completely verified.' }
    }
    elseif ($executionComplete) {
        $result.status = if ($result.execution.reboot_required) { 'completed_reboot_required' } else { 'completed' }
    }
    elseif ($result.status -ne 'failed_before_staging') { $result.status = 'deployment_failed_cleaned' }

    return [pscustomobject]$result
}

function Invoke-SasSmbScheduledTaskDeploymentFixture {
    <#
    .SYNOPSIS
    Runs a zero-network lifecycle simulation for deterministic failure contracts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'success','source_hash_mismatch','target_hash_mismatch','admin_share_denied',
            'task_creation_failure','task_run_failure','result_timeout','malformed_result',
            'task_deletion_failure','run_root_deletion_failure','remaining_task','remaining_file'
        )]
        [string]$Scenario
    )

    if (-not [IO.Path]::IsPathRooted($FixtureRoot)) { throw 'FixtureRoot must be absolute.' }
    New-Item -ItemType Directory -Path $FixtureRoot -Force | Out-Null
    $runId = 'software-install-20000101-000000-00000000'
    $taskName = 'SysAdminSuite-SoftwareInstall-00000000000000000000000000000000'
    $source = Join-Path $FixtureRoot 'source.exe'
    $runRoot = Join-Path $FixtureRoot $runId
    $staged = Join-Path $runRoot 'source.exe'
    $taskMarker = Join-Path $FixtureRoot 'task.marker'
    $workerResultPath = Join-Path $runRoot 'worker-result.json'
    [IO.File]::WriteAllText($source, 'approved fixture payload', [Text.Encoding]::UTF8)
    $expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    $result = New-SasSmbTaskResult -RunId $runId -Target 'fixture-target.example.test' -TaskName $taskName -SourceSha256 $expected
    $result.network_activity_performed = $false

    if ($Scenario -eq 'source_hash_mismatch') {
        $result.source_sha256 = ('f' * 64)
        $result.error = 'Source SHA-256 changed before SMB staging.'
        return [pscustomobject]$result
    }
    if ($Scenario -eq 'admin_share_denied') {
        $result.error = 'ADMIN$ access denied or unavailable.'
        return [pscustomobject]$result
    }

    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $staged -Force
    $result.target_mutation_performed = $true
    $result.cleanup.run_root_remaining = $true
    $result.target_sha256 = (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.worker_source_sha256 = $expected
    $result.worker_target_sha256 = $expected
    if ($Scenario -eq 'target_hash_mismatch') {
        [IO.File]::AppendAllText($staged, 'tampered')
        $result.target_sha256 = (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.error = 'Target or transient worker SHA-256 mismatch before task creation.'
    }
    else { $result.hashes_verified = $true }

    if (-not $result.error) {
        $result.task.create_attempted = $true
        if ($Scenario -eq 'task_creation_failure') { $result.error = 'Scheduled-task creation failed.' }
        else {
            [IO.File]::WriteAllText($taskMarker, $taskName)
            $result.task.created = $true
            $result.cleanup.task_remaining = $true
            $result.task.run_attempted = $true
            if ($Scenario -eq 'task_run_failure') { $result.error = 'Scheduled-task run failed.' }
            else {
                $result.task.started = $true
                if ($Scenario -eq 'result_timeout') { $result.error = 'Timed out waiting for the closed worker result.' }
                else {
                    $result.result_retrieval.attempted = $true
                    if ($Scenario -eq 'malformed_result') {
                        [IO.File]::WriteAllText($workerResultPath, '{malformed')
                        $result.result_retrieval.malformed = $true
                        $result.error = 'Retrieved worker result is malformed.'
                    }
                    else {
                        [IO.File]::WriteAllText($workerResultPath, '{"schema_version":"fixture-closed-result/v1"}')
                        $result.result_retrieval.succeeded = $true
                        $result.result_retrieval.local_path = $workerResultPath
                        $result.execution.identity_sid = 'S-1-5-18'
                        $result.execution.as_system = $true
                        $result.execution.installer_exit_code = 0
                        $result.execution.installer_status = 'completed'
                        $result.validation.before_payload_cleanup_succeeded = $true
                        $result.validation.after_payload_cleanup_succeeded = $true
                    }
                }
            }
        }
    }

    $result.cleanup.attempted = $true
    $result.task.delete_attempted = $true
    if ($Scenario -notin @('task_deletion_failure','remaining_task')) {
        if (Test-Path -LiteralPath $taskMarker) { Remove-Item -LiteralPath $taskMarker -Force }
        $result.task.deleted = $true
        $result.task.absent_verified = (-not (Test-Path -LiteralPath $taskMarker))
        $result.cleanup.task_deletion_succeeded = $result.task.absent_verified
        $result.cleanup.task_remaining = (-not $result.task.absent_verified)
    }
    else {
        $result.error = 'Scheduled-task teardown was not verified.'
        $result.cleanup.task_remaining = $true
    }

    if ($Scenario -notin @('run_root_deletion_failure','remaining_file')) {
        if (Test-Path -LiteralPath $runRoot) { Remove-Item -LiteralPath $runRoot -Recurse -Force }
        $result.cleanup.run_root_remaining = Test-Path -LiteralPath $runRoot
        $result.cleanup.run_root_deletion_succeeded = (-not $result.cleanup.run_root_remaining)
    }
    else {
        $result.error = 'Run-root teardown was not verified.'
        $result.cleanup.run_root_remaining = $true
    }

    $cleanupComplete = ($result.cleanup.task_deletion_succeeded -and $result.cleanup.run_root_deletion_succeeded -and
        -not $result.cleanup.task_remaining -and -not $result.cleanup.run_root_remaining)
    $executionComplete = ($result.result_retrieval.succeeded -and $result.execution.as_system -and
        $result.hashes_verified -and $result.validation.after_payload_cleanup_succeeded)
    if (-not $cleanupComplete) { $result.status = 'cleanup_failed' }
    elseif ($executionComplete) { $result.status = 'completed' }
    else { $result.status = 'deployment_failed_cleaned' }
    return [pscustomobject]$result
}

Export-ModuleMember -Function Test-SasDeploymentFqdn, Read-SasDeploymentTransportPreflight, Resolve-SasSoftwareDeploymentTransport, New-SasSmbTaskWorker, Test-SasSmbTaskWorkerResult, Invoke-SasSmbScheduledTaskDeployment, Invoke-SasSmbScheduledTaskDeploymentFixture
