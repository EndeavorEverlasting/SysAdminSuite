#Requires -Version 5.1
<#
.SYNOPSIS
Plan, apply, or validate the complete Cybernet client configuration.

.DESCRIPTION
Composes the merged Cybernet hardware batch with the approved Windows-native software package-set
controller. The tracked client-preference profile is the source of truth for no-sleep, physical power
button Do nothing, MCCS VCP 0xCA display-button lock, COM readiness, and the six-package clinical set.

Plan contacts neither targets nor the software share. Apply configures and validates hardware first,
installs the approved package set with AutoLogon last, then validates hardware again. Validate is
read-only and leaves software launch/behavior acceptance to the technician. No mode reboots a target.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Plan', 'Apply', 'Validate')]
    [string]$Mode = 'Plan',
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [ValidateRange(-1, 64)][int]$MonitorIndex = -1,
    [string]$OutputRoot,
    [ValidateRange(1, 25)][int]$MaxTargets = 25,
    [ValidateRange(10, 7200)][int]$SoftwareWaitTimeout = 1800,
    [string]$BashPath,
    [switch]$AllowTargetMutation,
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($FixtureMode -and $AllowTargetMutation) {
    throw 'FixtureMode is offline and cannot be combined with -AllowTargetMutation.'
}
if ($Mode -eq 'Apply' -and -not $FixtureMode -and -not $AllowTargetMutation) {
    throw 'Apply requires -AllowTargetMutation. Run Plan first and use one authorized pilot.'
}

$commonPath = Join-Path $PSScriptRoot 'CybernetHardware.Common.psm1'
$hardwareBatchPath = Join-Path $PSScriptRoot 'Invoke-CybernetBatchConfiguration.ps1'
$stageRunnerPath = Join-Path $PSScriptRoot 'Invoke-CybernetStage.ps1'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$profilePath = Join-Path $repoRoot 'Config\cybernet-client-preferences.json'
$packageSetPath = Join-Path $repoRoot 'configs\software-packages\windows-native-package-sets.json'
$softwareControllerPath = Join-Path $repoRoot 'bash\apps\sas-install-apps.sh'
foreach ($requiredPath in @($commonPath, $hardwareBatchPath, $stageRunnerPath, $profilePath, $packageSetPath, $softwareControllerPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing Cybernet client-configuration dependency: $requiredPath"
    }
}

