<#
.SYNOPSIS
Builds a packet-free delta plan from modular approved artifacts normalized to one denominator schema.

.DESCRIPTION
Every requested-population and evidence artifact is first resolved through the registered adapter layer
into the canonical network survey denominator contract. Planning begins only after every input package
passes that contract. The planner then ranks local evidence, compares observations, and stages a reduced
target file for the existing sas-network-preflight.ps1 workflow. It never runs DNS, ping, TCP, Nmap,
Naabu, or any target-side command.
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
$normalizerModule = Join-Path $repoRoot 'scripts/SasSurveyArtifactNormalizer.psm1'
$deltaModule = Join-Path $repoRoot 'scripts/SasDeltaEvidenceCache.psm1'
foreach ($modulePath in @($targetIntakeModule, $normalizerModule, $deltaModule)) {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Missing required module: $modulePath" }
}
Import-Module $targetIntakeModule -Force
Import-Module $normalizerModule -Force
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
$normalizedRoot = Join-Path $runOutput 'normalized_artifacts'
New-Item -ItemType Directory -Force -Path $runOutput, $runStaging, $normalizedRoot | Out-Null

$planPath = Join-Path $runOutput 'delta_preflight_plan.csv'
$skipPath = Join-Path $runOutput 'skipped_recent_evidence.csv'
$reviewPath = Join-Path $runOutput 'review_required.csv'
$summaryPath = Join-Path $runOutput 'delta_summary.json'
$readmePath = Join-Path $runOutput 'README.txt'
$observationPath = Join-Path $runOutput 'survey_observation_delta.csv'
$handoffPath = Join-Path $runOutput 'operator_handoff.txt'
$targetPath = Join-Path $runStaging 'to_probe_targets.txt'
$intakeManifestPath = Join-Path $runOutput 'artifact_intake_manifest.json'

$normalizationResults = New-Object System.Collections.Generic.List[object]
$requestedNormalization = Invoke-SasSurveyArtifactNormalization -Path $resolvedInput -Role requested_population -OutputDirectory $normalizedRoot -RepoRoot $repoRoot -NormalizedAt $ReferenceTime
$normalizationResults.Add($requestedNormalization)
$evidencePackages = New-Object System.Collections.Generic.List[object]
foreach ($evidencePath in @($resolvedEvidence)) {
    $result = Invoke-SasSurveyArtifactNormalization -Path $evidencePath -Role evidence_snapshot -OutputDirectory $normalizedRoot -RepoRoot $repoRoot -NormalizedAt $ReferenceTime
    $normalizationResults.Add($result)
    $evidencePackages.Add($result.Package)
}

$intakeManifest = [ordered]@{
    contract_version = '1.0.0'
    workflow_id = 'delta-preflight'
    run_id = $RunId
    generated_at = $ReferenceTime.ToString('o')
    denominator_schema = 'schemas/survey/network-survey-artifact-denominator.schema.json'
    adapter_registry = 'survey/network_survey_artifact_adapters.json'
    all_artifacts_valid = $true
    artifacts = @($normalizationResults | ForEach-Object {
        [ordered]@{
            artifact_id = $_.Package.artifact_id
            artifact_role = $_.Package.artifact_role
            adapter_id = $_.AdapterId
            source_path = $_.Package.source_path
            source_format = $_.Package.source_format
            normalized_package_path = $_.PackagePath
            validation_report_path = $_.ValidationPath
            row_count = $_.Package.row_count
        }
    })
    network_activity_performed = $false
    target_mutation_performed = $false
}
$intakeManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $intakeManifestPath -Encoding UTF8

$requestedRows = @(ConvertFrom-SasRequestedArtifactPackage -Package $requestedNormalization.Package)
if ($requestedRows.Count -eq 0) { throw 'Requested population package did not contain any denominator-valid rows.' }
$evidenceSnapshots = @(ConvertFrom-SasEvidenceArtifactPackages -Packages @($evidencePackages))
$normalizedArtifactPaths = @($normalizationResults | ForEach-Object { $_.PackagePath })
$validationReportPaths = @($normalizationResults | ForEach-Object { $_.ValidationPath })

$corePaths = @(
    (Join-Path $repoRoot 'scripts/Invoke-SasDeltaPreflightPlanRows.ps1'),
    (Join-Path $repoRoot 'scripts/Write-SasDeltaPreflightArtifacts.ps1')
)
foreach ($corePath in $corePaths) {
    if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) { throw "Missing delta planner core: $corePath" }
    . $corePath
}
