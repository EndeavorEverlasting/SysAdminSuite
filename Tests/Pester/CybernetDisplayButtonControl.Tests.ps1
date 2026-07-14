#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:orchestrator = Join-Path $repoRoot 'scripts\Invoke-SasCybernetDisplayButtonControl.ps1'
    $script:ddcciSource = Join-Path $repoRoot 'scripts\SasDdcciMonitorControl.cs'
    $script:eventProbe = Join-Path $repoRoot 'QRTasks\Test-DisplayMenuButtonEvent.ps1'

    if (-not ('SysAdminSuite.DisplayControl.MonitorController' -as [type])) {
        $source = Get-Content -LiteralPath $script:ddcciSource -Raw -Encoding UTF8
        Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
    }
}

Describe 'Cybernet MCCS 2.2 display-button control surfaces' {
    It 'Parses the network orchestrator without syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:orchestrator,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'Compiles the repo-owned Windows Monitor Configuration helper' {
        ('SysAdminSuite.DisplayControl.MonitorController' -as [type]) | Should -Not -BeNullOrEmpty
        [SysAdminSuite.DisplayControl.MonitorController]::MccsVersionCode | Should -Be 0xDF
        [SysAdminSuite.DisplayControl.MonitorController]::OsdButtonControlCode | Should -Be 0xCA
        [SysAdminSuite.DisplayControl.MonitorController]::LockedButtonValue | Should -Be 0x0303
    }

    It 'Requires explicit authorization and confirmation for Apply and Restore' {
        $content = Get-Content -LiteralPath $script:orchestrator -Raw -Encoding UTF8
        $content | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
        $content | Should -Match "ConfirmImpact\s*=\s*'High'"
        $content | Should -Match '\[switch\]\$AllowTargetMutation'
        $content | Should -Match 'Refusing \$Operation target mutation without -AllowTargetMutation'
        $content | Should -Match '\$PSCmdlet\.ShouldProcess'
    }

    It 'Keeps request-only and fixture paths before remote contact' {
        $content = Get-Content -LiteralPath $script:orchestrator -Raw -Encoding UTF8
        $content.IndexOf('if ($WhatIfPreference)') | Should -BeLessThan $content.IndexOf('Invoke-Command')
        $content.IndexOf('if ($FixtureMode)') | Should -BeLessThan $content.IndexOf('Invoke-Command')
        $content | Should -Match "status = 'PLANNED_WHATIF'"
        $content | Should -Match 'network_activity_performed = \$false'
        $content | Should -Match 'target_mutation_performed = \$false'
    }

    It 'Persists an exact restore contract from the original VCP value' {
        $content = Get-Content -LiteralPath $script:orchestrator -Raw -Encoding UTF8
        $content | Should -Match 'sas-cybernet-display-button-restore/v1'
        $content | Should -Match 'original_vcp_ca_value'
        $content | Should -Match 'Restore requires -RestoreManifest'
        $content | Should -Match 'RestoreButtonLock'
    }

    It 'Does not substitute Windows power policy or broad scanning for monitor control' {
        $content = (Get-Content -LiteralPath $script:orchestrator -Raw -Encoding UTF8) +
            (Get-Content -LiteralPath $script:ddcciSource -Raw -Encoding UTF8)
        foreach ($forbidden in @(
            'UIBUTTON_ACTION',
            'Test-Connection',
            'ping.exe',
            'powercfg.exe',
            'Set-ItemProperty',
            'Register-ScheduledTask',
            'New-Service'
        )) {
            $content | Should -Not -Match ([regex]::Escape($forbidden))
        }
    }
}

Describe 'Existing physical display menu event probe remains read-only' {
    It 'Collects evidence without applying the DDC CI mutation' {
        $content = Get-Content -LiteralPath $script:eventProbe -Raw -Encoding UTF8
        $content | Should -Match 'Get-WinEvent'
        $content | Should -Match 'OBSERVED_WINDOWS_EVENT'
        $content | Should -Match 'NO_WINDOWS_EVENT_OBSERVED'
        $content | Should -Not -Match 'SetVCPFeature'
        $content | Should -Not -Match '0x0303'
    }
}
