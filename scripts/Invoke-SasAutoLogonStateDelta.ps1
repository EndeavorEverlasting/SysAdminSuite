#Requires -Version 5.1
<#
.SYNOPSIS
Captures and compares read-only workstation state before and after auto-logon work.

.DESCRIPTION
Invoke-SasAutoLogonStateDelta captures explicit, low-noise evidence from approved Windows
workstations through PowerShell remoting. Evidence is returned to the admin box and written only
under an approved local SysAdminSuite output root. No scripts, reports, transcripts, or evidence
files are written to target workstations.

The workflow has three modes:
- Before: capture the baseline before a technician or deployment lane runs auto-logon setup.
- After: capture the same targets after the work and create per-target deltas plus a batch summary.
- Assess: capture current state without requiring a baseline.

The collector records host identity, bounded auto-logon registry posture, installed-software
inventory from uninstall registry keys, selected related services/tasks, reboot indicators, and
basic OS state. It never reads or exports the DefaultPassword value. Only a boolean indicating
whether that value exists is retained.

A state delta can prove that workstation state changed between captures. It cannot by itself prove
which human performed the change. TechnicianLabel is assignment metadata, not actor attribution.
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

function Get-SasObjectProperty {
    param(
        [object]$InputObject,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Write-SasJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$InputObject
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $InputObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SasSafeFileName {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -replace '[^A-Za-z0-9._-]', '_')
}

function Get-SasTargets {
    param(
        [string[]]$DirectTargets,
        [string]$CsvPath,
        [int]$Limit
    )

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($target in @($DirectTargets)) {
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $targets.Add($target.Trim())
        }
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
            if ($value) { $targets.Add($value) }
        }
    }

    $deduped = @($targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($deduped.Count -gt $Limit) {
        throw "Target count $($deduped.Count) exceeds MaxTargets $Limit. Split the run to keep remote reads bounded."
    }
    return $deduped
}

function Get-SasTargetsFromBaseline {
    param([Parameter(Mandatory = $true)][string]$BeforeDirectory)

    if (-not (Test-Path -LiteralPath $BeforeDirectory -PathType Container)) { return @() }
    $targets = foreach ($file in @(Get-ChildItem -LiteralPath $BeforeDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $snapshot = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $name = [string](Get-SasObjectProperty -InputObject $snapshot -Name 'computer_name' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($name)) { $name }
        }
        catch {
            Write-Warning "Unable to read baseline target from $($file.FullName): $($_.Exception.Message)"
        }
    }
    return @($targets | Sort-Object -Unique)
}

