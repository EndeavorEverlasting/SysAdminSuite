#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:runner = Join-Path $script:repoRoot 'scripts\Invoke-SasAutoLogonE2E.ps1'
    $script:application = Join-Path $script:repoRoot 'scripts\Invoke-SasAutoLogonDeployment.ps1'
    $script:adapter = Join-Path $script:repoRoot 'scripts\SasSoftwareDeploymentAdapter.psm1'
    $script:validatedDeployment = Join-Path $script:repoRoot 'scripts\Invoke-SasValidatedSoftwareDeployment.ps1'
    $script:legacyPlanner = Join-Path $script:repoRoot 'scripts\Invoke-SasSoftwareInstall.ps1'
    $script:matrixPath = Join-Path $script:repoRoot 'Tests\Fixtures\autologon-canonical-e2e\scenarios.json'
    $script:schemaPath = Join-Path $script:repoRoot 'schemas\harness\autologon-canonical-e2e-result.schema.json'
}

Describe 'Canonical AutoLogon composed E2E harness' {
    It 'parses every owned PowerShell surface under Windows PowerShell syntax' {
        foreach ($path in @($script:runner,$script:application,$script:adapter,$script:validatedDeployment,$script:legacyPlanner)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0 -Because $path
        }
    }

    It 'keeps the dedicated matrix closed to thirteen deterministic scenarios' {
        $matrix = Get-Content -LiteralPath $script:matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
        @($matrix.scenarios).Count | Should -Be 13
        @($matrix.scenarios | Select-Object -ExpandProperty id -Unique).Count | Should -Be 13
        $matrix.network_scope | Should -Be 'none'
        $matrix.live_target_mutation | Should -BeFalse
    }

    It 'caps fixture execution and receipt proof in the result schema' {
        $schema = Get-Content -LiteralPath $script:schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $schema.additionalProperties | Should -BeFalse
        $schema.properties.safety.properties.real_scheduled_task_created.const | Should -BeFalse
        $schema.properties.fixture_execution.properties.system_execution_is_simulated.const | Should -BeTrue
        $schema.properties.receipt.properties.classification.const | Should -Be 'contract_only'
        $schema.properties.receipt.properties.live_proof_promoted.const | Should -BeFalse
    }

    It 'contains no network, reboot, real scheduled-task, or credential command surface' {
        $content = Get-Content -LiteralPath $script:runner -Raw -Encoding UTF8
        foreach ($marker in @(
            'Test-NetConnection','Resolve-DnsName','Invoke-WebRequest','Register-ScheduledTask',
            'New-ScheduledTask','Restart-Computer','Get-Credential','ConvertTo-SecureString'
        )) {
            $content | Should -Not -Match ([regex]::Escape($marker))
        }
        $content | Should -Match 'system_execution_is_simulated=\$true'
        $content | Should -Match 'default_password_value_read=\$false'
        $content | Should -Match '\[AllowEmptyCollection\(\)\]\[Collections\.Generic\.List\[object\]\]\$List'
        $content | Should -Match 'scenarios=\$scenarioRows\.ToArray\(\)'
        $content | Should -Match 'artifacts=\$validationArtifacts\.ToArray\(\)'
        $content | Should -Not -Match 'scenarios=@\(\$scenarioRows\)'
        $content | Should -Not -Match 'artifacts=@\(\$validationArtifacts\)'
        $content | Should -Match 'failed_gate_ids='
        $content | Should -Match 'cleanup_failures='
        $content | Should -Match 'E2E_FAILURE\|\{0\}'
        $content | Should -Match '\$matrixLines\.Add\(\("E2E_FAILURE\|\{0\}"'
        $content | Should -Not -Match 'Write-Error \$failure'
        $content | Should -Match 'foreach \(\$fixtureCleanupRoot in @\(\$fixtureTarget,\$generatedRoot\)\)'
        $content | Should -Match 'Remove-Item -LiteralPath \$fixtureCleanupRoot -Recurse -Force -ErrorAction Stop'
        $content | Should -Match '\$composedCleanupVerified = \(\$adapterCleanupVerified -and \$localFixtureCleanupVerified\)'
        $content | Should -Match '\$composedZeroRemnantsVerified = \(\$zeroRunScopedRemnants -and \$localFixtureCleanupVerified\)'

        $frontDoorContent = Get-Content -LiteralPath $script:validatedDeployment -Raw -Encoding UTF8
        $frontDoorContent | Should -Match 'if \(\$AllowFixtures -and \$WhatIfPreference\)'
        $frontDoorContent | Should -Match "Normalize-UncRoot '\\\\fixture\.invalid\\'"
        $frontDoorContent | Should -Match '\$installParameters\.AllowFixtures = \$true'

        $plannerContent = Get-Content -LiteralPath $script:legacyPlanner -Raw -Encoding UTF8
        $plannerContent | Should -Match 'if \(\$AllowFixtures -and -not \$WhatIfPreference\)'
        $plannerContent | Should -Match "Normalize-SasUncRoot -Path '\\\\fixture\.invalid\\'"
    }
}