Import-Module $commonPath -Force
$targets = @(Resolve-SasCybernetTargets `
    -ComputerName $ComputerName `
    -TargetsCsv $TargetsCsv `
    -MaxTargets $MaxTargets `
    -RepoRoot $repoRoot `
    -Role 'Cybernet client-configuration target CSV')
$run = New-SasCybernetRunRoot `
    -OutputRoot $OutputRoot `
    -RepoRoot $repoRoot `
    -Prefix 'client-configuration' `
    -Role 'Cybernet client-configuration output root'
$summaryPath = Join-Path $run.run_root 'cybernet_client_configuration_summary.json'
$handoffPath = Join-Path $run.run_root 'operator_handoff.txt'
$acceptancePath = Join-Path $run.run_root 'technician_software_acceptance.txt'

$profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$profile.schema_version -ne 'sas-cybernet-client-preferences/v1') {
    throw "Unsupported Cybernet client-preference profile: $($profile.schema_version)"
}
if ([int]$profile.workflow.maximum_target_count -ne 25 -or $MaxTargets -gt [int]$profile.workflow.maximum_target_count) {
    throw 'The client-preference profile limits each run to 25 explicit targets.'
}
if ([string]$profile.hardware.physical_power_button_action -ne 'do_nothing' -or
    [string]$profile.hardware.display_button_control.vcp_code -ne '0xCA' -or
    [string]$profile.hardware.display_button_control.desired_value -ne '0x0303') {
    throw 'The tracked hardware preference profile is malformed or unsupported.'
}

$packageCatalog = Get-Content -LiteralPath $packageSetPath -Raw -Encoding UTF8 | ConvertFrom-Json
$packageSetId = [string]$profile.software.package_set_id
$packageSet = @($packageCatalog.package_sets | Where-Object { [string]$_.id -eq $packageSetId })
if ($packageSet.Count -ne 1) {
    throw "Approved software package set not found or ambiguous: $packageSetId"
}
$profilePackageIds = @($profile.software.package_ids | ForEach-Object { [string]$_ })
$catalogPackageIds = @($packageSet[0].package_ids | ForEach-Object { [string]$_ })
if (($profilePackageIds -join '|') -ne ($catalogPackageIds -join '|') -or
    $catalogPackageIds.Count -ne [int]$profile.software.package_count -or
    $catalogPackageIds[-1] -ne 'autologon') {
    throw 'The client-preference software order does not match the approved package-set catalog.'
}
$packageNames = @{}
foreach ($package in @($packageCatalog.packages)) {
    $packageNames[[string]$package.id] = [string]$package.display_name
}

function Get-SasGitBashPath {
    if (-not [string]::IsNullOrWhiteSpace($BashPath)) {
        if (-not (Test-Path -LiteralPath $BashPath -PathType Leaf)) { throw "Git Bash not found: $BashPath" }
        return (Resolve-Path -LiteralPath $BashPath).Path
    }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        (Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe')
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe')
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    $command = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw 'Git Bash is required for the approved Windows-native software package-set controller.'
}

function Get-SasPowerShellEngine {
    $processPath = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    if (-not [string]::IsNullOrWhiteSpace($processPath)) { return $processPath }
    foreach ($candidate in @('pwsh', 'powershell.exe', 'powershell')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'No PowerShell engine is available for the Cybernet hardware stage.'
}

function Invoke-SasHardwareStage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('Plan', 'Apply', 'Validate')][string]$HardwareMode
    )
    $parameters = [ordered]@{
        Mode = $HardwareMode
        ComputerName = @($targets)
        MonitorIndex = $MonitorIndex
        MaxTargets = $MaxTargets
        OutputRoot = (Join-Path $run.run_root $Name)
    }
    if ($FixtureMode) { $parameters['FixtureMode'] = $true }
    if ($HardwareMode -eq 'Apply' -and -not $FixtureMode) {
        $parameters['AllowTargetMutation'] = $true
        $parameters['Confirm'] = $false
    }
    $parameterPath = Join-Path $run.run_root ("{0}.parameters.json" -f $Name)
    Write-SasCybernetHardwareJson -Path $parameterPath -Value $parameters
    $consolePath = Join-Path $run.run_root ("{0}.console.log" -f $Name)
    $engine = Get-SasPowerShellEngine
    $console = @(& $engine -NoProfile -File $stageRunnerPath -ScriptPath $hardwareBatchPath -ParameterJson $parameterPath 2>&1 |
        ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $console | Set-Content -LiteralPath $consolePath -Encoding UTF8 -WhatIf:$false
    return [pscustomobject][ordered]@{
        name = $Name
        kind = 'hardware'
        mode = $HardwareMode
        status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        exit_code = $exitCode
        console_log = $consolePath
        parameter_document = $parameterPath
    }
}

function Invoke-SasSoftwareStage {
    param([Parameter(Mandatory = $true)][bool]$DryRun)
    $consolePath = Join-Path $run.run_root 'approved-software.console.log'
    $targetArgument = @($targets) -join ','
    $arguments = @(
        $softwareControllerPath,
        '--targets', $targetArgument,
        '--package-set', $packageSetId,
        '--allow-legacy',
        '--wait-timeout', [string]$SoftwareWaitTimeout
    )
    if ($DryRun) { $arguments += '--dry-run' }
    $bash = Get-SasGitBashPath
    Push-Location $repoRoot
    try {
        $console = @(& $bash @arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $console | Set-Content -LiteralPath $consolePath -Encoding UTF8 -WhatIf:$false
    return [pscustomobject][ordered]@{
        name = if ($DryRun) { 'approved-software-plan' } else { 'approved-software-install' }
        kind = 'software'
        package_set = $packageSetId
        status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        exit_code = $exitCode
        dry_run = $DryRun
        console_log = $consolePath
        controller_output_root = (Join-Path $repoRoot 'bash\apps\output')
    }
}

@(
    'Cybernet technician software acceptance',
    "Profile: $($profile.profile_id)",
    "Package set: $packageSetId",
    '',
    'Confirm each approved item through the normal user workflow:'
) + @($catalogPackageIds | ForEach-Object {
    $name = if ($packageNames.ContainsKey($_)) { $packageNames[$_] } else { $_ }
    "[ ] $name"
}) + @(
    '',
    '[ ] Expected shortcuts/applications exist.',
    '[ ] Each application opens and reaches its approved destination or expected ready state.',
    '[ ] AutoLogon is recorded as installed only; post-reboot automatic sign-in requires separate observation.',
    '[ ] No unapproved reboot was performed.',
    '[ ] Ticket/change acceptance was recorded outside Git.',
    '',
    'Do not classify the device complete until controller evidence, cleanup, hardware validation, and technician acceptance all pass.'
) | Set-Content -LiteralPath $acceptancePath -Encoding UTF8 -WhatIf:$false

$stages = @()
if ($Mode -eq 'Plan') {
    $stages += Invoke-SasHardwareStage -Name 'hardware-plan' -HardwareMode Plan
    if (@($stages | Where-Object exit_code -ne 0).Count -eq 0) {
        $stages += Invoke-SasSoftwareStage -DryRun $true
    }
}
elseif ($Mode -eq 'Validate') {
    $stages += Invoke-SasHardwareStage -Name 'hardware-validation' -HardwareMode Validate
}
else {
    if (-not $FixtureMode) {
        $scope = @($targets) -join ','
        $action = "Apply client profile $($profile.profile_id): hardware policy, package set $packageSetId, and post-software validation"
        if (-not $PSCmdlet.ShouldProcess($scope, $action)) { return }
    }
    $stages += Invoke-SasHardwareStage -Name 'hardware-apply' -HardwareMode Apply
    if (@($stages | Where-Object exit_code -ne 0).Count -eq 0) {
        $stages += Invoke-SasSoftwareStage -DryRun ([bool]$FixtureMode)
    }
    if (@($stages | Where-Object { $_.name -like 'approved-software-*' -and $_.exit_code -eq 0 }).Count -eq 1) {
        $stages += Invoke-SasHardwareStage -Name 'hardware-post-software-validation' -HardwareMode Validate
    }
}

$failedStages = @($stages | Where-Object exit_code -ne 0)
$status = if ($failedStages.Count -gt 0) {
    'ACTION_REQUIRED'
}
elif ($FixtureMode) {
    'FIXTURE_PASS'
}
elif ($Mode -eq 'Plan') {
    'PLAN_READY'
}
elif ($Mode -eq 'Validate') {
    'HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED'
}
else {
    'APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED'
}
$summary = [ordered]@{
    schema_version = 'sas-cybernet-client-configuration-summary/v1'
    run_id = $run.run_id
    profile_id = [string]$profile.profile_id
    mode = $Mode
    status = $status
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    target_count = $targets.Count
    package_set_id = $packageSetId
    package_count = $catalogPackageIds.Count
    stages = @($stages)
    failed_stage_count = $failedStages.Count
    fixture_mode = [bool]$FixtureMode
    network_activity_performed = ($Mode -ne 'Plan' -and -not $FixtureMode)
    target_mutation_attempted = ($Mode -eq 'Apply' -and -not $FixtureMode)
    target_mutation_performed = if ($Mode -eq 'Apply' -and -not $FixtureMode) { $null } else { $false }
    automatic_reboot_performed = $false
    com_mutation_performed = $false
    software_acceptance_required = $true
    software_acceptance_path = $acceptancePath
    summary_path = $summaryPath
}
Write-SasCybernetHardwareJson -Path $summaryPath -Value $summary
@(
    "Cybernet client configuration: $($run.run_id)",
    "Profile: $($profile.profile_id)",
    "Mode: $Mode",
    "Status: $status",
    "Targets: $($targets.Count)",
    "Approved software set: $packageSetId ($($catalogPackageIds.Count) packages; AutoLogon last)",
    'Hardware preference: sleep/hibernate Never, physical power button Do nothing, Privacy/Menu lock VCP 0xCA = 0x0303.',
    'COM must be COM1-COM4. Exact COM3-COM6 routes to local AutoFix and a separately authorized reboot.',
    'No reboot or remote COM mutation was performed by this workflow.',
    "Technician acceptance: $acceptancePath",
    "Summary: $summaryPath"
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
Write-Output ([pscustomobject]$summary)
if ($failedStages.Count -gt 0) { exit 1 }
exit 0
