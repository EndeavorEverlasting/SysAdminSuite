#Requires -Version 5.1
<#
.SYNOPSIS
Technician-facing launcher for the AutoLogon before/after state-delta workflow.

.DESCRIPTION
Provides a menu and stateful automation around Invoke-SasAutoLogonStateDelta.ps1 so a technician
does not need to remember a RunId, repeat a target manifest, or compose a PowerShell command.

The launcher stores only local workflow metadata under the approved AutoLogon evidence root. It does
not store credentials or password values, and it does not add any target mutation beyond the
read-only collector it delegates to.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Before', 'After', 'Assess', 'OpenLatest')]
    [string]$Action = 'Menu',

    [string]$TargetsCsv,
    [string[]]$ComputerName = @(),
    [string]$TechnicianLabel,
    [string]$RunId,
    [string]$OutputRoot,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$FixtureMode,
    [switch]$NonInteractive,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasPropertyValue {
    param([object]$InputObject, [string]$Name, [object]$Default = $null)

    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Write-SasOperatorJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-SasOperatorState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Operator state is unreadable: $Path. $($_.Exception.Message)"
    }
}

function Test-SasRunId {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value)) -and
        ($Value -match '^autologon-delta-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$')
}

function Test-SasIncompleteRun {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$CandidateRunId)

    if (-not (Test-SasRunId -Value $CandidateRunId)) { return $false }
    $runRoot = Join-Path -Path $Root -ChildPath $CandidateRunId
    $beforeManifest = Join-Path -Path $runRoot -ChildPath 'run_manifest_before.json'
    $afterManifest = Join-Path -Path $runRoot -ChildPath 'run_manifest_after.json'
    return (Test-Path -LiteralPath $beforeManifest -PathType Leaf) -and
        -not (Test-Path -LiteralPath $afterManifest -PathType Leaf)
}

function Get-SasIncompleteRuns {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                Test-SasIncompleteRun -Root $Root -CandidateRunId $_.Name
            } |
            Sort-Object -Property LastWriteTimeUtc -Descending
    )
}

function Resolve-SasAfterRunId {
    param(
        [string]$RequestedRunId,
        [object]$State,
        [string]$Root,
        [switch]$Unattended
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedRunId)) {
        if (-not (Test-SasRunId -Value $RequestedRunId)) {
            throw "Invalid RunId format: $RequestedRunId"
        }
        if (-not (Test-SasIncompleteRun -Root $Root -CandidateRunId $RequestedRunId)) {
            throw "RunId is not waiting for an After capture: $RequestedRunId"
        }
        return $RequestedRunId
    }

    $stateRunId = [string](Get-SasPropertyValue -InputObject $State -Name 'active_run_id' -Default '')
    if (Test-SasIncompleteRun -Root $Root -CandidateRunId $stateRunId) {
        return $stateRunId
    }

    $incomplete = @(Get-SasIncompleteRuns -Root $Root)
    if ($incomplete.Count -eq 0) {
        throw 'No saved Before capture is waiting for an After capture.'
    }
    if ($incomplete.Count -eq 1) {
        return $incomplete[0].Name
    }
    if ($Unattended) {
        $ids = @($incomplete | ForEach-Object { $_.Name }) -join ', '
        throw "Multiple incomplete AutoLogon runs exist. Supply -RunId explicitly. Runs: $ids"
    }

    Write-Host ''
    Write-Host 'More than one saved baseline is waiting for an After capture:' -ForegroundColor Yellow
    for ($index = 0; $index -lt $incomplete.Count; $index++) {
        Write-Host ('  [{0}] {1}' -f ($index + 1), $incomplete[$index].Name)
    }
    $selection = Read-Host 'Choose the baseline number'
    $number = 0
    if (-not [int]::TryParse($selection, [ref]$number) -or $number -lt 1 -or $number -gt $incomplete.Count) {
        throw 'No valid baseline was selected.'
    }
    return $incomplete[$number - 1].Name
}

