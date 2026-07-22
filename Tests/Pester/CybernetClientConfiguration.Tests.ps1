#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:orchestrator = Join-Path $script:repoRoot 'Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1'
    $script:profilePath = Join-Path $script:repoRoot 'Config\cybernet-client-preferences.json'
    $script:packageSetPath = Join-Path $script:repoRoot 'configs\software-packages\windows-native-package-sets.json'
}

Describe 'Cybernet client configuration PowerShell surface' {
    It 'parses cleanly' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:orchestrator,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'pins the exact client hardware preferences' {
        $profile = Get-Content -LiteralPath $script:profilePath -Raw | ConvertFrom-Json
        $profile.hardware.physical_power_button_action | Should -Be 'do_nothing'
        $profile.hardware.display_button_control.vcp_code | Should -Be '0xCA'
        $profile.hardware.display_button_control.desired_value | Should -Be '0x0303'
        @($profile.hardware.ready_com_ports) -join ',' | Should -Be 'COM1,COM2,COM3,COM4'
        $profile.workflow.automatic_reboot_forbidden | Should -BeTrue
    }

    It 'matches the six-package catalog with AutoLogon last' {
        $profile = Get-Content -LiteralPath $script:profilePath -Raw | ConvertFrom-Json
        $catalog = Get-Content -LiteralPath $script:packageSetPath -Raw | ConvertFrom-Json
        $packageSet = @($catalog.package_sets | Where-Object id -eq $profile.software.package_set_id)
        $packageSet.Count | Should -Be 1
        @($profile.software.package_ids).Count | Should -Be 6
        @($profile.software.package_ids) -join '|' | Should -Be (@($packageSet[0].package_ids) -join '|')
        @($packageSet[0].package_ids)[-1] | Should -Be 'autologon'
    }

    It 'keeps plan first and software acceptance separate' {
        $text = Get-Content -LiteralPath $script:orchestrator -Raw
        $text | Should -Match '\[string\]\$Mode\s*=\s*''Plan'''
        $text | Should -Match 'Apply requires -AllowTargetMutation'
        $text | Should -Match 'APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED'
        $text | Should -Match 'software_acceptance_required\s*=\s*\$true'
        $text | Should -Match 'automatic_reboot_performed\s*=\s*\$false'
        $text | Should -Match 'com_mutation_performed\s*=\s*\$false'
    }
}
