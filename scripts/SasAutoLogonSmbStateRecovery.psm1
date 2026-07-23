#Requires -Version 5.1
<#
.SYNOPSIS
Collect AutoLogon state through the canonical Kerberos SMB and Remote Task Scheduler boundary.
.DESCRIPTION
Stages one transient read-only worker, executes it once as LocalSystem, retrieves a nonce-bound
closed snapshot, and verifies task and staging teardown. The collector never reads DefaultPassword
data, accepts no credentials, and performs no configuration or software mutation. The temporary
worker and scheduled task are target mutations and therefore require explicit acknowledgements.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-SasAutoLogonRecoveryFqdn {
    param([Parameter(Mandatory = $true)][string]$ComputerName)
    return ($ComputerName -match '^(?=.{1,253}$)(?=.{1,63}\.)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$')
}

function Invoke-SasAutoLogonRecoverySchtasksCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = @(& "$env:WINDIR\System32\schtasks.exe" @Arguments 2>&1 | ForEach-Object { [string]$_ })
    [pscustomobject]@{
        exit_code = [int]$LASTEXITCODE
        output = ($output -join [Environment]::NewLine)
    }
}

function Test-SasAutoLogonRecoveryTaskAbsentText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot find|does not exist|not exist|cannot find the file')
}

function New-SasAutoLogonRecoveryWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('baseline','after','current')][string]$Phase,
        [Parameter(Mandatory = $true)][string]$Nonce,
        [Parameter(Mandatory = $true)][string]$ResultPath
    )

    $configuration = [ordered]@{
        run_id = $RunId
        phase = $Phase
        nonce = $Nonce
        result_path = $ResultPath
    }
    $configJson = $configuration | ConvertTo-Json -Depth 8 -Compress
    $configBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configJson))

    $worker = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$config = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CONFIG_BASE64__'))) | ConvertFrom-Json

function Get-RegistryValueSafe {
    param([string]$Path, [string]$Name)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        if (@($key.GetValueNames()) -notcontains $Name) { return $null }
        return $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    catch { return $null }
}

function Test-RegistryValueNameSafe {
    param([string]$Path, [string]$Name)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        return (@($key.GetValueNames()) -contains $Name)
    }
    catch { return $false }
}

function ConvertTo-AccountLeaf {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $leaf = $Value.Trim()
    if ($leaf.Contains('\')) { $leaf = $leaf.Split('\')[-1] }
    if ($leaf.Contains('@')) { $leaf = $leaf.Split('@')[0] }
    return $leaf.ToUpperInvariant()
}

function Get-AutoLogonStatus {
    param([string]$ExpectedName, [object]$IntentValue, [object]$EnabledValue, [object]$UserValue, [bool]$PasswordPresent)
    $expected = $ExpectedName.ToUpperInvariant()
    $actual = ConvertTo-AccountLeaf -Value ([string]$UserValue)
    $enabled = ([string]$EnabledValue).Trim() -in @('1', '0x1')
    $intent = ("$IntentValue").ToUpperInvariant().Replace('_', '').Replace(' ', '').Contains('AUTOLOGONYES')
    if ($enabled -and $actual -ne $expected) { return 'configured_user_mismatch' }
    if ($enabled -and $actual -eq $expected -and -not $PasswordPresent) { return 'configured_password_missing' }
    if ($enabled -and $actual -eq $expected -and $PasswordPresent) { return 'autologon_ready' }
    if ($intent) { return 'intent_only' }
    return 'not_configured'
}

function Get-InstalledSoftwareSafe {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $rows = foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                $name = [string]$item.DisplayName
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                [pscustomobject]@{
                    name = $name.Trim()
                    version = ([string]$item.DisplayVersion).Trim()
                    publisher = ([string]$item.Publisher).Trim()
                    install_date = ([string]$item.InstallDate).Trim()
                    registry_path = $key.Name
                }
            }
            catch {}
        }
    }
    return @($rows | Sort-Object -Property name, publisher, version, registry_path -Unique)
}