function Select-SasTargetCsv {
    param(
        [string]$RequestedPath,
        [string]$DefaultPath,
        [switch]$Unattended
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return $RequestedPath
    }
    if ($Unattended) {
        throw 'Before and Assess actions require -TargetsCsv or -ComputerName in noninteractive mode.'
    }

    if (Test-Path -LiteralPath $DefaultPath -PathType Leaf) {
        $answer = Read-Host "Use the saved pilot manifest '$DefaultPath'? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToUpperInvariant() -eq 'Y') {
            return $DefaultPath
        }
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select the approved AutoLogon target CSV'
        $dialog.Filter = 'CSV target manifests (*.csv)|*.csv|All files (*.*)|*.*'
        $defaultParent = Split-Path -Path $DefaultPath -Parent
        if (Test-Path -LiteralPath $defaultParent -PathType Container) {
            $dialog.InitialDirectory = $defaultParent
        }
        $dialog.Multiselect = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
    }
    catch {
        Write-Verbose "Windows file picker unavailable: $($_.Exception.Message)"
    }

    $typed = Read-Host 'Enter the approved target CSV path'
    if ([string]::IsNullOrWhiteSpace($typed)) {
        throw 'No target manifest was selected.'
    }
    return $typed.Trim('"')
}

function Resolve-SasTechnicianLabel {
    param([string]$RequestedLabel, [switch]$Unattended)

    if (-not [string]::IsNullOrWhiteSpace($RequestedLabel)) {
        return $RequestedLabel.Trim()
    }
    $defaultLabel = 'AutoLogon batch {0}' -f (Get-Date -Format 'yyyy-MM-dd')
    if ($Unattended) { return $defaultLabel }

    $typed = Read-Host "Assignment label [$defaultLabel]"
    if ([string]::IsNullOrWhiteSpace($typed)) { return $defaultLabel }
    return $typed.Trim()
}

function Get-SasBeforeManifest {
    param([string]$Root, [string]$CandidateRunId)

    $path = Join-Path -Path (Join-Path -Path $Root -ChildPath $CandidateRunId) -ChildPath 'run_manifest_before.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Before manifest not found: $path"
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-SasLatestRunRoot {
    param([string]$Root, [object]$State)

    $stateRunId = [string](Get-SasPropertyValue -InputObject $State -Name 'active_run_id' -Default '')
    if (Test-SasRunId -Value $stateRunId) {
        $stateRoot = Join-Path -Path $Root -ChildPath $stateRunId
        if (Test-Path -LiteralPath $stateRoot -PathType Container) { return $stateRoot }
    }

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $null }
    $latest = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-SasRunId -Value $_.Name } |
        Sort-Object -Property LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

function Open-SasEvidenceFolder {
    param([string]$Path, [switch]$Suppress)

    if ($Suppress -or [string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) | Out-Null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$collectorPath = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SasAutoLogonStateDelta.ps1'
$targetIntakeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $collectorPath -PathType Leaf)) {
    throw "AutoLogon state-delta collector not found: $collectorPath"
}
if (-not (Test-Path -LiteralPath $targetIntakeModule -PathType Leaf)) {
    throw "Target intake module not found: $targetIntakeModule"
}
Import-Module -Name $targetIntakeModule -Force

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey/output/autologon_state_delta'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'AutoLogon launcher output root'
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$statePath = Join-Path -Path $OutputRoot -ChildPath 'operator-state.json'
$state = Read-SasOperatorState -Path $statePath
$defaultTargetsCsv = Join-Path -Path $repoRoot -ChildPath 'targets/local/autologon-pilot.csv'
$invokedFromMenu = $Action -eq 'Menu'

