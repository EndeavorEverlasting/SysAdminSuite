#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
Offline contracts for the read-only AD OU / policy probe and SAS OU router.
No Active Directory, Group Policy, network, or target mutation occurs in these tests.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $probePath = Join-Path $repoRoot 'ActiveDirectory\Probe-ComputerOuPolicy.ps1'
    $routerPath = Join-Path $repoRoot 'ActiveDirectory\Invoke-SasAdOu.ps1'
    $movePath = Join-Path $repoRoot 'ActiveDirectory\Move-Computers-To-OU.ps1'
    $launcherPath = Join-Path $repoRoot 'scripts\SasPortableLauncher.ps1'
    $networkAwarePath = Join-Path $repoRoot 'scripts\Invoke-SasNetworkAwareField.ps1'
    $script:probe = Get-Content -LiteralPath $probePath -Raw
    $script:router = Get-Content -LiteralPath $routerPath -Raw
    $script:move = Get-Content -LiteralPath $movePath -Raw
    $script:launcher = Get-Content -LiteralPath $launcherPath -Raw
    $script:networkAware = Get-Content -LiteralPath $networkAwarePath -Raw
}

Describe 'AD OU policy probe -- syntax and read-only boundary' {
    It 'parses all new/owned PowerShell surfaces' {
        foreach ($path in @($probePath,$routerPath,$launcherPath,$networkAwarePath)) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }
    }

    It 'uses read-only AD and Group Policy evidence sources' {
        foreach ($required in @('Get-ADComputer','Get-ADOrganizationalUnit','Get-GPO','Get-GPOReport','Get-GPInheritance')) {
            $script:probe | Should -Match ([regex]::Escape($required))
        }
        $script:probe | Should -Match "\[string\]\$PolicyKeyword\s*=\s*'Imprivata'"
    }

    It 'contains no AD, GPO, or group mutation primitive' {
        foreach ($forbidden in @(
            'Move-ADObject','Set-AD','New-AD','Remove-AD','Disable-AD','Enable-AD',
            'Add-ADGroupMember','Remove-ADGroupMember','Set-GP','New-GP','Remove-GP',
            'Set-GPLink','New-GPLink','Remove-GPLink','Set-GPRegistryValue'
        )) {
            $script:probe | Should -Not -Match ([regex]::Escape($forbidden))
        }
    }

    It 'stores local ticket-ready evidence and explicit no-mutation markers' {
        $script:probe | Should -Match 'SysAdminSuite\\Evidence\\ActiveDirectory\\OuPolicyProbe'
        $script:probe | Should -Match 'Probe\.json'
        $script:probe | Should -Match 'Computers\.csv'
        $script:probe | Should -Match 'PolicyLinks\.csv'
        $script:probe | Should -Match 'TicketNotes\.txt'
        $script:probe | Should -Match 'sysadminsuite/ad-ou-policy-probe/v1'
        $script:probe | Should -Match 'target_mutation_performed\s*=\s*\$false'
        $script:probe | Should -Match 'gpo_mutation_performed\s*=\s*\$false'
        $script:probe | Should -Match 'group_membership_mutation_performed\s*=\s*\$false'
    }

    It 'treats a policy-linked managed OU as evidence rather than automatic move authority' {
        $script:probe | Should -Match 'unique_managed_policy_link_target_dn'
        $script:probe | Should -Match 'read-only policy-link evidence only; not authorization and not automatic move selection'
        $script:probe | Should -Match 'A policy-linked OU is evidence of GPO scope, not proof that OU placement alone installs/configures the application'
        $script:probe | Should -Match 'managedPolicyTargets\.Count -eq 1'
        $script:probe | Should -Match 'sas ad ou plan'
        $script:probe | Should -Not -Match 'sas ad ou apply'
    }

    It 'reuses the current managed-workstation OU boundary and rejects legacy placement roots' {
        $script:probe | Should -Match 'Managed\|Managed_Shared'
        $script:probe | Should -Match 'Workstations\|Shared_Workstations'
        $script:probe | Should -Match 'OU=_Workstations'
    }

    It 'does not commit live Northwell domain, target host, or GPO GUID data' {
        $script:probe | Should -Not -Match 'DC=nslijhs,DC=net'
        $script:probe | Should -Not -Match 'W[A-Z]{2}\d{3}(?:END|OPR|WCC|PSP|IME)\d{3}'
        $script:probe | Should -Not -Match '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'
    }
}

Describe 'SAS AD OU router -- existing mutator remains authority' {
    It 'requires the canonical protected-network gate before probe, plan, or apply' {
        $script:router | Should -Match 'Confirm-SasNorthwellNetwork\.ps1'
        $script:router | Should -Match 'Active Directory OU \$mode'
        $script:router | Should -Match '-NonInteractive'
    }

    It 'routes read-only probe to the policy evidence script with Imprivata as the field keyword' {
        $script:router | Should -Match 'Probe-ComputerOuPolicy\.ps1'
        $script:router | Should -Match "-PolicyKeyword 'Imprivata'"
    }

    It 'routes plan without Apply and apply through the existing guarded move engine' {
        $script:router | Should -Match 'Move-Computers-To-OU\.ps1'
        $script:router | Should -Match "'plan'"
        $script:router | Should -Match '& \$movePath -ComputerName \$hostName -TargetOU \$targetOu'
        $script:router | Should -Match "'apply'"
        $script:router | Should -Match '-Apply -ChangeReference \$changeReference'
        $script:router | Should -Not -Match '-ConfirmBatch'
        $script:router | Should -Not -Match '-MaxChanges'
    }

    It 'does not weaken the existing one-host move engine gates' {
        $script:move | Should -Match '\[int\]\$MaxChanges\s*=\s*1'
        $script:move | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
        $script:move | Should -Match "ConfirmImpact\s*=\s*'High'"
        $script:move | Should -Match 'Source OU changed after preflight'
        $script:move | Should -Match 'Post-move verification failed'
        $script:move | Should -Match 'Undo-OUMove\.ps1'
    }

    It 'is discoverable from the compatibility SAS dispatcher' {
        $script:launcher | Should -Match "'ad'\s*\{"
        $script:launcher | Should -Match 'ActiveDirectory\\Invoke-SasAdOu\.ps1'
        $script:launcher | Should -Match 'sas ad ou probe HOST'
        $script:launcher | Should -Match 'sas ad ou plan HOST'
        $script:launcher | Should -Match 'sas ad ou apply HOST'
    }
}

Describe 'Network intent -- valid AD OU commands are protected' {
    It 'has an explicit AD OU shape guard' {
        $script:networkAware | Should -Match 'Test-SasAdOuShapeForNetworkTransition'
        $script:networkAware | Should -Match "'ad'"
        $script:networkAware | Should -Match "\$intent\s*=\s*'ProtectedNorthwell'"
    }

    It 'does not auto-switch for malformed AD commands' {
        $script:networkAware | Should -Match 'Invalid/incomplete shapes.*CommandSpecific'
    }
}
