#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:validator = Join-Path $script:repoRoot 'scripts\Test-SasHostEligibility.ps1'
}

Describe 'AutoLogon explicit remote target authority' {
    BeforeEach {
        $script:previousMarker = [Environment]::GetEnvironmentVariable(
            'SAS_EXPLICIT_REMOTE_TARGET_REQUEST',
            [EnvironmentVariableTarget]::Process
        )
        Remove-Item Env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST -ErrorAction SilentlyContinue
        $script:missingPolicy = Join-Path $TestDrive 'policy-does-not-exist.json'
    }

    AfterEach {
        if ($null -eq $script:previousMarker) {
            Remove-Item Env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST -ErrorAction SilentlyContinue
        }
        else {
            $env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = $script:previousMarker
        }
    }

    It 'allows the canonical FQDN for the explicitly requested short remote target without a policy file' {
        $env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = 'fixturecyb01'
        $result = & $script:validator `
            -Target 'fixturecyb01.example.invalid' `
            -ExecContext remote `
            -PolicyPath $script:missingPolicy

        $result.eligible | Should -BeTrue
        $result.decision | Should -Be 'allowed'
        $result.reason_code | Should -Be 'EXPLICIT_REMOTE_TARGET_AUTHORIZED'
        $result.matched_pattern | Should -Be 'operator-explicit-target'
    }

    It 'does not authorize a different remote target' {
        $env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = 'fixturecyb01'
        $result = & $script:validator `
            -Target 'fixturecyb02.example.invalid' `
            -ExecContext remote `
            -PolicyPath $script:missingPolicy

        $result.eligible | Should -BeFalse
        $result.decision | Should -Be 'closed'
        $result.reason_code | Should -Be 'POLICY_FILE_MISSING'
    }

    It 'does not authorize localhost even when the marker names localhost' {
        $env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = 'localhost'
        $result = & $script:validator `
            -Target 'localhost' `
            -ExecContext remote `
            -PolicyPath $script:missingPolicy

        $result.eligible | Should -BeFalse
        $result.reason_code | Should -Be 'LOCAL_FALLBACK_BLOCKED'
    }

    It 'does not turn the marker into fixture or VM authority' {
        $env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = 'fixturecyb01'

        foreach ($context in @('fixture','vm')) {
            $result = & $script:validator `
                -Target 'fixturecyb01.example.invalid' `
                -ExecContext $context `
                -PolicyPath $script:missingPolicy

            $result.eligible | Should -BeFalse
            $result.reason_code | Should -Be 'POLICY_FILE_MISSING'
        }
    }

    It 'requires an exact FQDN when the operator supplied an FQDN' {
        $env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = 'fixturecyb01.example.invalid'

        $same = & $script:validator `
            -Target 'fixturecyb01.example.invalid' `
            -ExecContext remote `
            -PolicyPath $script:missingPolicy
        $other = & $script:validator `
            -Target 'fixturecyb01.other.invalid' `
            -ExecContext remote `
            -PolicyPath $script:missingPolicy

        $same.reason_code | Should -Be 'EXPLICIT_REMOTE_TARGET_AUTHORIZED'
        $other.reason_code | Should -Be 'POLICY_FILE_MISSING'
    }
}
