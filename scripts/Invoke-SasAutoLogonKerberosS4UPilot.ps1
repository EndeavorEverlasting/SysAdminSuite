#Requires -Version 5.1
<#
.SYNOPSIS
Configure AutoLogon remotely through Kerberos SMB and a passwordless S4U scheduled task.

.DESCRIPTION
Stages the approved AutoLogon package through Kerberos SMB, proves an exact safe first-install
baseline, executes the local staged worker under a passwordless elevated S4U task, captures the
read-only after state, and performs exact cleanup.

Every Task Scheduler native operation and every remote-result existence probe is bounded. Exact
task/run identity is checkpointed before /Create so interrupted runs can be recovered from disk
without process forensics. No target user session or scheduled-task password is required.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$AuthorizedBy = 'field-authorized operator',
    [string]$RequestReference = 'field deployment',
    [string]$ChangeReference = 'field deployment',
    [string]$TicketReference = 'field deployment',
    [string]$TechnicianLabel = 'AutoLogon Kerberos S4U administrator pilot',

    [ValidateRange(1,1440)]
    [int]$PreflightMaxAgeMinutes = 15,
    [ValidateRange(30,3600)]
    [int]$S4UResultTimeoutSeconds = 900,
    [ValidateRange(10,600)]
    [int]$StateResultTimeoutSeconds = 120,
    [ValidateRange(5,120)]
    [int]$NativeTaskTimeoutSeconds = 30,
    [ValidateRange(2,30)]
    [int]$RemoteProbeTimeoutSeconds = 8,

    [string]$OutputRoot,
    [switch]$AllowTargetMutation,
    [switch]$ConfirmS4U,
    [switch]$FixtureMode,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-SasS4UJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-SasS4UStage {
    param(
        [Parameter(Mandatory = $true)][string]$EvidenceRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateRange(1,22)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('START','PASS','FAIL','INFO')][string]$Status,
        [string]$Classification,
        [string]$Detail
    )
    $record = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-s4u-progress/v1'
        run_id = $RunId
        stage_number = $Number
        stage_name = $Name
        status = $Status
        classification = $Classification
        detail = $Detail
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-SasS4UJson -Path (Join-Path -Path $EvidenceRoot -ChildPath 'progress_checkpoint.json') -Value $record
    ($record | ConvertTo-Json -Depth 8 -Compress) |
        Add-Content -LiteralPath (Join-Path -Path $EvidenceRoot -ChildPath 'progress_history.jsonl') -Encoding UTF8
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " - $Detail" }
    Write-Host ("[{0}/22] {1}: {2}{3}" -f $Number,$Name,$Status,$suffix) -ForegroundColor Cyan
}

function Test-SasS4UTaskAbsentText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot find|does not exist|not exist|cannot find the file|the system cannot find')
}

function Test-SasS4UCaptureComplete {
    param($Lifecycle)
    return ($null -ne $Lifecycle -and [string]$Lifecycle.status -eq 'completed' -and
        [bool]$Lifecycle.worker.executed_as_system -and [bool]$Lifecycle.worker.hash_verified -and
        [bool]$Lifecycle.result_retrieval.succeeded -and [bool]$Lifecycle.cleanup.task_deletion_succeeded -and
        [bool]$Lifecycle.cleanup.run_root_deletion_succeeded -and -not [bool]$Lifecycle.cleanup.task_remaining -and
        -not [bool]$Lifecycle.cleanup.run_root_remaining)
}

function Get-SasS4UOperatorIdentity {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or $null -eq $identity.User) {
        throw 'Unable to resolve the current Windows security identity.'
    }
    $name = [string]$identity.Name
    $sid = [string]$identity.User.Value
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($sid)) {
        throw 'Current Windows identity is incomplete.'
    }
    if ($sid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) {
        throw 'S4U AutoLogon requires a named Windows domain identity, not a service account.'
    }
    if ($name -notmatch '^[^\\]+\\[^\\]+$') {
        throw 'S4U AutoLogon requires a domain-qualified Windows identity.'
    }
    $parts = $name.Split('\',2)
    if ($parts[0].Equals($env:COMPUTERNAME, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'S4U AutoLogon requires a domain identity; a controller-local account is not accepted.'
    }
    [pscustomobject][ordered]@{
        name = $name
        sid = $sid
        domain = $parts[0]
        account = $parts[1]
    }
}

function Get-SasS4UApprovedPackage {
    param(
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$HarnessApiPath
    )
    $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$catalog.schema_version -ne 'sas-approved-software-catalog/v1') {
        throw 'Approved software catalog schema is unsupported.'
    }
    $matches = @($catalog.packages | Where-Object { [string]$_.id -eq 'autologon' })
    if ($matches.Count -ne 1) { throw 'Approved AutoLogon package is missing or ambiguous.' }
    $package = $matches[0]
    if (-not [bool]$package.install_enabled) { throw 'Approved AutoLogon package is disabled.' }
    if ([string]::IsNullOrWhiteSpace([string]$package.installer_file)) {
        throw 'Approved AutoLogon installer filename is not pinned.'
    }
    if ([string]$package.default_install_mode -ne 'CopyThenInstall') {
        throw 'S4U AutoLogon requires the approved CopyThenInstall package.'
    }
    if (@($package.default_installer_arguments).Count -ne 0) {
        throw 'S4U AutoLogon currently permits only the approved empty argument set.'
    }
    if ([string]$package.installer_arguments_policy -ne 'approved_empty') {
        throw 'AutoLogon catalog does not record the approved-empty argument policy.'
    }

    $root = ([string]$catalog.software_share_root).Trim().Replace('/', '\').TrimEnd('\') + '\'
    if ($root -notmatch '^\\\\([^\\]+)\\$') {
        throw 'Approved software_share_root is not a UNC server root.'
    }
    $shareServer = $Matches[1]
    $api = Get-Content -LiteralPath $HarnessApiPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $approvedRoots = @($api.posture.approved_software_sources | ForEach-Object {
        ([string]$_).Trim().Replace('/', '\').TrimEnd('\') + '\'
    })
    if (@($approvedRoots | Where-Object { $_.Equals($root, [StringComparison]::OrdinalIgnoreCase) }).Count -ne 1) {
        throw 'AutoLogon software share root is not approved by the harness API.'
    }

    $relativeFolder = ([string]$package.source_folder_relative_path).Trim().Trim('\/').Replace('/', '\')
    $installer = ([string]$package.installer_file).Trim()
    $segments = @($relativeFolder -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $relativeFolder -or -not $installer -or $segments -contains '..' -or
        [IO.Path]::IsPathRooted($relativeFolder) -or [IO.Path]::GetFileName($installer) -ne $installer) {
        throw 'AutoLogon catalog contains an unsafe package path.'
    }

    [pscustomobject][ordered]@{
        id = 'autologon'
        display_name = [string]$package.display_name
        source_root = $root
        source_server = $shareServer
        installer_relative_path = "$relativeFolder\$installer"
        installer_file = $installer
        installer_arguments = @()
        canonical_system_install_enabled = $(if ($null -ne $package.PSObject.Properties['canonical_system_install_enabled']) {
            [bool]$package.canonical_system_install_enabled
        } else { $true })
        canonical_system_qualification_status = $(if ($null -ne $package.PSObject.Properties['canonical_system_qualification']) {
            [string]$package.canonical_system_qualification.status
        } else { '' })
    }
}

function Request-SasS4UKerberosTicket {
    param(
        [Parameter(Mandatory = $true)][string]$Spn,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $probe = Invoke-SasBoundedNative -FilePath "$env:WINDIR\System32\klist.exe" -Arguments @('get',$Spn) -TimeoutSeconds $TimeoutSeconds
    [pscustomobject][ordered]@{
        spn = $Spn
        issued = (-not [bool]$probe.timed_out -and [int]$probe.exit_code -eq 0)
        exit_code = [int]$probe.exit_code
        timed_out = [bool]$probe.timed_out
        timeout_seconds = $TimeoutSeconds
        ticket_bytes_emitted = $false
        raw_output_emitted = $false
    }
}

function Invoke-SasS4UBoundedPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptText,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
    $powershellExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    Invoke-SasBoundedNative -FilePath $powershellExe -Arguments @(
        '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded
    ) -TimeoutSeconds $TimeoutSeconds
}

function Test-SasS4UBoundedRemotePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('Leaf','Container','Any')][string]$PathType,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $path64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Path))
    $pathTypeClause = switch ($PathType) {
        'Leaf' { '-PathType Leaf' }
        'Container' { '-PathType Container' }
        default { '' }
    }
    $script = @"
