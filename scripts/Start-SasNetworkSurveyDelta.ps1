<#
.SYNOPSIS
Stateful technician launcher for repeated low-noise network survey delta runs.

.DESCRIPTION
Provides a menu that remembers the approved requested-population file, runs the packet-free delta
planner, optionally invokes the existing bounded network preflight after explicit confirmation, and
then regenerates the delta comparison with the new evidence. Technicians do not need to remember
RunIds, artifact paths, or PowerShell command lines.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Menu', 'Plan', 'Survey', 'Repeat', 'OpenLatest', 'Reset')]
    [string]$Action = 'Menu',

    [Parameter(Mandatory = $false)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string[]]$EvidenceFile = @(),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [int[]]$Ports = @(135, 445, 3389, 9100),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 8760)]
    [int]$ReachabilityTtlHours = 24,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$IdentityTtlDays = 7,

    [Parameter(Mandatory = $false)]
    [datetimeoffset]$ReferenceTime = [datetimeoffset]::Now,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmSurvey,

    [Parameter(Mandatory = $false)]
    [switch]$NonInteractive,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFixtures,

    [Parameter(Mandatory = $false)]
    [switch]$NoOpen,

    [Parameter(Mandatory = $false)]
    [string]$StateRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetModule = Join-Path $repoRoot 'scripts/SasTargetIntake.psm1'
$deltaModule = Join-Path $repoRoot 'scripts/SasDeltaEvidenceCache.psm1'
$planner = Join-Path $repoRoot 'survey/sas-delta-preflight-plan.ps1'
$preflight = Join-Path $repoRoot 'survey/sas-network-preflight.ps1'
foreach ($path in @($targetModule, $deltaModule, $planner, $preflight)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required network survey delta surface: $path" }
}
Import-Module $targetModule -Force
Import-Module $deltaModule -Force

$roots = Get-SasTargetIntakeRoots -RepoRoot $repoRoot
if (-not $StateRoot) { $StateRoot = Join-Path $roots.OutputRoots[0] 'network_survey_delta' }
Assert-SasApprovedOutputPath -Path $StateRoot -RepoRoot $repoRoot -Role 'network survey delta state root'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
$statePath = Join-Path $StateRoot 'operator-state.json'

function ConvertTo-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $rootUri = New-Object System.Uri(($repoRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar))
    $pathUri = New-Object System.Uri([System.IO.Path]::GetFullPath($Path))
    $relative = [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString())
    return $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Resolve-SavedRepoPath {
    param([string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return '' }
    $candidate = Join-Path $repoRoot $RelativePath
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    return ''
}

function Read-OperatorState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Operator state is unreadable. Use Reset from the launcher menu. State: $statePath" }
}

