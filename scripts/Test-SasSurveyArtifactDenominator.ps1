<#
.SYNOPSIS
Normalizes and validates one modular network-survey artifact against the canonical denominator contract.

.DESCRIPTION
Accepts an approved requested-population or evidence artifact, selects a registered adapter, emits a
canonical normalized package plus validation evidence, and fails closed when any row cannot satisfy the
denominator schema. This command performs no network activity and no target mutation.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidateSet('requested_population', 'evidence_snapshot')]
    [string]$Role,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFixtures,

    [Parameter(Mandatory = $false)]
    [switch]$AllowNonstandardInput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path $repoRoot 'scripts/SasTargetIntake.psm1'
$normalizerModule = Join-Path $repoRoot 'scripts/SasSurveyArtifactNormalizer.psm1'
foreach ($modulePath in @($targetIntakeModule, $normalizerModule)) {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Missing required module: $modulePath" }
}
Import-Module $targetIntakeModule -Force
Import-Module $normalizerModule -Force

$allowGenerated = $Role -eq 'evidence_snapshot'
Assert-SasApprovedInputPath -Path $Path -RepoRoot $repoRoot -Role "network survey $Role artifact" -AllowStaging -AllowGenerated:$allowGenerated -AllowFixtures:$AllowFixtures -AllowNonstandard:$AllowNonstandardInput
$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$roots = Get-SasTargetIntakeRoots -RepoRoot $repoRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $roots.OutputRoots[0] 'artifact_intake_validation' }
Assert-SasApprovedOutputPath -Path $OutputDirectory -RepoRoot $repoRoot -Role 'network survey denominator validation output' -AllowNonstandard:$AllowNonstandardInput

$result = Invoke-SasSurveyArtifactNormalization -Path $resolvedPath -Role $Role -OutputDirectory $OutputDirectory -RepoRoot $repoRoot
Write-Host "Adapter: $($result.AdapterId)"
Write-Host "Normalized package: $($result.PackagePath)"
Write-Host "Validation report: $($result.ValidationPath)"
Write-Host 'Network activity performed: false'
Write-Host 'Target mutation performed: false'
Write-Output $result
