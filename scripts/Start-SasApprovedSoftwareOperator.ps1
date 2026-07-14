#Requires -Version 5.1
<#
.SYNOPSIS
Technician operator surface for the approved software catalog workflow.

.DESCRIPTION
Delegates package selection, snapshots, and installation to Start-SasApprovedSoftwareInstall.ps1
and acceptance extraction to Invoke-SasApprovedSoftwareAcceptance.ps1. When the existing install
engine has already written a complete software_install_summary.json but cannot return that summary
cleanly through the PowerShell pipeline, this wrapper validates the durable artifact, records its
operator handoff in workflow state, and preserves any reported install failures.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'ListPackages', 'Before', 'Plan', 'Install', 'After', 'Acceptance', 'OpenLatest')]
    [string]$Action = 'Menu',

    [string]$TargetsCsv,
    [string]$PackageId,
    [string[]]$InstallerArguments = @(),
    [string[]]$ProcessName = @(),
    [string]$WindowTitlePattern,
    [string]$OutputRoot,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$ApplicationObserved,
    [switch]$AutoLogonObservedAfterReboot,
    [switch]$FixtureMode,
    [switch]$NonInteractive,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $PSScriptRoot 'Start-SasApprovedSoftwareInstall.ps1'
$acceptanceScript = Join-Path $PSScriptRoot 'Invoke-SasApprovedSoftwareAcceptance.ps1'
foreach ($requiredPath in @($engine, $acceptanceScript)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Approved software operator dependency not found: $requiredPath"
    }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/approved_software_install'
}

function Get-SasEngineParameters {
    param([Parameter(Mandatory = $true)][string]$EngineAction)

    $parameters = @{
        Action = $EngineAction
        OutputRoot = $OutputRoot
        MaxTargets = $MaxTargets
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetsCsv)) { $parameters['TargetsCsv'] = $TargetsCsv }
    if (-not [string]::IsNullOrWhiteSpace($PackageId)) { $parameters['PackageId'] = $PackageId }
    if (@($InstallerArguments).Count -gt 0) { $parameters['InstallerArguments'] = @($InstallerArguments) }
    if ($FixtureMode) { $parameters['FixtureMode'] = $true }
    if ($NonInteractive) { $parameters['NonInteractive'] = $true }
    if ($NoOpen) { $parameters['NoOpen'] = $true }
    return $parameters
}

function Get-SasAcceptanceParameters {
    $parameters = @{
        OutputRoot = $OutputRoot
        MaxTargets = $MaxTargets
    }
    if (@($ProcessName).Count -gt 0) { $parameters['ProcessName'] = @($ProcessName) }
    if (-not [string]::IsNullOrWhiteSpace($WindowTitlePattern)) { $parameters['WindowTitlePattern'] = $WindowTitlePattern }
    if ($ApplicationObserved) { $parameters['ApplicationObserved'] = $true }
    if ($AutoLogonObservedAfterReboot) { $parameters['AutoLogonObservedAfterReboot'] = $true }
    if ($FixtureMode) { $parameters['FixtureMode'] = $true }
    if ($NonInteractive) { $parameters['NonInteractive'] = $true }
    return $parameters
}

function Read-SasOperatorState {
    $statePath = Join-Path $OutputRoot 'operator-state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Approved software operator state not found: $statePath"
    }
    return [pscustomobject]@{
        path = $statePath
        value = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    }
}

function Write-SasOperatorState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$State
    )
    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SasLatestInstallSummary {
    param([Parameter(Mandatory = $true)][string]$RunRoot)

    $installRoot = Join-Path $RunRoot 'software_install'
    if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) {
        throw "Install output root was not created: $installRoot"
    }

    $summaryFiles = @(Get-ChildItem -LiteralPath $installRoot -Filter 'software_install_summary.json' -File -Recurse -ErrorAction Stop |
        Sort-Object -Property LastWriteTimeUtc -Descending)
    if ($summaryFiles.Count -eq 0) {
        throw "Canonical install summary was not written under: $installRoot"
    }

    $summaryPath = $summaryFiles[0].FullName
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    if ([string]$summary.schema_version -ne 'sas-software-install-summary/v1') {
        throw "Unexpected canonical install summary schema: $($summary.schema_version)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$summary.operator_handoff_path) -or
        -not (Test-Path -LiteralPath ([string]$summary.operator_handoff_path) -PathType Leaf)) {
        throw "Canonical install handoff is missing or invalid: $($summary.operator_handoff_path)"
    }

    return [pscustomobject]@{
        path = $summaryPath
        value = $summary
    }
}