function Write-OperatorState {
    param([Parameter(Mandatory = $true)]$State)
    $State.updated_at = [datetimeoffset]::Now.ToString('o')
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Get-InputCandidates {
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @(Get-SasCandidateTargetFile -RepoRoot $repoRoot)) {
        if ($candidate.Extension -in @('.csv', '.txt')) { $candidates.Add($candidate) }
    }
    if ($AllowFixtures) {
        foreach ($fixtureRoot in $roots.FixtureRoots) {
            if (-not (Test-Path -LiteralPath $fixtureRoot)) { continue }
            foreach ($candidate in @(Get-ChildItem -LiteralPath $fixtureRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.csv', '.txt') })) {
                $candidates.Add($candidate)
            }
        }
    }
    return @($candidates | Sort-Object FullName -Unique)
}

function Select-ApprovedInput {
    param($State)

    if ($InputFile) {
        Assert-SasApprovedInputPath -Path $InputFile -RepoRoot $repoRoot -Role 'saved requested population' -AllowStaging -AllowFixtures:$AllowFixtures
        return (Resolve-Path -LiteralPath $InputFile).Path
    }
    if ($State -and $State.input_file_relative) {
        $saved = Resolve-SavedRepoPath -RelativePath $State.input_file_relative
        if ($saved) { return $saved }
        Write-Warning 'Saved input no longer resolves under this repo root. Dynamic path rewriting/path rehydration is unsupported; reselect the approved source.'
    }
    if ($NonInteractive) { throw 'No saved requested population exists. Supply -InputFile for noninteractive use.' }

    $candidates = @(Get-InputCandidates)
    if ($candidates.Count -eq 0) {
        throw 'No approved .csv or .txt source files were found under targets/local or logs/targets.'
    }
    Write-Host ''
    Write-Host 'Select the approved requested-population file:'
    for ($index = 0; $index -lt $candidates.Count; $index++) {
        Write-Host ('[{0}] {1}' -f ($index + 1), (ConvertTo-RepoRelativePath $candidates[$index].FullName))
    }
    $selectionText = Read-Host 'Selection number'
    $selection = 0
    if (-not [int]::TryParse($selectionText, [ref]$selection) -or $selection -lt 1 -or $selection -gt $candidates.Count) {
        throw 'Invalid source selection.'
    }
    return $candidates[$selection - 1].FullName
}

function Get-DiscoveredEvidenceFiles {
    param([string]$RequestedInput)

    $files = New-Object System.Collections.Generic.List[string]
    foreach ($explicit in @($EvidenceFile)) {
        if (-not $explicit) { continue }
        Assert-SasApprovedInputPath -Path $explicit -RepoRoot $repoRoot -Role 'explicit survey evidence' -AllowStaging -AllowGenerated -AllowFixtures:$AllowFixtures
        $resolved = (Resolve-Path -LiteralPath $explicit).Path
        if (-not $files.Contains($resolved)) { $files.Add($resolved) }
    }

    $evidenceRoots = @(
        (Join-Path $roots.OutputRoots[0] 'network_preflight'),
        (Join-Path $roots.OutputRoots[0] 'ad_registered_population'),
        (Join-Path $roots.OutputRoots[0] 'ad_candidate_pool'),
        (Join-Path $roots.OutputRoots[0] 'SysAdminSuite_Artifacts'),
        $roots.OutputRoots[1],
        $roots.OutputRoots[2],
        $roots.SourceRoots[1]
    )
    foreach ($root in $evidenceRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($candidate in @(Get-ChildItem -LiteralPath $root -File -Recurse -Filter '*.csv' -ErrorAction SilentlyContinue)) {
            if ($candidate.FullName -eq $RequestedInput) { continue }
            if (-not $files.Contains($candidate.FullName)) { $files.Add($candidate.FullName) }
        }
    }
    return @($files)
}

function Invoke-DeltaPlan {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedInput,
        [switch]$Force,
        [string]$Reason
    )

    $evidence = @(Get-DiscoveredEvidenceFiles -RequestedInput $RequestedInput)
    $arguments = @{
        InputFile = $RequestedInput
        EvidenceFile = $evidence
        ReachabilityTtlHours = $ReachabilityTtlHours
        IdentityTtlDays = $IdentityTtlDays
        ReferenceTime = $ReferenceTime
        AllowFixtures = $AllowFixtures
    }
    if ($Force) {
        $arguments.ForceReprobe = $true
        $arguments.ForceReason = $Reason
    }
    return & $planner @arguments
}

function Open-LocalPath {
    param([string]$Path)
    if ($NoOpen -or -not $Path) { return }
    $directory = if (Test-Path -LiteralPath $Path -PathType Container) { $Path } else { Split-Path -Parent $Path }
    if (Test-Path -LiteralPath $directory -PathType Container) { Start-Process explorer.exe -ArgumentList @($directory) | Out-Null }
}

function New-DefaultState {
    return [pscustomobject][ordered]@{
        schema_version = 'network-survey-delta-state/v1'
        input_file_relative = ''
        attempt_count = 0
        distinct_time_buckets = @()
        last_action = ''
        last_delta_summary_relative = ''
        last_plan_relative = ''
        last_observation_delta_relative = ''
        last_preflight_csv_relative = ''
        last_attempt_at = ''
        updated_at = ''
    }
}

if ($Action -eq 'Menu') {
    Write-Host ''
    Write-Host 'SysAdminSuite Network Survey Delta'
    Write-Host '[1] Smart delta survey (reuse fresh evidence; probe only justified targets)'
    Write-Host '[2] Time-diverse repeat survey (explicit repeat; five-attempt cap)'
    Write-Host '[3] Compare/plan only (no network activity)'
    Write-Host '[4] Open latest evidence folder'
    Write-Host '[5] Reset saved survey source and cycle state'
    Write-Host '[Q] Quit'
    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $Action = 'Survey' }
        '2' { $Action = 'Repeat' }
        '3' { $Action = 'Plan' }
        '4' { $Action = 'OpenLatest' }
        '5' { $Action = 'Reset' }
        'Q' { return }
        default { throw 'Invalid menu selection.' }
    }
}

$state = Read-OperatorState
if (-not $state) { $state = New-DefaultState }

if ($Action -eq 'Reset') {
    if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
    Write-Host 'Saved survey cycle state was reset. Existing evidence artifacts were preserved.'
    return
}

if ($Action -eq 'OpenLatest') {
    $latestPath = Resolve-SavedRepoPath -RelativePath $state.last_delta_summary_relative
    if (-not $latestPath) { throw 'No latest delta summary is available. Run Plan or Survey first.' }
    Open-LocalPath -Path $latestPath
    Write-Host "Latest delta summary: $latestPath"
    return
}

$requestedInput = Select-ApprovedInput -State $state
$state.input_file_relative = ConvertTo-RepoRelativePath $requestedInput

