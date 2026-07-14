#Requires -Version 5.1
<#
.SYNOPSIS
Extract read-only application-launch and AutoLogon acceptance evidence for the active approved-software run.

.DESCRIPTION
Requires a completed AFTER snapshot from the catalog-driven install workflow. The collector observes
configured application processes and safe Windows Winlogon posture, then writes evidence only under
the active admin-workstation run directory. It never reads DefaultPassword data, application command
lines, credentials, or secret values and it never launches, stops, or mutates a target process.
#>
[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string[]]$ProcessName = @(),
    [string]$WindowTitlePattern,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$ApplicationObserved,
    [switch]$AutoLogonObservedAfterReboot,
    [switch]$FixtureMode,
    [switch]$NonInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repoRoot 'configs/software-packages/approved-apps.json'
$targetIntakeModule = Join-Path $PSScriptRoot 'SasTargetIntake.psm1'
foreach ($requiredPath in @($catalogPath, $targetIntakeModule)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required acceptance dependency not found: $requiredPath"
    }
}
Import-Module -Name $targetIntakeModule -Force

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/approved_software_install'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'approved software acceptance output root'

function Write-SasJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertTo-SasSafeName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'blank' }
    return ($Value.Trim() -replace '[^A-Za-z0-9._-]', '_')
}

function ConvertTo-SasAccountLeaf {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $leaf = $Value.Trim()
    if ($leaf.Contains('\')) { $leaf = $leaf.Split('\')[-1] }
    if ($leaf.Contains('@')) { $leaf = $leaf.Split('@')[0] }
    return $leaf.ToUpperInvariant()
}

function Read-SasOperatorState {
    $statePath = Join-Path $OutputRoot 'operator-state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Approved software operator state not found: $statePath"
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ([string]$state.workflow_status -ne 'after_complete') {
        throw "Acceptance extraction requires a completed AFTER snapshot. Current status: $($state.workflow_status)"
    }
    if (-not (Test-Path -LiteralPath ([string]$state.after_manifest_path) -PathType Leaf)) {
        throw "AFTER snapshot manifest is missing: $($state.after_manifest_path)"
    }
    return [pscustomobject]@{ path = $statePath; value = $state }
}

function Get-SasPackage {
    param([Parameter(Mandatory = $true)][string]$PackageId)
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    if ([string]$catalog.schema_version -ne 'sas-approved-software-catalog/v1') {
        throw "Unsupported approved software catalog schema: $($catalog.schema_version)"
    }
    $matches = @($catalog.packages | Where-Object {
        ([string]$_.id).Equals($PackageId, [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -ne 1) { throw "Approved package id not found or ambiguous: $PackageId" }
    return $matches[0]
}

function Get-SasTargets {
    param([Parameter(Mandatory = $true)][string]$CsvPath)
    Assert-SasApprovedInputPath -Path $CsvPath -RepoRoot $repoRoot -Role 'approved software acceptance target manifest' -AllowStaging
    $targets = @()
    foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
        foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
            if ($row.PSObject.Properties.Name -contains $column) {
                $candidate = ([string]$row.$column).Trim()
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    $targets += $candidate
                    break
                }
            }
        }
    }
    $targets = @($targets | Sort-Object -Unique)
    if ($targets.Count -eq 0) { throw 'No targets were available for acceptance extraction.' }
    if ($targets.Count -gt $MaxTargets) {
        throw "Target count $($targets.Count) exceeds MaxTargets $MaxTargets. Split the acceptance run."
    }
    return $targets
}

function Get-SasConfiguredProcessNames {
    param([Parameter(Mandatory = $true)]$Package)
    $names = @($ProcessName)
    if ($names.Count -eq 0 -and $null -ne $Package.acceptance) {
        $names = @($Package.acceptance.application_process_names)
    }
    if ($names.Count -eq 0 -and -not $NonInteractive -and
        [string]$Package.acceptance.autologon_profile -eq 'none') {
        $line = Read-Host 'Approved application process names separated by |, without command-line arguments'
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $names = @($line.Split('|'))
        }
    }

    $normalized = @($names | ForEach-Object {
        $value = ([string]$_).Trim()
        if ($value.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
            $value = $value.Substring(0, $value.Length - 4)
        }
        if ($value) { $value }
    } | Sort-Object -Unique)

    if ($normalized.Count -gt 12) { throw 'At most 12 explicit process names may be observed.' }
    foreach ($name in $normalized) {
        if ($name -notmatch '^[A-Za-z0-9._-]+$') {
            throw "Unsafe process name. Supply a process base name only: $name"
        }
    }
    return $normalized
}

function Get-SasWindowPattern {
    param([Parameter(Mandatory = $true)]$Package)
    $pattern = $WindowTitlePattern
    if ([string]::IsNullOrWhiteSpace($pattern) -and $null -ne $Package.acceptance) {
        $pattern = [string]$Package.acceptance.application_window_title_pattern
    }
    if ([string]::IsNullOrWhiteSpace($pattern)) { return $null }
    if ($pattern.Length -gt 120) { throw 'WindowTitlePattern must be 120 characters or fewer.' }
    try { $null = [regex]::new($pattern) }
    catch { throw "WindowTitlePattern is not a valid regular expression: $($_.Exception.Message)" }
    return $pattern
}

function Get-SasBeforeBootTime {
    param([string]$RunRoot, [string]$Target)
    $path = Join-Path (Join-Path $RunRoot 'before') ((ConvertTo-SasSafeName -Value $Target) + '.json')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $snapshot = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return [string]$snapshot.identity.last_boot_time_utc
    }
    catch { return $null }
}