function New-SasFixtureSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Phase
    )

    $afterLike = $Phase -ne 'before'
    $autoStatus = if ($afterLike) { 'autologon_ready' } else { 'not_configured' }
    $software = @(
        [pscustomobject]@{
            name = 'Contoso Base Agent'
            version = '1.0.0'
            publisher = 'Contoso'
            install_date = '20260101'
            registry_path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ContosoBase'
        }
    )
    if ($afterLike) {
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
            last_boot_time_utc = if ($afterLike) { '2026-07-13T16:00:00Z' } else { '2026-07-13T12:00:00Z' }
            logged_on_user = if ($afterLike) { "SAMPLE\$($Target.ToUpperInvariant())" } else { 'SAMPLE\TECH'
        }
        autologon = [pscustomobject]@{
            postinstall_set_autologon = if ($afterLike) { 'Autologon_YES' } else { 'Autologon_NO' }
            auto_admin_logon = if ($afterLike) { '1' } else { '0' }
            default_user_name = if ($afterLike) { $Target.ToUpperInvariant() } else { '' }
            default_domain_name = if ($afterLike) { 'SAMPLE' } else { '' }
            force_auto_logon = ''
            default_password_present = $afterLike
            default_password_value_collected = $false
            expected_user_name = $Target.ToUpperInvariant()
            expected_user_match = $afterLike
            status = $autoStatus
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

    function Get-SafeRegistryValue {
        param([string]$Path, [string]$Name)
        try {
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
            $property = $item.PSObject.Properties[$Name]
            if ($null -eq $property) { return $null }
            return $property.Value
        }
        catch { return $null }
    }

    function Test-SafeRegistryValuePresent {
        param([string]$Path, [string]$Name)
        try {
            if (-not (Test-Path -LiteralPath $Path)) { return $false }
            $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
            return ($null -ne $item.PSObject.Properties[$Name])
        }
        catch { return $false }
    }

    function Normalize-AccountLeaf {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
        $leaf = $Value.Trim()
        if ($leaf.Contains('\')) { $leaf = $leaf.Split('\')[-1] }
        if ($leaf.Contains('@')) { $leaf = $leaf.Split('@')[0] }
        return $leaf.ToUpperInvariant()
    }

    function Get-AutoLogonStatus {
        param(
            [string]$ComputerName,
            [object]$PostInstallMarker,
            [object]$AutoAdminLogon,
            [object]$DefaultUserName
        )

        $expected = $ComputerName.ToUpperInvariant()
        $actual = Normalize-AccountLeaf -Value ([string]$DefaultUserName)
        $autoEnabled = ([string]$AutoAdminLogon).Trim() -in @('1', '0x1')
        $markerBlob = ("$PostInstallMarker").ToUpperInvariant().Replace('_', '').Replace(' ', '')
        $intent = $markerBlob.Contains('AUTOLOGONYES')

        if ($autoEnabled -and $actual -eq $expected) { return 'autologon_ready' }
        if ($autoEnabled -and $actual -ne $expected) { return 'configured_user_mismatch' }
        if ($intent) { return 'intent_only' }
        return 'not_configured'
    }

    function Get-InstalledSoftware {
        $roots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        $rows = foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                try {
                    $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                    $displayName = [string]$item.DisplayName
                    if ([string]::IsNullOrWhiteSpace($displayName)) { continue }
                    [pscustomobject]@{
                        name = $displayName.Trim()
                        version = ([string]$item.DisplayVersion).Trim()
                        publisher = ([string]$item.Publisher).Trim()
                        install_date = ([string]$item.InstallDate).Trim()
                        registry_path = $key.Name
                    }
                }
                catch {}
            }
        }
        return @($rows | Sort-Object name, publisher, version, registry_path -Unique)
    }

    function Get-RelatedServices {
        try {
            $pattern = '(?i)(autologon|auto logon|imprivata|citrix|vmware|horizon|epic)'
            return @(Get-CimInstance Win32_Service -ErrorAction Stop |
                Where-Object { ([string]$_.Name -match $pattern) -or ([string]$_.DisplayName -match $pattern) } |
                Select-Object @{n='name';e={$_.Name}}, @{n='display_name';e={$_.DisplayName}},
                    @{n='state';e={$_.State}}, @{n='start_mode';e={$_.StartMode}}, @{n='start_name';e={$_.StartName}} |
                Sort-Object name)
        }
        catch { return @() }
    }

    function Get-RelatedScheduledTasks {
        if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return @() }
        try {
            $pattern = '(?i)(autologon|auto logon|imprivata|citrix|vmware|horizon|epic)'
            return @(Get-ScheduledTask -ErrorAction Stop |
                Where-Object { ([string]$_.TaskName -match $pattern) -or ([string]$_.TaskPath -match $pattern) } |
                Select-Object @{n='task_path';e={$_.TaskPath}}, @{n='task_name';e={$_.TaskName}}, @{n='state';e={[string]$_.State}} |
                Sort-Object task_path, task_name)
        }
        catch { return @() }
    }

    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop

    $postInstallPath = 'HKLM:\SOFTWARE\NSLIJHS\PostInstall'
    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    $postInstallMarker = Get-SafeRegistryValue -Path $postInstallPath -Name 'SetAutoLogon'
    $autoAdminLogon = Get-SafeRegistryValue -Path $winlogonPath -Name 'AutoAdminLogon'
    $defaultUserName = Get-SafeRegistryValue -Path $winlogonPath -Name 'DefaultUserName'
    $defaultDomainName = Get-SafeRegistryValue -Path $winlogonPath -Name 'DefaultDomainName'
    $forceAutoLogon = Get-SafeRegistryValue -Path $winlogonPath -Name 'ForceAutoLogon'
    $defaultPasswordPresent = Test-SafeRegistryValuePresent -Path $winlogonPath -Name 'DefaultPassword'
    $expectedUser = $env:COMPUTERNAME.ToUpperInvariant()
    $actualUser = Normalize-AccountLeaf -Value ([string]$defaultUserName)

    [pscustomobject]@{
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
            last_boot_time_utc = if ($operatingSystem.LastBootUpTime) { $operatingSystem.LastBootUpTime.ToUniversalTime().ToString('o') } else { $null }
            logged_on_user = $computer.UserName
        }
        autologon = [pscustomobject]@{
            postinstall_set_autologon = $postInstallMarker
            auto_admin_logon = $autoAdminLogon
            default_user_name = $defaultUserName
            default_domain_name = $defaultDomainName
            force_auto_logon = $forceAutoLogon
            default_password_present = [bool]$defaultPasswordPresent
            default_password_value_collected = $false
            expected_user_name = $expectedUser
            expected_user_match = ($actualUser -eq $expectedUser)
            status = Get-AutoLogonStatus -ComputerName $env:COMPUTERNAME -PostInstallMarker $postInstallMarker -AutoAdminLogon $autoAdminLogon -DefaultUserName $defaultUserName
        }
        installed_software = @(Get-InstalledSoftware)
        related_services = @(Get-RelatedServices)
        related_scheduled_tasks = @(Get-RelatedScheduledTasks)
        reboot = [pscustomobject]@{
            component_based_servicing_pending = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
            windows_update_pending = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
            pending_file_rename_operations = (Test-SafeRegistryValuePresent -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations')
        }
        collection_notes = @(
            'read_only_remote_collection',
            'uninstall_registry_used_instead_of_win32_product',
            'default_password_value_not_collected',
            'no_target_side_sysadminsuite_artifacts'
        )
    }
}