$result = [ordered]@{
    schema_version = 'sas-autologon-smb-state-worker-result/v1'
    run_id = [string]$config.run_id
    phase = [string]$config.phase
    nonce = [string]$config.nonce
    execution_identity_sid = $null
    execution_as_system = $false
    snapshot = $null
    result_complete = $false
    error = $null
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $result.execution_identity_sid = [string]$identity.User.Value
    $result.execution_as_system = ($result.execution_identity_sid -eq 'S-1-5-18')
    if (-not $result.execution_as_system) { throw 'State recovery task did not execute as LocalSystem.' }

    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $postInstallPath = 'HKLM:\SOFTWARE\NSLIJHS\PostInstall'
    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $intentValue = Get-RegistryValueSafe -Path $postInstallPath -Name 'SetAutoLogon'
    $enabledValue = Get-RegistryValueSafe -Path $winlogonPath -Name 'AutoAdminLogon'
    $userValue = Get-RegistryValueSafe -Path $winlogonPath -Name 'DefaultUserName'
    $domainValue = Get-RegistryValueSafe -Path $winlogonPath -Name 'DefaultDomainName'
    $forceValue = Get-RegistryValueSafe -Path $winlogonPath -Name 'ForceAutoLogon'
    $countValue = Get-RegistryValueSafe -Path $winlogonPath -Name 'AutoLogonCount'
    $passwordPresent = Test-RegistryValueNameSafe -Path $winlogonPath -Name 'DefaultPassword'
    $expectedUser = $env:COMPUTERNAME.ToUpperInvariant()
    $actualUser = ConvertTo-AccountLeaf -Value ([string]$userValue)

    $result.snapshot = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-state-snapshot/v1'
        snapshot_id = [guid]::NewGuid().ToString()
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        capture_phase = [string]$config.phase
        computer_name = $env:COMPUTERNAME.ToUpperInvariant()
        collection_status = 'success'
        error = $null
        identity = [pscustomobject][ordered]@{
            domain = $computer.Domain
            manufacturer = $computer.Manufacturer
            model = $computer.Model
            bios_serial = $bios.SerialNumber
            os_caption = $operatingSystem.Caption
            os_version = $operatingSystem.Version
            os_build = $operatingSystem.BuildNumber
            last_boot_time_utc = $(if ($operatingSystem.LastBootUpTime) { $operatingSystem.LastBootUpTime.ToUniversalTime().ToString('o') } else { $null })
            logged_on_user = $computer.UserName
        }
        autologon = [pscustomobject][ordered]@{
            postinstall_set_autologon = $intentValue
            auto_admin_logon = $enabledValue
            default_user_name = $userValue
            default_domain_name = $domainValue
            force_auto_logon = $forceValue
            auto_logon_count = $countValue
            default_password_present = [bool]$passwordPresent
            default_password_value_collected = $false
            expected_user_name = $expectedUser
            expected_user_match = ($actualUser -eq $expectedUser)
            status = Get-AutoLogonStatus -ExpectedName $env:COMPUTERNAME -IntentValue $intentValue -EnabledValue $enabledValue -UserValue $userValue -PasswordPresent ([bool]$passwordPresent)
        }
        installed_software = @(Get-InstalledSoftwareSafe)
        related_services = @()
        related_scheduled_tasks = @()
        reboot = [pscustomobject][ordered]@{
            component_based_servicing_pending = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
            windows_update_pending = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
            pending_file_rename_operations = (Test-RegistryValueNameSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations')
        }
        collection_notes = @(
            'read_only_state_collection_via_kerberos_smb_task',
            'default_password_value_not_collected',
            'transient_worker_cleanup_required'
        )
    }
    $result.result_complete = $true
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
    $result | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination ([string]$config.result_path) -Force
}
'@

    $worker = $worker.Replace('__CONFIG_BASE64__', $configBase64)
    $worker | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-SasAutoLogonRecoveryWorkerResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$Nonce
    )
    if ([string]$Result.schema_version -ne 'sas-autologon-smb-state-worker-result/v1') { throw 'State worker schema is invalid.' }
    if ([string]$Result.run_id -ne $RunId -or [string]$Result.phase -ne $Phase -or [string]$Result.nonce -ne $Nonce) {
        throw 'State worker identity or nonce is invalid.'
    }
    if (-not [bool]$Result.result_complete -or -not [bool]$Result.execution_as_system) {
        throw "State worker did not complete as LocalSystem: $($Result.error)"
    }
    if ($null -eq $Result.snapshot -or [string]$Result.snapshot.schema_version -ne 'sas-autologon-state-snapshot/v1' -or
        [string]$Result.snapshot.collection_status -ne 'success') {
        throw 'State worker returned an incomplete snapshot.'
    }
    if ([bool]$Result.snapshot.autologon.default_password_value_collected) {
        throw 'State worker violated the DefaultPassword non-collection contract.'
    }
    return $true
}

