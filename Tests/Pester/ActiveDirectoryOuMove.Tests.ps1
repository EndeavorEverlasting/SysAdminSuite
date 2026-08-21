#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
  Offline contracts for the reversible Active Directory OU move engine.
  No Active Directory connection or target mutation occurs in these tests.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $movePath = Join-Path $repoRoot 'ActiveDirectory\Move-Computers-To-OU.ps1'
    $groupPath = Join-Path $repoRoot 'ActiveDirectory\Add-Computers-To-PrintingGroup.ps1'
    $script:move = Get-Content -LiteralPath $movePath -Raw
    $script:group = Get-Content -LiteralPath $groupPath -Raw
}

Describe 'Move-Computers-To-OU.ps1 -- syntax and separation' {
    It 'Exists' {
        $movePath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($movePath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Keeps OU movement separate from printing-group membership' {
        $script:move | Should -Match 'intentionally separate from Add-Computers-To-PrintingGroup\.ps1'
        $script:group | Should -Not -Match 'Move-ADObject'
    }
}

Describe 'Move-Computers-To-OU.ps1 -- operator gates' {
    It 'Supports ShouldProcess with high-impact confirmation' {
        $script:move | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
        $script:move | Should -Match "ConfirmImpact\s*=\s*'High'"
    }

    It 'Has distinct single-computer and host-list parameter sets' {
        $script:move | Should -Match "ParameterSetName\s*=\s*'Single'"
        $script:move | Should -Match "ParameterSetName\s*=\s*'Batch'"
        $script:move | Should -Match '\$ComputerName'
        $script:move | Should -Match '\$HostListPath'
    }

    It 'Requires an explicit Apply switch before mutation' {
        $script:move | Should -Match '\[switch\]\$Apply'
        $script:move | Should -Match 'if\s*\(\$Apply\)'
        $script:move | Should -Match 'if\s*\(\$PSCmdlet\.ShouldProcess'
    }

    It 'Requires a change reference for Apply but does not misrepresent it as external authorization validation' {
        $script:move | Should -Match '\$ChangeReference'
        $script:move | Should -Match 'ChangeReference is required with -Apply for operator audit/traceability'
        $script:move | Should -Match 'does not validate external approval'
        $script:move | Should -Not -Match '\$AuthorizationReference'
    }

    It 'Defaults the live change ceiling to one computer' {
        $script:move | Should -Match '\[int\]\$MaxChanges\s*=\s*1'
        $script:move | Should -Match 'Planned changes.*exceed -MaxChanges'
    }

    It 'Requires an extra batch confirmation for more than one change' {
        $script:move | Should -Match '\[switch\]\$ConfirmBatch'
        $script:move | Should -Match 'More than one OU move requires -ConfirmBatch'
    }

    It 'Supports an expected source OU guard for the single-host pilot' {
        $script:move | Should -Match '\$ExpectedSourceOU'
        $script:move | Should -Match 'SourceMismatch'
    }
}

Describe 'Move-Computers-To-OU.ps1 -- placement and AD proof' {
    It 'Validates the target OU exists before planning moves' {
        $script:move | Should -Match 'Get-ADOrganizationalUnit'
        $script:move | Should -Match 'Target OU.*was not found or is not readable'
    }

    It 'Blocks both forbidden legacy OU paths' {
        $script:move | Should -Match 'Workstations\|Shared_Workstations'
        $script:move | Should -Match 'OU=_Workstations'
    }

    It 'Allows only the current managed workstation roots' {
        $script:move | Should -Match 'Managed\|Managed_Shared'
        $script:move | Should -Match 'OU=_Workstations'
        $script:move | Should -Match 'Test-SasApprovedManagedTargetOU'
    }

    It 'Matches placement roots on complete DN component boundaries' {
        $script:move | Should -Match '\(\?:\^\|,\)OU='
        $script:move | Should -Match 'OU=_Workstations\(\?:,\|\$\)'
        $script:move | Should -Not -Match 'IndexOf\(\$pattern'
    }

    It 'Uses immutable ObjectGUID identity for moves' {
        $script:move | Should -Match 'Identity\s*=\s*\[guid\]\$row\.ObjectGUID'
        $script:move | Should -Match 'Move-ADObject\s+@moveParams'
    }

    It 'Re-reads source state immediately before mutation' {
        $script:move | Should -Match 'Re-read immediately before mutation'
        $script:move | Should -Match 'Source OU changed after preflight'
    }

    It 'Verifies the resulting OU from AD after every move' {
        $script:move | Should -Match 'Post-move verification failed'
        $script:move | Should -Match '\$row\.Outcome\s*=\s*''Moved'''
    }

    It 'Stops later mutations after the first failed move' {
        $script:move | Should -Match '\$stopAfterFailure\s*=\s*\$true'
        $script:move | Should -Match 'SkippedAfterFailure'
    }

    It 'Aborts Apply when any preflight lookup or source guard fails' {
        $script:move | Should -Match 'Outcome\s*-in\s*@\(''LookupFailed'',\s*''SourceMismatch''\)'
        $script:move | Should -Match 'no OU moves were attempted'
    }
}

Describe 'Move-Computers-To-OU.ps1 -- local evidence and rollback' {
    It 'Keeps runtime evidence under local SysAdminSuite cache by default' {
        $script:move | Should -Match '\$env:LOCALAPPDATA'
        $script:move | Should -Match 'SysAdminSuite\\Cache\\ActiveDirectory\\OUMove'
    }

    It 'Writes preflight, plan and result artifacts' {
        $script:move | Should -Match 'Preflight\.csv'
        $script:move | Should -Match 'Plan\.json'
        $script:move | Should -Match 'Results\.csv'
        $script:move | Should -Match 'Results\.json'
        $script:move | Should -Match 'sysadminsuite/ad-ou-move-plan/v1'
        $script:move | Should -Match 'sysadminsuite/ad-ou-move-result/v1'
        $script:move | Should -Match 'change_reference_role'
    }

    It 'Generates undo only for verified Moved rows' {
        $script:move | Should -Match 'Where-Object\s*\{\s*\$_\.Outcome\s*-eq\s*''Moved''\s*\}'
        $script:move | Should -Match 'Undo-OUMove\.ps1'
    }

    It 'Guards rollback against later OU drift' {
        $script:move | Should -Match 'ExpectedCurrentOU'
        $script:move | Should -Match 'Rollback blocked for'
        $script:move | Should -Match 'Rollback verification failed for'
    }

    It 'Makes the generated undo high-impact and ShouldProcess-aware' {
        $script:move | Should -Match 'Generated by SysAdminSuite Move-Computers-To-OU\.ps1'
        $script:move | Should -Match "CmdletBinding\(SupportsShouldProcess = \`$true, ConfirmImpact = ''High''\)"
    }

    It 'Labels generated undo ChangeReference as audit evidence rather than an authorization mechanism' {
        $script:move | Should -Match 'Change reference \(audit only\)'
        $script:move | Should -Match 'ChangeReference is audit evidence only'
    }

    It 'Does not commit an environment-specific domain or live hostname' {
        $script:move | Should -Not -Match 'DC=nslijhs,DC=net'
        $script:move | Should -Not -Match 'W[A-Z]{2}\d{3}(?:END|OPR|WCC|PSP|IME)\d{3}'
    }
}
