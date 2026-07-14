#Requires -Version 5.1
<#
.SYNOPSIS
    Fail-closed host eligibility gate for SysAdminSuite package access and execution.

.DESCRIPTION
    Test-SasHostEligibility validates whether a target host is eligible for package
    access or execution under a given execution context. It enforces:
    - Private hostname-policy match (no real hostnames committed)
    - Exact request authorization (ticket, change reference, authorizer)
    - Fail-closed on: missing policy, malformed policy, no pattern match,
      unsupported context, local fallback blocked, unauthorized request

.PARAMETER Hostname
    Sanitized hostname of the target to validate.

.PARAMETER ExecContext
    Execution context: fixture, vm, local, remote, cybernet_physical.

.PARAMETER PolicyPath
    Path to the host-eligibility-policy JSON file.

.PARAMETER TicketReference
    Ticket reference for authorization (required when require_authorization is true).

.PARAMETER ChangeReference
    Change reference for authorization (required when require_authorization is true).

.PARAMETER Authorizer
    Authorizer identity (must be in allowed_authorizers list).

.PARAMETER DryRun
    When specified, performs validation without emitting a decision artifact.

.PARAMETER OutputRoot
    Directory for the decision artifact. Defaults to runs/host-eligibility/.

.EXAMPLE
    Test-SasHostEligibility -Hostname 'CYB-PHYS-001.example.com' -ExecContext 'cybernet_physical' -PolicyPath 'Config/host-eligibility-policy.json' -TicketReference 'CHG-001' -ChangeReference 'CHG-001' -Authorizer 'sas-admin@example.com'
