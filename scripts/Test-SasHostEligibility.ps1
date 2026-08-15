#Requires -Version 5.1
<#
.SYNOPSIS
Host eligibility gate for SysAdminSuite software installation.

.DESCRIPTION
Test-SasHostEligibility evaluates whether a target hostname is eligible to receive
package execution under a specific execution context.

The generic policy path remains fail-closed. The one exception is an explicit remote
target carried by the canonical AutoLogon operator launcher in the process-scoped
SAS_EXPLICIT_REMOTE_TARGET_REQUEST environment variable. That marker is scoped to the
operator command and only authorizes the same non-local target (or the canonical FQDN
for the same short hostname). It does not authorize localhost, a different hostname,
local execution, fixture execution, or VM execution.

This makes the operator's explicit `sas autologon Remote HOST` target the authority for
that one transaction without requiring a pre-existing machine-local JSON policy.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [ValidateSet('local', 'remote', 'fixture', 'vm')]
    [string]$ExecContext,

    [Parameter(Mandatory = $false)]
    [string]$PolicyPath,

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SasPolicyPath {
    [CmdletBinding()]
    param(
        [string]$ExplicitPath,
        [string]$RepoRootPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return [System.IO.Path]::GetFullPath($ExplicitPath)
    }

    $root = $RepoRootPath
    if ([string]::IsNullOrWhiteSpace($root)) {
        $cursor = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..') -PathType Container) {
            (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        }
        else {
            (Get-Location).Path
        }

        while ($cursor) {
            if ((Test-Path -LiteralPath (Join-Path $cursor 'targets/README.md')) -and
                (Test-Path -LiteralPath (Join-Path $cursor 'survey'))) {
                $root = $cursor
                break
            }
            $parent = Split-Path -Parent $cursor
            if (-not $parent -or $parent -eq $cursor) { break }
            $cursor = $parent
        }
    }

    if ([string]::IsNullOrWhiteSpace($root)) {
        throw 'Unable to resolve SysAdminSuite repo root for host eligibility policy.'
    }

    return Join-Path (Join-Path $root 'Config') 'host-eligibility-policy.local.json'
}

function New-SasHostEligibilityResult {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutionContext,
        [Parameter(Mandatory = $true)][bool]$Eligible,
        [Parameter(Mandatory = $true)][string]$Decision,
        [Parameter(Mandatory = $true)][string]$ReasonCode,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][string]$ResolvedPolicyPath,
        [AllowNull()][string]$PolicyVersion,
        [AllowNull()][string]$MatchedPattern,
        [string[]]$AllowedContexts = @()
    )

    return [pscustomobject]@{
        schema_version     = 'sas-host-eligibility-result/v1'
        execution_context  = $ExecutionContext
        target             = '[redacted]'
        eligible           = $Eligible
        decision           = $Decision
        reason_code        = $ReasonCode
        reason             = $Reason
        policy_path        = $ResolvedPolicyPath
        policy_version     = $PolicyVersion
        matched_pattern    = $MatchedPattern
        allowed_contexts   = @($AllowedContexts)
    }
}

function Test-SasExplicitRemoteTargetRequest {
    param(
        [string]$RequestedTarget,
        [string]$ResolvedTarget
    )

    if ([string]::IsNullOrWhiteSpace($RequestedTarget) -or
        [string]::IsNullOrWhiteSpace($ResolvedTarget)) {
        return $false
    }

    $requested = $RequestedTarget.Trim().TrimEnd('.').ToLowerInvariant()
    $resolved = $ResolvedTarget.Trim().TrimEnd('.').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($requested) -or [string]::IsNullOrWhiteSpace($resolved)) {
        return $false
    }

    if ($requested.Contains('.')) {
        return $resolved.Equals($requested, [StringComparison]::OrdinalIgnoreCase)
    }

    return (
        $resolved.Equals($requested, [StringComparison]::OrdinalIgnoreCase) -or
        $resolved.StartsWith(($requested + '.'), [StringComparison]::OrdinalIgnoreCase)
    )
}

