#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][int]$PrNumber,
    [string]$ExpectedCandidateSha,
    [string]$ExpectedBaseSha,
    [string]$ExpectedMergeSha,
    [string]$ExpectedTarget,
    [string]$Actor,
    [string]$EventName,
    [string]$PolicyPath = 'Config/promotion-policy.json',
    [string]$OutputPath = 'promotion-candidate.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GhJson {
    param([Parameter(Mandatory)][string]$Path)
    $raw = @(& gh api $Path 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "gh api failed for '$Path' with exit code ${exitCode}: $($raw -join [Environment]::NewLine)"
    }
    return (($raw -join [Environment]::NewLine) | ConvertFrom-Json -Depth 100)
}

function Get-GhPrChangedFiles {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][int]$Number)
    $raw = @(& gh api --paginate --jq '.[].filename' "repos/$Repo/pulls/$Number/files?per_page=100" 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Unable to enumerate changed files for PR #${Number}: $($raw -join [Environment]::NewLine)"
    }
    return @($raw | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
}

if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    throw "Promotion policy not found: $PolicyPath"
}

$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json -Depth 50
if ($policy.schema_version -ne 'sas-promotion-policy/v1') {
    throw "Unsupported promotion policy schema: $($policy.schema_version)"
}

if ($Actor -eq 'github-actions[bot]') {
    throw 'Recursive writer guard: github-actions[bot] may not authorize a promotion run.'
}

$repo = Invoke-GhJson -Path "repos/$Repository"
$pr = $null
for ($attempt = 1; $attempt -le 6; $attempt++) {
    $pr = Invoke-GhJson -Path "repos/$Repository/pulls/$PrNumber"
    if ($null -ne $pr.mergeable) { break }
    if ($attempt -lt 6) { Start-Sleep -Seconds 2 }
}

if ($pr.state -ne 'open') { throw "PR #$PrNumber is not open." }
if ([bool]$pr.draft) { throw "PR #$PrNumber is draft." }
if ($null -eq $pr.mergeable) { throw "PR #$PrNumber mergeability remained unknown after bounded retries." }
if (-not [bool]$pr.mergeable) { throw "PR #$PrNumber is not mergeable." }

$defaultBranch = [string]$repo.default_branch
$baseRef = [string]$pr.base.ref
$headRef = [string]$pr.head.ref
$headSha = [string]$pr.head.sha
$headRepo = [string]$pr.head.repo.full_name
$prAuthor = [string]$pr.user.login
$repoOwner = [string]$repo.owner.login
$body = if ($null -eq $pr.body) { '' } else { [string]$pr.body }
$mergeSha = [string]$pr.merge_commit_sha

if (@($policy.allowed_targets) -notcontains $baseRef) {
    throw "Unauthorized promotion target '$baseRef'. Allowed: $(@($policy.allowed_targets) -join ', ')."
}
if ($baseRef -ne $defaultBranch) {
    throw "Promotion target '$baseRef' is not the repository default branch '$defaultBranch'."
}
if ($ExpectedTarget -and $baseRef -ne $ExpectedTarget) {
    throw "Promotion target moved or mismatched: expected '$ExpectedTarget', found '$baseRef'."
}
if ([bool]$policy.require_same_repository_head -and $headRepo -ne $Repository) {
    throw "Cross-repository promotion is forbidden: '$headRepo'."
}
if (-not $headRef.StartsWith([string]$policy.source_branch_prefix, [StringComparison]::Ordinal)) {
    throw "Promotion source branch '$headRef' does not use required prefix '$($policy.source_branch_prefix)'."
}
$markerPresent = @($body -split "\r?\n" | ForEach-Object { $_.Trim() }) -contains [string]$policy.authorization_marker
if (-not $markerPresent) {
    throw "PR #$PrNumber is missing exact authorization marker '$($policy.authorization_marker)'."
}
if ([bool]$policy.require_repository_owner_pr_author -and $prAuthor -ne $repoOwner) {
    throw "PR author '$prAuthor' is not repository owner '$repoOwner'."
}
if ($ExpectedCandidateSha -and $headSha -ne $ExpectedCandidateSha) {
    throw "Candidate moved: expected '$ExpectedCandidateSha', found '$headSha'."
}

$changedFiles = Get-GhPrChangedFiles -Repo $Repository -Number $PrNumber
$manualOnlyHits = @($changedFiles | Where-Object { @($policy.manual_only_paths) -contains $_ })
if ($manualOnlyHits.Count -gt 0) {
    throw "Automated promotion may not self-certify control-plane changes. Manual-only path(s): $($manualOnlyHits -join ', ')."
}

$branch = Invoke-GhJson -Path "repos/$Repository/branches/$baseRef"
$currentBaseSha = [string]$branch.commit.sha
if ([string]$pr.base.sha -ne $currentBaseSha) {
    throw "PR base is stale: PR reports '$($pr.base.sha)', current '$baseRef' is '$currentBaseSha'."
}
if ($ExpectedBaseSha -and $currentBaseSha -ne $ExpectedBaseSha) {
    throw "Base moved after validation: expected '$ExpectedBaseSha', found '$currentBaseSha'."
}
if (-not $mergeSha) { throw "PR #$PrNumber has no synthetic merge candidate SHA." }
if ($ExpectedMergeSha -and $mergeSha -ne $ExpectedMergeSha) {
    throw "Synthetic merge candidate moved after validation: expected '$ExpectedMergeSha', found '$mergeSha'."
}

$mergeCommit = Invoke-GhJson -Path "repos/$Repository/commits/$mergeSha"
$parents = @($mergeCommit.parents | ForEach-Object { [string]$_.sha })
if ($parents.Count -lt 2 -or $parents -notcontains $headSha -or $parents -notcontains $currentBaseSha) {
    throw "Synthetic merge candidate '$mergeSha' is not pinned to source '$headSha' and base '$currentBaseSha'."
}

$policySha256 = (Get-FileHash -LiteralPath $PolicyPath -Algorithm SHA256).Hash.ToLowerInvariant()
$result = [ordered]@{
    schema_version = 'sas-promotion-candidate/v1'
    resolved_at = (Get-Date).ToUniversalTime().ToString('o')
    repository = $Repository
    pr_number = $PrNumber
    event = $EventName
    actor = $Actor
    default_branch = $defaultBranch
    base_ref = $baseRef
    base_sha = $currentBaseSha
    source_branch = $headRef
    source_head_sha = $headSha
    synthetic_merge_sha = $mergeSha
    merge_method = [string]$policy.merge_method
    promotion_transport = [string]$policy.promotion_transport
    branch_protected = [bool]$branch.protected
    changed_files = @($changedFiles)
    policy_sha256 = $policySha256
    proof_ceiling = [string]$policy.proof_ceiling
}

$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$result | ConvertTo-Json -Depth 20
