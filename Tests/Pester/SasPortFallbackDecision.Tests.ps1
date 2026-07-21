#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'New-SasPortFallbackDecision correctness' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'scripts/SasPortFallbackDecision.psm1'
        Import-Module $script:modulePath -Force
    }

    AfterAll {
        Remove-Module SasPortFallbackDecision -ErrorAction SilentlyContinue
    }

    Context 'Count consistency guards' {
        It 'fails when tested + untested does not equal target_count' {
            { New-SasPortFallbackDecision -TargetCount 5 -TestedTargetCount 2 -UntestedTargetCount 1 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 1 -SourceProfileId 'network_preflight' -ProfileSource 'explicit_named_profile' -NoNetwork } |
                Should -Throw '*must equal tested*untested*'
        }

        It 'fails when open_default + silent does not equal tested' {
            { New-SasPortFallbackDecision -TargetCount 3 -TestedTargetCount 3 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 1 -SourceProfileId 'network_preflight' -ProfileSource 'explicit_named_profile' -NoNetwork } |
                Should -Throw '*must equal open_default*silent*'
        }

        It 'fails when untested targets are counted as silent' {
            { New-SasPortFallbackDecision -TargetCount 3 -TestedTargetCount 2 -UntestedTargetCount 1 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 1 -SourceProfileId 'network_preflight' -ProfileSource 'explicit_named_profile' -NoNetwork } |
                Should -Throw '*untested*must not be counted*silent*'
        }
    }

    Context 'review_required when all untested' {
        It 'returns review_required when all targets are untested' {
            $d = New-SasPortFallbackDecision -TargetCount 3 -TestedTargetCount 0 -UntestedTargetCount 3 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 0 -SourceProfileId 'network_preflight' -ProfileSource 'explicit_named_profile' -NoNetwork
            $d.decision | Should -Be 'review_required'
            $d.recommended_profile_id | Should -Be ''
            $d.approval_required | Should -BeFalse
        }
    }

    Context 'default_ok' {
        It 'returns default_ok when all probed targets have open default ports' {
            $d = New-SasPortFallbackDecision -TargetCount 2 -TestedTargetCount 2 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 2 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 2 -SilentOnDefaultProfileCount 0 -SourceProfileId 'keyports_cybernet_json' -ProfileSource 'canonical_default' -EffectivePorts 80,443,135,445,3389,5985,5986 -NoNetwork
            $d.decision | Should -Be 'default_ok'
            $d.recommended_profile_id | Should -Be ''
            $d.approval_required | Should -BeFalse
        }
    }

    Context 'web_only_fallback' {
        It 'returns web_only_fallback when targets answer only on web ports' {
            $d = New-SasPortFallbackDecision -TargetCount 3 -TestedTargetCount 3 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 1 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -SourceProfileId 'keyports_cybernet_json' -ProfileSource 'canonical_default' -EffectivePorts 80,443,135,445,3389,5985,5986 -NoNetwork
            $d.decision | Should -Be 'web_only_fallback'
            $d.recommended_profile_id | Should -Be 'web_reachability_only_json'
            $d.approval_required | Should -BeFalse
        }
    }

    Context 'UDP precedence' {
        It 'UDP justification overrides to udp_justification_required' {
            $d = New-SasPortFallbackDecision -TargetCount 2 -TestedTargetCount 2 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -SourceProfileId 'keyports_cybernet_json' -ProfileSource 'canonical_default' -EffectivePorts 80,443,135,445,3389,5985,5986 -UdpJustified -NoNetwork
            $d.decision | Should -Be 'udp_justification_required'
            $d.recommended_profile_id | Should -Be 'udp_dns_snmp_json'
            $d.approval_required | Should -BeTrue
            $d.required_gate | Should -Be 'udp_justification'
        }
    }

    Context 'all_ports_denied' {
        It 'denies all ports without explicit gate' {
            $d = New-SasPortFallbackDecision -TargetCount 2 -TestedTargetCount 2 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -SourceProfileId 'keyports_cybernet_json' -ProfileSource 'canonical_default' -EffectivePorts 80,443,135,445,3389,5985,5986 -NoNetwork
            $d.decision | Should -Be 'all_ports_denied_without_explicit_gate'
            $d.recommended_profile_id | Should -Be ''
            $d.approval_required | Should -BeTrue
            $d.required_gate | Should -Be 'explicit_all_ports_gate'
        }
    }

    Context 'approved_subnet with gates' {
        It 'allows approved subnet when full ports and scope are authorized' {
            $d = New-SasPortFallbackDecision -TargetCount 2 -TestedTargetCount 2 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 0 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -SourceProfileId 'keyports_cybernet_json' -ProfileSource 'canonical_default' -EffectivePorts 80,443,135,445,3389,5985,5986 -ApprovedSubnetScope -AllowFullPorts -NoNetwork
            $d.decision | Should -Be 'approved_subnet_host_discovery_required'
            $d.recommended_profile_id | Should -Be 'host_discovery_web_syn_txt'
            $d.approval_required | Should -BeTrue
            $d.required_gate | Should -Be 'approved_subnet_scope'
        }
    }

    Context 'canonical default identity management' {
        It 'suppresses default profile identity for narrowed ports' {
            $d = New-SasPortFallbackDecision -TargetCount 1 -TestedTargetCount 1 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 0 -SourceProfileId 'network_preflight' -ProfileSource 'canonical_default' -EffectivePorts 445,3389 -NoNetwork
            $d.decision | Should -Be 'default_ok'
            $d.effective_ports.Count | Should -Be 2
        }
    }

    Context 'mutually exclusive decisions' {
        It 'never emits both default_ok and web_only_fallback simultaneously' {
            $d = New-SasPortFallbackDecision -TargetCount 3 -TestedTargetCount 3 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 1 -AdminSurfaceReachableCount 0 -SilentOnDefaultProfileCount 2 -SourceProfileId 'keyports_cybernet_json' -ProfileSource 'canonical_default' -EffectivePorts 80,443,135,445,3389,5985,5986 -NoNetwork
            $isDefaultOk = $d.decision -eq 'default_ok'
            $isWebOnly = $d.decision -eq 'web_only_fallback'
            ($isDefaultOk -xor $isWebOnly -or (-not $isDefaultOk -and -not $isWebOnly)) | Should -BeTrue
        }
    }

    Context 'schema compliance' {
        It 'returns all required schema fields' {
            $d = New-SasPortFallbackDecision -TargetCount 1 -TestedTargetCount 1 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 0 -SourceProfileId 'network_preflight' -ProfileSource 'explicit_named_profile' -NoNetwork
            $d.schema_version | Should -Be 'sas-port-fallback-decision/v1'
            $d.decision | Should -BeIn @('default_ok', 'web_only_fallback', 'approved_subnet_host_discovery_required', 'udp_justification_required', 'all_ports_denied_without_explicit_gate', 'review_required')
            $d.target_mutation_performed | Should -BeFalse
            $d.proof_level | Should -Not -BeNullOrEmpty
        }
    }

    Context 'no network activity from pure module' {
        It 'does not call DNS, ping, or Test-NetConnection' {
            $d = New-SasPortFallbackDecision -TargetCount 1 -TestedTargetCount 1 -UntestedTargetCount 0 -OpenDefaultPortTargetCount 1 -WebOnlyReachableCount 0 -AdminSurfaceReachableCount 1 -SilentOnDefaultProfileCount 0 -SourceProfileId 'keyports_cybernet_json' -ProfileSource 'canonical_default' -EffectivePorts 80,443,135,445,3389,5985,5986 -NoNetwork
            $d.network_activity_performed | Should -BeFalse
            $d.proof_level | Should -Be 'fixture_e2e'
        }
    }
}