$forceRepeat = $Action -eq 'Repeat'
if ($forceRepeat -and [int]$state.attempt_count -ge 5) {
    throw 'The five-attempt low-noise cap has been reached for this saved survey cycle. Reset only after lead review or start a newly approved source cycle.'
}
if ($forceRepeat -and $state.last_attempt_at) {
    $lastAttempt = ConvertTo-SasDeltaTimestamp ([string]$state.last_attempt_at)
    if ($lastAttempt) {
        $lastBucket = Get-SasDeltaTimeBucket -Timestamp $lastAttempt
        $currentBucket = Get-SasDeltaTimeBucket -Timestamp $ReferenceTime
        if ($lastBucket -eq $currentBucket) {
            throw "Time-diverse repeat refused: the prior attempt and current request are both in the '$currentBucket' bucket. Use Smart delta survey now or retry in a different time bucket."
        }
    }
}
$forceReason = if ($forceRepeat) { 'time_diverse_repeat_from_technician_launcher' } else { '' }
$plan = Invoke-DeltaPlan -RequestedInput $requestedInput -Force:$forceRepeat -Reason $forceReason

$state.last_action = $Action
$state.last_delta_summary_relative = ConvertTo-RepoRelativePath $plan.summary_path
$state.last_plan_relative = ConvertTo-RepoRelativePath $plan.plan_path
$state.last_observation_delta_relative = ConvertTo-RepoRelativePath $plan.observation_delta_path
Write-OperatorState -State $state

Write-Host ''
Write-Host "Delta plan complete. Probe-required targets: $($plan.probe_required_count); review-required rows: $($plan.review_required_count)."
Write-Host "Observation delta: $($plan.observation_delta_path)"

if ($Action -eq 'Plan') {
    Open-LocalPath -Path $plan.plan_path
    return
}

if ([int]$plan.probe_required_count -eq 0) {
    Write-Host 'No network survey is justified by this delta plan. Review the generated skip/review artifacts.'
    Open-LocalPath -Path $plan.plan_path
    return
}

if ($AllowFixtures) { throw 'Fixture mode cannot execute live network preflight.' }
if (-not $ConfirmSurvey) {
    if ($NonInteractive) { throw 'Network survey requires -ConfirmSurvey in noninteractive mode.' }
    Write-Host ''
    Write-Host "The existing read-only preflight will survey $($plan.probe_required_count) reduced targets on ports: $($Ports -join ',')."
    $confirmation = (Read-Host 'Type SURVEY to continue').Trim().ToUpperInvariant()
    if ($confirmation -ne 'SURVEY') {
        Write-Host 'Survey cancelled. The packet-free delta plan was preserved.'
        return
    }
}

$beforeFiles = @{}
$networkOutput = Join-Path $roots.OutputRoots[0] 'network_preflight'
if (Test-Path -LiteralPath $networkOutput) {
    foreach ($file in @(Get-ChildItem -LiteralPath $networkOutput -File -Filter 'network_preflight_*.csv' -ErrorAction SilentlyContinue)) { $beforeFiles[$file.FullName] = $true }
}

& $preflight -TargetFile $plan.to_probe_targets_path -Ports $Ports

$newCsv = @(Get-ChildItem -LiteralPath $networkOutput -File -Filter 'network_preflight_*.csv' -ErrorAction SilentlyContinue |
    Where-Object { -not $beforeFiles.ContainsKey($_.FullName) } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1)
if ($newCsv.Count -eq 0) { throw 'Network preflight returned without a new CSV artifact; state was not advanced.' }

$state.attempt_count = [int]$state.attempt_count + 1
$bucket = Get-SasDeltaTimeBucket -Timestamp $ReferenceTime
$buckets = @($state.distinct_time_buckets)
if ($buckets -notcontains $bucket) { $buckets += $bucket }
$state.distinct_time_buckets = $buckets
$state.last_preflight_csv_relative = ConvertTo-RepoRelativePath $newCsv[0].FullName
$state.last_attempt_at = $ReferenceTime.ToString('o')

$postPlan = Invoke-DeltaPlan -RequestedInput $requestedInput
$state.last_action = 'SurveyCompleted'
$state.last_delta_summary_relative = ConvertTo-RepoRelativePath $postPlan.summary_path
$state.last_plan_relative = ConvertTo-RepoRelativePath $postPlan.plan_path
$state.last_observation_delta_relative = ConvertTo-RepoRelativePath $postPlan.observation_delta_path
Write-OperatorState -State $state

Write-Host ''
Write-Host 'Survey and automatic delta comparison completed.'
Write-Host "Attempt count: $($state.attempt_count) of 5"
Write-Host "Distinct time buckets: $($state.distinct_time_buckets -join ', ')"
Write-Host "New survey CSV: $($newCsv[0].FullName)"
Write-Host "Updated observation delta: $($postPlan.observation_delta_path)"
Open-LocalPath -Path $postPlan.plan_path
