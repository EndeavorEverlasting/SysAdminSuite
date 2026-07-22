#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Canonical target-name resolution' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'scripts/SasTargetNameResolution.psm1'
        Import-Module $script:modulePath -Force
    }

    AfterAll {
        Remove-Module SasTargetNameResolution -ErrorAction SilentlyContinue
    }

    It 'resolves a short hostname to one canonical FQDN' {
        $resolver = {
            param($Name)
            if ($Name -in @('CYBERNET-TEST-01', 'CYBERNET-TEST-01.example.test')) {
                [pscustomobject]@{
                    canonical_name = 'CYBERNET-TEST-01.example.test'
                    addresses = @('192.0.2.10')
                }
            }
        }
        $result = Resolve-SasCanonicalTargetFqdn `
            -TargetName 'CYBERNET-TEST-01' `
            -SuffixCandidates @('example.test') `
            -DnsResolver $resolver

        $result.fqdn | Should -Be 'cybernet-test-01.example.test'
        $result.disposition | Should -Be 'UNIQUE_CANONICAL_FQDN'
        $result.addresses | Should -Contain '192.0.2.10'
    }

    It 'fails closed when one short hostname maps to multiple canonical FQDNs' {
        $resolver = {
            param($Name)
            if ($Name -eq 'CYBERNET-TEST-01.alpha.test') {
                return [pscustomobject]@{ canonical_name = $Name; addresses = @('192.0.2.10') }
            }
            if ($Name -eq 'CYBERNET-TEST-01.beta.test') {
                return [pscustomobject]@{ canonical_name = $Name; addresses = @('192.0.2.11') }
            }
        }
        {
            Resolve-SasCanonicalTargetFqdn `
                -TargetName 'CYBERNET-TEST-01' `
                -SuffixCandidates @('alpha.test', 'beta.test') `
                -DnsResolver $resolver
        } | Should -Throw '*multiple canonical FQDNs*'
    }

    It 'fails closed when DNS canonicalizes to a different host label' {
        $resolver = {
            param($Name)
            [pscustomobject]@{
                canonical_name = 'DIFFERENT-HOST.example.test'
                addresses = @('192.0.2.10')
            }
        }
        {
            Resolve-SasCanonicalTargetFqdn `
                -TargetName 'CYBERNET-TEST-01' `
                -SuffixCandidates @('example.test') `
                -DnsResolver $resolver
        } | Should -Throw '*different canonical host identity*'
    }

    It 'rejects malformed host input before DNS lookup' {
        { Resolve-SasCanonicalTargetFqdn -TargetName 'bad host name' -DnsResolver { } } |
            Should -Throw '*valid short hostname*'
    }
}
