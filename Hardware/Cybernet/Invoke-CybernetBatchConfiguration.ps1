#Requires -Version 5.1
<#
.SYNOPSIS
Plan, apply, or validate the bounded Cybernet hardware configuration as one workflow.

.DESCRIPTION
Composes the repository's canonical hardware authorities in this order:
1. standby and hibernate idle timeouts = Never;
2. Windows physical power-button action = Do nothing;
3. eligible integrated-display Privacy/Menu and display power buttons disabled through MCCS VCP 0xCA;
4. read-only post-install validation, including COM-port classification.

COM remapping is intentionally not performed remotely. An exact COM3-COM6 result routes the technician
to the existing local AutoFix and reboot workflow. Plan is the default and contacts no targets.
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
    [switch]$AllowTargetMutation,
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($FixtureMode -and $AllowTargetMutation) { throw 'FixtureMode is offline and cannot be combined with -AllowTargetMutation.' }
if ($Mode -eq 'Apply' -and -not $FixtureMode -and -not $AllowTargetMutation) {
    throw 'Apply requires -AllowTargetMutation. Run Plan or FixtureMode first.'
}

$common = Join-Path $PSScriptRoot 'CybernetHardware.Common.psm1'
if (-not (Test-Path -LiteralPath $common -PathType Leaf)) { throw "Missing shared Cybernet hardware module: $common" }
Import-Module $common -Force
$repoRoot = Get-SasCybernetRepositoryRoot
$targets = @(Resolve-SasCybernetTargets -ComputerName $ComputerName -TargetsCsv $TargetsCsv -MaxTargets $MaxTargets -RepoRoot $repoRoot -Role 'Cybernet batch configuration target CSV')
$run = New-SasCybernetRunRoot -OutputRoot $OutputRoot -RepoRoot $repoRoot -Prefix 'batch-configuration' -Role 'Cybernet batch configuration output root'
$summaryPath = Join-Path $run.run_root 'cybernet_batch_configuration_summary.json'
$handoffPath = Join-Path $run.run_root 'operator_handoff.txt'