if ($invokedFromMenu) {
    Clear-Host
    Write-Host 'SysAdminSuite AutoLogon Verification' -ForegroundColor Cyan
    Write-Host 'No RunId or PowerShell command needs to be remembered.' -ForegroundColor Green
    Write-Host ''

    $activeRunId = [string](Get-SasPropertyValue -InputObject $state -Name 'active_run_id' -Default '')
    if (Test-SasIncompleteRun -Root $OutputRoot -CandidateRunId $activeRunId) {
        Write-Host "Saved baseline waiting for completion: $activeRunId" -ForegroundColor Yellow
        Write-Host ''
    }

    Write-Host '[1] Capture BEFORE state'
    Write-Host '[2] Capture AFTER state and compare automatically'
    Write-Host '[3] Assess current state only'
    Write-Host '[4] Open latest evidence folder'
    Write-Host '[Q] Quit'
    Write-Host ''
    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $Action = 'Before' }
        '2' { $Action = 'After' }
        '3' { $Action = 'Assess' }
        '4' { $Action = 'OpenLatest' }
        'Q' { return }
        default { throw 'No valid menu action was selected.' }
    }
}

switch ($Action) {
    'Before' {
        $activeRunId = [string](Get-SasPropertyValue -InputObject $state -Name 'active_run_id' -Default '')
        if ([string]::IsNullOrWhiteSpace($RunId) -and (Test-SasIncompleteRun -Root $OutputRoot -CandidateRunId $activeRunId)) {
            throw "Baseline $activeRunId is still waiting for an After capture. Finish it before starting another batch."
        }

        $effectiveRunId = $RunId
        if ([string]::IsNullOrWhiteSpace($effectiveRunId)) {
            $effectiveRunId = 'autologon-delta-{0}-{1}' -f (
                Get-Date -Format 'yyyyMMdd-HHmmss'
            ), ([guid]::NewGuid().ToString('N').Substring(0, 8))
        }
        if (-not (Test-SasRunId -Value $effectiveRunId)) {
            throw "Invalid RunId format: $effectiveRunId"
        }

        $effectiveCsv = $TargetsCsv
        if (@($ComputerName).Count -eq 0) {
            $effectiveCsv = Select-SasTargetCsv -RequestedPath $TargetsCsv -DefaultPath $defaultTargetsCsv -Unattended:$NonInteractive
            Assert-SasApprovedInputPath -Path $effectiveCsv -RepoRoot $repoRoot -Role 'AutoLogon target manifest'
            $effectiveCsv = (Resolve-Path -LiteralPath $effectiveCsv).Path
        }
        $effectiveLabel = Resolve-SasTechnicianLabel -RequestedLabel $TechnicianLabel -Unattended:$NonInteractive

        $collectorArguments = @{
            Mode = 'Before'
            RunId = $effectiveRunId
            OutputRoot = $OutputRoot
            TechnicianLabel = $effectiveLabel
            MaxTargets = $MaxTargets
            FixtureMode = [bool]$FixtureMode
        }
        if (@($ComputerName).Count -gt 0) {
            $collectorArguments.ComputerName = @($ComputerName)
        }
        else {
            $collectorArguments.TargetsCsv = $effectiveCsv
        }

        $result = & $collectorPath @collectorArguments
        $operatorState = [ordered]@{
            schema_version = 'sas-autologon-state-delta-operator-state/v1'
            active_run_id = $effectiveRunId
            phase = 'before_complete'
            technician_label = $effectiveLabel
            targets_csv = $effectiveCsv
            computer_names = @($ComputerName)
            target_count = [int](Get-SasPropertyValue -InputObject $result -Name 'target_count' -Default 0)
            before_completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            after_completed_at_utc = $null
            default_password_value_collected = $false
            target_mutation_performed = $false
        }
        Write-SasOperatorJson -Path $statePath -Value $operatorState

        Write-Host ''
        Write-Host 'BEFORE capture saved.' -ForegroundColor Green
        Write-Host "Batch: $effectiveRunId"
        Write-Host 'After the approved AutoLogon work, open this same launcher and choose option 2.' -ForegroundColor Cyan
        $result
    }

    'After' {
        $effectiveRunId = Resolve-SasAfterRunId -RequestedRunId $RunId -State $state -Root $OutputRoot -Unattended:$NonInteractive
        $beforeManifest = Get-SasBeforeManifest -Root $OutputRoot -CandidateRunId $effectiveRunId
        $savedLabel = [string](Get-SasPropertyValue -InputObject $state -Name 'technician_label' -Default '')
        if ([string]::IsNullOrWhiteSpace($savedLabel)) {
            $savedLabel = [string](Get-SasPropertyValue -InputObject $beforeManifest -Name 'technician_label' -Default '')
        }
        $effectiveLabel = if ([string]::IsNullOrWhiteSpace($TechnicianLabel)) { $savedLabel } else { $TechnicianLabel.Trim() }

        Write-Host "Completing saved baseline: $effectiveRunId" -ForegroundColor Cyan
        Write-Host "Targets recovered automatically: $(@(Get-SasPropertyValue -InputObject $beforeManifest -Name 'targets' -Default @()).Count)"

        $collectorArguments = @{
            Mode = 'After'
            RunId = $effectiveRunId
            OutputRoot = $OutputRoot
            TechnicianLabel = $effectiveLabel
            MaxTargets = $MaxTargets
            FixtureMode = [bool]$FixtureMode
        }
        $result = & $collectorPath @collectorArguments

        $operatorState = [ordered]@{
            schema_version = 'sas-autologon-state-delta-operator-state/v1'
            active_run_id = $effectiveRunId
            phase = 'after_complete'
            technician_label = $effectiveLabel
            targets_csv = [string](Get-SasPropertyValue -InputObject $state -Name 'targets_csv' -Default '')
            computer_names = @(Get-SasPropertyValue -InputObject $state -Name 'computer_names' -Default @())
            target_count = [int](Get-SasPropertyValue -InputObject $result -Name 'target_count' -Default 0)
            before_completed_at_utc = Get-SasPropertyValue -InputObject $state -Name 'before_completed_at_utc'
            after_completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            default_password_value_collected = $false
            target_mutation_performed = $false
        }
        Write-SasOperatorJson -Path $statePath -Value $operatorState

        Write-Host ''
        Write-Host 'AFTER capture and comparison complete.' -ForegroundColor Green
        Write-Host "Summary: $($result.summary_csv)"
        Open-SasEvidenceFolder -Path $result.output_root -Suppress:$NoOpen
        $result
    }

    'Assess' {
        $effectiveCsv = $TargetsCsv
        if (@($ComputerName).Count -eq 0) {
            $effectiveCsv = Select-SasTargetCsv -RequestedPath $TargetsCsv -DefaultPath $defaultTargetsCsv -Unattended:$NonInteractive
            Assert-SasApprovedInputPath -Path $effectiveCsv -RepoRoot $repoRoot -Role 'AutoLogon target manifest'
            $effectiveCsv = (Resolve-Path -LiteralPath $effectiveCsv).Path
        }
        $effectiveLabel = Resolve-SasTechnicianLabel -RequestedLabel $TechnicianLabel -Unattended:$NonInteractive

        $collectorArguments = @{
            Mode = 'Assess'
            OutputRoot = $OutputRoot
            TechnicianLabel = $effectiveLabel
            MaxTargets = $MaxTargets
            FixtureMode = [bool]$FixtureMode
        }
        if (@($ComputerName).Count -gt 0) {
            $collectorArguments.ComputerName = @($ComputerName)
        }
        else {
            $collectorArguments.TargetsCsv = $effectiveCsv
        }
        $result = & $collectorPath @collectorArguments
        Open-SasEvidenceFolder -Path $result.output_root -Suppress:$NoOpen
        $result
    }

    'OpenLatest' {
        $latestRoot = Get-SasLatestRunRoot -Root $OutputRoot -State $state
        if ([string]::IsNullOrWhiteSpace($latestRoot)) {
            throw 'No AutoLogon state-delta evidence folder exists yet.'
        }
        Write-Host "Opening: $latestRoot" -ForegroundColor Cyan
        Open-SasEvidenceFolder -Path $latestRoot -Suppress:$NoOpen
        [pscustomobject]@{
            action = 'OpenLatest'
            output_root = $latestRoot
            state_path = $statePath
        }
    }
}
