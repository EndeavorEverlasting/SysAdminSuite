#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:modulePath = Join-Path $script:repoRoot 'scripts\SasAutoLogonSmbStateRecovery.psm1'
    $script:orchestratorPath = Join-Path $script:repoRoot 'scripts\Invoke-SasAutoLogonWinRmRecovery.ps1'
    $script:starterPath = Join-Path $script:repoRoot 'scripts\Start-SasAutoLogonWinRmRecovery.ps1'
}

Describe 'AutoLogon WinRM-blocker recovery' {
    It 'parses all PowerShell recovery surfaces under Windows PowerShell' {
        foreach ($path in @($script:modulePath, $script:orchestratorPath, $script:starterPath)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0 -Because $path
        }
    }

    It 'validates exact FQDN recovery targets' {
        Import-Module $script:modulePath -Force
        Test-SasAutoLogonRecoveryFqdn -ComputerName 'host.example.invalid' | Should -BeTrue
        Test-SasAutoLogonRecoveryFqdn -ComputerName 'shortname' | Should -BeFalse
        Test-SasAutoLogonRecoveryFqdn -ComputerName 'bad name.example.invalid' | Should -BeFalse
    }

    It 'completes the fixture recovery only after the canonical final-step gate passes' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-winrm-recovery-' + [guid]::NewGuid().ToString('N'))
        try {
            $result = & $script:orchestratorPath -FixtureMode -FixtureScenario success -OutputRoot $root -PassThru
            $result.classification | Should -Be 'RECOVERED_DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING'
            $result.result.fixture_mode | Should -BeTrue
            $result.result.final_gate_passed | Should -BeTrue
            $result.result.final_gate_run_id | Should -Match '^autologon-delta-'
            Test-Path -LiteralPath $result.result.final_gate_result_path -PathType Leaf | Should -BeTrue
            $result.result.network_activity_performed | Should -BeFalse
            $result.result.target_mutation_performed | Should -BeFalse
            $result.result.configuration_mutation_performed | Should -BeFalse
            $result.result.collector_cleanup_verified | Should -BeTrue
            $result.result.deployment_cleanup_verified | Should -BeTrue
            $result.result.runtime_proof_pending | Should -BeTrue
            $result.result.default_password_value_collected | Should -BeFalse
            $result.result.automatic_reboot_performed | Should -BeFalse
            $result.result.winrm_enabled_or_modified | Should -BeFalse
            $result.result.baseline_status | Should -Be 'not_configured'
            $result.result.after_status | Should -Be 'autologon_ready'
            Test-Path -LiteralPath $result.result_path -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $result.summary_path -PathType Leaf | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'stops without deployment or a final-step gate when the SMB baseline is already configured' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-winrm-recovery-' + [guid]::NewGuid().ToString('N'))
        try {
            $result = & $script:orchestratorPath -FixtureMode -FixtureScenario already_configured -OutputRoot $root -PassThru
            $result.classification | Should -Be 'ALREADY_CONFIGURED_RUNTIME_PENDING'
            $result.result.final_gate_passed | Should -BeFalse
            $result.result.deployment_complete | Should -BeFalse
            $result.result.configuration_mutation_performed | Should -BeFalse
            $result.result.baseline_status | Should -Be 'autologon_ready'
            $result.result.runtime_proof_pending | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'fails closed when transient collector cleanup is not proven' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-winrm-recovery-' + [guid]::NewGuid().ToString('N'))
        try {
            { & $script:orchestratorPath -FixtureMode -FixtureScenario cleanup_failure -OutputRoot $root -PassThru } |
                Should -Throw '*RECOVERY_CLEANUP_REVIEW_REQUIRED*'
            $resultFile = Get-ChildItem -LiteralPath $root -Filter 'autologon_winrm_recovery_result.json' -File -Recurse |
                Select-Object -First 1
            $resultFile | Should -Not -BeNullOrEmpty
            $closed = Get-Content -LiteralPath $resultFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $closed.classification | Should -Be 'RECOVERY_CLEANUP_REVIEW_REQUIRED'
            $closed.final_gate_passed | Should -BeFalse
            $closed.runtime_proof_pending | Should -BeFalse
            $closed.default_password_value_collected | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'fails closed on a synthetic deployment failure after the final-step gate' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-winrm-recovery-' + [guid]::NewGuid().ToString('N'))
        try {
            { & $script:orchestratorPath -FixtureMode -FixtureScenario deployment_failure -OutputRoot $root -PassThru } |
                Should -Throw '*RECOVERY_FAILED*'
            $resultFile = Get-ChildItem -LiteralPath $root -Filter 'autologon_winrm_recovery_result.json' -File -Recurse |
                Select-Object -First 1
            $closed = Get-Content -LiteralPath $resultFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $closed.final_gate_passed | Should -BeTrue
            $closed.deployment_complete | Should -BeFalse
            $closed.configuration_mutation_performed | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
