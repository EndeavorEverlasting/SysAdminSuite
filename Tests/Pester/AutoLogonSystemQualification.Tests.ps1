#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:qualificationScript = Join-Path $script:repoRoot 'scripts\Invoke-SasAutoLogonSystemQualification.ps1'
    $script:approvedCatalog = Join-Path $script:repoRoot 'configs\software-packages\approved-apps.json'
    $script:packageSetCatalog = Join-Path $script:repoRoot 'configs\software-packages\windows-native-package-sets.json'
    $script:qualificationCatalog = Join-Path $script:repoRoot 'configs\software-packages\autologon-system-qualification-catalog.json'
}

Describe 'AutoLogon canonical LocalSystem qualification' {
    It 'parses the qualification surface under Windows PowerShell 5.1' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:qualificationScript,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
    }

    It 'blocks the failed production artifact in both production catalogs' {
        $approved = Get-Content -LiteralPath $script:approvedCatalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $native = Get-Content -LiteralPath $script:packageSetCatalog -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($catalog in @($approved, $native)) {
            $autologon = @($catalog.packages | Where-Object id -eq 'autologon')
            $autologon.Count | Should -Be 1
            $autologon[0].install_enabled | Should -BeFalse
            $autologon[0].canonical_system_install_enabled | Should -BeFalse
            $autologon[0].canonical_system_qualification.status | Should -Be 'failed_runtime_validation'
        }
    }

    It 'keeps the final-step exception narrow and qualification-only' {
        $catalog = Get-Content -LiteralPath $script:qualificationCatalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $catalog.catalog_policy.qualification_only | Should -BeTrue
        $catalog.catalog_policy.canonical_production_install_enabled | Should -BeFalse
        @($catalog.packages).Count | Should -Be 1
        $catalog.packages[0].id | Should -Be 'autologon'
        $catalog.packages[0].install_enabled | Should -BeTrue
        $catalog.packages[0].readiness | Should -Be 'qualification_only'
    }

    It 'completes a sanitized candidate fixture without live proof claims' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-system-qualification-' + [guid]::NewGuid().ToString('N'))
        try {
            $output = & $script:qualificationScript -Action Fixture -FixtureMode -FixtureScenario success -OutputRoot $root -PassThru
            $output.classification | Should -Be 'QUALIFIED_FOR_CANONICAL_SYSTEM'
            $output.result.fixture_mode | Should -BeTrue
            $output.result.proof_level | Should -Be 'sanitized_fixture_contract'
            $output.result.canonical_catalog_promoted | Should -BeFalse
            $output.result.automatic_reboot_performed | Should -BeFalse
            $output.result.automatic_sign_in_observed | Should -BeFalse
            $output.result.postcondition_auto_admin_logon | Should -Be '1'
            $output.result.postcondition_default_password_name_present | Should -BeTrue
            $output.result.postcondition_expected_user_match | Should -BeTrue
            $output.result.collector_cleanup_verified | Should -BeTrue
            $output.result.deployment_cleanup_verified | Should -BeTrue
            Test-Path -LiteralPath $output.result_path -PathType Leaf | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'rejects an identical failed candidate in fixture classification' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-system-qualification-' + [guid]::NewGuid().ToString('N'))
        try {
            $output = & $script:qualificationScript -Action Fixture -FixtureMode -FixtureScenario same_failed_candidate -OutputRoot $root -PassThru
            $output.classification | Should -Be 'QUALIFICATION_BLOCKED_IDENTICAL_FAILED_CANDIDATE'
            $output.result.candidate_materially_differs_from_failed_invocation | Should -BeFalse
            $output.result.canonical_catalog_promoted | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'fails closed on a dirty baseline fixture' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-system-qualification-' + [guid]::NewGuid().ToString('N'))
        try {
            $output = & $script:qualificationScript -Action Fixture -FixtureMode -FixtureScenario dirty_baseline -OutputRoot $root -PassThru
            $output.classification | Should -Be 'QUALIFICATION_BLOCKED_DIRTY_BASELINE'
            $output.result.baseline_clean | Should -BeFalse
            $output.result.canonical_catalog_promoted | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'does not treat process completion as a successful postcondition' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-system-qualification-' + [guid]::NewGuid().ToString('N'))
        try {
            $output = & $script:qualificationScript -Action Fixture -FixtureMode -FixtureScenario unsupported_postcondition -OutputRoot $root -PassThru
            $output.classification | Should -Be 'CANDIDATE_UNSUPPORTED_SYSTEM_POSTCONDITION'
            $output.result.postcondition_auto_admin_logon | Should -Be '0'
            $output.result.postcondition_default_password_name_present | Should -BeFalse
            $output.result.postcondition_expected_user_match | Should -BeFalse
            $output.result.canonical_catalog_promoted | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'requires cleanup proof before qualification' {
        $root = Join-Path $script:repoRoot ('survey\output\tests\autologon-system-qualification-' + [guid]::NewGuid().ToString('N'))
        try {
            $output = & $script:qualificationScript -Action Fixture -FixtureMode -FixtureScenario cleanup_failure -OutputRoot $root -PassThru
            $output.classification | Should -Be 'QUALIFICATION_CLEANUP_REVIEW_REQUIRED'
            $output.result.collector_cleanup_verified | Should -BeFalse
            $output.result.canonical_catalog_promoted | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
