#Requires -Version 5.1
<#
.SYNOPSIS
Creates a schema-backed, registered, machine-local-path-free sprint handoff capsule.
.DESCRIPTION
Reads actual Git state, resolves skills and capabilities from repository manifests, creates the canonical run context, registers the capsule, and writes a compact operator handoff. This operation does not authorize network or target mutation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]*$')][string]$SprintId,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]*$')][string]$Lane,
    [Parameter(Mandatory)][string]$Mission,
    [Parameter(Mandatory)][string[]]$OwnedPaths,
    [Parameter(Mandatory)][string[]]$ForbiddenScope,
    [ValidatePattern('^[a-z][a-z0-9-]*$')][string[]]$Dependencies = @(),
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]*$')][string]$PrimarySkill,
    [ValidatePattern('^[a-z][a-z0-9-]*$')][string[]]$AdditionalSkills = @(),
    [Parameter(Mandatory)][string]$WorkflowSpec,
    [Parameter(Mandatory)][string[]]$ExpectedArtifacts,
    [Parameter(Mandatory)][string[]]$Completed,
    [string[]]$Remaining = @(),
    [string[]]$Blockers = @(),
    [Parameter(Mandatory)][string[]]$ValidationCommands,
    [string[]]$SkippedChecks = @(),
    [Parameter(Mandatory)][ValidateSet('P0_schema_validation','P1_static_lint','P2_unit_proof','P3_integration','P4_unit_test','P5_smoke','P6_E2E_fixture','P7_E2E_live','P8_runtime')][string]$ProofLevel,
    [Parameter(Mandatory)][string]$ProofCeiling,
    [Parameter(Mandatory)][string[]]$ClaimsNotMade,
    [Parameter(Mandatory)][string]$NextCommand,
    [ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$BaseBranch = 'main',
    [string]$RepositorySlug,
    [string]$RepoRoot,
    [string]$OutputRoot,
    [switch]$AllowDirtyWorktree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-SasRepoRelativePath {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Field)
    $normalized = $Value.Trim() -replace '\\','/'
    if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -match '^[A-Za-z]:/' -or $normalized.StartsWith('/') -or $normalized.StartsWith('~') -or $normalized -match '(^|/)\.\.(/|$)') {
        throw "REJECT: $Field must contain repository-relative paths only: $Value"
    }
    $normalized.TrimEnd('/')
}

function Assert-SasSafeHandoffText {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Field)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "REJECT: $Field must not be empty." }
    if ($Value.Length -gt 1000) { throw "REJECT: $Field exceeds the 1000-character capsule limit." }
    if ($Value -match '(?i)(?:[A-Za-z]:[\\/]|(?:^|\s)/(?!/)\S+|%USERPROFILE%|\$HOME|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY|(?:password|token|secret)\s*[:=])') {
        throw "REJECT: $Field contains a machine-local path or secret-like value."
    }
}

function Assert-SasUniqueList {
    param([object[]]$Values,[Parameter(Mandatory)][string]$Field)
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in @($Values)) {
        $text = [string]$value
        if (-not $seen.Add($text)) { throw "REJECT: $Field must contain unique values: $text" }
    }
}

function Get-SasPathComparison {
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return [System.StringComparison]::OrdinalIgnoreCase
    }
    return [System.StringComparison]::Ordinal
}

function Test-SasPathOverlap {
    param([Parameter(Mandatory)][string]$Left,[Parameter(Mandatory)][string]$Right)
    $a = ($Left.Trim('/') -replace '\\','/').ToLowerInvariant()
    $b = ($Right.Trim('/') -replace '\\','/').ToLowerInvariant()
    $a -eq $b -or $a.StartsWith($b + '/') -or $b.StartsWith($a + '/')
}

function Invoke-SasGitText {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git -C $script:ResolvedRepoRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: git -C <repo> $($Arguments -join ' ')`n$($output -join "`n")" }
    ($output -join "`n").Trim()
}

