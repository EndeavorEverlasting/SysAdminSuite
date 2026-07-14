#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Test-SasHostEligibility' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'scripts/Test-SasHostEligibility.ps1'
        . $script:modulePath
        $script:validPolicy = Join-Path $repoRoot 'Tests/fixtures/host-eligibility/valid-policy.json'
        $script:fixtureOnlyPolicy = Join-Path $repoRoot 'Tests/fixtures/host-eligibility/fixture-only-policy.json'
        $script:unsupportedSchemaPolicy = Join-Path $repoRoot 'Tests/fixtures/host-eligibility/unsupported-schema-version.json'
    }

    Context 'fail-closed policy missing' {
        It 'returns ineligible when policy file does not exist' {
            $result = Test-SasHostEligibility `
                -Hostname 'FIXTURE-001.example.com' `
                -ExecContext 'fixture' `
                -PolicyPath 'Tests/fixtures/host-eligibility/nonexistent.json' `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'policy_missing'
        }
    }

    Context 'fail-closed policy malformed' {
        It 'returns ineligible when policy is not valid JSON' {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ('bad-policy-' + [guid]::NewGuid().Guid + '.json')
            Set-Content -LiteralPath $tmpFile -Encoding UTF8 -Value '{ bad json {{{'
            $result = Test-SasHostEligibility `
                -Hostname 'FIXTURE-001.example.com' `
                -ExecContext 'fixture' `
                -PolicyPath $tmpFile `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'policy_malformed'
            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'unsupported schema version' {
        It 'returns ineligible for wrong schema version' {
            $result = Test-SasHostEligibility `
                -Hostname 'FIXTURE-001.example.com' `
                -ExecContext 'fixture' `
                -PolicyPath $script:unsupportedSchemaPolicy `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'policy_schema_version_unsupported'
        }
    }

    Context 'unsupported execution context' {
        It 'returns ineligible for undefined context' {
            $result = Test-SasHostEligibility `
                -Hostname 'FIXTURE-001.example.com' `
                -ExecContext 'remote' `
                -PolicyPath $script:fixtureOnlyPolicy `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'context_not_supported'
        }
    }

    Context 'disabled context' {
        It 'returns ineligible for disabled local context' {
            $result = Test-SasHostEligibility `
                -Hostname 'LOCAL-001.example.com' `
                -ExecContext 'local' `
                -PolicyPath $script:validPolicy `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'context_disabled'
        }
    }

    Context 'hostname no match' {
        It 'returns ineligible when hostname does not match any pattern' {
            $result = Test-SasHostEligibility `
                -Hostname 'UNKNOWN-HOST.example.com' `
                -ExecContext 'fixture' `
                -PolicyPath $script:validPolicy `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'hostname_no_match'
        }
    }

    Context 'fixture context - authorized' {
        It 'returns eligible for matching fixture hostname' {
            $result = Test-SasHostEligibility `
                -Hostname 'FIXTURE-001.example.com' `
                -ExecContext 'fixture' `
                -PolicyPath $script:validPolicy `
                -DryRun
            $result.eligible | Should -BeTrue
            $result.reason | Should -Be 'eligible'
        }
    }

    Context 'vm context - authorized' {
        It 'returns eligible for matching VM hostname' {
            $result = Test-SasHostEligibility `
                -Hostname 'VM-TEST-042.example.com' `
                -ExecContext 'vm' `
                -PolicyPath $script:validPolicy `
                -DryRun
            $result.eligible | Should -BeTrue
            $result.reason | Should -Be 'eligible'
        }
    }

    Context 'cybernet physical - authorized' {
        It 'returns eligible for authorized Cybernet physical host' {
            $result = Test-SasHostEligibility `
                -Hostname 'CYB-PHYS-001.example.com' `
                -ExecContext 'cybernet_physical' `
                -PolicyPath $script:validPolicy `
                -TicketReference 'CHG-001' `
                -ChangeReference 'CHG-001' `
                -Authorizer 'sas-admin@example.com' `
                -DryRun
            $result.eligible | Should -BeTrue
            $result.reason | Should -Be 'eligible'
        }
    }

    Context 'cybernet physical - authorization failures' {
        It 'returns ineligible when ticket reference is missing' {
            $result = Test-SasHostEligibility `
                -Hostname 'CYB-PHYS-001.example.com' `
                -ExecContext 'cybernet_physical' `
                -PolicyPath $script:validPolicy `
                -ChangeReference 'CHG-001' `
                -Authorizer 'sas-admin@example.com' `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'authorization_ticket_missing'
        }

        It 'returns ineligible when change reference is missing' {
            $result = Test-SasHostEligibility `
                -Hostname 'CYB-PHYS-001.example.com' `
                -ExecContext 'cybernet_physical' `
                -PolicyPath $script:validPolicy `
                -TicketReference 'CHG-001' `
                -Authorizer 'sas-admin@example.com' `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'authorization_change_missing'
        }

        It 'returns ineligible when authorizer is not in allowed list' {
            $result = Test-SasHostEligibility `
                -Hostname 'CYB-PHYS-001.example.com' `
                -ExecContext 'cybernet_physical' `
                -PolicyPath $script:validPolicy `
                -TicketReference 'CHG-001' `
                -ChangeReference 'CHG-001' `
                -Authorizer 'unauthorized-person@example.com' `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'authorization_authorizer_not_allowed'
        }

        It 'returns ineligible when authorizer is missing' {
            $result = Test-SasHostEligibility `
                -Hostname 'CYB-PHYS-001.example.com' `
                -ExecContext 'cybernet_physical' `
                -PolicyPath $script:validPolicy `
                -TicketReference 'CHG-001' `
                -ChangeReference 'CHG-001' `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'authorization_authorizer_missing'
        }
    }

    Context 'remote context - authorization' {
        It 'returns eligible for authorized remote host' {
            $result = Test-SasHostEligibility `
                -Hostname 'REMOTE-AUTOPILOT-007.example.com' `
                -ExecContext 'remote' `
                -PolicyPath $script:validPolicy `
                -TicketReference 'CHG-042' `
                -ChangeReference 'CHG-042' `
                -Authorizer 'sas-deploy@example.com' `
                -DryRun
            $result.eligible | Should -BeTrue
            $result.reason | Should -Be 'eligible'
        }

        It 'returns ineligible for remote host without authorization' {
            $result = Test-SasHostEligibility `
                -Hostname 'REMOTE-AUTOPILOT-007.example.com' `
                -ExecContext 'remote' `
                -PolicyPath $script:validPolicy `
                -DryRun
            $result.eligible | Should -BeFalse
            $result.reason | Should -Be 'authorization_ticket_missing'
        }
    }

    Context 'Cybernet repair pattern' {
        It 'returns eligible for CYB-REPAIR pattern when authorized' {
            $result = Test-SasHostEligibility `
                -Hostname 'CYB-REPAIR-012.example.com' `
                -ExecContext 'cybernet_physical' `
                -PolicyPath $script:validPolicy `
                -TicketReference 'CHG-012' `
                -ChangeReference 'CHG-012' `
                -Authorizer 'sas-admin@example.com' `
                -DryRun
            $result.eligible | Should -BeTrue
            $result.reason | Should -Be 'eligible'
        }
    }

    Context 'decision artifact emission' {
        It 'writes decision artifact when DryRun is not set' {
            $tmpOutput = Join-Path ([System.IO.Path]::GetTempPath()) ('elig-' + [guid]::NewGuid().Guid)
            $result = Test-SasHostEligibility `
                -Hostname 'FIXTURE-001.example.com' `
                -ExecContext 'fixture' `
                -PolicyPath $script:validPolicy `
                -OutputRoot $tmpOutput
            $result.eligible | Should -BeTrue
            $files = Get-ChildItem -LiteralPath $tmpOutput -Filter '*.json'
            $files.Count | Should -BeGreaterOrEqual 1
            $decision = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
            $decision.eligible | Should -BeTrue
            $decision.hostname | Should -Be 'FIXTURE-001.example.com'
            Remove-Item -LiteralPath $tmpOutput -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
