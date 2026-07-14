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

    It 'builds one profile-agnostic effective context for reports and agents' {
        $context = New-SasLowNoiseContextObject -ProfileId 'network_preflight' -ProfileSource 'explicit_subset_override' -EvidenceSource 'synthetic_fixture' -Disposition 'fixture_complete' -Reason 'synthetic contract proof' -NetworkActivityPerformed $false -TargetMutationPerformed $false -NextAction 'Review the fixture.' -EffectivePorts 135,445
        $context.profile_id | Should -Be 'network_preflight'
        $context.profile_source | Should -Be 'explicit_subset_override'
        ($context.effective_constraints.ports -join ',') | Should -Be '135,445'
        $context.target_mutation_performed | Should -BeFalse
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

Describe 'Get-SasPortFallbackDecision correctness' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'scripts/SasLowNoisePolicy.psm1'
        Import-Module $script:modulePath -Force
    }

    AfterAll {
        Remove-Module SasLowNoisePolicy -ErrorAction SilentlyContinue
    }

    It 'reports review_required when all targets are untested (NotChecked)' {
        $d = Get-SasPortFallbackDecision -TargetCount 3 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 0 -UntestedCount 3
        $d.decision | Should -Be 'review_required'
        $d.default_ports_blocked_or_filtered_count | Should -Be 0
        $d.untested_target_count | Should -Be 3
        $d.fallback_profile_recommended | Should -Be ''
    }

    It 'distinguishes untested targets from confirmed-silent targets' {
        $d = Get-SasPortFallbackDecision -TargetCount 4 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 1 -UntestedCount 2 -AllowFullPorts
        $d.open_default_port_target_count | Should -Be 1
        $d.default_ports_blocked_or_filtered_count | Should -Be 1
        $d.untested_target_count | Should -Be 2
        $d.decision | Should -Be 'web_only_fallback'
    }

    It 'returns default_ok when all probed targets have open default ports and none are silent' {
        $d = Get-SasPortFallbackDecision -TargetCount 2 -OpenDefaultPortTargetCount 2 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 2 -SilentOnDefaultProfileCount 0
        $d.decision | Should -Be 'default_ok'
        $d.fallback_profile_recommended | Should -Be ''
    }

    It 'emits canonical default_profile when effective ports match the default' {
        $d = Get-SasPortFallbackDecision -TargetCount 1 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 0 -EffectivePorts 80,443,135,445,3389,5985,5986
        $d.default_profile | Should -Be 'keyports_cybernet_json'
        $d.ports_requested.Count | Should -Be 7
    }

    It 'suppresses default_profile and ports_requested when ports are narrowed' {
        $d = Get-SasPortFallbackDecision -TargetCount 1 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 0 -EffectivePorts 445,3389
        $d.default_profile | Should -Be ''
        $d.ports_requested.Count | Should -Be 0
    }

    It 'makes decision and fallback_profile mutually exclusive for web_only_fallback' {
        $d = Get-SasPortFallbackDecision -TargetCount 2 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 1 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -AllowFullPorts
        $d.decision | Should -Be 'web_only_fallback'
        $d.fallback_profile_recommended | Should -Be 'web_reachability_only_json'
    }

    It 'makes UDP justification override the full decision, not just the profile' {
        $d = Get-SasPortFallbackDecision -TargetCount 2 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 1 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -UdpJustified
        $d.decision | Should -Be 'udp_justification_required'
        $d.fallback_profile_recommended | Should -Be 'udp_dns_snmp_json'
        $d.fallback_requires_approval | Should -BeTrue
    }

    It 'makes all-ports deny gate reachable when silent targets exist and AllowFullPorts is absent' {
        $d = Get-SasPortFallbackDecision -TargetCount 2 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2
        $d.decision | Should -Be 'all_ports_denied_without_explicit_gate'
        $d.fallback_requires_approval | Should -BeTrue
        $d.fallback_profile_recommended | Should -Be ''
    }

    It 'gives UDP justification precedence over all-ports deny' {
        $d = Get-SasPortFallbackDecision -TargetCount 2 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -UdpJustified
        $d.decision | Should -Be 'udp_justification_required'
        $d.fallback_profile_recommended | Should -Be 'udp_dns_snmp_json'
    }

    It 'gives all-ports deny precedence over approved-subnet fallback' {
        $d = Get-SasPortFallbackDecision -TargetCount 2 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -ApprovedSubnetScope
        $d.decision | Should -Be 'all_ports_denied_without_explicit_gate'
        $d.fallback_requires_approval | Should -BeTrue
        $d.fallback_profile_recommended | Should -Be ''
    }

    It 'uses approved-subnet fallback when AllowFullPorts is set' {
        $d = Get-SasPortFallbackDecision -TargetCount 2 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -ApprovedSubnetScope -AllowFullPorts
        $d.decision | Should -Be 'approved_subnet_host_discovery_required'
        $d.fallback_profile_recommended | Should -Be 'host_discovery_web_syn_txt'
        $d.fallback_requires_approval | Should -BeTrue
    }

    It 'never emits both default_ok and web_only_fallback simultaneously' {
        $d = Get-SasPortFallbackDecision -TargetCount 3 -OpenDefaultPortTargetCount 2 -WebOnlyReachableCount 1 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 1
        $isDefaultOk = $d.decision -eq 'default_ok'
        $isWebOnly = $d.decision -eq 'web_only_fallback'
        ($isDefaultOk -xor $isWebOnly -or (-not $isDefaultOk -and -not $isWebOnly)) | Should -BeTrue
    }
}
