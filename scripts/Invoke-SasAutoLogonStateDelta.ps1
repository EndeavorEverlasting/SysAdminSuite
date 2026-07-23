#Requires -Version 5.1
<#
.SYNOPSIS
Capture and compare read-only workstation state before and after auto-logon work.

.DESCRIPTION
Uses explicit target names and PowerShell remoting to collect bounded Windows state. Evidence is
written only on the admin workstation under an approved, gitignored SysAdminSuite output root.
No SysAdminSuite script, report, transcript, or evidence file is written to target workstations.

The collector records auto-logon registry posture, installed software from uninstall registry
keys, selected related services and scheduled tasks, host identity, boot time, logged-on user,
and reboot indicators. It checks whether Winlogon's DefaultPassword value name exists, but never
reads or exports that value's data.

A state delta can prove that workstation state changed. It cannot prove which person performed
the change. TechnicianLabel is assignment metadata, not actor attribution.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Before', 'After', 'Assess')]
    [string]$Mode,

    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [string]$RunId,
    [string]$OutputRoot,
    [string]$TechnicianLabel,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasProperty {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Write-SasJson {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertTo-SasSafeName {
    param([string]$Value)
    return ($Value -replace '[^A-Za-z0-9._-]', '_')
}

function Get-SasTargets {
    param([string[]]$Direct, [string]$CsvPath, [int]$Limit)

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($target in @($Direct)) {
        if (-not [string]::IsNullOrWhiteSpace($target)) { $items.Add($target.Trim()) }
    }

    if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
        if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
            throw "TargetsCsv not found: $CsvPath"
        }
        foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
            $value = $null
            foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
                if ($row.PSObject.Properties.Name -contains $column) {
                    $candidate = [string]$row.$column
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $value = $candidate.Trim()
                        break
                    }
                }
            }
            if ($value) { $items.Add($value) }
        }
    }

    $targets = @($items | Sort-Object -Unique)
    if ($targets.Count -gt $Limit) {
        throw "Target count $($targets.Count) exceeds MaxTargets $Limit. Split the run to keep remote reads bounded."
    }
    return $targets
}

function Get-SasBaselineTargets {
    param([string]$BeforeDirectory)
    if (-not (Test-Path -LiteralPath $BeforeDirectory -PathType Container)) { return @() }

    $targets = foreach ($file in @(Get-ChildItem -LiteralPath $BeforeDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $snapshot = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $requested = [string](Get-SasProperty -Object $snapshot -Name 'requested_target' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($requested)) { $requested }
        }
        catch {
            Write-Warning "Unable to read baseline target from $($file.FullName): $($_.Exception.Message)"
        }
    }
    return @($targets | Sort-Object -Unique)
}

function New-SasFixtureSnapshot {
    param([string]$Target, [string]$Phase)

    $isAfter = $Phase -eq 'after'
    $software = @(
        [pscustomobject]@{
            name = 'Contoso Base Agent'
            version = '1.0.0'
            publisher = 'Contoso'
            install_date = '20260101'
            registry_path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ContosoBase'
        }
    )
    if ($isAfter) {
        $software += [pscustomobject]@{
            name = 'Sample Auto Logon Setup'
            version = '1.0.0'
            publisher = 'Sample Publisher'
            install_date = '20260713'
            registry_path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SampleAutoLogon'
        }
    }

    return [pscustomobject]@{
        schema_version = 'sas-autologon-state-snapshot/v1'
        snapshot_id = [guid]::NewGuid().ToString()
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        capture_phase = $Phase
        requested_target = $Target
        computer_name = $Target.ToUpperInvariant()
        collection_status = 'success'
        error = $null
        identity = [pscustomobject]@{
            domain = 'sample.local'
            manufacturer = 'Sample'
            model = 'Fixture Workstation'
            bios_serial = 'FIXTURE-SERIAL'
            os_caption = 'Microsoft Windows 11 Enterprise'
            os_version = '10.0.26100'
            os_build = '26100'
            last_boot_time_utc = $(if ($isAfter) { '2026-07-13T16:00:00Z' } else { '2026-07-13T12:00:00Z' })
            logged_on_user = $(if ($isAfter) { "SAMPLE\$($Target.ToUpperInvariant())" } else { 'SAMPLE\TECH' })
        }
        autologon = [pscustomobject]@{
            postinstall_set_autologon = $(if ($isAfter) { 'Autologon_YES' } else { 'Autologon_NO' })
            auto_admin_logon = $(if ($isAfter) { '1' } else { '0' })
            default_user_name = $(if ($isAfter) { $Target.ToUpperInvariant() } else { '' })
            default_domain_name = $(if ($isAfter) { 'SAMPLE' } else { '' })
            force_auto_logon = ''
            auto_logon_count = ''
            default_password_present = [bool]$isAfter
            default_password_value_collected = $false
            expected_user_name = $Target.ToUpperInvariant()
            expected_user_match = [bool]$isAfter
            status = $(if ($isAfter) { 'autologon_ready' } else { 'not_configured' })
        }
        installed_software = @($software)
        related_services = @()
        related_scheduled_tasks = @()
        reboot = [pscustomobject]@{
            component_based_servicing_pending = $false
            windows_update_pending = $false
            pending_file_rename_operations = $false
        }
        collection_notes = @('fixture_mode', 'no_network_activity', 'no_target_mutation')
    }
}