function Invoke-SasSnapshotCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Phase,
        [switch]$UseFixture
    )

    if ($UseFixture) {
        return New-SasFixtureSnapshot -Target $Target -Phase $Phase
    }

    $localAliases = @('localhost', '.', '127.0.0.1', $env:COMPUTERNAME)
    try {
        if ($localAliases -contains $Target) {
            return & $remoteCollector $Phase
        }

        $session = $null
        try {
            $sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 180000
            $session = New-PSSession -ComputerName $Target -SessionOption $sessionOption
            return Invoke-Command -Session $session -ScriptBlock $remoteCollector -ArgumentList $Phase
        }
        finally {
            if ($session) { Remove-PSSession -Session $session }
        }
    }
    catch {
        return [pscustomobject]@{
            schema_version = 'sas-autologon-state-snapshot/v1'
            snapshot_id = [guid]::NewGuid().ToString()
            captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            capture_phase = $Phase
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
        $name = ([string](Get-SasObjectProperty -InputObject $row -Name 'name' -Default '')).Trim().ToLowerInvariant()
        $publisher = ([string](Get-SasObjectProperty -InputObject $row -Name 'publisher' -Default '')).Trim().ToLowerInvariant()
        if (-not $name) { continue }
        $map["$name|$publisher"] = $row
    }
    return $map
}

function Compare-SasSoftware {
    param([object[]]$BeforeRows, [object[]]$AfterRows)

    $beforeMap = Get-SasSoftwareMap -Rows $BeforeRows
    $afterMap = Get-SasSoftwareMap -Rows $AfterRows
    $keys = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
    $changes = foreach ($key in $keys) {
        $before = if ($beforeMap.ContainsKey($key)) { $beforeMap[$key] } else { $null }
        $after = if ($afterMap.ContainsKey($key)) { $afterMap[$key] } else { $null }
        if ($null -eq $before) {
            [pscustomobject]@{ change = 'added'; name = $after.name; publisher = $after.publisher; before_version = $null; after_version = $after.version }
        }
        elseif ($null -eq $after) {
            [pscustomobject]@{ change = 'removed'; name = $before.name; publisher = $before.publisher; before_version = $before.version; after_version = $null }
        }
        elseif ([string]$before.version -ne [string]$after.version) {
            [pscustomobject]@{ change = 'version_changed'; name = $after.name; publisher = $after.publisher; before_version = $before.version; after_version = $after.version }
        }
    }
    return @($changes)
}