`$ErrorActionPreference = 'Stop'
`$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$path64'))
if (Test-Path -LiteralPath `$path $pathTypeClause) {
    [Console]::Out.Write('EXISTS')
    exit 0
}
[Console]::Out.Write('ABSENT')
exit 3
"@
    $probe = Invoke-SasS4UBoundedPowerShell -ScriptText $script -TimeoutSeconds $TimeoutSeconds
    [pscustomobject][ordered]@{
        exists = (-not [bool]$probe.timed_out -and [int]$probe.exit_code -eq 0 -and ([string]$probe.output).Trim() -eq 'EXISTS')
        absent = (-not [bool]$probe.timed_out -and [int]$probe.exit_code -eq 3 -and ([string]$probe.output).Trim() -eq 'ABSENT')
        timed_out = [bool]$probe.timed_out
        exit_code = [int]$probe.exit_code
        timeout_seconds = $TimeoutSeconds
        error = [string]$probe.error
    }
}

function Copy-SasS4UBoundedRemoteResult {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $source64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Source))
    $destination64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Destination))
    $script = @"
`$ErrorActionPreference = 'Stop'
`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$source64'))
`$destination = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$destination64'))
Copy-Item -LiteralPath `$source -Destination `$destination -Force -ErrorAction Stop
exit 0
"@
    Invoke-SasS4UBoundedPowerShell -ScriptText $script -TimeoutSeconds $TimeoutSeconds
}

function New-SasS4UWorker {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('Probe','Install')][string]$Mode,
        [Parameter(Mandatory = $true)][string]$ExpectedSid,
        [Parameter(Mandatory = $true)][string]$ResultPath,
        [string]$InstallerPath,
        [string]$InstallerSha256
    )
    $configuration = [ordered]@{
        mode = $Mode
        expected_sid = $ExpectedSid
        result_path = $ResultPath
        installer_path = $InstallerPath
        installer_sha256 = $InstallerSha256
    }
    $json = $configuration | ConvertTo-Json -Depth 8 -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))

    $worker = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$config = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CONFIG__'))) | ConvertFrom-Json
$result = [ordered]@{
    schema_version = 'sas-autologon-kerberos-s4u-worker-result/v1'
    mode = [string]$config.mode
    execution_identity_name = $null
    execution_identity_sid = $null
    identity_matches_expected_sid = $false
    is_administrator = $false
    user_interactive = $false
    session_id = -1
    installer_sha256_verified = $false
    installer_exit_code = $null
    completed = $false
    error = $null
    default_password_value_collected = $false
}
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $result.execution_identity_name = [string]$identity.Name
    $result.execution_identity_sid = [string]$identity.User.Value
    $result.identity_matches_expected_sid = ([string]$identity.User.Value).Equals([string]$config.expected_sid, [StringComparison]::OrdinalIgnoreCase)
    $result.is_administrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $result.user_interactive = [Environment]::UserInteractive
    $result.session_id = [Diagnostics.Process]::GetCurrentProcess().SessionId
    if (-not $result.identity_matches_expected_sid) { throw 'S4U task identity SID does not match the authorized controller principal.' }
    if (-not $result.is_administrator) { throw 'S4U task principal is not running with an elevated administrator token.' }

    if ([string]$config.mode -eq 'Install') {
        if (-not (Test-Path -LiteralPath ([string]$config.installer_path) -PathType Leaf)) { throw 'Staged AutoLogon installer is missing.' }
        $hash = (Get-FileHash -LiteralPath ([string]$config.installer_path) -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.installer_sha256_verified = $hash -eq ([string]$config.installer_sha256).ToLowerInvariant()
        if (-not $result.installer_sha256_verified) { throw 'Staged AutoLogon installer SHA-256 changed before execution.' }
        $process = Start-Process -FilePath ([string]$config.installer_path) -ArgumentList @() -Wait -PassThru
        $result.installer_exit_code = [int]$process.ExitCode
    }
    else {
        $result.installer_sha256_verified = $true
    }
    $result.completed = $true
}
catch {
    $result.error = $_.Exception.Message
}
finally {
    $parent = Split-Path -Parent ([string]$config.result_path)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = [string]$config.result_path + '.tmp'
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination ([string]$config.result_path) -Force
}
'@
    $worker.Replace('__CONFIG__', $encoded) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Save-SasS4UTaskLifecycle {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Lifecycle
    )
    $Lifecycle.updated_utc = (Get-Date).ToUniversalTime().ToString('o')
    Write-SasS4UJson -Path $Path -Value ([pscustomobject]$Lifecycle)
}