function New-SasAutoLogonRecoveryLifecycle {
    param([string]$RunId, [string]$ComputerName, [string]$Phase, [string]$TaskName)
    [ordered]@{
        schema_version = 'sas-autologon-smb-state-capture/v1'
        run_id = $RunId
        target = $ComputerName
        phase = $Phase
        transport = 'SmbScheduledTask'
        selected_before_mutation = $true
        preflight_classification = $null
        task = [ordered]@{
            name = $TaskName
            create_attempted = $false
            created = $false
            run_attempted = $false
            started = $false
            delete_attempted = $false
            deleted = $false
            absent_verified = $false
        }
        worker = [ordered]@{
            source_sha256 = $null
            target_sha256 = $null
            hash_verified = $false
            executed_as_system = $false
        }
        result_retrieval = [ordered]@{
            attempted = $false
            succeeded = $false
            malformed = $false
            local_path = $null
        }
        cleanup = [ordered]@{
            attempted = $false
            task_deletion_succeeded = $false
            run_root_deletion_succeeded = $false
            task_remaining = $false
            run_root_remaining = $false
        }
        snapshot = $null
        status = 'failed_before_staging'
        network_activity_performed = $false
        target_mutation_performed = $false
        configuration_mutation_performed = $false
        software_mutation_performed = $false
        default_password_value_collected = $false
        error = $null
    }
}

function Invoke-SasAutoLogonSmbStateCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('baseline','after','current')][string]$Phase,
        [Parameter(Mandatory = $true)][string]$PreflightResultPath,
        [Parameter(Mandatory = $true)][string]$LocalRunRoot,
        [Parameter(Mandatory = $true)][switch]$AllowNetworkActivity,
        [Parameter(Mandatory = $true)][switch]$AllowTargetMutation,
        [ValidateRange(1, 1440)][int]$PreflightMaxAgeMinutes = 15,
        [ValidateRange(10, 600)][int]$ResultTimeoutSeconds = 120
    )

    if (-not (Test-SasAutoLogonRecoveryFqdn -ComputerName $ComputerName)) { throw 'State recovery requires the exact authorized FQDN.' }
    if ($RunId -notmatch '^autologon-recovery-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { throw 'State recovery RunId is invalid.' }
    if (-not $AllowNetworkActivity) { throw 'SMB state recovery requires explicit -AllowNetworkActivity acknowledgement.' }
    if (-not $AllowTargetMutation) { throw 'SMB state recovery requires explicit -AllowTargetMutation acknowledgement for the transient task and staging root.' }
    if (-not (Test-Path -LiteralPath $LocalRunRoot -PathType Container)) { New-Item -ItemType Directory -Path $LocalRunRoot -Force | Out-Null }

    $adapterModule = Join-Path $PSScriptRoot 'SasSoftwareDeploymentAdapter.psm1'
    Import-Module $adapterModule -Force
    $preflight = Read-SasDeploymentTransportPreflight -Path $PreflightResultPath -MaxAgeMinutes $PreflightMaxAgeMinutes
    if ([string]$preflight.decision.classification -ne 'kerberos_smb_task_ready' -or
        [string]$preflight.decision.selected_transport -ne 'kerberos_smb_task' -or
        -not [bool]$preflight.proof.preflight_complete -or
        -not [bool]$preflight.proof.transport_authorization_proven) {
        throw 'SMB state recovery requires one fresh kerberos_smb_task_ready P02 result.'
    }

    $nonce = [guid]::NewGuid().ToString('N')
    $taskName = 'SysAdminSuite-AutoLogonStateRead-{0}' -f ([guid]::NewGuid().ToString('N'))
    $lifecycle = New-SasAutoLogonRecoveryLifecycle -RunId $RunId -ComputerName $ComputerName -Phase $Phase -TaskName $taskName
    $lifecycle.preflight_classification = [string]$preflight.decision.classification
    $cRoot = "\\$ComputerName\C$"
    $adminRoot = "\\$ComputerName\ADMIN$"
    $remoteWindowsRoot = "C:\ProgramData\SysAdminSuite\AutoLogonStateRecovery\$RunId\$Phase"
    $remoteUncRoot = Join-Path $cRoot "ProgramData\SysAdminSuite\AutoLogonStateRecovery\$RunId\$Phase"
    $remoteWorker = Join-Path $remoteWindowsRoot 'Invoke-StateReadWorker.ps1'
    $remoteWorkerUnc = Join-Path $remoteUncRoot 'Invoke-StateReadWorker.ps1'
    $remoteResult = Join-Path $remoteWindowsRoot 'worker-result.json'
    $remoteResultUnc = Join-Path $remoteUncRoot 'worker-result.json'
    $localWorker = Join-Path $LocalRunRoot ("state-worker-{0}.ps1" -f $nonce)
    $localResult = Join-Path $LocalRunRoot ("state-result-{0}-{1}.json" -f $Phase, $nonce)
    $stagingBegan = $false

    try {
        $lifecycle.network_activity_performed = $true
        if (-not (Test-Path -LiteralPath $adminRoot -PathType Container)) { throw 'ADMIN$ access denied or unavailable.' }
        if (-not (Test-Path -LiteralPath $cRoot -PathType Container)) { throw 'C$ access denied or unavailable.' }

        New-SasAutoLogonRecoveryWorker -Path $localWorker -RunId $RunId -Phase $Phase -Nonce $nonce -ResultPath $remoteResult
        $lifecycle.worker.source_sha256 = (Get-FileHash -LiteralPath $localWorker -Algorithm SHA256).Hash.ToLowerInvariant()
        New-Item -ItemType Directory -Path $remoteUncRoot -Force -ErrorAction Stop | Out-Null
        $stagingBegan = $true
        $lifecycle.target_mutation_performed = $true
        $lifecycle.cleanup.run_root_remaining = $true
        Copy-Item -LiteralPath $localWorker -Destination $remoteWorkerUnc -Force -ErrorAction Stop
        $lifecycle.worker.target_sha256 = (Get-FileHash -LiteralPath $remoteWorkerUnc -Algorithm SHA256).Hash.ToLowerInvariant()
        $lifecycle.worker.hash_verified = ($lifecycle.worker.source_sha256 -eq $lifecycle.worker.target_sha256)
        if (-not $lifecycle.worker.hash_verified) { throw 'Transient state worker SHA-256 mismatch.' }
        $lifecycle.status = 'staged_hash_verified'

        $when = (Get-Date).AddMinutes(1).ToString('HH:mm')
        $taskCommand = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $remoteWorker"
        $lifecycle.task.create_attempted = $true
        $create = Invoke-SasAutoLogonRecoverySchtasksCommand -Arguments @('/Create','/S',$ComputerName,'/RU','SYSTEM','/SC','ONCE','/ST',$when,'/TN',$taskName,'/TR',$taskCommand,'/RL','HIGHEST','/F')
        if ($create.exit_code -ne 0) { throw "State task creation failed: $($create.output)" }
        $lifecycle.task.created = $true
        $lifecycle.cleanup.task_remaining = $true

        $lifecycle.task.run_attempted = $true
        $run = Invoke-SasAutoLogonRecoverySchtasksCommand -Arguments @('/Run','/S',$ComputerName,'/TN',$taskName)
        if ($run.exit_code -ne 0) { throw "State task run failed: $($run.output)" }
        $lifecycle.task.started = $true
        $lifecycle.status = 'task_started'

        $lifecycle.result_retrieval.attempted = $true
        $deadline = (Get-Date).AddSeconds($ResultTimeoutSeconds)
        while (-not (Test-Path -LiteralPath $remoteResultUnc -PathType Leaf)) {
            if ((Get-Date) -ge $deadline) { throw "Timed out after $ResultTimeoutSeconds seconds waiting for the state result." }
            Start-Sleep -Seconds 2
        }
        Copy-Item -LiteralPath $remoteResultUnc -Destination $localResult -Force -ErrorAction Stop
        $lifecycle.result_retrieval.local_path = $localResult
        try {
            $workerResult = Get-Content -LiteralPath $localResult -Raw -Encoding UTF8 | ConvertFrom-Json
            $null = Test-SasAutoLogonRecoveryWorkerResult -Result $workerResult -RunId $RunId -Phase $Phase -Nonce $nonce
        }
        catch {
            $lifecycle.result_retrieval.malformed = $true
            throw "Retrieved state result is invalid: $($_.Exception.Message)"
        }
        $lifecycle.result_retrieval.succeeded = $true
        $lifecycle.worker.executed_as_system = [bool]$workerResult.execution_as_system
        $snapshot = $workerResult.snapshot
        $snapshot | Add-Member -NotePropertyName requested_target -NotePropertyValue $ComputerName -Force
        $snapshot | Add-Member -NotePropertyName collection_transport -NotePropertyValue 'kerberos_smb_task' -Force
        $lifecycle.snapshot = $snapshot
        $lifecycle.status = 'captured_pending_cleanup'
    }
    catch {
        $lifecycle.error = $_.Exception.Message
        if ($lifecycle.status -notin @('captured_pending_cleanup')) { $lifecycle.status = 'capture_failed_pending_cleanup' }
    }
    finally {
        if (Test-Path -LiteralPath $localWorker -PathType Leaf) { Remove-Item -LiteralPath $localWorker -Force -ErrorAction SilentlyContinue }
        if ($stagingBegan -or $lifecycle.task.create_attempted) {
            $lifecycle.cleanup.attempted = $true
            $lifecycle.task.delete_attempted = $true
            $delete = Invoke-SasAutoLogonRecoverySchtasksCommand -Arguments @('/Delete','/S',$ComputerName,'/TN',$taskName,'/F')
            $lifecycle.task.deleted = ($delete.exit_code -eq 0 -or (Test-SasAutoLogonRecoveryTaskAbsentText -Text $delete.output))
            $lifecycle.cleanup.task_deletion_succeeded = $lifecycle.task.deleted
            $query = Invoke-SasAutoLogonRecoverySchtasksCommand -Arguments @('/Query','/S',$ComputerName,'/TN',$taskName)
            $lifecycle.task.absent_verified = ($query.exit_code -ne 0 -and (Test-SasAutoLogonRecoveryTaskAbsentText -Text $query.output))
            $lifecycle.cleanup.task_remaining = (-not $lifecycle.task.absent_verified)
            try {
                if (Test-Path -LiteralPath $remoteUncRoot) { Remove-Item -LiteralPath $remoteUncRoot -Recurse -Force -ErrorAction Stop }
                $lifecycle.cleanup.run_root_remaining = Test-Path -LiteralPath $remoteUncRoot
                $lifecycle.cleanup.run_root_deletion_succeeded = (-not $lifecycle.cleanup.run_root_remaining)
            }
            catch {
                $lifecycle.cleanup.run_root_remaining = $true
                $lifecycle.cleanup.run_root_deletion_succeeded = $false
                if ($lifecycle.error) { $lifecycle.error = "$($lifecycle.error); state staging cleanup failed: $($_.Exception.Message)" }
                else { $lifecycle.error = "State staging cleanup failed: $($_.Exception.Message)" }
            }
        }
    }

    $cleanupComplete = ($lifecycle.cleanup.attempted -and $lifecycle.cleanup.task_deletion_succeeded -and
        $lifecycle.task.absent_verified -and $lifecycle.cleanup.run_root_deletion_succeeded -and
        -not $lifecycle.cleanup.task_remaining -and -not $lifecycle.cleanup.run_root_remaining)
    if (-not $cleanupComplete) {
        $lifecycle.status = 'cleanup_failed'
        if (-not $lifecycle.error) { $lifecycle.error = 'State task or staging teardown was not completely verified.' }
    }
    elseif ($lifecycle.result_retrieval.succeeded -and $lifecycle.worker.executed_as_system -and $lifecycle.worker.hash_verified) {
        $lifecycle.status = 'completed'
    }
    else {
        $lifecycle.status = 'capture_failed_cleaned'
    }
    return [pscustomobject]$lifecycle
}