function Get-SasPowerShellEngine {
    $processPath = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    if (-not [string]::IsNullOrWhiteSpace($processPath)) { return $processPath }
    foreach ($candidate in @('pwsh', 'powershell.exe', 'powershell')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'No PowerShell engine is available for bounded child-script execution.'
}

function Invoke-SasCybernetStage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$StageOutput
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { throw "Missing Cybernet batch stage: $ScriptPath" }
    $engine = Get-SasPowerShellEngine
    $consolePath = Join-Path $run.run_root ("{0}.console.log" -f $Name)
    $childArguments = @('-NoProfile', '-File', $ScriptPath) + $Arguments + @('-OutputRoot', $StageOutput, '-MaxTargets', [string]$MaxTargets)
    $output = @(& $engine @childArguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath $consolePath -Encoding UTF8 -WhatIf:$false
    return [pscustomobject][ordered]@{
        name = $Name
        script = $ScriptPath
        exit_code = $exitCode
        status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        output_root = $StageOutput
        console_log = $consolePath
    }
}

$targetArguments = @('-ComputerName') + @($targets)
$commonArguments = @($targetArguments)
if ($FixtureMode) { $commonArguments += '-FixtureMode' }
$stages = @()

if ($Mode -eq 'Plan') {
    $stages += Invoke-SasCybernetStage -Name 'no-sleep-plan' -ScriptPath (Join-Path $PSScriptRoot 'Set-NoSleep.ps1') -StageOutput (Join-Path $run.run_root 'no-sleep') -Arguments ($commonArguments + '-WhatIf')
    $stages += Invoke-SasCybernetStage -Name 'power-button-plan' -ScriptPath (Join-Path $PSScriptRoot 'Set-PowerButtonDoNothing.ps1') -StageOutput (Join-Path $run.run_root 'power-button') -Arguments ($commonArguments + '-WhatIf')
    $stages += Invoke-SasCybernetStage -Name 'privacy-button-plan' -ScriptPath (Join-Path $PSScriptRoot 'Disable-PrivacyButton.ps1') -StageOutput (Join-Path $run.run_root 'privacy-button') -Arguments ($commonArguments + @('-MonitorIndex', [string]$MonitorIndex, '-WhatIf'))
    $stages += Invoke-SasCybernetStage -Name 'validation-plan' -ScriptPath (Join-Path $PSScriptRoot 'PostInstall-Validation.ps1') -StageOutput (Join-Path $run.run_root 'validation') -Arguments ($targetArguments + @('-MonitorIndex', [string]$MonitorIndex, '-PlanOnly'))
}
elseif ($Mode -eq 'Validate') {
    $validateArgs = $commonArguments + @('-MonitorIndex', [string]$MonitorIndex)
    $stages += Invoke-SasCybernetStage -Name 'postinstall-validation' -ScriptPath (Join-Path $PSScriptRoot 'PostInstall-Validation.ps1') -StageOutput (Join-Path $run.run_root 'validation') -Arguments $validateArgs
}
else {
    if (-not $FixtureMode) {
        $scope = $targets -join ','
        if (-not $PSCmdlet.ShouldProcess($scope, 'Apply no-sleep, physical power-button, and DDC/CI Privacy/Menu controls, then validate')) {
            return
        }
        $commonArguments += @('-AllowTargetMutation', '-Confirm:$false')
    }
    $stages += Invoke-SasCybernetStage -Name 'no-sleep-apply' -ScriptPath (Join-Path $PSScriptRoot 'Set-NoSleep.ps1') -StageOutput (Join-Path $run.run_root 'no-sleep') -Arguments $commonArguments
    $stages += Invoke-SasCybernetStage -Name 'power-button-apply' -ScriptPath (Join-Path $PSScriptRoot 'Set-PowerButtonDoNothing.ps1') -StageOutput (Join-Path $run.run_root 'power-button') -Arguments $commonArguments
    $stages += Invoke-SasCybernetStage -Name 'privacy-button-apply' -ScriptPath (Join-Path $PSScriptRoot 'Disable-PrivacyButton.ps1') -StageOutput (Join-Path $run.run_root 'privacy-button') -Arguments ($commonArguments + @('-MonitorIndex', [string]$MonitorIndex))
    $validationArgs = $targetArguments + @('-MonitorIndex', [string]$MonitorIndex)
    if ($FixtureMode) { $validationArgs += '-FixtureMode' }
    $stages += Invoke-SasCybernetStage -Name 'postinstall-validation' -ScriptPath (Join-Path $PSScriptRoot 'PostInstall-Validation.ps1') -StageOutput (Join-Path $run.run_root 'validation') -Arguments $validationArgs
}

$failedStages = @($stages | Where-Object { $_.exit_code -ne 0 })
$status = if ($failedStages.Count -eq 0) {
    if ($Mode -eq 'Plan') { 'PLAN_READY' } elseif ($Mode -eq 'Validate') { 'VALIDATED' } else { 'APPLIED_AND_VALIDATED' }
}
else { 'ACTION_REQUIRED' }
$summary = [ordered]@{
    schema_version = 'sas-cybernet-batch-configuration-summary/v1'
    run_id = $run.run_id
    mode = $Mode
    status = $status
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    target_count = $targets.Count
    fixture_mode = [bool]$FixtureMode
    stages = @($stages)
    failed_stage_count = $failedStages.Count
    network_activity_performed = ($Mode -ne 'Plan' -and -not $FixtureMode)
    target_mutation_performed = ($Mode -eq 'Apply' -and -not $FixtureMode -and @($stages | Where-Object { $_.name -like '*apply' -and $_.exit_code -eq 0 }).Count -gt 0)
    com_mutation_performed = $false
    com_repair_policy = 'LOCAL_ONLY_EXISTING_AUTOFIX'
    summary_path = $summaryPath
}
Write-SasCybernetHardwareJson -Path $summaryPath -Value $summary
@(
    "Cybernet batch configuration: $($run.run_id)",
    "Mode: $Mode",
    "Status: $status",
    "Targets: $($targets.Count)",
    "Failed stages: $($failedStages.Count)",
    'COM-port mutation was not performed. Exact COM3-COM6 findings route to the local AutoFix and reboot workflow.',
    'A fixture PASS is contract proof only. Use one authorized Cybernet pilot before expanding the target list.',
    "Summary: $summaryPath"
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
Write-Output ([pscustomobject]$summary)
if ($failedStages.Count -gt 0) { exit 1 }
exit 0