function Complete-SasInstallStateFromArtifact {
    param([Parameter(Mandatory = $true)][ValidateSet('Plan', 'Install')][string]$CompletedAction)

    $stateRecord = Read-SasOperatorState
    $state = $stateRecord.value
    $summaryRecord = Get-SasLatestInstallSummary -RunRoot ([string]$state.run_root)
    $summary = $summaryRecord.value

    if ([int]$summary.target_count -ne [int]$state.target_count) {
        throw "Canonical install summary target count $($summary.target_count) does not match Before snapshot target count $($state.target_count)."
    }

    if ($CompletedAction -eq 'Plan') {
        if ([int]$summary.planned_count -ne [int]$summary.target_count -or [int]$summary.failed_count -ne 0) {
            throw "WhatIf summary is incomplete: planned=$($summary.planned_count), targets=$($summary.target_count), failed=$($summary.failed_count)."
        }
        $state.workflow_status = 'install_planned_whatif'
    }
    else {
        $state.workflow_status = 'install_attempted'
    }

    $state.install_summary_path = [string]$summary.operator_handoff_path
    Write-SasOperatorState -Path $stateRecord.path -State $state

    Write-Host $(if ($CompletedAction -eq 'Plan') { 'INSTALL PLAN COMPLETE' } else { 'INSTALL ATTEMPT COMPLETE' })
    Write-Host "Install summary: $($summaryRecord.path)"
    Write-Host "Install handoff: $($state.install_summary_path)"

    if ($CompletedAction -eq 'Install' -and
        ([int]$summary.failed_count -gt 0 -or
         [int]$summary.cleanup_failure_count -gt 0 -or
         [int]$summary.repo_artifact_remaining_count -gt 0)) {
        throw "Install attempt produced unresolved results. Failed=$($summary.failed_count), cleanup failures=$($summary.cleanup_failure_count), target remnants=$($summary.repo_artifact_remaining_count)."
    }
}

function Invoke-SasEngineAction {
    param([Parameter(Mandatory = $true)][string]$EngineAction)

    $parameters = Get-SasEngineParameters -EngineAction $EngineAction
    if ($EngineAction -notin @('Plan', 'Install')) {
        & $engine @parameters
        return
    }

    try {
        & $engine @parameters
    }
    catch {
        $expectedReturnFailure = $_.Exception.Message -like '*Canonical install wrapper did not return its summary object*'
        if (-not $expectedReturnFailure) { throw }
        Complete-SasInstallStateFromArtifact -CompletedAction $EngineAction
    }
}

function Initialize-SasAcceptanceState {
    $stateRecord = Read-SasOperatorState
    $state = $stateRecord.value
    if ([string]$state.workflow_status -ne 'after_complete') {
        throw "Acceptance extraction requires a completed AFTER snapshot. Current status: $($state.workflow_status)"
    }

    foreach ($propertyName in @('acceptance_summary_path', 'acceptance_proof_level')) {
        if ($null -eq $state.PSObject.Properties[$propertyName]) {
            $state | Add-Member -NotePropertyName $propertyName -NotePropertyValue $null
        }
    }
    Write-SasOperatorState -Path $stateRecord.path -State $state
}

function Invoke-SasAcceptanceAction {
    Initialize-SasAcceptanceState
    $parameters = Get-SasAcceptanceParameters
    & $acceptanceScript @parameters
}

function Wait-SasOperator {
    if (-not $NonInteractive) { $null = Read-Host 'Press Enter to continue' }
}

function Show-SasMenu {
    while ($true) {
        Clear-Host
        Write-Host 'SysAdminSuite - Approved Software Install'
        Write-Host 'Catalog: Epic, AllScripts, AutoLogon'
        Write-Host ''
        Write-Host '[1] List approved packages and readiness'
        Write-Host '[2] Select package and capture BEFORE snapshot'
        Write-Host '[3] Plan selected package install (WhatIf)'
        Write-Host '[4] Install selected package after confirmed BEFORE snapshot'
        Write-Host '[5] Capture AFTER snapshot and compare'
        Write-Host '[6] Extract application launch and AutoLogon behavior'
        Write-Host '[7] Open latest evidence folder'
        Write-Host '[Q] Quit'
        Write-Host ''

        $choice = Read-Host 'Select action'
        try {
            switch -Regex ($choice) {
                '^1$' { Invoke-SasEngineAction -EngineAction ListPackages; Wait-SasOperator }
                '^2$' { Invoke-SasEngineAction -EngineAction Before; Wait-SasOperator }
                '^3$' { Invoke-SasEngineAction -EngineAction Plan; Wait-SasOperator }
                '^4$' { Invoke-SasEngineAction -EngineAction Install; Wait-SasOperator }
                '^5$' { Invoke-SasEngineAction -EngineAction After; Wait-SasOperator }
                '^6$' { Invoke-SasAcceptanceAction; Wait-SasOperator }
                '^7$' { Invoke-SasEngineAction -EngineAction OpenLatest; Wait-SasOperator }
                '(?i)^q$' { return }
                default { Write-Warning "Unknown selection: $choice"; Wait-SasOperator }
            }
        }
        catch {
            Write-Error $_
            Wait-SasOperator
        }
    }
}

if ($Action -eq 'Menu') {
    Show-SasMenu
}
elseif ($Action -eq 'Acceptance') {
    Invoke-SasAcceptanceAction
}
else {
    Invoke-SasEngineAction -EngineAction $Action
}
