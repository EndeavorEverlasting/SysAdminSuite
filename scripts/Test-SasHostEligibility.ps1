#Requires -Version 5.1
<#
.SYNOPSIS
Fail-closed host eligibility gate for SysAdminSuite software installation.

.DESCRIPTION
Test-SasHostEligibility evaluates whether a target hostname is eligible to receive
package execution under a specific execution context. The gate must be placed before
share access, package copying, installer invocation, or registry/service mutation.

Execution contexts:
  local   - The package process would run on $env:COMPUTERNAME.
  remote  - The admin box coordinates, but the package process runs on a named remote target.
  fixture - A synthetic installer runs in a repository-controlled isolated fixture.
  vm      - The real package runs only inside a disposable lab VM.

When the operator-local policy is absent, malformed, ambiguous, or unmatched, the gate
fails closed. There is no -Force, environment variable, or undocumented override that
allows an ineligible host.
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

$validContexts = @('local', 'remote', 'fixture', 'vm')

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
        $marker = Join-Path $PSScriptRoot '..' | Split-Path
        $cursor = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..') -PathType Container) {
            (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        } else {
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

    return Join-Path $root 'Config' | Join-Path -ChildPath 'host-eligibility-policy.local.json'
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

    if (-not (Test-Path -LiteralPath $resolvedPolicyPath -PathType Leaf)) {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'POLICY_FILE_MISSING'
            reason             = 'Host eligibility policy file not found. Gate fails closed when the operator-local policy is absent.'
            policy_path        = $resolvedPolicyPath
            policy_version     = $null
            matched_pattern    = $null
            allowed_contexts   = @()
        }
    }

    $rawContent = Get-Content -LiteralPath $resolvedPolicyPath -Raw -Encoding UTF8
    try {
        $policy = $rawContent | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'POLICY_MALFORMED_JSON'
            reason             = 'Host eligibility policy file is not valid JSON. Gate fails closed when the policy is malformed.'
            policy_path        = $resolvedPolicyPath
            policy_version     = $null
            matched_pattern    = $null
            allowed_contexts   = @()
        }
    }

    if ([string]$policy.schema_version -ne 'sas-host-eligibility-policy/v1') {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'POLICY_SCHEMA_UNSUPPORTED'
            reason             = 'Host eligibility policy schema version is not supported. Expected sas-host-eligibility-policy/v1.'
            policy_path        = $resolvedPolicyPath
            policy_version     = $null
            matched_pattern    = $null
            allowed_contexts   = @()
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$policy.policy_id) -or
        [string]::IsNullOrWhiteSpace([string]$policy.policy_version)) {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'POLICY_ID_OR_VERSION_MISSING'
            reason             = 'Host eligibility policy is missing required policy_id or policy_version.'
            policy_path        = $resolvedPolicyPath
            policy_version     = $null
            matched_pattern    = $null
            allowed_contexts   = @()
        }
    }

    $patterns = @($policy.patterns)
    if ($patterns.Count -eq 0) {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'POLICY_NO_PATTERNS'
            reason             = 'Host eligibility policy defines no patterns. Gate fails closed when the policy is ambiguous.'
            policy_path        = $resolvedPolicyPath
            policy_version     = [string]$policy.policy_version
            matched_pattern    = $null
            allowed_contexts   = @()
        }
    }

    foreach ($pattern in $patterns) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern.name) -or
            [string]::IsNullOrWhiteSpace([string]$pattern.regex)) {
            return [pscustomobject]@{
                schema_version     = 'sas-host-eligibility-result/v1'
                execution_context  = $ExecContext
                target             = '[redacted]'
                eligible           = $false
                decision           = 'closed'
                reason_code        = 'POLICY_PATTERN_INVALID'
                reason             = 'Host eligibility policy contains a pattern with missing name or regex.'
                policy_path        = $resolvedPolicyPath
                policy_version     = [string]$policy.policy_version
                matched_pattern    = $null
                allowed_contexts   = @()
            }
        }
    }

    $patternNames = @($patterns | ForEach-Object { [string]$_.name } | Sort-Object)
    $duplicates = @($patternNames | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($duplicates.Count -gt 0) {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'POLICY_DUPLICATE_PATTERNS'
            reason             = 'Host eligibility policy contains duplicate pattern names. Gate fails closed when the policy is ambiguous.'
            policy_path        = $resolvedPolicyPath
            policy_version     = [string]$policy.policy_version
            matched_pattern    = $null
            allowed_contexts   = @()
        }
    }

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'TARGET_EMPTY'
            reason             = 'Target hostname is empty. No empty target is eligible for package execution.'
            policy_path        = $resolvedPolicyPath
            policy_version     = [string]$policy.policy_version
            matched_pattern    = $null
            allowed_contexts   = @()
        }
    }

    $normalizedTarget = $Target.Trim()
    $localNames = @($env:COMPUTERNAME, 'localhost', '127.0.0.1', '::1', '.')
    $isLocalTarget = @($localNames | Where-Object {
        $normalizedTarget -eq $_ -or
        $normalizedTarget -eq $_.ToLowerInvariant()
    }).Count -gt 0

    $matchedPattern = $null
    foreach ($pattern in $patterns) {
        $regex = [regex]::new([string]$pattern.regex)
        if ($regex.IsMatch($normalizedTarget)) {
            $matchedPattern = $pattern
            break
        }
    }

    $patternActions = if ($null -ne $matchedPattern) {
        @($matchedPattern.actions | ForEach-Object { [string]$_ })
    }
    else {
        @()
    }
    $matchedPatternName = if ($null -ne $matchedPattern) { [string]$matchedPattern.name } else { $null }

    if ($ExecContext -in @('remote', 'vm') -and $isLocalTarget) {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'LOCAL_FALLBACK_BLOCKED'
            reason             = "ExecutionContext '$ExecContext' requires a non-local target. Implicit localhost fallback is not permitted."
            policy_path        = $resolvedPolicyPath
            policy_version     = [string]$policy.policy_version
            matched_pattern    = $matchedPatternName
            allowed_contexts   = @($patternActions)
        }
    }

    if ($null -eq $matchedPattern) {
        if ($ExecContext -in @('fixture', 'vm')) {
            return [pscustomobject]@{
                schema_version     = 'sas-host-eligibility-result/v1'
                execution_context  = $ExecContext
                target             = '[redacted]'
                eligible           = $true
                decision           = 'allowed'
                reason_code        = 'UNSUPPORTED_HOST_FIT_FOR_FIXTURE_OR_VM'
                reason             = "ExecutionContext '$ExecContext' allows execution on hosts not explicitly listed in the policy."
                policy_path        = $resolvedPolicyPath
                policy_version     = [string]$policy.policy_version
                matched_pattern    = $null
                allowed_contexts   = @($ExecContext)
            }
        }

        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'NO_PATTERN_MATCH'
            reason             = 'Target hostname did not match any pattern in the host eligibility policy.'
            policy_path        = $resolvedPolicyPath
            policy_version     = [string]$policy.policy_version
            matched_pattern    = $null
            allowed_contexts   = @()
        }
    }

    if ($ExecContext -notin $patternActions) {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'CONTEXT_NOT_ALLOWED_FOR_PATTERN'
            reason             = "Target matched pattern '$([string]$matchedPattern.name)' but ExecutionContext '$ExecContext' is not in the pattern's allowed actions."
            policy_path        = $resolvedPolicyPath
            policy_version     = [string]$policy.policy_version
            matched_pattern    = [string]$matchedPattern.name
            allowed_contexts   = @($patternActions)
        }
    }

    if ($ExecContext -eq 'local' -and -not $isLocalTarget) {
        return [pscustomobject]@{
            schema_version     = 'sas-host-eligibility-result/v1'
            execution_context  = $ExecContext
            target             = '[redacted]'
            eligible           = $false
            decision           = 'closed'
            reason_code        = 'LOCAL_CONTEXT_TARGET_MISMATCH'
            reason             = 'ExecutionContext is local but the target does not match the local machine identity.'
            policy_path        = $resolvedPolicyPath
            policy_version     = [string]$policy.policy_version
            matched_pattern    = [string]$matchedPattern.name
            allowed_contexts   = @($patternActions)
        }
    }

    return [pscustomobject]@{
        schema_version     = 'sas-host-eligibility-result/v1'
        execution_context  = $ExecContext
        target             = '[redacted]'
        eligible           = $true
        decision           = 'allowed'
        reason_code        = 'PATTERN_MATCH_AND_CONTEXT_ALLOWED'
        reason             = "Target matched pattern '$([string]$matchedPattern.name)' and ExecutionContext '$ExecContext' is an allowed action."
        policy_path        = $resolvedPolicyPath
        policy_version     = [string]$policy.policy_version
        matched_pattern    = [string]$matchedPattern.name
        allowed_contexts   = @($patternActions)
    }
}

Test-SasHostEligibility -Target $Target -ExecContext $ExecContext -PolicyPath $PolicyPath -RepoRoot $RepoRoot
