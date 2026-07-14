#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:orchestrator = Join-Path $repoRoot 'scripts\Invoke-SasCybernetPowerHardening.ps1'
    $script:localPreset = Join-Path $repoRoot 'QRTasks\Set-PowerComfortDefaults.ps1'
    $script:probe = Join-Path $repoRoot 'QRTasks\Test-DisplayMenuButtonEvent.ps1'
    $script:dispatcher = Join-Path $repoRoot 'QRTasks\Invoke-TechTask.ps1'
}

Describe 'Cybernet power-hardening PowerShell surfaces' {
    It 'Parses the orchestrator and local probe without syntax errors' {
        foreach ($path in @($script:orchestrator, $script:probe)) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    It 'Preserves the known-good physical power-button Do nothing action' {
        $content = Get-Content -LiteralPath $script:localPreset -Raw
        $content | Should -Match '7648efa3-dd9c-4e3e-b566-50f929386280'
        $content.Contains("@('/setacvalueindex', `$g, 'SUB_BUTTONS', `$powerButtonAction, '0')") | Should -Be $true
        $content.Contains("@('/setdcvalueindex', `$g, 'SUB_BUTTONS', `$powerButtonAction, '0')") | Should -Be $true
        $content | Should -Not -Match 'UIBUTTON_ACTION'
    }

    It 'Requires explicit mutation authorization and ShouldProcess confirmation' {
        $content = Get-Content -LiteralPath $script:orchestrator -Raw
        $content | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
        $content | Should -Match 'ConfirmImpact\s*=\s*''High'''
        $content | Should -Match '\[switch\]\$AllowTargetMutation'
        $content | Should -Match 'Refusing target mutation without -AllowTargetMutation'
        $content | Should -Match '\$PSCmdlet\.ShouldProcess'
    }

    It 'Keeps WhatIf and fixture modes before remote contact' {
        $content = Get-Content -LiteralPath $script:orchestrator -Raw
        $content.IndexOf('if ($WhatIfPreference)') | Should -BeLessThan $content.IndexOf('Invoke-Command -ComputerName $target')
        $content.IndexOf('if ($FixtureMode)') | Should -BeLessThan $content.IndexOf('Invoke-Command -ComputerName $target')
        $content | Should -Match "status = 'PLANNED_WHATIF'"
        $content | Should -Match "status = 'FIXTURE_PASS'"
        $content | Should -Match 'network_activity_performed = \$false'
        $content | Should -Match 'target_mutation_performed = \$false'
    }

    It 'Does not broaden the remote repair into unrelated comfort settings or scanning' {
        $content = Get-Content -LiteralPath $script:orchestrator -Raw
        foreach ($forbidden in @('VIDEOIDLE', 'STANDBYIDLE', 'HIBERNATEIDLE', 'DISKIDLE', 'LIDACTION', 'UIBUTTON_ACTION', 'Test-Connection', 'ping.exe')) {
            $content | Should -Not -Match ([regex]::Escape($forbidden))
        }
    }

    It 'Fails closed on the physical display menu button claim' {
        $content = Get-Content -LiteralPath $script:orchestrator -Raw
        $content | Should -Match 'NOT_APPLIED_UNPROVEN'
        $content | Should -Match 'Do not claim this button is disabled'
    }
}

Describe 'Display menu button probe' {
    It 'Is registered in the QR task dispatcher' {
        $content = Get-Content -LiteralPath $script:dispatcher -Raw
        $content | Should -Match "DisplayMenuButtonProbe\s*=\s*'Test-DisplayMenuButtonEvent\.ps1'"
    }

    It 'Captures evidence without changing system state' {
        $content = Get-Content -LiteralPath $script:probe -Raw
        $content | Should -Match 'Get-WinEvent'
        $content | Should -Match 'OBSERVED_WINDOWS_EVENT'
        $content | Should -Match 'NO_WINDOWS_EVENT_OBSERVED'
        foreach ($forbidden in @('powercfg', 'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'Clear-EventLog', 'wevtutil', 'Invoke-Command', 'Enter-PSSession', 'New-Service', 'Register-ScheduledTask')) {
            $content | Should -Not -Match ([regex]::Escape($forbidden))
        }
    }
}
