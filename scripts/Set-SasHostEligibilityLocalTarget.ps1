#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Target,

    [ValidateSet('remote')]
    [string]$ExecContext = 'remote',

    [string]$RepoRoot,
    [string]$PolicyPath,

    [switch]$ConfirmLocalAuthorization,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmLocalAuthorization) {
    throw 'Explicit -ConfirmLocalAuthorization is required before changing the operator-local host eligibility policy.'
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
    $RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
}

if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $RepoRoot 'Config\host-eligibility-policy.local.json'
}
else {
    $PolicyPath = [IO.Path]::GetFullPath($PolicyPath)
}

$validator = Join-Path $RepoRoot 'scripts\Test-SasHostEligibility.ps1'
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw "Host eligibility validator not found: $validator"
}

$normalizedTarget = $Target.Trim().TrimEnd('.').ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($normalizedTarget)) {
    throw 'Target cannot be empty.'
}
if ($normalizedTarget -in @('localhost','127.0.0.1','::1','.')) {
    throw 'Operator-local authorization cannot target localhost or loopback.'
}

$exactRegex = '^(?i:' + [regex]::Escape($normalizedTarget) + ')$'
$patternName = 'operator-exact-' + ($normalizedTarget -replace '[^a-z0-9._-]','-')

$policy = $null
if (Test-Path -LiteralPath $PolicyPath -PathType Leaf) {
    try {
        $policy = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Existing operator-local host eligibility policy is malformed; refusing to overwrite it: $($_.Exception.Message)"
    }

    if ([string]$policy.schema_version -ne 'sas-host-eligibility-policy/v1') {
        throw 'Existing operator-local host eligibility policy has an unsupported schema; refusing to overwrite it.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$policy.policy_id) -or [string]::IsNullOrWhiteSpace([string]$policy.policy_version)) {
        throw 'Existing operator-local host eligibility policy is missing policy_id or policy_version; refusing to overwrite it.'
    }

    $backup = $PolicyPath + '.before-exact-target-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
    Copy-Item -LiteralPath $PolicyPath -Destination $backup -Force
}
else {
    $policy = [pscustomobject][ordered]@{
        schema_version = 'sas-host-eligibility-policy/v1'
        policy_id = 'operator-local-host-eligibility'
        policy_version = (Get-Date -Format 'yyyy.MM.dd')
        default_allowed_contexts = @('remote')
        patterns = @()
    }
}

$patterns = @($policy.patterns)
$patterns = @($patterns | Where-Object {
    -not (
        ([string]$_.name).Equals($patternName, [StringComparison]::OrdinalIgnoreCase) -or
        ([string]$_.regex).Equals($exactRegex, [StringComparison]::Ordinal)
    )
})

$exactPattern = [pscustomobject][ordered]@{
    name = $patternName
    match_type = 'regex'
    regex = $exactRegex
    actions = @($ExecContext)
}

# Exact operator authorization is intentionally first because the validator uses
# first-match semantics. This avoids a broader pre-existing pattern shadowing the
# explicitly authorized hostname.
$policy.patterns = @($exactPattern) + $patterns
$policy.policy_version = (Get-Date -Format 'yyyy.MM.dd')

$parent = Split-Path -Parent $PolicyPath
if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$policy | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $PolicyPath -Encoding UTF8

$result = & $validator -Target $normalizedTarget -ExecContext $ExecContext -PolicyPath $PolicyPath -RepoRoot $RepoRoot
if (-not [bool]$result.eligible -or [string]$result.decision -ne 'allowed' -or [string]$result.matched_pattern -ne $patternName) {
    throw "Operator-local host eligibility policy was written but did not authorize the exact target. reason_code=$($result.reason_code); reason=$($result.reason)"
}

$output = [pscustomobject][ordered]@{
    target = $normalizedTarget
    execution_context = $ExecContext
    policy_path = $PolicyPath
    matched_pattern = $result.matched_pattern
    eligible = [bool]$result.eligible
    decision = [string]$result.decision
    reason_code = [string]$result.reason_code
}

if ($PassThru) { return $output }
$output | Format-List