$remoteCollector = {
    param([string]$Phase)

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    function Get-RegistryValueSafe {
        param([string]$Path, [string]$Name)
        try {
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -notcontains $Name) { return $null }
            return $key.GetValue(
                $Name,
                $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
            )
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

    function Get-RelatedServicesSafe {
        try {
            $pattern = '(?i)(autologon|auto logon|imprivata|citrix|vmware|horizon|epic)'
            return @(Get-CimInstance Win32_Service -ErrorAction Stop |
                Where-Object { ([string]$_.Name -match $pattern) -or ([string]$_.DisplayName -match $pattern) } |
                Select-Object @{n='name';e={$_.Name}}, @{n='display_name';e={$_.DisplayName}},
                    @{n='state';e={$_.State}}, @{n='start_mode';e={$_.StartMode}}, @{n='start_name';e={$_.StartName}} |
                Sort-Object -Property name)
        }
        catch { return @() }
    }

    function Get-RelatedTasksSafe {
        if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return @() }
        try {
            $pattern = '(?i)(autologon|auto logon|imprivata|citrix|vmware|horizon|epic)'
            return @(Get-ScheduledTask -ErrorAction Stop |
                Where-Object { ([string]$_.TaskName -match $pattern) -or ([string]$_.TaskPath -match $pattern) } |
                Select-Object @{n='task_path';e={$_.TaskPath}}, @{n='task_name';e={$_.TaskName}},
                    @{n='state';e={[string]$_.State}} |
                Sort-Object -Property task_path, task_name)
        }
        catch { return @() }
    }

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

    return [pscustomobject]@{
        schema_version = 'sas-autologon-state-snapshot/v1'
        snapshot_id = [guid]::NewGuid().ToString()
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        capture_phase = $Phase
        computer_name = $env:COMPUTERNAME.ToUpperInvariant()
        collection_status = 'success'
        error = $null
        identity = [pscustomobject]@{
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
        autologon = [pscustomobject]@{
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
        related_services = @(Get-RelatedServicesSafe)
        related_scheduled_tasks = @(Get-RelatedTasksSafe)
        reboot = [pscustomobject]@{
            component_based_servicing_pending = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
            windows_update_pending = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
            pending_file_rename_operations = (Test-RegistryValueNameSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations')
        }
        collection_notes = @(
            'read_only_remote_collection',
            'uninstall_registry_used_instead_of_product_class_query',
            'default_password_value_not_collected',
            'no_target_side_sysadminsuite_artifacts'
        )
    }
}

function Invoke-SasCapture {
    param([string]$Target, [string]$Phase, [switch]$UseFixture)

    if ($UseFixture) { return New-SasFixtureSnapshot -Target $Target -Phase $Phase }

    try {
        $localAliases = @('localhost', '.', '127.0.0.1', $env:COMPUTERNAME)
        if ($localAliases -contains $Target) {
            $snapshot = & $remoteCollector $Phase
        }
        else {
            $session = $null
            try {
                $option = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 180000
                $session = New-PSSession -ComputerName $Target -SessionOption $option
                $snapshot = Invoke-Command -Session $session -ScriptBlock $remoteCollector -ArgumentList $Phase
            }
            finally {
                if ($session) { Remove-PSSession -Session $session }
            }
        }
        $snapshot | Add-Member -NotePropertyName requested_target -NotePropertyValue $Target -Force
        return $snapshot
    }
    catch {
        return [pscustomobject]@{
            schema_version = 'sas-autologon-state-snapshot/v1'
            snapshot_id = [guid]::NewGuid().ToString()
            captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            capture_phase = $Phase
            requested_target = $Target
            computer_name = $Target.ToUpperInvariant()
            collection_status = 'failed'
            error = $_.Exception.Message
            identity = $null
            autologon = $null
            installed_software = @()
            related_services = @()
            related_scheduled_tasks = @()
            reboot = $null
            collection_notes = @('collection_failed', 'no_target_mutation_attempted')
        }
    }
}

function Get-SasSoftwareMap {
    param([object[]]$Rows)
    $map = @{}
    foreach ($row in @($Rows)) {
        $name = ([string](Get-SasProperty -Object $row -Name 'name' -Default '')).Trim().ToLowerInvariant()
        $publisher = ([string](Get-SasProperty -Object $row -Name 'publisher' -Default '')).Trim().ToLowerInvariant()
        if ($name) { $map["$name|$publisher"] = $row }
    }
    return $map
}

function Compare-SasSoftware {
    param([object[]]$BeforeRows, [object[]]$AfterRows)
    $beforeMap = Get-SasSoftwareMap -Rows $BeforeRows
    $afterMap = Get-SasSoftwareMap -Rows $AfterRows
    $keys = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)

    $changes = foreach ($key in $keys) {
        $beforeItem = if ($beforeMap.ContainsKey($key)) { $beforeMap[$key] } else { $null }
        $afterItem = if ($afterMap.ContainsKey($key)) { $afterMap[$key] } else { $null }
        if ($null -eq $beforeItem) {
            [pscustomobject]@{ change='added'; name=$afterItem.name; publisher=$afterItem.publisher; before_version=$null; after_version=$afterItem.version }
        }
        elseif ($null -eq $afterItem) {
            [pscustomobject]@{ change='removed'; name=$beforeItem.name; publisher=$beforeItem.publisher; before_version=$beforeItem.version; after_version=$null }
        }
        elseif ([string]$beforeItem.version -ne [string]$afterItem.version) {
            [pscustomobject]@{ change='version_changed'; name=$afterItem.name; publisher=$afterItem.publisher; before_version=$beforeItem.version; after_version=$afterItem.version }
        }
    }
    return @($changes)
}

function New-SasDelta {
    param([object]$Before, [object]$After, [string]$AssignmentLabel)

    $beforeCollection = [string](Get-SasProperty -Object $Before -Name 'collection_status' -Default 'failed')
    $afterCollection = [string](Get-SasProperty -Object $After -Name 'collection_status' -Default 'failed')
    $beforeAuto = Get-SasProperty -Object $Before -Name 'autologon'
    $afterAuto = Get-SasProperty -Object $After -Name 'autologon'
    $beforeStatus = [string](Get-SasProperty -Object $beforeAuto -Name 'status' -Default 'unknown')
    $afterStatus = [string](Get-SasProperty -Object $afterAuto -Name 'status' -Default 'unknown')

    $fields = @(
        'postinstall_set_autologon','auto_admin_logon','default_user_name','default_domain_name',
        'force_auto_logon','auto_logon_count','default_password_present','expected_user_match','status'
    )
    $autoChanges = foreach ($field in $fields) {
        $beforeValue = Get-SasProperty -Object $beforeAuto -Name $field
        $afterValue = Get-SasProperty -Object $afterAuto -Name $field
        if ([string]$beforeValue -ne [string]$afterValue) {
            [pscustomobject]@{ field=$field; before=$beforeValue; after=$afterValue }
        }
    }
    $autoChanges = @($autoChanges)

    $beforeSoftware = @(Get-SasProperty -Object $Before -Name 'installed_software' -Default @())
    $afterSoftware = @(Get-SasProperty -Object $After -Name 'installed_software' -Default @())
    $softwareChanges = @(Compare-SasSoftware -BeforeRows $beforeSoftware -AfterRows $afterSoftware)

    $beforeReady = $beforeStatus -eq 'autologon_ready'
    $afterReady = $afterStatus -eq 'autologon_ready'
    $decision = 'INCONCLUSIVE'
    $reason = 'One or both snapshots were unavailable or incomplete.'

    if ($beforeCollection -eq 'success' -and $afterCollection -eq 'success') {
        if ($beforeReady -and $afterReady) {
            $decision = 'ALREADY_CONFIGURED_BEFORE'
            $reason = 'The baseline already showed complete auto-logon posture; the later capture does not prove new technician work.'
        }
        elseif ($beforeReady -and -not $afterReady) {
            $decision = 'REGRESSION_REVIEW'
            $reason = 'Auto-logon was ready before the work but is not ready afterward.'
        }
        elseif (-not $beforeReady -and $afterReady) {
            $decision = 'CONFIRMED_STATE_TRANSITION'
            $reason = 'The workstation changed from non-ready to complete auto-logon registry posture with the expected hostname-based account.'
        }
        elseif ($autoChanges.Count -eq 0) {
            $decision = 'NO_MATERIAL_CHANGE'
            $reason = 'No auto-logon registry or status difference was observed.'
        }
        else {
            $decision = 'PARTIAL_CHANGE_REVIEW'
            $reason = 'Some auto-logon evidence changed, but the final workstation state is not fully ready.'
        }
    }

    return [pscustomobject]@{
        schema_version = 'sas-autologon-state-delta/v1'
        compared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        computer_name = [string](Get-SasProperty -Object $After -Name 'computer_name' -Default 'unknown')
        requested_target = [string](Get-SasProperty -Object $After -Name 'requested_target' -Default '')
        technician_label = $AssignmentLabel
        technician_execution_proven = $false
        actor_attribution = 'not_proven_by_state_delta'
        decision = $decision
        decision_reason = $reason
        state_change_observed = ($autoChanges.Count -gt 0 -or $softwareChanges.Count -gt 0)
        before_status = $beforeStatus
        after_status = $afterStatus
        after_expected_user_match = [bool](Get-SasProperty -Object $afterAuto -Name 'expected_user_match' -Default $false)
        autologon_changes = $autoChanges
        installed_software_changes = @($softwareChanges)
        before_snapshot_id = Get-SasProperty -Object $Before -Name 'snapshot_id'
        after_snapshot_id = Get-SasProperty -Object $After -Name 'snapshot_id'
        safety = [pscustomobject]@{
            target_mutation_performed = $false
            target_side_sysadminsuite_artifacts_written = $false
            default_password_value_collected = $false
            human_actor_attribution_claimed = $false
        }
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $targetIntakeModule -PathType Leaf)) {
    throw "Missing target intake module: $targetIntakeModule"
}
Import-Module -Name $targetIntakeModule -Force

if (-not [string]::IsNullOrWhiteSpace($TargetsCsv)) {
    Assert-SasApprovedInputPath -Path $TargetsCsv -RepoRoot $repoRoot -Role 'auto-logon target manifest'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey/output/autologon_state_delta'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'auto-logon state delta output root'

if (-not $FixtureMode) {
    $networkGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasNetworkGuard.psm1'
    if (-not (Test-Path -LiteralPath $networkGuardModule -PathType Leaf)) {
        throw "Missing shared network guard module: $networkGuardModule"
    }
    Import-Module -Name $networkGuardModule -Force
    Assert-SasNorthwellWifi
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    if ($Mode -eq 'After') { throw 'After mode requires -RunId from the Before capture.' }
    $RunId = 'autologon-delta-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
}
if ($RunId -notmatch '^autologon-delta-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') {
    throw "Invalid RunId format: $RunId"
}

$runRoot = Join-Path -Path $OutputRoot -ChildPath $RunId
$beforeDirectory = Join-Path -Path $runRoot -ChildPath 'before'
$afterDirectory = Join-Path -Path $runRoot -ChildPath 'after'
$currentDirectory = Join-Path -Path $runRoot -ChildPath 'current'
$deltaDirectory = Join-Path -Path $runRoot -ChildPath 'delta'

$targets = @(Get-SasTargets -Direct $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets)
if ($Mode -eq 'After' -and $targets.Count -eq 0) {
    $targets = @(Get-SasBaselineTargets -BeforeDirectory $beforeDirectory)
}
if ($targets.Count -eq 0) {
    throw 'No explicit targets were supplied. Use -ComputerName or -TargetsCsv.'
}

if ($Mode -eq 'Before' -and (Test-Path -LiteralPath $runRoot)) {
    throw "Refusing to overwrite existing baseline run: $runRoot"
}
if ($Mode -eq 'After' -and -not (Test-Path -LiteralPath $beforeDirectory -PathType Container)) {
    throw "Baseline directory not found: $beforeDirectory"
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$phaseDirectory = if ($Mode -eq 'Before') { $beforeDirectory } elseif ($Mode -eq 'After') { $afterDirectory } else { $currentDirectory }
New-Item -ItemType Directory -Path $phaseDirectory -Force | Out-Null
if ($Mode -eq 'After') { New-Item -ItemType Directory -Path $deltaDirectory -Force | Out-Null }

$phase = $Mode.ToLowerInvariant()
$manifestPath = Join-Path -Path $runRoot -ChildPath ("run_manifest_{0}.json" -f $phase)
$manifest = [ordered]@{
    schema_version = 'sas-autologon-state-delta-run/v1'
    run_id = $RunId
    mode = $Mode
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    technician_label = $TechnicianLabel
    target_count = $targets.Count
    targets = $targets
    fixture_mode = [bool]$FixtureMode
    target_mutation_performed = $false
    target_side_sysadminsuite_artifacts_written = $false
    default_password_value_collected = $false
}
Write-SasJson -Path $manifestPath -Value $manifest

$snapshots = New-Object System.Collections.Generic.List[object]
$deltas = New-Object System.Collections.Generic.List[object]
$rows = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
    $safeTarget = ConvertTo-SasSafeName -Value $target
    $snapshot = Invoke-SasCapture -Target $target -Phase $phase -UseFixture:$FixtureMode
    $snapshotPath = Join-Path -Path $phaseDirectory -ChildPath "$safeTarget.json"
    Write-SasJson -Path $snapshotPath -Value $snapshot
    $snapshots.Add($snapshot)

    if ($Mode -eq 'After') {
        $beforePath = Join-Path -Path $beforeDirectory -ChildPath "$safeTarget.json"
        if (Test-Path -LiteralPath $beforePath -PathType Leaf) {
            $beforeSnapshot = Get-Content -LiteralPath $beforePath -Raw | ConvertFrom-Json
            $delta = New-SasDelta -Before $beforeSnapshot -After $snapshot -AssignmentLabel $TechnicianLabel
        }
        else {
            $delta = [pscustomobject]@{
                schema_version = 'sas-autologon-state-delta/v1'
                computer_name = $target
                requested_target = $target
                technician_label = $TechnicianLabel
                technician_execution_proven = $false
                actor_attribution = 'not_proven_by_state_delta'
                decision = 'INCONCLUSIVE'
                decision_reason = "Baseline snapshot missing: $beforePath"
                state_change_observed = $false
                before_status = 'missing'
                after_status = 'unknown'
                after_expected_user_match = $false
                autologon_changes = @()
                installed_software_changes = @()
            }
        }

        $deltaPath = Join-Path -Path $deltaDirectory -ChildPath "$safeTarget.json"
        Write-SasJson -Path $deltaPath -Value $delta
        $deltas.Add($delta)
        $rows.Add([pscustomobject]@{
            ComputerName = $delta.computer_name
            TechnicianLabel = $TechnicianLabel
            Decision = $delta.decision
            BeforeStatus = $delta.before_status
            AfterStatus = $delta.after_status
            StateChangeObserved = $delta.state_change_observed
            ExpectedUserMatch = $delta.after_expected_user_match
            AutoLogonChangeCount = @($delta.autologon_changes).Count
            SoftwareAddedCount = @($delta.installed_software_changes | Where-Object { $_.change -eq 'added' }).Count
            ActorAttribution = $delta.actor_attribution
            EvidencePath = $deltaPath
        })
    }
    else {
        $autoState = Get-SasProperty -Object $snapshot -Name 'autologon'
        $status = [string](Get-SasProperty -Object $autoState -Name 'status' -Default 'unknown')
        $rows.Add([pscustomobject]@{
            ComputerName = $snapshot.computer_name
            TechnicianLabel = $TechnicianLabel
            Decision = $(if ($Mode -eq 'Before') { 'BASELINE_CAPTURED' } else { 'CURRENT_STATE_CAPTURED' })
            BeforeStatus = $(if ($Mode -eq 'Before') { $status } else { '' })
            AfterStatus = $(if ($Mode -eq 'Assess') { $status } else { '' })
            StateChangeObserved = $false
            ExpectedUserMatch = [bool](Get-SasProperty -Object $autoState -Name 'expected_user_match' -Default $false)
            AutoLogonChangeCount = 0
            SoftwareAddedCount = 0
            ActorAttribution = 'not_applicable_without_before_after_pair'
            EvidencePath = $snapshotPath
        })
    }
}

$summaryCsvPath = Join-Path -Path $runRoot -ChildPath 'autologon_state_delta_summary.csv'
$summaryJsonPath = Join-Path -Path $runRoot -ChildPath 'autologon_state_delta_summary.json'
$handoffPath = Join-Path -Path $runRoot -ChildPath 'operator_handoff.txt'
$rows | Export-Csv -LiteralPath $summaryCsvPath -NoTypeInformation -Encoding UTF8

$summary = [ordered]@{
    schema_version = 'sas-autologon-state-delta-summary/v1'
    run_id = $RunId
    mode = $Mode
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    technician_label = $TechnicianLabel
    target_count = $targets.Count
    collection_success_count = @($snapshots | Where-Object { $_.collection_status -eq 'success' }).Count
    collection_failure_count = @($snapshots | Where-Object { $_.collection_status -ne 'success' }).Count
    confirmed_state_transition_count = @($deltas | Where-Object { $_.decision -eq 'CONFIRMED_STATE_TRANSITION' }).Count
    already_configured_before_count = @($deltas | Where-Object { $_.decision -eq 'ALREADY_CONFIGURED_BEFORE' }).Count
    no_material_change_count = @($deltas | Where-Object { $_.decision -eq 'NO_MATERIAL_CHANGE' }).Count
    partial_change_review_count = @($deltas | Where-Object { $_.decision -eq 'PARTIAL_CHANGE_REVIEW' }).Count
    regression_review_count = @($deltas | Where-Object { $_.decision -eq 'REGRESSION_REVIEW' }).Count
    inconclusive_count = @($deltas | Where-Object { $_.decision -eq 'INCONCLUSIVE' }).Count
    technician_execution_proven = $false
    actor_attribution = 'state_delta_does_not_prove_human_identity'
    target_mutation_performed = $false
    target_side_sysadminsuite_artifacts_written = $false
    default_password_value_collected = $false
    summary_csv = $summaryCsvPath
    phase_manifest = $manifestPath
    results = $rows.ToArray()
}
Write-SasJson -Path $summaryJsonPath -Value $summary

$handoff = @(
    'SysAdminSuite auto-logon workstation state delta',
    "Run ID: $RunId",
    "Mode: $Mode",
    "Targets: $($targets.Count)",
    "Technician/assignment label: $(if ($TechnicianLabel) { $TechnicianLabel } else { '[not supplied]' })",
    "Summary CSV: $summaryCsvPath",
    "Summary JSON: $summaryJsonPath",
    '',
    'CONFIRMED_STATE_TRANSITION proves a before/after workstation-state transition, not the identity of the human actor.',
    'DefaultPassword data is never collected. Evidence stays on the admin box; no SysAdminSuite evidence is written to targets.'
)
if ($Mode -eq 'Before') {
    $handoff += ''
    $handoff += 'After approved auto-logon work completes:'
    $handoff += 'Double-click Run-AutoLogonStateDelta.cmd and choose option 2. The launcher remembers this run ID and baseline targets.'
}
$handoff | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Auto-logon state delta run: $RunId" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Cyan
Write-Host "Targets: $($targets.Count)" -ForegroundColor Cyan
Write-Host "Evidence: $runRoot" -ForegroundColor Green
Write-Host "Summary: $summaryCsvPath" -ForegroundColor Green

[pscustomobject]@{
    run_id = $RunId
    mode = $Mode
    target_count = $targets.Count
    output_root = $runRoot
    summary_csv = $summaryCsvPath
    summary_json = $summaryJsonPath
    handoff = $handoffPath
    target_mutation_performed = $false
    target_side_sysadminsuite_artifacts_written = $false
}
