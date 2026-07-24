#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:s4uScript = Join-Path $script:repoRoot 'scripts\Invoke-SasAutoLogonKerberosS4UPilot.ps1'
}

Describe 'AutoLogon Kerberos S4U remote pilot' {
    It 'parses the S4U pilot under Windows PowerShell 5.1' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:s4uScript,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
    }

    It 'runs a sanitized S4U fixture without network or target mutation claims' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-kerberos-s4u-' + [guid]::NewGuid().ToString('N'))
        try {
            $output = & $script:s4uScript `
                -ComputerName 'fixture.invalid' `
                -FixtureMode `
                -OutputRoot $root `
                -PassThru

            $output.classification | Should -Be 'KERBEROS_S4U_FIXTURE_READY'
            $output.result.fixture_mode | Should -BeTrue
            $output.result.target_mutation_performed | Should -BeFalse
            $output.result.network_activity_performed | Should -BeFalse
            $output.result.task_logon_type | Should -Be 'S4U'
            $output.result.task_run_level | Should -Be 'HighestAvailable'
            $output.result.password_supplied_or_stored | Should -BeFalse
            $output.result.target_user_session_required | Should -BeFalse
            $output.result.task_network_access_expected | Should -BeFalse
            $output.result.default_password_value_collected | Should -BeFalse
            $output.result.automatic_reboot_performed | Should -BeFalse
            $output.result.automatic_sign_in_observed | Should -BeFalse
            $output.result.canonical_system_qualification_changed | Should -BeFalse
            $output.result.proof_level | Should -Be 'sanitized_fixture_contract'
            Test-Path -LiteralPath $output.result_path -PathType Leaf | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'keeps S4U separate from the failed LocalSystem qualification state' {
        $content = Get-Content -LiteralPath $script:s4uScript -Raw -Encoding UTF8
        $content | Should -Match "'/RU',\$PrincipalName,'/NP'"
        $content | Should -Match "'/RL','HIGHEST'"
        $content | Should -Match "target_user_session_required = \$false"
        $content | Should -Match "password_supplied_or_stored = \$false"
        $content | Should -Match "canonical_system_qualification_changed = \$false"
        $content | Should -Not -Match 'QUALIFIED_FOR_CANONICAL_SYSTEM'
        $content | Should -Not -Match 'InteractiveToken'
        $content | Should -Not -Match "['\"]\/RP['\"]"
    }
}