function New-SasFixtureAcceptance {
    param(
        [string]$Target,
        $Package,
        [string[]]$ProcessNames,
        [string]$TitlePattern,
        [string]$BeforeBootTime
    )

    $applicationRequired = $ProcessNames.Count -gt 0
    $processes = @()
    if ($applicationRequired) {
        $processes = @([pscustomobject]@{
            process_name = $ProcessNames[0]
            process_id = 4242
            session_id = 1
            executable_path = "C:\Program Files\Fixture\$($ProcessNames[0]).exe"
            start_time_utc = '2026-07-14T12:05:00Z'
            responding = $true
            main_window_title = $(if ($TitlePattern) { 'Fixture Ready Surface' } else { '' })
            window_title_matched = $true
            command_line_collected = $false
        })
    }

    $autologonRequired = [string]$Package.acceptance.autologon_profile -eq 'windows_winlogon'
    $expectedUser = $Target.ToUpperInvariant()
    return [pscustomobject]@{
        schema_version = 'sas-approved-software-acceptance-target/v1'
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        requested_target = $Target
        computer_name = $Target.ToUpperInvariant()
        collection_status = 'success'
        error = $null
        application = [pscustomobject]@{
            required = $applicationRequired
            configured_process_names = $ProcessNames
            observed_processes = $processes
            status = $(if ($applicationRequired) { 'launch_observed' } else { 'not_configured' })
            command_line_collected = $false
        }
        autologon = [pscustomobject]@{
            required = $autologonRequired
            profile = [string]$Package.acceptance.autologon_profile
            expected_user_name = $expectedUser
            configured_user_name = $(if ($autologonRequired) { $expectedUser } else { '' })
            configured_domain_name = $(if ($autologonRequired) { 'FIXTURE' } else { '' })
            auto_admin_logon = $(if ($autologonRequired) { '1' } else { '' })
            default_password_present = $autologonRequired
            default_password_value_collected = $false
            configuration_status = $(if ($autologonRequired) { 'autologon_ready' } else { 'not_applicable' })
            current_logged_on_user = $(if ($autologonRequired) { "FIXTURE\$expectedUser" } else { 'FIXTURE\TECH' })
            current_session_matches_expected = $autologonRequired
            before_boot_time_utc = $BeforeBootTime
            current_boot_time_utc = '2026-07-14T12:00:00Z'
            reboot_after_before_snapshot = $autologonRequired
            behavior_status = $(if ($autologonRequired) { 'session_match_after_reboot_observed' } else { 'not_applicable' })
        }
        machine_evidence_status = 'ready_for_technician_review'
        safety = [pscustomobject]@{
            target_mutation_performed = $false
            target_side_sysadminsuite_artifacts_written = $false
            default_password_value_collected = $false
            application_command_line_collected = $false
        }
        collection_notes = @('fixture_mode', 'no_network_activity', 'no_target_mutation')
    }
}

