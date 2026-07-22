#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:entrypoint = Join-Path $script:repoRoot 'scripts\Invoke-SasAutoLogonDeployment.ps1'
    $script:matrixPath = Join-Path $script:repoRoot 'Tests\Fixtures\autologon-canonical-transport\scenarios.json'
    $script:matrix = Get-Content -LiteralPath $script:matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

Describe 'Canonical AutoLogon deployment fixture matrix' {
    It 'parses the application entrypoint without errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:entrypoint, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'executes every closed fixture scenario without live proof promotion' {
        foreach ($scenario in @($script:matrix.scenarios)) {
            $outputRoot = Join-Path $script:repoRoot ('survey\output\autologon_canonical_pester\' + [string]$scenario.id + '-' + [guid]::NewGuid().ToString('N'))
            try {
                $result = & $script:entrypoint `
                    -ComputerName 'SAMPLE001' `
                    -FixtureMode `
                    -FixtureScenario ([string]$scenario.id) `
                    -OutputRoot $outputRoot

                $result.status | Should -Be $(if ([string]$scenario.classification -eq 'fixture_contract_pass') { 'FIXTURE_PASS' } else { 'FIXTURE_FAIL' })
                $result.deployment_result_json | Should -Exist
                $deployment = Get-Content -LiteralPath $result.deployment_result_json -Raw -Encoding UTF8 | ConvertFrom-Json
                $deployment.schema_version | Should -Be 'sas-autologon-deployment-result/v1'
                $deployment.classification | Should -Be ([string]$scenario.classification)
                @($deployment.reason_codes) | Should -Contain ([string]$scenario.reason_code)
                $deployment.deployment.final_gate_passed | Should -Be ([bool]$scenario.final_gate_passed)
                $deployment.transport.canonical_front_door_used | Should -Be ([bool]$scenario.canonical_front_door_used)
                $deployment.network_activity_performed | Should -BeFalse
                $deployment.target_mutation_performed | Should -BeFalse
                $deployment.deployment.task_created | Should -BeFalse
                $deployment.deployment.executed_as_system | Should -BeFalse
                $deployment.deployment.installer_executed | Should -BeFalse
                $deployment.deployment.result_retrieved | Should -BeFalse
                $deployment.deployment.cleanup_verified | Should -BeFalse
                $deployment.deployment.zero_remnants_verified | Should -BeFalse
                $deployment.proof_level | Should -Be 'sanitized_fixture_contract'
            }
            finally {
                if ([IO.Directory]::Exists($outputRoot)) { [IO.Directory]::Delete($outputRoot, $true) }
            }
        }
    }
}