function New-SasAutoLogonRecoveryFixtureSnapshot {
    param([string]$Target, [string]$Phase, [bool]$Ready)
    $software = @([pscustomobject]@{ name='Contoso Base Agent'; version='1.0'; publisher='Contoso'; install_date='20260101'; registry_path='fixture-base' })
    if ($Ready) { $software += [pscustomobject]@{ name='NW AutoLogon Setup x64'; version='1.0'; publisher='Northwell'; install_date='20260722'; registry_path='fixture-autologon' } }
    [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-state-snapshot/v1'
        snapshot_id = [guid]::NewGuid().ToString()
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        capture_phase = $Phase
        requested_target = $Target
        computer_name = $Target.ToUpperInvariant()
        collection_status = 'success'
        error = $null
        identity = [pscustomobject]@{ domain='fixture.invalid'; manufacturer='Fixture'; model='Fixture Workstation'; bios_serial='FIXTURE'; os_caption='Windows'; os_version='10.0'; os_build='26100'; last_boot_time_utc='2026-07-22T00:00:00Z'; logged_on_user='FIXTURE\TECH' }
        autologon = [pscustomobject]@{
            postinstall_set_autologon = $(if ($Ready) { 'Autologon_YES' } else { 'Autologon_NO' })
            auto_admin_logon = $(if ($Ready) { '1' } else { '0' })
            default_user_name = $(if ($Ready) { $Target.Split('.')[0].ToUpperInvariant() } else { '' })
            default_domain_name = $(if ($Ready) { 'FIXTURE' } else { '' })
            force_auto_logon = ''
            auto_logon_count = ''
            default_password_present = $Ready
            default_password_value_collected = $false
            expected_user_name = $Target.Split('.')[0].ToUpperInvariant()
            expected_user_match = $Ready
            status = $(if ($Ready) { 'autologon_ready' } else { 'not_configured' })
        }
        installed_software = @($software)
        related_services = @()
        related_scheduled_tasks = @()
        reboot = [pscustomobject]@{ component_based_servicing_pending=$false; windows_update_pending=$false; pending_file_rename_operations=$false }
        collection_notes = @('fixture_mode','no_network_activity','no_target_mutation')
        collection_transport = 'fixture'
    }
}