function Invoke-SasS4UTask {
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('Probe','Install')][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$PrincipalName,
        [Parameter(Mandatory = $true)][string]$WorkerPath,
        [Parameter(Mandatory = $true)][string]$RemoteResultPath,
        [Parameter(Mandatory = $true)][string]$RemoteResultUnc,
        [Parameter(Mandatory = $true)][string]$LocalResultPath,
        [Parameter(Mandatory = $true)][string]$LifecyclePath,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$NativeTimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$RemoteProbeTimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$CreateStage,
        [Parameter(Mandatory = $true)][int]$RunStage,
        [Parameter(Mandatory = $true)][int]$ResultStage,
        [Parameter(Mandatory = $true)][int]$CleanupStage
    )

    $modeUpper = $Mode.ToUpperInvariant()
    $lifecycle = [ordered]@{
        schema_version = 'sas-autologon-s4u-task-lifecycle/v2'
        run_id = $RunId
        mode = $Mode
        task_name = $TaskName
        target = $Target
        principal = $PrincipalName
        s4u_principal = $PrincipalName
        logon_type = 'S4U'
        run_level = 'HighestAvailable'
        password_stored = $false
        target_user_session_required = $false
        network_access_from_task_expected = $false
        remote_worker_path = $WorkerPath
        remote_result_path = $RemoteResultPath
        remote_result_unc = $RemoteResultUnc
        local_result_path = $LocalResultPath
        create_attempted = $false
        create_succeeded = $false
        run_attempted = $false
        run_succeeded = $false
        result_retrieved = $false
        delete_attempted = $false
        delete_succeeded = $false
        absent_verified = $false
        created = $false
        started = $false
        deleted = $false
        current_stage = 'identity_checkpointed_before_create'
        classification = "S4U_${modeUpper}_IDENTITY_CHECKPOINTED"
        result = $null
        native = [ordered]@{
            create = $null
            run = $null
            delete = $null
            query = $null
            result_probe_last = $null
            result_copy = $null
        }
        timestamps = [ordered]@{
            identity_checkpointed_utc = (Get-Date).ToUniversalTime().ToString('o')
            create_attempted_utc = $null
            create_succeeded_utc = $null
            run_attempted_utc = $null
            run_succeeded_utc = $null
            result_retrieved_utc = $null
            delete_attempted_utc = $null
            delete_succeeded_utc = $null
            absent_verified_utc = $null
        }
        error = $null
        updated_utc = $null
    }

    # Required crash-recovery checkpoint: exact task/run identity exists before schtasks /Create.
    Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle

    try {
        $startTime = (Get-Date).AddMinutes(2).ToString('HH:mm')
        $taskCommand = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$WorkerPath`""

        Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $CreateStage -Name "$Mode task create" -Status START
        $lifecycle.create_attempted = $true
        $lifecycle.current_stage = 'create_attempted'
        $lifecycle.classification = "S4U_${modeUpper}_CREATE_PENDING"
        $lifecycle.timestamps.create_attempted_utc = (Get-Date).ToUniversalTime().ToString('o')
        Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle

        $create = Invoke-SasBoundedNative -FilePath "$env:WINDIR\System32\schtasks.exe" -Arguments @(
            '/Create','/S',$Target,'/RU',$PrincipalName,'/NP','/SC','ONCE','/ST',$startTime,
            '/TN',$TaskName,'/TR',$taskCommand,'/RL','HIGHEST','/F'
        ) -TimeoutSeconds $NativeTimeoutSeconds
        $lifecycle.native.create = $create
        if ([bool]$create.timed_out) {
            $lifecycle.classification = "S4U_${modeUpper}_CREATE_TIMEOUT"
            $effectiveCreateTimeoutSeconds = $NativeTimeoutSeconds
            if ($null -ne $create.PSObject.Properties['timeout_seconds']) {
                $effectiveCreateTimeoutSeconds = [int]$create.timeout_seconds
            }
            throw "S4U $Mode task creation timed out after $effectiveCreateTimeoutSeconds seconds."
        }
        if ([int]$create.exit_code -ne 0) {
            $lifecycle.classification = "S4U_${modeUpper}_CREATE_FAILED"
            throw "S4U $Mode task creation failed: $($create.output) $($create.error)"
        }
        $lifecycle.create_succeeded = $true
        $lifecycle.created = $true
        $lifecycle.current_stage = 'create_succeeded'
        $lifecycle.timestamps.create_succeeded_utc = (Get-Date).ToUniversalTime().ToString('o')
        Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle
        Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $CreateStage -Name "$Mode task create" -Status PASS

        Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $RunStage -Name "$Mode task run" -Status START
        $lifecycle.run_attempted = $true
        $lifecycle.current_stage = 'run_attempted'
        $lifecycle.classification = "S4U_${modeUpper}_RUN_PENDING"
        $lifecycle.timestamps.run_attempted_utc = (Get-Date).ToUniversalTime().ToString('o')
        Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle

        $run = Invoke-SasBoundedNative -FilePath "$env:WINDIR\System32\schtasks.exe" -Arguments @(
            '/Run','/S',$Target,'/TN',$TaskName
        ) -TimeoutSeconds $NativeTimeoutSeconds
        $lifecycle.native.run = $run
        if ([bool]$run.timed_out) {
            $lifecycle.classification = "S4U_${modeUpper}_RUN_TIMEOUT"
            throw "S4U $Mode task run timed out after $NativeTimeoutSeconds seconds."
        }
        if ([int]$run.exit_code -ne 0) {
            $lifecycle.classification = "S4U_${modeUpper}_RUN_FAILED"
            throw "S4U $Mode task start failed: $($run.output) $($run.error)"
        }
        $lifecycle.run_succeeded = $true
        $lifecycle.started = $true
        $lifecycle.current_stage = 'run_succeeded'
        $lifecycle.timestamps.run_succeeded_utc = (Get-Date).ToUniversalTime().ToString('o')
        Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle
        Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $RunStage -Name "$Mode task run" -Status PASS

        Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $ResultStage -Name "$Mode result" -Status START
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $resultReady = $false
        while ((Get-Date) -lt $deadline) {
            $remainingSeconds = [Math]::Max(1, [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds))
            $attemptTimeout = [Math]::Min($RemoteProbeTimeoutSeconds, $remainingSeconds)
            $probe = Test-SasS4UBoundedRemotePath -Path $RemoteResultUnc -PathType Leaf -TimeoutSeconds $attemptTimeout
            $lifecycle.native.result_probe_last = $probe
            $lifecycle.current_stage = 'result_poll'
            Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle
            if ([bool]$probe.exists) {
                $resultReady = $true
                break
            }
            if (-not [bool]$probe.absent -and -not [bool]$probe.timed_out) {
                $lifecycle.classification = "S4U_${modeUpper}_RESULT_PROBE_FAILED"
                throw "S4U $Mode result probe failed with exit code $($probe.exit_code): $($probe.error)"
            }
            Start-Sleep -Seconds 2
        }
        if (-not $resultReady) {
            $lifecycle.classification = "S4U_${modeUpper}_RESULT_TIMEOUT"
            throw "Timed out after $TimeoutSeconds seconds waiting for S4U $Mode task result."
        }

        $remainingCopySeconds = [Math]::Max($RemoteProbeTimeoutSeconds, [Math]::Min(30, $NativeTimeoutSeconds))
        $copy = Copy-SasS4UBoundedRemoteResult -Source $RemoteResultUnc -Destination $LocalResultPath -TimeoutSeconds $remainingCopySeconds
        $lifecycle.native.result_copy = $copy
        if ([bool]$copy.timed_out -or [int]$copy.exit_code -ne 0) {
            $lifecycle.classification = "S4U_${modeUpper}_RESULT_RETRIEVAL_FAILED"
            throw "S4U $Mode result retrieval failed or timed out: $($copy.error)"
        }

        $result = Get-Content -LiteralPath $LocalResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$result.schema_version -ne 'sas-autologon-kerberos-s4u-worker-result/v1') {
            $lifecycle.classification = "S4U_${modeUpper}_RESULT_SCHEMA_BLOCKED"
            throw 'S4U worker returned an unsupported result schema.'
        }
        if ([bool]$result.default_password_value_collected) {
            $lifecycle.classification = "S4U_${modeUpper}_SECRET_COLLECTION_BLOCKED"
            throw 'S4U worker violated the DefaultPassword non-collection contract.'
        }
        $lifecycle.result_retrieved = $true
        $lifecycle.result = $result
        $lifecycle.current_stage = 'result_retrieved'
        $lifecycle.timestamps.result_retrieved_utc = (Get-Date).ToUniversalTime().ToString('o')
        Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle
        Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $ResultStage -Name "$Mode result" -Status PASS
    }
    catch {
        $lifecycle.error = $_.Exception.Message
        if ([string]$lifecycle.classification -notmatch '^S4U_') {
            $lifecycle.classification = "S4U_${modeUpper}_FAILED"
        }
        Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle
        Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number ([int]$ResultStage) -Name "$Mode task" -Status FAIL -Classification ([string]$lifecycle.classification) -Detail $lifecycle.error
    }
    finally {
        Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $CleanupStage -Name "$Mode cleanup" -Status START
        $lifecycle.delete_attempted = $true
        $lifecycle.current_stage = 'delete_attempted'
        $lifecycle.timestamps.delete_attempted_utc = (Get-Date).ToUniversalTime().ToString('o')
        Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle

        $delete = Invoke-SasBoundedNative -FilePath "$env:WINDIR\System32\schtasks.exe" -Arguments @(
            '/Delete','/S',$Target,'/TN',$TaskName,'/F'
        ) -TimeoutSeconds $NativeTimeoutSeconds
        $lifecycle.native.delete = $delete
        $lifecycle.delete_succeeded = (-not [bool]$delete.timed_out -and
            ([int]$delete.exit_code -eq 0 -or (Test-SasS4UTaskAbsentText -Text ([string]$delete.output))))
        $lifecycle.deleted = $lifecycle.delete_succeeded
        if ($lifecycle.delete_succeeded) {
            $lifecycle.timestamps.delete_succeeded_utc = (Get-Date).ToUniversalTime().ToString('o')
        }

        $query = Invoke-SasBoundedNative -FilePath "$env:WINDIR\System32\schtasks.exe" -Arguments @(
            '/Query','/S',$Target,'/TN',$TaskName
        ) -TimeoutSeconds $NativeTimeoutSeconds
        $lifecycle.native.query = $query
        $lifecycle.absent_verified = (-not [bool]$query.timed_out -and [int]$query.exit_code -ne 0 -and
            (Test-SasS4UTaskAbsentText -Text (([string]$query.output) + "`n" + ([string]$query.error))))
        if ($lifecycle.absent_verified) {
            $lifecycle.timestamps.absent_verified_utc = (Get-Date).ToUniversalTime().ToString('o')
        }

        if ($lifecycle.result_retrieved -and $lifecycle.delete_succeeded -and $lifecycle.absent_verified -and -not $lifecycle.error) {
            $lifecycle.classification = "S4U_${modeUpper}_COMPLETED"
            $lifecycle.current_stage = 'completed'
            Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $CleanupStage -Name "$Mode cleanup" -Status PASS
        }
        elseif (-not $lifecycle.absent_verified) {
            if ([string]::IsNullOrWhiteSpace([string]$lifecycle.error)) {
                $lifecycle.error = "Exact S4U $Mode task absence could not be verified."
            }
            if ([string]$lifecycle.classification -notmatch 'TIMEOUT|FAILED|BLOCKED') {
                $lifecycle.classification = "S4U_${modeUpper}_CLEANUP_UNVERIFIED"
            }
            $lifecycle.current_stage = 'cleanup_unverified'
            Write-SasS4UStage -EvidenceRoot $EvidenceRoot -RunId $RunId -Number $CleanupStage -Name "$Mode cleanup" -Status FAIL -Classification ([string]$lifecycle.classification) -Detail $lifecycle.error
        }
        Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle
    }

    [pscustomobject]$lifecycle
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$catalogPath = Join-Path -Path $repoRoot -ChildPath 'configs\software-packages\approved-apps.json'
$harnessApiPath = Join-Path -Path $repoRoot -ChildPath 'harness\api\sas-harness-api.json'
$preflightScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-SasSoftwareDeploymentTransport.ps1'
$finalGateScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SasAutoLogonFinalStepGate.ps1'
$stateModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'SasAutoLogonSmbStateRecovery.psm1'
$networkGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasNetworkGuard.psm1'
$targetResolutionModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetNameResolution.psm1'
$sourceIdentityModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasSoftwareSourceIdentity.psm1'
$baselinePolicyModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasAutoLogonBaselinePolicy.psm1'
$boundedNativeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasBoundedNative.psm1'
$exactCleanupScript = Join-Path -Path $PSScriptRoot -ChildPath 'Remove-SasExactRemoteAutoLogonRunRoot.ps1'

