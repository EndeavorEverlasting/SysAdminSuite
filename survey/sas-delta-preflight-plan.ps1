<#
.SYNOPSIS
Builds a packet-free delta plan from approved requested targets and prior local evidence.

.DESCRIPTION
Ranks local evidence before any new network survey. The planner writes a complete decision CSV,
review/skip sidecars, a direct latest-versus-previous observation delta, and a reduced staged target
file for the existing sas-network-preflight.ps1 workflow. It never runs DNS, ping, TCP, Nmap, Naabu,
or any target-side command.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string[]]$EvidenceFile = @(),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 8760)]
    [int]$ReachabilityTtlHours = 24,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$IdentityTtlDays = 7,

    [Parameter(Mandatory = $false)]
    [switch]$ForceReprobe,

    [Parameter(Mandatory = $false)]
    [string]$ForceReason,

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [datetimeoffset]$ReferenceTime = [datetimeoffset]::Now,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string]$StagingRoot,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFixtures,

    [Parameter(Mandatory = $false)]
    [switch]$AllowNonstandardInput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ForceReprobe -and [string]::IsNullOrWhiteSpace($ForceReason)) {
    throw '-ForceReprobe requires a non-empty -ForceReason so the extra packets are attributable.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path $repoRoot 'scripts/SasTargetIntake.psm1'
$deltaModule = Join-Path $repoRoot 'scripts/SasDeltaEvidenceCache.psm1'
foreach ($modulePath in @($targetIntakeModule, $deltaModule)) {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Missing required module: $modulePath" }
}
Import-Module $targetIntakeModule -Force
Import-Module $deltaModule -Force

Assert-SasApprovedInputPath -Path $InputFile -RepoRoot $repoRoot -Role 'delta requested population' -AllowStaging -AllowFixtures:$AllowFixtures -AllowNonstandard:$AllowNonstandardInput
$resolvedInput = (Resolve-Path -LiteralPath $InputFile).Path

$resolvedEvidence = New-Object System.Collections.Generic.List[string]
foreach ($path in @($EvidenceFile)) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    Assert-SasApprovedInputPath -Path $path -RepoRoot $repoRoot -Role 'delta evidence file' -AllowStaging -AllowGenerated -AllowFixtures:$AllowFixtures -AllowNonstandard:$AllowNonstandardInput
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if (-not $resolvedEvidence.Contains($resolved)) { $resolvedEvidence.Add($resolved) }
}

$roots = Get-SasTargetIntakeRoots -RepoRoot $repoRoot
if (-not $OutputRoot) { $OutputRoot = Join-Path $roots.OutputRoots[0] 'delta_preflight' }
if (-not $StagingRoot) { $StagingRoot = Join-Path $roots.StagingRoot 'delta_preflight' }
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'delta output root' -AllowNonstandard:$AllowNonstandardInput
if (-not (Test-SasPathUnderRoot -Path $StagingRoot -Root $roots.StagingRoot)) {
    if (-not $AllowNonstandardInput) { throw "Delta staging root must remain under survey/input. Refusing: $StagingRoot" }
    Write-Warning "NONSTANDARD STAGING OVERRIDE: $StagingRoot"
}

if (-not $RunId) { $RunId = 'delta-{0}-{1}' -f $ReferenceTime.ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8)) }
if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,96}$') { throw "Invalid RunId: $RunId" }

$runOutput = Join-Path $OutputRoot $RunId
$runStaging = Join-Path $StagingRoot $RunId
New-Item -ItemType Directory -Force -Path $runOutput, $runStaging | Out-Null

$planPath = Join-Path $runOutput 'delta_preflight_plan.csv'
$skipPath = Join-Path $runOutput 'skipped_recent_evidence.csv'
$reviewPath = Join-Path $runOutput 'review_required.csv'
$summaryPath = Join-Path $runOutput 'delta_summary.json'
$readmePath = Join-Path $runOutput 'README.txt'
$observationPath = Join-Path $runOutput 'survey_observation_delta.csv'
$handoffPath = Join-Path $runOutput 'operator_handoff.txt'
$targetPath = Join-Path $runStaging 'to_probe_targets.txt'

$requestedRows = @(ConvertTo-SasRequestedRows -Path $resolvedInput)
if ($requestedRows.Count -eq 0) { throw 'Requested population file did not contain any usable rows.' }
$evidenceSnapshots = @(ConvertTo-SasEvidenceSnapshots -Paths @($resolvedEvidence))


$corePaths = @(
    (Join-Path $repoRoot 'scripts/Invoke-SasDeltaPreflightPlanRows.ps1'),
    (Join-Path $repoRoot 'scripts/Write-SasDeltaPreflightArtifacts.ps1')
)
foreach ($corePath in $corePaths) {
    if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) { throw "Missing delta planner core: $corePath" }
    . $corePath
}