$remoteCollector = {
    param(
        [string]$PackageId,
        [string]$PackageName,
        [string[]]$ProcessNames,
        [string]$TitlePattern,
        [bool]$RequireResponding,
        [string]$AutoLogonProfile,
        [string]$ExpectedUserRule,
        [string]$BeforeBootTime
    )

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    function ConvertTo-AccountLeaf {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
        $leaf = $Value.Trim()
        if ($leaf.Contains('\')) { $leaf = $leaf.Split('\')[-1] }
        if ($leaf.Contains('@')) { $leaf = $leaf.Split('@')[0] }
        return $leaf.ToUpperInvariant()
    }

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

    $applicationRequired = $ProcessNames.Count -gt 0
    $observedProcesses = @()
    foreach ($configuredName in @($ProcessNames)) {
        foreach ($process in @(Get-Process -Name $configuredName -ErrorAction SilentlyContinue)) {
            $path = $null
            $startTime = $null
            $responding = $false
            $windowTitle = ''
            try { $path = $process.Path } catch {}
            try { $startTime = $process.StartTime.ToUniversalTime().ToString('o') } catch {}
            try { $responding = [bool]$process.Responding } catch {}
            try { $windowTitle = [string]$process.MainWindowTitle } catch {}
            $titleMatched = if ([string]::IsNullOrWhiteSpace($TitlePattern)) { $true } else { $windowTitle -match $TitlePattern }
            $observedProcesses += [pscustomobject]@{
                process_name = [string]$process.ProcessName
                process_id = [int]$process.Id
                session_id = [int]$process.SessionId
                executable_path = $path
                start_time_utc = $startTime
                responding = $responding
                main_window_title = $windowTitle
                window_title_matched = [bool]$titleMatched
                command_line_collected = $false
            }
        }
    }

    $applicationStatus = 'not_configured'
    if ($applicationRequired) {
        if ($observedProcesses.Count -eq 0) {
            $applicationStatus = 'not_running'
        }
        elseif ($RequireResponding -and @($observedProcesses | Where-Object { $_.responding }).Count -eq 0) {
            $applicationStatus = 'running_not_responding'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($TitlePattern) -and
            @($observedProcesses | Where-Object { $_.window_title_matched }).Count -eq 0) {
            $applicationStatus = 'running_window_not_matched'
        }
        else {
            $applicationStatus = 'launch_observed'
        }
    }

    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $autologonRequired = $AutoLogonProfile -eq 'windows_winlogon'
    $expectedUser = if ($ExpectedUserRule -eq 'computer_name') { $env:COMPUTERNAME.ToUpperInvariant() } else { '' }
    $autoAdminLogon = $null
    $configuredUser = $null
    $configuredDomain = $null
    $passwordPresent = $false
    $configurationStatus = 'not_applicable'
    $sessionMatch = $false
    $rebootObserved = $false
    $behaviorStatus = 'not_applicable'

    if ($autologonRequired) {
        $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        $autoAdminLogon = Get-RegistryValueSafe -Path $winlogon -Name 'AutoAdminLogon'
        $configuredUser = Get-RegistryValueSafe -Path $winlogon -Name 'DefaultUserName'
        $configuredDomain = Get-RegistryValueSafe -Path $winlogon -Name 'DefaultDomainName'
        $passwordPresent = Test-RegistryValueNameSafe -Path $winlogon -Name 'DefaultPassword'
        $enabled = ([string]$autoAdminLogon).Trim() -in @('1', '0x1')
        $configuredLeaf = ConvertTo-AccountLeaf -Value ([string]$configuredUser)
        $currentLeaf = ConvertTo-AccountLeaf -Value ([string]$computer.UserName)
        $sessionMatch = -not [string]::IsNullOrWhiteSpace($expectedUser) -and $currentLeaf -eq $expectedUser

        if (-not $enabled) { $configurationStatus = 'not_enabled' }
        elseif ($configuredLeaf -ne $expectedUser) { $configurationStatus = 'configured_user_mismatch' }
        elseif (-not $passwordPresent) { $configurationStatus = 'configured_password_missing' }
        else { $configurationStatus = 'autologon_ready' }

        $currentBoot = $os.LastBootUpTime.ToUniversalTime()
        if (-not [string]::IsNullOrWhiteSpace($BeforeBootTime)) {
            $beforeBootValue = [datetime]::MinValue
            if ([datetime]::TryParse($BeforeBootTime, [ref]$beforeBootValue)) {
                $rebootObserved = $currentBoot -gt $beforeBootValue.ToUniversalTime()
            }
        }

        if ($configurationStatus -ne 'autologon_ready') {
            $behaviorStatus = $configurationStatus
        }
        elseif ($sessionMatch -and $rebootObserved) {
            $behaviorStatus = 'session_match_after_reboot_observed'
        }
        elseif ($sessionMatch) {
            $behaviorStatus = 'session_match_observed_without_reboot_delta'
        }
        else {
            $behaviorStatus = 'configured_ready_current_session_mismatch'
        }
    }

    $applicationReady = -not $applicationRequired -or $applicationStatus -eq 'launch_observed'
    $autologonReady = -not $autologonRequired -or $behaviorStatus -eq 'session_match_after_reboot_observed'
    $machineStatus = if ($applicationReady -and $autologonReady) { 'ready_for_technician_review' } else { 'partial_review' }

    return [pscustomobject]@{
        schema_version = 'sas-approved-software-acceptance-target/v1'
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        requested_target = $env:COMPUTERNAME
        computer_name = $env:COMPUTERNAME.ToUpperInvariant()
        package_id = $PackageId
        package_name = $PackageName
        collection_status = 'success'
        error = $null
        application = [pscustomobject]@{
            required = $applicationRequired
            configured_process_names = $ProcessNames
            observed_processes = $observedProcesses
            status = $applicationStatus
            command_line_collected = $false
        }
        autologon = [pscustomobject]@{
            required = $autologonRequired
            profile = $AutoLogonProfile
            expected_user_name = $expectedUser
            configured_user_name = $configuredUser
            configured_domain_name = $configuredDomain
            auto_admin_logon = $autoAdminLogon
            default_password_present = [bool]$passwordPresent
            default_password_value_collected = $false
            configuration_status = $configurationStatus
            current_logged_on_user = [string]$computer.UserName
            current_session_matches_expected = [bool]$sessionMatch
            before_boot_time_utc = $BeforeBootTime
            current_boot_time_utc = $os.LastBootUpTime.ToUniversalTime().ToString('o')
            reboot_after_before_snapshot = [bool]$rebootObserved
            behavior_status = $behaviorStatus
        }
        machine_evidence_status = $machineStatus
        safety = [pscustomobject]@{
            target_mutation_performed = $false
            target_side_sysadminsuite_artifacts_written = $false
            default_password_value_collected = $false
            application_command_line_collected = $false
        }
        collection_notes = @('read_only_acceptance_extraction', 'no_application_launch_or_stop', 'no_secret_collection')
    }
}

$stateRecord = Read-SasOperatorState
$state = $stateRecord.value
$package = Get-SasPackage -PackageId ([string]$state.package_id)
$targets = @(Get-SasTargets -CsvPath ([string]$state.targets_csv))
$processNames = @(Get-SasConfiguredProcessNames -Package $package)
$titlePattern = Get-SasWindowPattern -Package $package

if (-not $FixtureMode -and -not $NonInteractive) {
    if ($processNames.Count -gt 0 -and -not $ApplicationObserved) {
        $answer = Read-Host 'Did you directly observe the application reach its expected ready surface? [y/N]'
        $ApplicationObserved = $answer -match '^(?i)y(es)?$'
    }
    if ([string]$package.acceptance.autologon_profile -eq 'windows_winlogon' -and
        -not $AutoLogonObservedAfterReboot) {
        $answer = Read-Host 'Did you directly observe automatic sign-in after reboot? [y/N]'
        $AutoLogonObservedAfterReboot = $answer -match '^(?i)y(es)?$'
    }
}

$acceptanceRoot = Join-Path ([string]$state.run_root) 'acceptance'
New-Item -ItemType Directory -Path $acceptanceRoot -Force | Out-Null
$results = @()
foreach ($target in $targets) {
    $beforeBoot = Get-SasBeforeBootTime -RunRoot ([string]$state.run_root) -Target $target
    $path = Join-Path $acceptanceRoot ((ConvertTo-SasSafeName -Value $target) + '.json')
    try {
        if ($FixtureMode) {
            $result = New-SasFixtureAcceptance -Target $target -Package $package -ProcessNames $processNames -TitlePattern $titlePattern -BeforeBootTime $beforeBoot
        }
        else {
            $session = $null
            $localAliases = @('localhost', '.', '127.0.0.1', $env:COMPUTERNAME)
            if ($localAliases -contains $target) {
                $result = & $remoteCollector ([string]$package.id) ([string]$package.display_name) $processNames $titlePattern ([bool]$package.acceptance.require_responding_process) ([string]$package.acceptance.autologon_profile) ([string]$package.acceptance.expected_autologon_user_rule) $beforeBoot
            }
            else {
                try {
                    $option = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 180000
                    $session = New-PSSession -ComputerName $target -SessionOption $option
                    $result = Invoke-Command -Session $session -ScriptBlock $remoteCollector -ArgumentList ([string]$package.id), ([string]$package.display_name), $processNames, $titlePattern, ([bool]$package.acceptance.require_responding_process), ([string]$package.acceptance.autologon_profile), ([string]$package.acceptance.expected_autologon_user_rule), $beforeBoot
                }
                finally {
                    if ($session) { Remove-PSSession -Session $session }
                }
            }
            $result.requested_target = $target
        }
    }
    catch {
        $result = [pscustomobject]@{
            schema_version = 'sas-approved-software-acceptance-target/v1'
            captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            requested_target = $target
            computer_name = $target.ToUpperInvariant()
            package_id = [string]$package.id
            package_name = [string]$package.display_name
            collection_status = 'failed'
            error = $_.Exception.Message
            application = $null
            autologon = $null
            machine_evidence_status = 'inconclusive'
            safety = [pscustomobject]@{
                target_mutation_performed = $false
                target_side_sysadminsuite_artifacts_written = $false
                default_password_value_collected = $false
                application_command_line_collected = $false
            }
        }
    }
    Write-SasJsonFile -Path $path -Value $result
    $results += $result
}

$failed = @($results | Where-Object { $_.collection_status -ne 'success' })
$machineReady = @($results | Where-Object { $_.machine_evidence_status -eq 'ready_for_technician_review' })
$appRequired = $processNames.Count -gt 0
$autoRequired = [string]$package.acceptance.autologon_profile -eq 'windows_winlogon'
$attestationComplete = (-not $appRequired -or $ApplicationObserved) -and (-not $autoRequired -or $AutoLogonObservedAfterReboot)

$proofLevel = 'PARTIAL_REVIEW'
if ($FixtureMode) {
    $proofLevel = 'FIXTURE_ONLY'
}
elseif ($failed.Count -eq 0 -and $machineReady.Count -eq $targets.Count -and $attestationComplete) {
    $proofLevel = 'TECHNICIAN_ATTESTED_MACHINE_EVIDENCE'
}
elseif ($failed.Count -eq 0 -and $machineReady.Count -eq $targets.Count) {
    $proofLevel = 'MACHINE_EVIDENCE_READY_FOR_TECHNICIAN_REVIEW'
}

$summary = [pscustomobject]@{
    schema_version = 'sas-approved-software-acceptance-summary/v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    package_id = [string]$package.id
    package_name = [string]$package.display_name
    run_root = [string]$state.run_root
    target_count = $targets.Count
    success_count = $targets.Count - $failed.Count
    failed_count = $failed.Count
    machine_ready_count = $machineReady.Count
    configured_process_names = $processNames
    window_title_pattern_configured = -not [string]::IsNullOrWhiteSpace($titlePattern)
    technician_attestation = [pscustomobject]@{
        application_observed_ready = [bool]$ApplicationObserved
        autologon_observed_after_reboot = [bool]$AutoLogonObservedAfterReboot
        actor_identity_proven = $false
        attestation_is_not_machine_verification = $true
    }
    proof_level = $proofLevel
    runtime_proof = ($proofLevel -eq 'TECHNICIAN_ATTESTED_MACHINE_EVIDENCE')
    results = $results
    proof_boundaries = @(
        'process_observation_does_not_prove_business_workflow_success',
        'current_session_match_does_not_alone_prove_automatic_logon',
        'technician_attestation_does_not_prove_actor_identity',
        'fixture_evidence_is_not_live_runtime_proof'
    )
    safety = [pscustomobject]@{
        target_mutation_performed = $false
        target_side_sysadminsuite_artifacts_written = $false
        default_password_value_collected = $false
        application_command_line_collected = $false
    }
}

$summaryPath = Join-Path $acceptanceRoot 'acceptance-summary.json'
Write-SasJsonFile -Path $summaryPath -Value $summary
$state.acceptance_summary_path = $summaryPath
$state.acceptance_proof_level = $proofLevel
$state.workflow_status = 'acceptance_extracted'
Write-SasJsonFile -Path $stateRecord.path -Value $state

Write-Host "ACCEPTANCE EXTRACTION COMPLETE - Package: $($package.display_name)"
Write-Host "Proof level: $proofLevel"
Write-Host "Summary: $summaryPath"
return $summary