foreach ($required in @(
    $catalogPath,$harnessApiPath,$preflightScript,$finalGateScript,$stateModulePath,$networkGuardModule,
    $targetResolutionModule,$sourceIdentityModule,$baselinePolicyModule,$boundedNativeModule,$exactCleanupScript
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing Kerberos S4U AutoLogon dependency: $required"
    }
}

Import-Module $stateModulePath -Force
Import-Module $targetResolutionModule -Force
Import-Module $sourceIdentityModule -Force
Import-Module $baselinePolicyModule -Force
Import-Module $boundedNativeModule -Force

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey\output\runs\autologon-kerberos-s4u'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

if ($FixtureMode) {
    $fixtureRoot = Join-Path -Path $OutputRoot -ChildPath 'fixture-autologon-kerberos-s4u'
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $fixture = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-kerberos-s4u-pilot-result/v1'
        classification = 'KERBEROS_S4U_FIXTURE_READY'
        fixture_mode = $true
        target_mutation_performed = $false
        network_activity_performed = $false
        task_logon_type = 'S4U'
        task_run_level = 'HighestAvailable'
        password_supplied_or_stored = $false
        target_user_session_required = $false
        task_network_access_expected = $false
        default_password_value_collected = $false
        automatic_reboot_performed = $false
        automatic_sign_in_observed = $false
        canonical_system_qualification_changed = $false
        proof_level = 'sanitized_fixture_contract'
        proof_ceiling = 'Fixture only; no live Kerberos identity, S4U task, installer execution, registry state, reboot, or automatic sign-in is proven.'
    }
    $fixturePath = Join-Path -Path $fixtureRoot -ChildPath 'autologon_kerberos_s4u_pilot_result.json'
    Write-SasS4UJson -Path $fixturePath -Value $fixture
    if ($PassThru) {
        return [pscustomobject]@{ classification=$fixture.classification; result_path=$fixturePath; result=$fixture }
    }
    Write-Host $fixture.classification -ForegroundColor Green
    return
}