#>
function Test-SasHostEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $true)]
        [ValidateSet('fixture','vm','local','remote','cybernet_physical')]
        [string]$ExecContext,

        [Parameter(Mandatory = $true)]
        [string]$PolicyPath,

        [Parameter(Mandatory = $false)]
        [string]$TicketReference,

        [Parameter(Mandatory = $false)]
        [string]$ChangeReference,

        [Parameter(Mandatory = $false)]
        [string]$Authorizer,

        [switch]$DryRun,

        [string]$OutputRoot
    )

    $ErrorActionPreference = 'Stop'

    # --- Gate: policy file exists ---
    if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        $result = [ordered]@{
            eligible    = $false
            reason      = 'policy_missing'
            detail      = "Host eligibility policy not found: $PolicyPath"
            hostname    = $Hostname
            context     = $ExecContext
            checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            policy_path = $PolicyPath
        }
        if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
        return $result
    }

    # --- Gate: policy parseable ---
    try {
        $policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
    }
    catch {
        $result = [ordered]@{
            eligible    = $false
            reason      = 'policy_malformed'
            detail      = "Failed to parse host eligibility policy: $($_.Exception.Message)"
            hostname    = $Hostname
            context     = $ExecContext
            checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            policy_path = $PolicyPath
        }
        if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
        return $result
    }

    # --- Gate: schema version ---
    if ($policy.schema_version -ne 'sas-host-eligibility-policy/v1') {
        $result = [ordered]@{
            eligible    = $false
            reason      = 'policy_schema_version_unsupported'
            detail      = "Unsupported policy schema version: $($policy.schema_version)"
            hostname    = $Hostname
            context     = $ExecContext
            checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            policy_path = $PolicyPath
        }
        if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
        return $result
    }

    # --- Gate: context exists in policy ---
    $contextProp = $policy.execution_contexts.PSObject.Properties[$ExecContext]
    if (-not $contextProp) {
        $result = [ordered]@{
            eligible    = $false
            reason      = 'context_not_supported'
            detail      = "Execution context '$ExecContext' is not defined in the policy."
            hostname    = $Hostname
            context     = $ExecContext
            checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            policy_path = $PolicyPath
        }
        if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
        return $result
    }

    $contextRule = $contextProp.Value

    # --- Gate: context enabled ---
    if (-not $contextRule.enabled) {
        $result = [ordered]@{
            eligible    = $false
            reason      = 'context_disabled'
            detail      = "Execution context '$ExecContext' is disabled in the policy."
            hostname    = $Hostname
            context     = $ExecContext
            checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            policy_path = $PolicyPath
        }
        if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
        return $result
    }

    # --- Gate: context has hostname patterns ---
    $patterns = @($contextRule.hostname_patterns)
    if ($patterns.Count -eq 0) {
        $result = [ordered]@{
            eligible    = $false
            reason      = 'context_no_patterns'
            detail      = "Execution context '$ExecContext' has no hostname patterns defined."
            hostname    = $Hostname
            context     = $ExecContext
            checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            policy_path = $PolicyPath
        }
        if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
        return $result
    }

    # --- Gate: hostname matches a pattern ---
    $matched = $false
    foreach ($pattern in $patterns) {
        $regexPattern = [regex]::Escape($pattern) -replace '\\\*', '.*'
        if ($Hostname -match "(?i)^$regexPattern$") {
            $matched = $true
            break
        }
    }

    if (-not $matched) {
        $result = [ordered]@{
            eligible    = $false
            reason      = 'hostname_no_match'
            detail      = "Hostname '$Hostname' does not match any pattern in context '$ExecContext'."
            hostname    = $Hostname
            context     = $ExecContext
            checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            policy_path = $PolicyPath
        }
        if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
        return $result
    }

    # --- Gate: authorization (when required) ---
    if ($contextRule.require_authorization) {
        $authSpec = $policy.authorization

        if ($authSpec.require_ticket_reference -and [string]::IsNullOrWhiteSpace($TicketReference)) {
            $result = [ordered]@{
                eligible    = $false
                reason      = 'authorization_ticket_missing'
                detail      = "Ticket reference is required for context '$ExecContext'."
                hostname    = $Hostname
                context     = $ExecContext
                checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
                policy_path = $PolicyPath
            }
            if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
            return $result
        }

        if ($authSpec.require_change_reference -and [string]::IsNullOrWhiteSpace($ChangeReference)) {
            $result = [ordered]@{
                eligible    = $false
                reason      = 'authorization_change_missing'
                detail      = "Change reference is required for context '$ExecContext'."
                hostname    = $Hostname
                context     = $ExecContext
                checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
                policy_path = $PolicyPath
            }
            if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
            return $result
        }

        if ([string]::IsNullOrWhiteSpace($Authorizer)) {
            $result = [ordered]@{
                eligible    = $false
                reason      = 'authorization_authorizer_missing'
                detail      = "Authorizer identity is required for context '$ExecContext'."
                hostname    = $Hostname
                context     = $ExecContext
                checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
                policy_path = $PolicyPath
            }
            if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
            return $result
        }

        $allowedAuthorizers = @($authSpec.allowed_authorizers)
        $authorizerMatch = $allowedAuthorizers | Where-Object {
            $_ -eq $Authorizer
        }
        if (-not $authorizerMatch) {
            $result = [ordered]@{
                eligible    = $false
                reason      = 'authorization_authorizer_not_allowed'
                detail      = "Authorizer '$Authorizer' is not in the allowed authorizers list."
                hostname    = $Hostname
                context     = $ExecContext
                checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
                policy_path = $PolicyPath
            }
            if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
            return $result
        }
    }

    # --- Eligible ---
    $result = [ordered]@{
        eligible    = $true
        reason      = 'eligible'
        detail      = "Host '$Hostname' is eligible under context '$ExecContext'."
        hostname    = $Hostname
        context     = $ExecContext
        checked_at  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        policy_path = $PolicyPath
    }
    if (-not $DryRun) { Save-SasEligibilityDecision -Result $result -OutputRoot $OutputRoot }
    return $result
}

function Save-SasEligibilityDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result,

        [string]$OutputRoot
    )

    if (-not $OutputRoot) {
        $OutputRoot = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) -ChildPath 'runs' | Join-Path -ChildPath 'host-eligibility'
    }

    if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
        New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
    }

    $safeContext = $Result.context -replace '[^a-zA-Z0-9_-]', '-'
    $timestamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $fileName = "eligibility-$safeContext-$timestamp.json"
    $filePath = Join-Path $OutputRoot $fileName

    $Result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $filePath -Encoding UTF8
}