function Invoke-SasAutoLogonSmbStateCaptureFixture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)][ValidateSet('baseline','after','current')][string]$Phase,
        [ValidateSet('success','already_configured','capture_failure','cleanup_failure')][string]$Scenario = 'success'
    )
    if (-not [IO.Path]::IsPathRooted($FixtureRoot)) { throw 'FixtureRoot must be absolute.' }
    New-Item -ItemType Directory -Path $FixtureRoot -Force | Out-Null
    $target = 'fixture-autologon.example.invalid'
    $runId = 'autologon-recovery-20000101-000000-00000000'
    $taskName = 'SysAdminSuite-AutoLogonStateRead-00000000000000000000000000000000'
    $lifecycle = New-SasAutoLogonRecoveryLifecycle -RunId $runId -ComputerName $target -Phase $Phase -TaskName $taskName
    $lifecycle.preflight_classification = 'kerberos_smb_task_ready'
    if ($Scenario -eq 'capture_failure') {
        $lifecycle.status = 'capture_failed_cleaned'
        $lifecycle.cleanup.attempted = $true
        $lifecycle.cleanup.task_deletion_succeeded = $true
        $lifecycle.cleanup.run_root_deletion_succeeded = $true
        $lifecycle.task.absent_verified = $true
        $lifecycle.error = 'Synthetic state capture failure.'
        return [pscustomobject]$lifecycle
    }
    $ready = ($Scenario -eq 'already_configured' -or $Phase -eq 'after')
    $lifecycle.snapshot = New-SasAutoLogonRecoveryFixtureSnapshot -Target $target -Phase $Phase -Ready:$ready
    $lifecycle.worker.source_sha256 = ('1' * 64)
    $lifecycle.worker.target_sha256 = ('1' * 64)
    $lifecycle.worker.hash_verified = $true
    $lifecycle.worker.executed_as_system = $true
    $lifecycle.result_retrieval.attempted = $true
    $lifecycle.result_retrieval.succeeded = $true
    $lifecycle.cleanup.attempted = $true
    $lifecycle.task.created = $true
    $lifecycle.task.started = $true
    $lifecycle.task.deleted = ($Scenario -ne 'cleanup_failure')
    $lifecycle.task.absent_verified = ($Scenario -ne 'cleanup_failure')
    $lifecycle.cleanup.task_deletion_succeeded = ($Scenario -ne 'cleanup_failure')
    $lifecycle.cleanup.run_root_deletion_succeeded = ($Scenario -ne 'cleanup_failure')
    $lifecycle.cleanup.task_remaining = ($Scenario -eq 'cleanup_failure')
    $lifecycle.cleanup.run_root_remaining = ($Scenario -eq 'cleanup_failure')
    $lifecycle.status = $(if ($Scenario -eq 'cleanup_failure') { 'cleanup_failed' } else { 'completed' })
    if ($Scenario -eq 'cleanup_failure') { $lifecycle.error = 'Synthetic state recovery teardown failure.' }
    return [pscustomobject]$lifecycle
}

Export-ModuleMember -Function Test-SasAutoLogonRecoveryFqdn, New-SasAutoLogonRecoveryWorker, Test-SasAutoLogonRecoveryWorkerResult, Invoke-SasAutoLogonSmbStateCapture, Invoke-SasAutoLogonSmbStateCaptureFixture