function Test-SasHostEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [ValidateSet('local', 'remote', 'fixture', 'vm')]
        [string]$ExecContext,

        [Parameter(Mandatory = $false)]
        [string]$PolicyPath,

        [Parameter(Mandatory = $false)]
        [string]$RepoRoot
    )

    $resolvedPolicyPath = Resolve-SasPolicyPath -ExplicitPath $PolicyPath -RepoRootPath $RepoRoot

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'TARGET_EMPTY' -Reason 'Target hostname is empty. No empty target is eligible for package execution.' `
            -ResolvedPolicyPath $resolvedPolicyPath
    }

    $normalizedTarget = $Target.Trim().TrimEnd('.')
    $localNames = @($env:COMPUTERNAME, 'localhost', '127.0.0.1', '::1', '.')
    $isLocalTarget = @($localNames | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        $normalizedTarget.Equals(([string]$_).Trim().TrimEnd('.'), [StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0

    if ($ExecContext -in @('remote', 'vm') -and $isLocalTarget) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'LOCAL_FALLBACK_BLOCKED' `
            -Reason "ExecutionContext '$ExecContext' requires a non-local target. Implicit localhost fallback is not permitted." `
            -ResolvedPolicyPath $resolvedPolicyPath
    }

    # Product path: the canonical AutoLogon launcher carries the operator's explicit
    # one-target request into every child process. For remote execution only, that exact
    # request (or its canonical FQDN expansion) is sufficient authorization. The local
    # policy is deliberately not consulted, so missing/stale policy cannot veto Deploy.
    if ($ExecContext -eq 'remote' -and
        (Test-SasExplicitRemoteTargetRequest -RequestedTarget $env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST -ResolvedTarget $normalizedTarget)) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $true -Decision 'allowed' `
            -ReasonCode 'EXPLICIT_REMOTE_TARGET_AUTHORIZED' `
            -Reason 'Explicit one-target operator command authorized this exact remote target; operator-local policy is not required for this invocation.' `
            -ResolvedPolicyPath $resolvedPolicyPath -MatchedPattern 'operator-explicit-target' -AllowedContexts @('remote')
    }

    if (-not (Test-Path -LiteralPath $resolvedPolicyPath -PathType Leaf)) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'POLICY_FILE_MISSING' `
            -Reason 'Host eligibility policy file not found. Gate fails closed when no explicit operator target authorization is present.' `
            -ResolvedPolicyPath $resolvedPolicyPath
    }

    try {
        $policy = Get-Content -LiteralPath $resolvedPolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'POLICY_MALFORMED_JSON' -Reason 'Host eligibility policy file is not valid JSON.' `
            -ResolvedPolicyPath $resolvedPolicyPath
    }

    if ([string]$policy.schema_version -ne 'sas-host-eligibility-policy/v1') {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'POLICY_SCHEMA_UNSUPPORTED' `
            -Reason 'Host eligibility policy schema version is not supported. Expected sas-host-eligibility-policy/v1.' `
            -ResolvedPolicyPath $resolvedPolicyPath
    }

    if ([string]::IsNullOrWhiteSpace([string]$policy.policy_id) -or
        [string]::IsNullOrWhiteSpace([string]$policy.policy_version)) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'POLICY_ID_OR_VERSION_MISSING' `
            -Reason 'Host eligibility policy is missing required policy_id or policy_version.' `
            -ResolvedPolicyPath $resolvedPolicyPath
    }

    $patterns = @($policy.patterns)
    if ($patterns.Count -eq 0) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'POLICY_NO_PATTERNS' -Reason 'Host eligibility policy defines no patterns.' `
            -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version)
    }

    foreach ($pattern in $patterns) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern.name) -or
            [string]::IsNullOrWhiteSpace([string]$pattern.regex)) {
            return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
                -ReasonCode 'POLICY_PATTERN_INVALID' `
                -Reason 'Host eligibility policy contains a pattern with missing name or regex.' `
                -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version)
        }
    }

    $duplicates = @(
        $patterns |
        ForEach-Object { [string]$_.name } |
        Sort-Object |
        Group-Object |
        Where-Object { $_.Count -gt 1 }
    )
    if ($duplicates.Count -gt 0) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'POLICY_DUPLICATE_PATTERNS' `
            -Reason 'Host eligibility policy contains duplicate pattern names.' `
            -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version)
    }

    $matchedPattern = $null
    foreach ($pattern in $patterns) {
        try { $regex = [regex]::new([string]$pattern.regex) }
        catch {
            return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
                -ReasonCode 'POLICY_PATTERN_INVALID' -Reason 'Host eligibility policy contains an invalid regular expression.' `
                -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version)
        }
        if ($regex.IsMatch($normalizedTarget)) {
            $matchedPattern = $pattern
            break
        }
    }

    $patternActions = if ($null -ne $matchedPattern) {
        @($matchedPattern.actions | ForEach-Object { [string]$_ })
    }
    else { @() }
    $matchedPatternName = if ($null -ne $matchedPattern) { [string]$matchedPattern.name } else { $null }

    if ($null -eq $matchedPattern) {
        if ($ExecContext -in @('fixture', 'vm')) {
            return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $true -Decision 'allowed' `
                -ReasonCode 'UNSUPPORTED_HOST_FIT_FOR_FIXTURE_OR_VM' `
                -Reason "ExecutionContext '$ExecContext' allows execution on hosts not explicitly listed in the policy." `
                -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version) `
                -AllowedContexts @($ExecContext)
        }

        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'NO_PATTERN_MATCH' -Reason 'Target hostname did not match any pattern in the host eligibility policy.' `
            -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version)
    }

    if ($ExecContext -notin $patternActions) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'CONTEXT_NOT_ALLOWED_FOR_PATTERN' `
            -Reason "Target matched pattern '$matchedPatternName' but ExecutionContext '$ExecContext' is not in the pattern's allowed actions." `
            -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version) `
            -MatchedPattern $matchedPatternName -AllowedContexts $patternActions
    }

    if ($ExecContext -eq 'local' -and -not $isLocalTarget) {
        return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $false -Decision 'closed' `
            -ReasonCode 'LOCAL_CONTEXT_TARGET_MISMATCH' `
            -Reason 'ExecutionContext is local but the target does not match the local machine identity.' `
            -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version) `
            -MatchedPattern $matchedPatternName -AllowedContexts $patternActions
    }

    return New-SasHostEligibilityResult -ExecutionContext $ExecContext -Eligible $true -Decision 'allowed' `
        -ReasonCode 'PATTERN_MATCH_AND_CONTEXT_ALLOWED' `
        -Reason "Target matched pattern '$matchedPatternName' and ExecutionContext '$ExecContext' is an allowed action." `
        -ResolvedPolicyPath $resolvedPolicyPath -PolicyVersion ([string]$policy.policy_version) `
        -MatchedPattern $matchedPatternName -AllowedContexts $patternActions
}

Test-SasHostEligibility -Target $Target -ExecContext $ExecContext -PolicyPath $PolicyPath -RepoRoot $RepoRoot