function ConvertTo-SasRepoRelative {
    param([Parameter(Mandatory)][string]$Path)
    $rootFull = [IO.Path]::GetFullPath($script:ResolvedRepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $pathFull = [IO.Path]::GetFullPath($Path)
    $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    $comparison = Get-SasPathComparison
    if (-not $pathFull.StartsWith($prefix,$comparison)) { throw 'REJECT: generated artifact escaped the repository root.' }
    $pathFull.Substring($prefix.Length) -replace '\\','/'
}

$modulePath = Join-Path $PSScriptRoot '..\scripts\SasRunContext.psm1'
Import-Module (Resolve-Path $modulePath) -Force
if (-not $RepoRoot) {
    $candidateRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $rootOutput = @(& git -C $candidateRoot rev-parse --show-toplevel 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to resolve repository root from the generator path: $($rootOutput -join "`n")" }
    $RepoRoot = ($rootOutput -join "`n").Trim()
}
$script:ResolvedRepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$gitRoot = Invoke-SasGitText @('rev-parse','--show-toplevel')
if (-not ([IO.Path]::GetFullPath($gitRoot)).Equals($script:ResolvedRepoRoot,(Get-SasPathComparison))) { throw 'REJECT: RepoRoot does not match the active Git repository root.' }

$owned = @($OwnedPaths | ForEach-Object { Assert-SasRepoRelativePath $_ 'OwnedPaths' })
$forbidden = @($ForbiddenScope | ForEach-Object { Assert-SasRepoRelativePath $_ 'ForbiddenScope' })
$expected = @($ExpectedArtifacts | ForEach-Object { Assert-SasRepoRelativePath $_ 'ExpectedArtifacts' })
$workflow = Assert-SasRepoRelativePath $WorkflowSpec 'WorkflowSpec'
Assert-SasUniqueList -Values $owned -Field 'OwnedPaths'
Assert-SasUniqueList -Values $forbidden -Field 'ForbiddenScope'
Assert-SasUniqueList -Values $expected -Field 'ExpectedArtifacts'
Assert-SasUniqueList -Values @($Dependencies) -Field 'Dependencies'
Assert-SasUniqueList -Values @($AdditionalSkills) -Field 'AdditionalSkills'
$handoffLists = [ordered]@{
    Completed = @($Completed)
    Remaining = @($Remaining)
    Blockers = @($Blockers)
    ValidationCommands = @($ValidationCommands)
    SkippedChecks = @($SkippedChecks)
    ClaimsNotMade = @($ClaimsNotMade)
}
foreach ($entry in $handoffLists.GetEnumerator()) {
    Assert-SasUniqueList -Values $entry.Value -Field $entry.Key
    foreach ($value in @($entry.Value)) { Assert-SasSafeHandoffText -Value ([string]$value) -Field $entry.Key }
}
foreach ($entry in ([ordered]@{ Title=$Title; Mission=$Mission; ProofCeiling=$ProofCeiling; NextCommand=$NextCommand }).GetEnumerator()) {
    Assert-SasSafeHandoffText -Value ([string]$entry.Value) -Field $entry.Key
}
foreach ($left in $owned) { foreach ($right in $forbidden) { if (Test-SasPathOverlap $left $right) { throw "REJECT: owned and forbidden scope overlap: $left <-> $right" } } }
if (-not (Test-Path -LiteralPath (Join-Path $script:ResolvedRepoRoot $workflow) -PathType Leaf)) { throw "REJECT: workflow spec does not exist: $workflow" }

$capabilityManifest = Get-Content (Join-Path $script:ResolvedRepoRoot 'harness/api/agent-capability-manifest.json') -Raw | ConvertFrom-Json
$routingManifest = Get-Content (Join-Path $script:ResolvedRepoRoot 'harness/api/agent-routing-manifest.json') -Raw | ConvertFrom-Json
$skillIds = @($PrimarySkill) + @($AdditionalSkills)
if (@($skillIds | Select-Object -Unique).Count -ne $skillIds.Count) { throw 'REJECT: selected skills must be unique.' }
$selectedSkills = foreach ($skillId in $skillIds) {
    $match = @($capabilityManifest.skills | Where-Object id -eq $skillId)
    if ($match.Count -ne 1) { throw "REJECT: selected skill is not uniquely declared in the capability manifest: $skillId" }
    $match[0]
}
$primaryRoute = @($routingManifest.triggers | Where-Object { $_.target_type -eq 'skill' -and $_.target -eq $PrimarySkill })
if ($primaryRoute.Count -ne 1) { throw "REJECT: primary skill is not uniquely routed: $PrimarySkill" }
$capabilityIds = @($selectedSkills | ForEach-Object { @($_.capability_ids) } | Sort-Object -Unique)

$headSha = Invoke-SasGitText @('rev-parse','HEAD')
$headBranch = Invoke-SasGitText @('branch','--show-current')
if ([string]::IsNullOrWhiteSpace($headBranch)) { $headBranch = 'DETACHED' }
$statusText = Invoke-SasGitText @('status','--porcelain=v1','--untracked-files=all')
$statusLines = @($statusText -split "`r?`n" | Where-Object { $_ })
$dirtyPaths = foreach ($line in $statusLines) {
    $path = if ($line.Length -gt 3) { $line.Substring(3).Trim() } else { $line.Trim() }
    if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
    Assert-SasRepoRelativePath $path 'Git dirty path'
}
$worktreeClean = @($dirtyPaths).Count -eq 0
if (-not $worktreeClean -and -not $AllowDirtyWorktree) { throw 'REJECT: worktree is dirty. Preserve or isolate the work before generating a handoff capsule.' }

if (-not $RepositorySlug) {
    $origin = Invoke-SasGitText @('remote','get-url','origin')
    $match = [regex]::Match($origin,'github\.com[:/](?<slug>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?$')
    if (-not $match.Success) { throw 'REJECT: unable to derive a safe repository slug from origin. Pass -RepositorySlug owner/repo.' }
    $RepositorySlug = $match.Groups['slug'].Value
}
if ($RepositorySlug -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'REJECT: RepositorySlug must be owner/repo.' }

$contextArgs = @{ WorkflowId='agent-sprint-capsule'; RepoRoot=$script:ResolvedRepoRoot; RequestSummary=$Mission; SourceArtifact='repository Git state and tracked harness authorities'; CreatedBy='New-SasSprintCapsule' }
if ($OutputRoot) { $contextArgs.OutputRoot = $OutputRoot }
$context = New-SasRunContext @contextArgs
$capsulePath = Join-Path $context.directories.artifacts 'agent-sprint-capsule.json'
$capsuleRelative = ConvertTo-SasRepoRelative $capsulePath
$registryRelative = ConvertTo-SasRepoRelative $context.artifact_registry_path

$capsule = [ordered]@{
    schema_version='sas-agent-sprint-capsule/v2'; schema_path='schemas/harness/agent-sprint-capsule.schema.json'
    capsule=[ordered]@{ capsule_id="$SprintId-capsule"; generated_at=(Get-Date).ToUniversalTime().ToString('o'); generator_version='2.0.0'; workflow_id='agent-sprint-capsule'; run_id=$context.run_id; output_path=$capsuleRelative; artifact_registry_path=$registryRelative }
    repository=[ordered]@{ slug=$RepositorySlug; base_branch=$BaseBranch; head_branch=$headBranch; head_sha=$headSha; worktree_clean=$worktreeClean; dirty_paths=@($dirtyPaths) }
    sprint=[ordered]@{ id=$SprintId; title=$Title; lane=$Lane; mission=$Mission }
    scope=[ordered]@{ owned_paths=$owned; forbidden_scope=$forbidden; dependencies=@($Dependencies) }
    routing=[ordered]@{ primary_skill=$PrimarySkill; additional_skills=@($AdditionalSkills); capability_ids=$capabilityIds; workflow_spec=$workflow }
    artifacts=[ordered]@{ expected=$expected; generated=@($capsuleRelative,$registryRelative,(ConvertTo-SasRepoRelative $context.summary_path),(ConvertTo-SasRepoRelative $context.operator_handoff_path)) }
    validation=[ordered]@{ ordered_commands=@($ValidationCommands); skipped_checks=@($SkippedChecks) }
    proof=[ordered]@{ level=$ProofLevel; ceiling=$ProofCeiling; claims_not_made=@($ClaimsNotMade) }
    handoff=[ordered]@{ completed=@($Completed); remaining=@($Remaining); blockers=@($Blockers); next_command=$NextCommand; final_response_sections=@('CONTEXT','WORK COMMITTED','VALIDATION','BLOCKERS / GAPS','FINAL GIT STATE','NEXT COMMAND') }
}
$capsule | ConvertTo-Json -Depth 12 | Set-Content $capsulePath -Encoding UTF8
Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'agent-sprint-capsule' -Path $capsuleRelative -Tracked $false -LiveData $false -Generated $true -Description 'Machine-local-path-free compressed repository sprint handoff.' -SourceArtifact 'repository Git state and tracked harness authorities' -NetworkActivity 'No network activity performed.' -CreatedBy 'New-SasSprintCapsule' | Out-Null
$registry = Get-Content $context.artifact_registry_path -Raw | ConvertFrom-Json
[ordered]@{ schema_version='sas-run-summary/v1'; workflow_id='agent-sprint-capsule'; run_id=$context.run_id; network_activity='No network activity performed.'; artifact_count=@($registry.artifacts).Count; review_required=(@($Remaining).Count -gt 0 -or @($Blockers).Count -gt 0); status='COMPLETE'; capsule_path=$capsuleRelative; proof_level=$ProofLevel; proof_ceiling=$ProofCeiling } | ConvertTo-Json -Depth 6 | Set-Content $context.summary_path -Encoding UTF8
@('SYSADMINSUITE SPRINT HANDOFF',"Sprint: $SprintId - $Title","Repository: $RepositorySlug","Branch: $headBranch","Head: $headSha","Primary skill: $PrimarySkill","Capabilities: $($capabilityIds -join ', ')","Completed: $($Completed -join '; ')","Remaining: $($Remaining -join '; ')","Blockers: $($Blockers -join '; ')","Proof: $ProofLevel - $ProofCeiling","Capsule: $capsuleRelative","Next command: $NextCommand") | Set-Content $context.operator_handoff_path -Encoding UTF8
Write-Host "CAPSULE_PATH=$capsuleRelative"
Write-Host "ARTIFACT_REGISTRY=$registryRelative"
Write-Output $capsule