$package = Get-SasS4UApprovedPackage -CatalogPath $catalogPath -HarnessApiPath $harnessApiPath
$operator = Get-SasS4UOperatorIdentity
$runId = 'autologon-kerberos-s4u-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$stateRunId = 'autologon-recovery-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$gateRunId = 'autologon-delta-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path -Path $OutputRoot -ChildPath $runId
$evidenceRoot = Join-Path -Path $runRoot -ChildPath 'evidence'
$actionsRoot = Join-Path -Path $runRoot -ChildPath 'actions'
New-Item -ItemType Directory -Path $runRoot,$evidenceRoot,$actionsRoot -Force | Out-Null
$resultPath = Join-Path -Path $runRoot -ChildPath 'autologon_kerberos_s4u_pilot_result.json'

$classification = 'KERBEROS_S4U_AUTOLOGON_FAILED'
$errorMessage = $null
$preflightPath = $null
$baseline = $null
$after = $null
$gate = $null
$probeLifecycle = $null
$installLifecycle = $null
$sourceHash = $null
$targetHash = $null
$targetResolution = $null
$sourceIdentity = $null
$resolvedTarget = $null
$stagingCleanupVerified = $false
$installerExitCode = $null
$sourceHashVerified = $false
$afterReady = $false
$targetMutationPerformed = $false
$stagingStarted = $false
$shareTicket = $null
$targetKerberosProven = $false