function Get-SasNamedMap {
    param([object[]]$Rows, [string[]]$IdentityProperties)
    $map = @{}
    foreach ($row in @($Rows)) {
        $parts = foreach ($propertyName in $IdentityProperties) {
            ([string](Get-SasObjectProperty -InputObject $row -Name $propertyName -Default '')).Trim().ToLowerInvariant()
        }
        $key = $parts -join '|'
        if ($key) { $map[$key] = $row }
    }
    return $map
}

function Compare-SasNamedRows {
    param(
        [object[]]$BeforeRows,
        [object[]]$AfterRows,
        [string[]]$IdentityProperties,
        [string[]]$ComparedProperties
    )

    $beforeMap = Get-SasNamedMap -Rows $BeforeRows -IdentityProperties $IdentityProperties
    $afterMap = Get-SasNamedMap -Rows $AfterRows -IdentityProperties $IdentityProperties
    $keys = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
    $changes = foreach ($key in $keys) {
        $before = if ($beforeMap.ContainsKey($key)) { $beforeMap[$key] } else { $null }
        $after = if ($afterMap.ContainsKey($key)) { $afterMap[$key] } else { $null }
        if ($null -eq $before) {
            [pscustomobject]@{ change = 'added'; identity = $key; before = $null; after = $after }
            continue
        }
        if ($null -eq $after) {
            [pscustomobject]@{ change = 'removed'; identity = $key; before = $before; after = $null }
            continue
        }
        $changed = $false
        foreach ($propertyName in $ComparedProperties) {
            if ([string](Get-SasObjectProperty $before $propertyName '') -ne [string](Get-SasObjectProperty $after $propertyName '')) {
                $changed = $true
                break
            }
        }
        if ($changed) {
            [pscustomobject]@{ change = 'modified'; identity = $key; before = $before; after = $after }
        }
    }
    return @($changes)
}

