#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'SasLowNoisePolicy canonical provider' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'scripts/SasLowNoisePolicy.psm1'
        $script:originalPolicyPath = $env:SAS_LOW_NOISE_POLICY_PATH
        Import-Module $script:modulePath -Force
    }

    AfterAll {
        $env:SAS_LOW_NOISE_POLICY_PATH = $script:originalPolicyPath
        Remove-Module SasLowNoisePolicy -ErrorAction SilentlyContinue
    }

    It 'loads the canonical policy and network preflight profile' {
        $policy = Get-SasLowNoisePolicy
        $profile = Get-SasLowNoiseProfile -Id 'network_preflight'
        $policy.SchemaVersion | Should -Be 'sas-low-noise-policy/v1'
        $policy.PolicyVersion | Should -Be '1.1'
        ($profile.ports -join ',') | Should -Be '135,445,3389,9100'
    }

    It 'returns profile copies instead of shared mutable state' {
        $first = Get-SasLowNoiseProfile -Id 'network_preflight'
        $first.id = 'changed-by-caller'
        (Get-SasLowNoiseProfile -Id 'network_preflight').id | Should -Be 'network_preflight'
    }

    It 'rejects unknown profiles' {
        { Get-SasLowNoiseProfile -Id 'not-a-profile' } | Should -Throw '*Unknown or duplicated low-noise profile*'
    }

    It 'fails closed when an explicit policy path is missing' {
        $env:SAS_LOW_NOISE_POLICY_PATH = Join-Path ([System.IO.Path]::GetTempPath()) 'missing-sas-low-noise-policy.json'
        { Get-SasLowNoisePolicy } | Should -Throw '*Canonical low-noise policy is missing*'
        $env:SAS_LOW_NOISE_POLICY_PATH = $script:originalPolicyPath
    }
}