try {
    Import-Module $networkGuardModule -Force
    Assert-SasNorthwellWifi

    $targetResolution = Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName
    if (@($targetResolution.addresses).Count -lt 1) { throw 'Target resolution returned no address.' }
    $resolvedTarget = [string]$targetResolution.fqdn
    Write-SasS4UJson -Path (Join-Path -Path $evidenceRoot -ChildPath 'target_resolution.json') -Value $targetResolution

    Write-Host "Target: $resolvedTarget" -ForegroundColor Cyan
    Write-Host "S4U principal: $($operator.name)" -ForegroundColor Cyan
    Write-Host "Package: $($package.display_name)"
    Write-Host 'Target login required: No' -ForegroundColor Green
    Write-Host 'Task password stored: No' -ForegroundColor Green
    Write-Host 'Canonical LocalSystem qualification remains unchanged.' -ForegroundColor Yellow

    if (-not $AllowTargetMutation -or -not $ConfirmS4U) {
        $ack = (Read-Host "Type S4U $($targetResolution.short_name) to run the one-target remote AutoLogon pilot").Trim()
        if ($ack -cne "S4U $($targetResolution.short_name)") {
            throw 'Kerberos S4U AutoLogon acknowledgement was not supplied.'
        }
        $AllowTargetMutation = $true
        $ConfirmS4U = $true
    }

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 1 -Name 'transport preflight' -Status START
    $preflight = & $preflightScript -ComputerName $resolvedTarget -AllowNetworkActivity -TransportIntent kerberos_smb_task `
        -OutputRoot (Join-Path -Path $runRoot -ChildPath 'preflight') -PassThru
    $preflightPath = [string]$preflight.result_path
    if ([string]$preflight.result.decision.classification -ne 'kerberos_smb_task_ready') {
        $classification = 'KERBEROS_S4U_TRANSPORT_BLOCKED'
        throw "Kerberos SMB/task preflight did not pass: $($preflight.result.decision.classification)"
    }
    $observations = $preflight.result.observations
    $targetKerberosProven = ([bool]$observations.identity.tgt_present -and
        [bool]$observations.service_tickets.cifs.issued -and [bool]$observations.service_tickets.host.issued -and
        [bool]$observations.admin_share.authorized -and [bool]$observations.scheduled_task_query.succeeded)
    if (-not $targetKerberosProven) {
        $classification = 'KERBEROS_S4U_KERBEROS_IDENTITY_BLOCKED'
        throw 'Preflight did not prove the current token has the required TGT, target CIFS/HOST tickets, admin-share authorization, and Task Scheduler authorization.'
    }
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 1 -Name 'transport preflight' -Status PASS

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 2 -Name 'canonical software source resolution' -Status START
    $sourceIdentity = Resolve-SasCanonicalSoftwareSourceIdentity -ApprovedServer $package.source_server
    Write-SasS4UJson -Path (Join-Path -Path $evidenceRoot -ChildPath 'software_source_identity.json') -Value $sourceIdentity
    if (-not [bool]$sourceIdentity.address_overlap_verified) {
        $classification = 'KERBEROS_S4U_SOFTWARE_SOURCE_IDENTITY_BLOCKED'
        throw 'Canonical software-source identity was not tied to the approved alias by address overlap.'
    }
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 2 -Name 'canonical software source resolution' -Status PASS -Detail ([string]$sourceIdentity.canonical_fqdn)

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 3 -Name 'source CIFS ticket' -Status START
    $shareTicket = Request-SasS4UKerberosTicket -Spn ([string]$sourceIdentity.cifs_spn) -TimeoutSeconds $NativeTaskTimeoutSeconds
    Write-SasS4UJson -Path (Join-Path -Path $evidenceRoot -ChildPath 'software_source_kerberos_ticket.json') -Value $shareTicket
    if (-not [bool]$shareTicket.issued) {
        $classification = 'KERBEROS_S4U_SOFTWARE_SOURCE_KERBEROS_BLOCKED'
        throw 'Kerberos service ticket for the approved canonical software-source identity was not issued.'
    }
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 3 -Name 'source CIFS ticket' -Status PASS

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 4 -Name 'baseline capture' -Status START
    $baseline = Invoke-SasAutoLogonSmbStateCapture -ComputerName $resolvedTarget -RunId $stateRunId -Phase baseline `
        -PreflightResultPath $preflightPath -LocalRunRoot (Join-Path -Path $evidenceRoot -ChildPath 'baseline') `
        -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
        -ResultTimeoutSeconds $StateResultTimeoutSeconds
    Write-SasS4UJson -Path (Join-Path -Path $evidenceRoot -ChildPath 'baseline_lifecycle.json') -Value $baseline
    if ($baseline.snapshot) {
        Write-SasS4UJson -Path (Join-Path -Path $evidenceRoot -ChildPath 'baseline_snapshot.json') -Value $baseline.snapshot
    }
    if (-not (Test-SasS4UCaptureComplete -Lifecycle $baseline)) {
        $classification = 'KERBEROS_S4U_BASELINE_BLOCKED'
        throw "Baseline collection or cleanup failed: $($baseline.status). $($baseline.error)"
    }
    if (-not ([string]$baseline.snapshot.computer_name).Equals([string]$targetResolution.short_name, [StringComparison]::OrdinalIgnoreCase)) {
        $classification = 'KERBEROS_S4U_TARGET_IDENTITY_BLOCKED'
        throw 'Baseline endpoint identity does not match the resolved target.'
    }
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 4 -Name 'baseline capture' -Status PASS

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 5 -Name 'baseline eligibility' -Status START
    if (-not (Test-SasAutoLogonFirstInstallBaseline -Snapshot $baseline.snapshot)) {
        $classification = 'KERBEROS_S4U_DIRTY_BASELINE'
        throw 'Target is not an exact safe first-install AutoLogon baseline. Do not reinstall blindly.'
    }
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 5 -Name 'baseline eligibility' -Status PASS -Detail ([string]$baseline.snapshot.autologon.status)

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 6 -Name 'final-step gate' -Status START
    $beforeManifest = [pscustomobject][ordered]@{
        run_id = $gateRunId
        phase = 'before_complete'
        targets = @([pscustomobject]@{ computer_name=$resolvedTarget; hostname=$resolvedTarget })
        source_snapshot = (Join-Path -Path $evidenceRoot -ChildPath 'baseline_snapshot.json')
    }
    $beforeManifestPath = Join-Path -Path $actionsRoot -ChildPath 's4u_before_manifest.json'
    Write-SasS4UJson -Path $beforeManifestPath -Value $beforeManifest
    $gateRoot = Join-Path -Path $evidenceRoot -ChildPath 'final-gate'
    $gate = & $finalGateScript -Target $resolvedTarget -RunId $gateRunId -BeforeSnapshotPath $beforeManifestPath `
        -ApprovedAppsPath $catalogPath -OutputRoot $gateRoot -ExecContext remote -TechnicianLabel $TechnicianLabel
    if (-not [bool]$gate.overall_pass) {
        $classification = 'KERBEROS_S4U_FINAL_GATE_BLOCKED'
        throw "AutoLogon final-step gate blocked execution: $($gate.blocked_reason)"
    }
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 6 -Name 'final-step gate' -Status PASS

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 7 -Name 'source hash' -Status START
    $canonicalSourceRoot = ([string]$sourceIdentity.canonical_unc_root).TrimEnd('\') + '\'
    $sourcePath = $canonicalSourceRoot + $package.installer_relative_path
    $sourceExists = Test-SasS4UBoundedRemotePath -Path $sourcePath -PathType Leaf -TimeoutSeconds $RemoteProbeTimeoutSeconds
    if (-not [bool]$sourceExists.exists) {
        $classification = 'KERBEROS_S4U_SOURCE_BLOCKED'
        if ([bool]$sourceExists.timed_out) {
            throw 'Timed out checking the approved AutoLogon installer through the canonical Kerberos source identity.'
        }
        throw "Approved AutoLogon installer is unavailable through the canonical source identity: $sourcePath"
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 7 -Name 'source hash' -Status PASS -Detail $sourceHash

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 8 -Name 'staging/hash verification' -Status START
    $cRoot = "\\$resolvedTarget\C$"
    $remoteWindowsRoot = "C:\ProgramData\SysAdminSuite\AutoLogonKerberosS4U\$runId"
    $remoteUncRoot = "$cRoot\ProgramData\SysAdminSuite\AutoLogonKerberosS4U\$runId"
    New-Item -ItemType Directory -Path $remoteUncRoot -Force | Out-Null
    $targetMutationPerformed = $true
    $stagingStarted = $true
    $remoteInstaller = Join-Path -Path $remoteWindowsRoot -ChildPath $package.installer_file
    $remoteInstallerUnc = Join-Path -Path $remoteUncRoot -ChildPath $package.installer_file
    Copy-Item -LiteralPath $sourcePath -Destination $remoteInstallerUnc -Force -ErrorAction Stop
    $targetHash = (Get-FileHash -LiteralPath $remoteInstallerUnc -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourceHashVerified = $sourceHash -eq $targetHash
    if (-not $sourceHashVerified) {
        $classification = 'KERBEROS_S4U_STAGE_HASH_BLOCKED'
        throw 'Staged AutoLogon installer SHA-256 does not match the approved source copy.'
    }
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 8 -Name 'staging/hash verification' -Status PASS

    $probeWorkerLocal = Join-Path -Path $actionsRoot -ChildPath 's4u-probe-worker.ps1'
    $probeWorkerRemote = Join-Path -Path $remoteWindowsRoot -ChildPath 's4u-probe-worker.ps1'
    $probeWorkerRemoteUnc = Join-Path -Path $remoteUncRoot -ChildPath 's4u-probe-worker.ps1'
    $probeResultRemote = Join-Path -Path $remoteWindowsRoot -ChildPath 's4u-probe-result.json'
    $probeResultRemoteUnc = Join-Path -Path $remoteUncRoot -ChildPath 's4u-probe-result.json'
    $probeResultLocal = Join-Path -Path $evidenceRoot -ChildPath 's4u_probe_result.json'
    $probeLifecyclePath = Join-Path -Path $evidenceRoot -ChildPath 's4u_probe_lifecycle.json'
    New-SasS4UWorker -Path $probeWorkerLocal -Mode Probe -ExpectedSid $operator.sid -ResultPath $probeResultRemote
    Copy-Item -LiteralPath $probeWorkerLocal -Destination $probeWorkerRemoteUnc -Force -ErrorAction Stop
    $probeTask = 'SysAdminSuite-AutoLogonS4UProbe-{0}' -f ([guid]::NewGuid().ToString('N'))

    $probeLifecycle = Invoke-SasS4UTask -Target $resolvedTarget -TaskName $probeTask -RunId $runId -Mode Probe `
        -PrincipalName $operator.name -WorkerPath $probeWorkerRemote -RemoteResultPath $probeResultRemote `
        -RemoteResultUnc $probeResultRemoteUnc -LocalResultPath $probeResultLocal -LifecyclePath $probeLifecyclePath `
        -EvidenceRoot $evidenceRoot -TimeoutSeconds 120 -NativeTimeoutSeconds $NativeTaskTimeoutSeconds `
        -RemoteProbeTimeoutSeconds $RemoteProbeTimeoutSeconds -CreateStage 9 -RunStage 10 -ResultStage 11 -CleanupStage 12

    if (-not $probeLifecycle.result_retrieved -or -not $probeLifecycle.delete_succeeded -or -not $probeLifecycle.absent_verified) {
        $classification = [string]$probeLifecycle.classification
        if ([string]::IsNullOrWhiteSpace($classification)) { $classification = 'KERBEROS_S4U_PROBE_FAILED' }
        throw "S4U probe failed or cleanup was not verified: $($probeLifecycle.error)"
    }
    if (-not [bool]$probeLifecycle.result.completed -or -not [bool]$probeLifecycle.result.identity_matches_expected_sid -or
        -not [bool]$probeLifecycle.result.is_administrator) {
        $classification = 'KERBEROS_S4U_PRINCIPAL_NOT_ELEVATED'
        throw "S4U principal did not execute with the expected elevated administrator token: $($probeLifecycle.result.error)"
    }

    $installWorkerLocal = Join-Path -Path $actionsRoot -ChildPath 's4u-install-worker.ps1'
    $installWorkerRemote = Join-Path -Path $remoteWindowsRoot -ChildPath 's4u-install-worker.ps1'
    $installWorkerRemoteUnc = Join-Path -Path $remoteUncRoot -ChildPath 's4u-install-worker.ps1'
    $installResultRemote = Join-Path -Path $remoteWindowsRoot -ChildPath 's4u-install-result.json'
    $installResultRemoteUnc = Join-Path -Path $remoteUncRoot -ChildPath 's4u-install-result.json'
    $installResultLocal = Join-Path -Path $evidenceRoot -ChildPath 's4u_install_result.json'
    $installLifecyclePath = Join-Path -Path $evidenceRoot -ChildPath 's4u_install_lifecycle.json'
    New-SasS4UWorker -Path $installWorkerLocal -Mode Install -ExpectedSid $operator.sid -ResultPath $installResultRemote `
        -InstallerPath $remoteInstaller -InstallerSha256 $sourceHash
    Copy-Item -LiteralPath $installWorkerLocal -Destination $installWorkerRemoteUnc -Force -ErrorAction Stop
    $installTask = 'SysAdminSuite-AutoLogonS4UInstall-{0}' -f ([guid]::NewGuid().ToString('N'))

    Write-Host ''
    Write-Host "Starting AutoLogon remotely as S4U principal $($operator.name)." -ForegroundColor Cyan
    Write-Host 'No target login is required. The S4U task has local-resource access only.' -ForegroundColor Green

    $installLifecycle = Invoke-SasS4UTask -Target $resolvedTarget -TaskName $installTask -RunId $runId -Mode Install `
        -PrincipalName $operator.name -WorkerPath $installWorkerRemote -RemoteResultPath $installResultRemote `
        -RemoteResultUnc $installResultRemoteUnc -LocalResultPath $installResultLocal -LifecyclePath $installLifecyclePath `
        -EvidenceRoot $evidenceRoot -TimeoutSeconds $S4UResultTimeoutSeconds -NativeTimeoutSeconds $NativeTaskTimeoutSeconds `
        -RemoteProbeTimeoutSeconds $RemoteProbeTimeoutSeconds -CreateStage 13 -RunStage 14 -ResultStage 15 -CleanupStage 16

    if (-not $installLifecycle.result_retrieved -or -not $installLifecycle.delete_succeeded -or -not $installLifecycle.absent_verified) {
        $classification = [string]$installLifecycle.classification
        if ([string]::IsNullOrWhiteSpace($classification)) { $classification = 'KERBEROS_S4U_INSTALL_TASK_FAILED' }
        throw "S4U installer task failed or cleanup was not verified: $($installLifecycle.error)"
    }
    if (-not [bool]$installLifecycle.result.completed -or -not [bool]$installLifecycle.result.installer_sha256_verified) {
        $classification = 'KERBEROS_S4U_INSTALLER_FAILED'
        throw "S4U installer worker failed: $($installLifecycle.result.error)"
    }
    $installerExitCode = [int]$installLifecycle.result.installer_exit_code
    if ($installerExitCode -notin @(0,3010)) {
        $classification = 'KERBEROS_S4U_INSTALLER_FAILED'
        throw "AutoLogon installer returned unsupported exit code $installerExitCode."
    }

    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 17 -Name 'after-state capture' -Status START
    $after = Invoke-SasAutoLogonSmbStateCapture -ComputerName $resolvedTarget -RunId $stateRunId -Phase after `
        -PreflightResultPath $preflightPath -LocalRunRoot (Join-Path -Path $evidenceRoot -ChildPath 'after') `
        -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
        -ResultTimeoutSeconds $StateResultTimeoutSeconds
    Write-SasS4UJson -Path (Join-Path -Path $evidenceRoot -ChildPath 'after_lifecycle.json') -Value $after
    if ($after.snapshot) {
        Write-SasS4UJson -Path (Join-Path -Path $evidenceRoot -ChildPath 'after_snapshot.json') -Value $after.snapshot
    }
    if (-not (Test-SasS4UCaptureComplete -Lifecycle $after)) {
        $classification = 'KERBEROS_S4U_AFTER_CAPTURE_FAILED'
        throw "After collection or cleanup failed: $($after.status). $($after.error)"
    }
    if (-not ([string]$after.snapshot.computer_name).Equals([string]$targetResolution.short_name, [StringComparison]::OrdinalIgnoreCase)) {
        $classification = 'KERBEROS_S4U_TARGET_IDENTITY_BLOCKED'
        throw 'After endpoint identity does not match the resolved target.'
    }

    $post = $after.snapshot.autologon
    $afterReady = ([string]$post.postinstall_set_autologon -eq 'Autologon_YES' -and
        [string]$post.auto_admin_logon -eq '1' -and [bool]$post.default_password_present -and
        [bool]$post.expected_user_match -and [string]$post.status -eq 'autologon_ready')
    if (-not $afterReady) {
        $classification = 'KERBEROS_S4U_POSTCONDITION_FAILED'
        throw 'S4U installer completed, but required pre-reboot AutoLogon registry postconditions were not established.'
    }
    Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 17 -Name 'after-state capture' -Status PASS

    $classification = 'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING'
}
catch {
    $errorMessage = $_.Exception.Message
}
finally {
    if ($resolvedTarget -and $runId -and $stagingStarted) {
        try {
            Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 18 -Name 'staging cleanup' -Status START
            $cleanup = & $exactCleanupScript -ComputerName $resolvedTarget -RunId $runId -ConfirmExactCleanup -TimeoutSeconds $NativeTaskTimeoutSeconds
            $stagingCleanupVerified = ([string]$cleanup.classification -eq 'EXACT_REMOTE_AUTOLOGON_RUN_ROOT_CLEANED' -and
                [bool]$cleanup.exact_run_root_absent)
            Write-SasS4UJson -Path (Join-Path -Path $evidenceRoot -ChildPath 'staging_cleanup_result.json') -Value $cleanup
            if ($stagingCleanupVerified) {
                Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 18 -Name 'staging cleanup' -Status PASS
            } else {
                Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 18 -Name 'staging cleanup' -Status FAIL
            }
        }
        catch {
            $stagingCleanupVerified = $false
            Write-SasS4UStage -EvidenceRoot $evidenceRoot -RunId $runId -Number 18 -Name 'staging cleanup' -Status FAIL -Detail $_.Exception.Message
            if ($errorMessage) {
                $errorMessage = "$errorMessage; S4U staging cleanup failed: $($_.Exception.Message)"
            } else {
                $errorMessage = "S4U staging cleanup failed: $($_.Exception.Message)"
            }
        }
    }
    elseif (-not $stagingStarted) {
        $stagingCleanupVerified = $true
    }
}

if ($classification -eq 'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING' -and -not $stagingCleanupVerified) {
    $classification = 'KERBEROS_S4U_CLEANUP_REVIEW_REQUIRED'
}

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-kerberos-s4u-pilot-result/v2'
    run_id = $runId
    classification = $classification
    reason = $errorMessage
    fixture_mode = $false
    target = $resolvedTarget
    target_resolution = $targetResolution
    software_source_identity = $sourceIdentity
    authorization = [pscustomobject][ordered]@{
        authorized_by = $AuthorizedBy
        request_reference = $RequestReference
        change_reference = $ChangeReference
        ticket_reference = $TicketReference
    }
    execution = [pscustomobject][ordered]@{
        principal = $operator.name
        principal_sid = $operator.sid
        transport = 'kerberos_smb_remote_task_scheduler'
        task_logon_type = 'S4U'
        task_run_level = 'HighestAvailable'
        password_supplied_or_stored = $false
        target_user_session_required = $false
        task_network_access_expected = $false
        controller_tgt_and_target_service_tickets_proven = $targetKerberosProven
        software_source_cifs_ticket_proven = ($shareTicket -and [bool]$shareTicket.issued)
        native_task_timeout_seconds = $NativeTaskTimeoutSeconds
        remote_probe_timeout_seconds = $RemoteProbeTimeoutSeconds
    }
    package = [pscustomobject][ordered]@{
        id = $package.id
        display_name = $package.display_name
        installer_file = $package.installer_file
        installer_arguments = @()
        source_sha256 = $sourceHash
        staged_sha256 = $targetHash
        source_target_hash_match = $sourceHashVerified
        canonical_system_install_enabled = $package.canonical_system_install_enabled
        canonical_system_qualification_status = $package.canonical_system_qualification_status
        canonical_system_qualification_changed = $false
    }
    probe = $probeLifecycle
    install = $installLifecycle
    installer_exit_code = $installerExitCode
    preflight_result_path = $preflightPath
    final_step_gate_passed = ($gate -and [bool]$gate.overall_pass)
    before_snapshot_path = $(if ($baseline -and $baseline.snapshot) { Join-Path -Path $evidenceRoot -ChildPath 'baseline_snapshot.json' } else { $null })
    after_snapshot_path = $(if ($after -and $after.snapshot) { Join-Path -Path $evidenceRoot -ChildPath 'after_snapshot.json' } else { $null })
    pre_reboot_autologon_ready = $afterReady
    staging_cleanup_verified = $stagingCleanupVerified
    target_mutation_performed = $targetMutationPerformed
    network_activity_performed = $true
    default_password_value_collected = $false
    automatic_reboot_performed = $false
    automatic_sign_in_observed = $false
    canonical_system_qualification_changed = $false
    proof_level = $(if ($classification -eq 'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING') {
        'live_kerberos_s4u_admin_install_pre_reboot_state'
    } else { 'insufficient' })
    proof_ceiling = 'This lane can prove Kerberos-authenticated controller authorization, passwordless elevated S4U execution, exact staged package hash, and required pre-reboot AutoLogon registry posture. It does not prove reboot completion, automatic sign-in, post-reboot application behavior, or LocalSystem compatibility.'
}
Write-SasS4UJson -Path $resultPath -Value $result

Write-Host ''
$color = if ($classification -eq 'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING') { 'Green' } else { 'Yellow' }
Write-Host "AutoLogon Kerberos S4U pilot: $classification" -ForegroundColor $color
Write-Host "Evidence: $resultPath"
if ($classification -eq 'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING') {
    Write-Host 'Remote pre-reboot AutoLogon state is configured. Target login was not required.' -ForegroundColor Green
    Write-Host 'Next proof gate is the separately approved restart and restart-cycle observation.' -ForegroundColor Cyan
}
else {
    Write-Host "Reason: $errorMessage" -ForegroundColor Yellow
}

if ($PassThru) {
    return [pscustomobject]@{ classification=$classification; result_path=$resultPath; result=$result }
}
if ($classification -ne 'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING') {
    throw "AutoLogon Kerberos S4U pilot stopped at $classification. $errorMessage"
}
exit 0