function New-SasAutoLogonDelta {
    param(
        [Parameter(Mandatory = $true)][object]$Before,
        [Parameter(Mandatory = $true)][object]$After,
        [string]$AssignmentLabel
    )

    $beforeCollection = [string](Get-SasObjectProperty -InputObject $Before -Name 'collection_status' -Default 'failed')
    $afterCollection = [string](Get-SasObjectProperty -InputObject $After -Name 'collection_status' -Default 'failed')
    $beforeAuto = Get-SasObjectProperty -InputObject $Before -Name 'autologon'
    $afterAuto = Get-SasObjectProperty -InputObject $After -Name 'autologon'
    $beforeStatus = [string](Get-SasObjectProperty -InputObject $beforeAuto -Name 'status' -Default 'unknown')
    $afterStatus = [string](Get-SasObjectProperty -InputObject $afterAuto -Name 'status' -Default 'unknown')

    $autoFields = @(
        'postinstall_set_autologon',
        'auto_admin_logon',
        'default_user_name',
        'default_domain_name',
        'force_auto_logon',
        'default_password_present',
        'expected_user_match',
        'status'
    )
    $autoChanges = foreach ($field in $autoFields) {
        $beforeValue = Get-SasObjectProperty -InputObject $beforeAuto -Name $field
        $afterValue = Get-SasObjectProperty -InputObject $afterAuto -Name $field
        if ([string]$beforeValue -ne [string]$afterValue) {
            [pscustomobject]@{ field = $field; before = $beforeValue; after = $afterValue }
        }
    }
    $autoChanges = @($autoChanges)

    $softwareChanges = Compare-SasSoftware -BeforeRows @(Get-SasObjectProperty $Before 'installed_software' @()) -AfterRows @(Get-SasObjectProperty $After 'installed_software' @())
    $serviceChanges = Compare-SasNamedRows -BeforeRows @(Get-SasObjectProperty $Before 'related_services' @()) -AfterRows @(Get-SasObjectProperty $After 'related_services' @()) -IdentityProperties @('name') -ComparedProperties @('display_name', 'state', 'start_mode', 'start_name')
    $taskChanges = Compare-SasNamedRows -BeforeRows @(Get-SasObjectProperty $Before 'related_scheduled_tasks' @()) -AfterRows @(Get-SasObjectProperty $After 'related_scheduled_tasks' @()) -IdentityProperties @('task_path', 'task_name') -ComparedProperties @('state')

    $beforeIdentity = Get-SasObjectProperty -InputObject $Before -Name 'identity'
    $afterIdentity = Get-SasObjectProperty -InputObject $After -Name 'identity'
    $identityFields = @('domain', 'manufacturer', 'model', 'bios_serial', 'os_caption', 'os_version', 'os_build', 'last_boot_time_utc', 'logged_on_user')
    $identityChanges = foreach ($field in $identityFields) {
        $beforeValue = Get-SasObjectProperty -InputObject $beforeIdentity -Name $field
        $afterValue = Get-SasObjectProperty -InputObject $afterIdentity -Name $field
        if ([string]$beforeValue -ne [string]$afterValue) {
            [pscustomobject]@{ field = $field; before = $beforeValue; after = $afterValue }
        }
    }
    $identityChanges = @($identityChanges)

    $beforeReady = $beforeStatus -eq 'autologon_ready'
    $afterReady = $afterStatus -eq 'autologon_ready'
    $decision = 'INCONCLUSIVE'
    $reason = 'One or both snapshots were unavailable or incomplete.'

    if ($beforeCollection -eq 'success' -and $afterCollection -eq 'success') {
        if ($beforeReady -and $afterReady) {
            $decision = 'ALREADY_CONFIGURED_BEFORE'
            $reason = 'The baseline already showed a complete auto-logon posture; the later capture does not prove new technician work.'
        }
        elseif ($beforeReady -and -not $afterReady) {
            $decision = 'REGRESSION_REVIEW'
            $reason = 'Auto-logon was ready before the work but is not ready afterward.'
        }
        elseif (-not $beforeReady -and $afterReady) {
            $decision = 'CONFIRMED_STATE_TRANSITION'
            $reason = 'The workstation changed from a non-ready state to complete auto-logon registry posture with the expected hostname-based account.'
        }
        elseif ($autoChanges.Count -eq 0) {
            $decision = 'NO_MATERIAL_CHANGE'
            $reason = 'No auto-logon registry/status difference was observed between the two captures.'
        }
        else {
            $decision = 'PARTIAL_CHANGE_REVIEW'
            $reason = 'Some auto-logon evidence changed, but the final workstation state is not fully ready.'
        }
    }

    return [pscustomobject]@{
        schema_version = 'sas-autologon-state-delta/v1'
        compared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        computer_name = [string](Get-SasObjectProperty -InputObject $After -Name 'computer_name' -Default (Get-SasObjectProperty -InputObject $Before -Name 'computer_name' -Default 'unknown'))
        technician_label = $AssignmentLabel
        technician_execution_proven = $false
        actor_attribution = 'not_proven_by_state_delta'
        decision = $decision
        decision_reason = $reason
        state_change_observed = ($autoChanges.Count -gt 0 -or $softwareChanges.Count -gt 0 -or $serviceChanges.Count -gt 0 -or $taskChanges.Count -gt 0)
        before_status = $beforeStatus
        after_status = $afterStatus
        after_expected_user_match = [bool](Get-SasObjectProperty -InputObject $afterAuto -Name 'expected_user_match' -Default $false)
        autologon_changes = $autoChanges
        installed_software_changes = @($softwareChanges)
        related_service_changes = @($serviceChanges)
        related_scheduled_task_changes = @($taskChanges)
        identity_changes = $identityChanges
        before_snapshot_id = Get-SasObjectProperty -InputObject $Before -Name 'snapshot_id'
        after_snapshot_id = Get-SasObjectProperty -InputObject $After -Name 'snapshot_id'
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
    if ($Mode -eq 'After') {
        throw 'After mode requires -RunId from the Before capture.'
    }
    $RunId = 'autologon-delta-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
}
if ($RunId -notmatch '^autologon-delta-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') {
    throw "RunId does not match the required autologon-delta timestamp format: $RunId"
}

$runRoot = Join-Path -Path $OutputRoot -ChildPath $RunId
$beforeDir = Join-Path -Path $runRoot -ChildPath 'before'
$afterDir = Join-Path -Path $runRoot -ChildPath 'after'
$currentDir = Join-Path -Path $runRoot -ChildPath 'current'
$deltaDir = Join-Path -Path $runRoot -ChildPath 'delta'

$targets = @(Get-SasTargets -DirectTargets $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets)
if ($Mode -eq 'After' -and $targets.Count -eq 0) {
    $targets = @(Get-SasTargetsFromBaseline -BeforeDirectory $beforeDir)
}
if ($targets.Count -eq 0) {
    throw 'No targets were supplied. Use -ComputerName or -TargetsCsv; After mode may also reuse targets from the saved baseline.'
}
if ($targets.Count -gt $MaxTargets) {
    throw "Target count $($targets.Count) exceeds MaxTargets $MaxTargets."
}

if ($Mode -eq 'Before' -and (Test-Path -LiteralPath $runRoot)) {
    throw "Refusing to overwrite an existing baseline run: $runRoot"
}
if ($Mode -eq 'After' -and -not (Test-Path -LiteralPath $beforeDir -PathType Container)) {
    throw "Baseline directory not found for RunId $RunId: $beforeDir"
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$phaseDirectory = if ($Mode -eq 'Before') { $beforeDir } elseif ($Mode -eq 'After') { $afterDir } else { $currentDir }
New-Item -ItemType Directory -Path $phaseDirectory -Force | Out-Null
if ($Mode -eq 'After') { New-Item -ItemType Directory -Path $deltaDir -Force | Out-Null }

$manifestPath = Join-Path -Path $runRoot -ChildPath 'run_manifest.json'
$manifest = [ordered]@{
    schema_version = 'sas-autologon-state-delta-run/v1'
    run_id = $RunId
    mode = $Mode
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    technician_label = $TechnicianLabel
    target_count = $targets.Count
    targets = $targets
    output_root = $runRoot
    fixture_mode = [bool]$FixtureMode
    posture = 'read_only_explicit_targets_local_evidence_no_default_password_value_no_actor_attribution'
    target_mutation_performed = $false
    target_side_sysadminsuite_artifacts_written = $false
}
Write-SasJson -Path $manifestPath -InputObject $manifest

$snapshots = New-Object System.Collections.Generic.List[object]
$deltas = New-Object System.Collections.Generic.List[object]
$summaryRows = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
    $safeTarget = Get-SasSafeFileName -Value $target
    $phaseName = $Mode.ToLowerInvariant()
    $snapshot = Invoke-SasSnapshotCapture -Target $target -Phase $phaseName -UseFixture:$FixtureMode
    $snapshotPath = Join-Path -Path $phaseDirectory -ChildPath "$safeTarget.json"
    Write-SasJson -Path $snapshotPath -InputObject $snapshot
    $snapshots.Add($snapshot)

    if ($Mode -eq 'After') {
        $beforePath = Join-Path -Path $beforeDir -ChildPath "$safeTarget.json"
        if (-not (Test-Path -LiteralPath $beforePath -PathType Leaf)) {
            $delta = [pscustomobject]@{
                schema_version = 'sas-autologon-state-delta/v1'
                compared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
                computer_name = $target
                technician_label = $TechnicianLabel
                technician_execution_proven = $false
                actor_attribution = 'not_proven_by_state_delta'
                decision = 'INCONCLUSIVE'
                decision_reason = "Baseline snapshot missing: $beforePath"
                state_change_observed = $false
                before_status = 'missing'
                after_status = [string](Get-SasObjectProperty (Get-SasObjectProperty $snapshot 'autologon') 'status' 'unknown')
                after_expected_user_match = $false
                autologon_changes = @()
                installed_software_changes = @()
                related_service_changes = @()
                related_scheduled_task_changes = @()
                identity_changes = @()
                safety = [pscustomobject]@{
                    target_mutation_performed = $false
                    target_side_sysadminsuite_artifacts_written = $false
                    default_password_value_collected = $false
                    human_actor_attribution_claimed = $false
                }
            }
        }
        else {
            $before = Get-Content -LiteralPath $beforePath -Raw | ConvertFrom-Json
            $delta = New-SasAutoLogonDelta -Before $before -After $snapshot -AssignmentLabel $TechnicianLabel
        }

        $deltaPath = Join-Path -Path $deltaDir -ChildPath "$safeTarget.json"
        Write-SasJson -Path $deltaPath -InputObject $delta
        $deltas.Add($delta)
        $summaryRows.Add([pscustomobject]@{
            ComputerName = $delta.computer_name
            TechnicianLabel = $TechnicianLabel
            Decision = $delta.decision
            BeforeStatus = $delta.before_status
            AfterStatus = $delta.after_status
            StateChangeObserved = $delta.state_change_observed
            ExpectedUserMatch = $delta.after_expected_user_match
            AutoLogonChangeCount = @($delta.autologon_changes).Count
            SoftwareAddedCount = @($delta.installed_software_changes | Where-Object { $_.change -eq 'added' }).Count
            SoftwareRemovedCount = @($delta.installed_software_changes | Where-Object { $_.change -eq 'removed' }).Count
            SoftwareVersionChangedCount = @($delta.installed_software_changes | Where-Object { $_.change -eq 'version_changed' }).Count
            ActorAttribution = $delta.actor_attribution
            EvidencePath = $deltaPath
        })
    }
    else {
        $auto = Get-SasObjectProperty -InputObject $snapshot -Name 'autologon'
        $summaryRows.Add([pscustomobject]@{
            ComputerName = $snapshot.computer_name
            TechnicianLabel = $TechnicianLabel
            Decision = if ($Mode -eq 'Before') { 'BASELINE_CAPTURED' } else { 'CURRENT_STATE_CAPTURED' }
            BeforeStatus = if ($Mode -eq 'Before') { [string](Get-SasObjectProperty $auto 'status' 'unknown') } else { '' }
            AfterStatus = if ($Mode -eq 'Assess') { [string](Get-SasObjectProperty $auto 'status' 'unknown') } else { '' }
            StateChangeObserved = $false
            ExpectedUserMatch = [bool](Get-SasObjectProperty $auto 'expected_user_match' $false)
            AutoLogonChangeCount = 0
            SoftwareAddedCount = 0
            SoftwareRemovedCount = 0
            SoftwareVersionChangedCount = 0
            ActorAttribution = 'not_applicable_without_before_after_pair'
            EvidencePath = $snapshotPath
        })
    }
}

$summaryCsvPath = Join-Path -Path $runRoot -ChildPath 'autologon_state_delta_summary.csv'
$summaryJsonPath = Join-Path -Path $runRoot -ChildPath 'autologon_state_delta_summary.json'
$handoffPath = Join-Path -Path $runRoot -ChildPath 'operator_handoff.txt'
$summaryRows | Export-Csv -LiteralPath $summaryCsvPath -NoTypeInformation -Encoding UTF8

$batchSummary = [ordered]@{
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
    run_manifest = $manifestPath
    results = @($summaryRows)
}
Write-SasJson -Path $summaryJsonPath -InputObject $batchSummary

$handoff = New-Object System.Collections.Generic.List[string]
$handoff.Add('SysAdminSuite auto-logon workstation state delta')
$handoff.Add("Run ID: $RunId")
$handoff.Add("Mode: $Mode")
$handoff.Add("Targets: $($targets.Count)")
$handoff.Add("Technician/assignment label: $(if ($TechnicianLabel) { $TechnicianLabel } else { '[not supplied]' })")
$handoff.Add("Summary CSV: $summaryCsvPath")
$handoff.Add("Summary JSON: $summaryJsonPath")
$handoff.Add('')
$handoff.Add('Interpretation: CONFIRMED_STATE_TRANSITION proves a before/after workstation-state transition, not the identity of the human actor.')
$handoff.Add('DefaultPassword values are never collected. Evidence remains on the admin box; no SysAdminSuite evidence is written to targets.')
if ($Mode -eq 'Before') {
    $handoff.Add('')
    $handoff.Add('After the technician or deployment lane completes the approved auto-logon work, run:')
    $handoff.Add(".\scripts\Invoke-SasAutoLogonStateDelta.ps1 -Mode After -RunId $RunId -TargetsCsv <same-approved-manifest>")
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