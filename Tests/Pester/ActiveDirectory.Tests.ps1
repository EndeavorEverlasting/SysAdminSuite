#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Offline unit tests for ActiveDirectory\ scripts and the OU analysis
    logic in Tests\Preflight.ps1.
    Validates parameter contracts, output schema, and OU-path extraction
    without requiring a live AD environment.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $addComputersPath = Join-Path $repoRoot 'ActiveDirectory\Add-Computers-To-PrintingGroup.ps1'
    $preflightPath    = Join-Path $repoRoot 'Tests\Preflight.ps1'
}

# ── Add-Computers-To-PrintingGroup.ps1 ────────────────────────────

Describe 'Add-Computers-To-PrintingGroup.ps1 -- script-level checks' {
    BeforeAll {
        $script:content = Get-Content -Path $addComputersPath -Raw
    }

    It 'Script file exists' {
        $addComputersPath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($addComputersPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Requires a -HostListPath parameter' {
        $script:content | Should -Match '\$HostListPath'
    }

    It 'Requires a -GroupName parameter' {
        $script:content | Should -Match '\$GroupName'
    }

    It 'Supports -PlanOnly for dry-run OU analysis without AD changes' {
        $script:content | Should -Match '\[switch\]\$PlanOnly'
    }

    It 'Supports ShouldProcess (-WhatIf / -Confirm)' {
        $script:content | Should -Match 'SupportsShouldProcess'
    }

    It 'Extracts OUPath from DistinguishedName for OU placement analysis' {
        $script:content | Should -Match 'OUPath'
        # The regex splits after the first RDN to get the parent OU
        $script:content | Should -Match "DistinguishedName\s+-split\s+'[^']*',\s*2"
    }

    It 'Collects preflight snapshot with OU and identity columns' {
        $script:content | Should -Match 'CanonicalName'
        $script:content | Should -Match 'ObjectGUID'
        $script:content | Should -Match 'OperatingSystem'
        $script:content | Should -Match 'LastLogonDate'
        $script:content | Should -Match 'sAMAccountName'
    }

    It 'Exports a Preflight.csv snapshot before making changes' {
        $script:content | Should -Match 'Preflight\.csv'
        $script:content | Should -Match 'Export-Csv.*Preflight'
    }

    It 'Generates an undo script for rollback safety' {
        $script:content | Should -Match 'Undo-GroupMembership\.ps1'
        $script:content | Should -Match 'Remove-ADGroupMember'
    }

    It 'Generates an HTML results report' {
        $script:content | Should -Match 'Results\.html'
        $script:content | Should -Match 'ConvertTo-Html'
    }

    It 'Uses chunked batching with retry logic for resilience' {
        $script:content | Should -Match '\$ChunkSize'
        $script:content | Should -Match '\$RetryCount'
        $script:content | Should -Match '\$RetryDelaySeconds'
    }

    It 'Documents the OU placement policy (Security 2025-07-08) in the header' {
        $script:content | Should -Match 'OU PLACEMENT POLICY'
        $script:content | Should -Match 'FORBIDDEN'
        $script:content | Should -Match 'Managed_Shared'
    }

    It 'Defines ForbiddenOUPatterns for legacy OU detection' {
        $script:content | Should -Match '\$ForbiddenOUPatterns'
        $script:content | Should -Match 'OU=Workstations,OU=_Workstations'
        $script:content | Should -Match 'OU=Shared_Workstations,OU=_Workstations'
    }

    It 'Flags OUPolicyWarning when a computer is in a forbidden OU' {
        $script:content | Should -Match 'OUPolicyWarning'
        $script:content | Should -Match 'LEGACY OU'
    }

    It 'Does NOT contain Move-ADObject (analysis only, never moves)' {
        $script:content | Should -Not -Match 'Move-ADObject'
    }
}

# ── Preflight.ps1 -- OU analysis section ──────────────────────────

Describe 'Tests\Preflight.ps1 -- OU analysis checks' {
    BeforeAll {
        $script:pfContent = Get-Content -Path $preflightPath -Raw
    }

    It 'Preflight script exists' {
        $preflightPath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($preflightPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Accepts a -TargetOU parameter for OU placement analysis' {
        $script:pfContent | Should -Match '\$TargetOU'
    }

    It 'Uses Get-ADOrganizationalUnit to validate the target OU' {
        $script:pfContent | Should -Match 'Get-ADOrganizationalUnit'
    }

    It 'Inspects nTSecurityDescriptor ACL for delegation rights' {
        $script:pfContent | Should -Match 'nTSecurityDescriptor'
        $script:pfContent | Should -Match 'ActiveDirectoryRights'
    }

    It 'Checks for CreateChild and WriteProperty permissions' {
        $script:pfContent | Should -Match 'CreateChild'
        $script:pfContent | Should -Match 'WriteProperty'
    }

    It 'Reports token group membership for rights analysis' {
        $script:pfContent | Should -Match 'function\s+Get-TokenGroups'
        $script:pfContent | Should -Match 'WindowsIdentity'
    }

    It 'Exports results to both CSV and JSON' {
        $script:pfContent | Should -Match 'Export-Csv'
        $script:pfContent | Should -Match 'ConvertTo-Json'
    }

    It 'Includes reference links for AD privilege guidance' {
        $script:pfContent | Should -Match 'ADPrivGroups'
        $script:pfContent | Should -Match 'learn\.microsoft\.com'
    }

    It 'Handles missing ActiveDirectory module gracefully' {
        $script:pfContent | Should -Match 'ActiveDirectory module not available'
    }

    It 'Documents the OU placement policy in script help' {
        $script:pfContent | Should -Match 'OU PLACEMENT POLICY'
        $script:pfContent | Should -Match 'ANALYSIS-ONLY'
    }

    It 'Defines ForbiddenOUPatterns for legacy OU detection' {
        $script:pfContent | Should -Match '\$ForbiddenOUPatterns'
        $script:pfContent | Should -Match 'OU=Workstations,OU=_Workstations'
    }

    It 'Flags forbidden legacy OUs with a Fail result' {
        $script:pfContent | Should -Match 'Legacy OU check'
        $script:pfContent | Should -Match 'FORBIDDEN'
    }

    It 'Does NOT contain Move-ADObject (analysis only, never moves)' {
        $script:pfContent | Should -Not -Match 'Move-ADObject'
    }

    It 'Labels OU checks as read-only delegation analysis' {
        $script:pfContent | Should -Match 'Delegation analysis \(read-only\)'
    }
}

