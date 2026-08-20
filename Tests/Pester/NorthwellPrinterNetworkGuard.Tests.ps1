#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:startPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:batchPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterBatch.ps1'
    $script:undoPath = Join-Path $script:repoRoot 'mapping\Undo-NorthwellPrinterChange.ps1'
    $script:guardPath = Join-Path $script:repoRoot 'scripts\SasNetworkGuard.psm1'
    $script:authorityPath = Join-Path $script:repoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
}

Describe 'Northwell printer protected-network authority contract' {
    It 'routes quick, batch, and undo through the shared authority facade before live engine work' {
        foreach ($path in @($script:startPath,$script:batchPath,$script:undoPath)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Match 'scripts\\SasNorthwellNetworkAuthority\.psm1'
            $text | Should -Match 'Import-Module \$authorityModule -Force'
            $text | Should -Match 'Assert-SasNorthwellNetwork'
        }

        $quick = Get-Content -LiteralPath $script:startPath -Raw
        $guard = $quick.IndexOf('Assert-SasNorthwellNetwork',[StringComparison]::Ordinal)
        $engine = $quick.IndexOf('& $engine @invokeParameters',[StringComparison]::Ordinal)
        $guard | Should -BeGreaterThan -1
        $engine | Should -BeGreaterThan $guard
    }

    It 'preserves offline quick WhatIf planning without weakening live management' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match 'if \(-not \$WhatIf\)'
        $text | Should -Match '\$invokeParameters\.WhatIf = \$true'
    }

    It 'keeps live DomainAuthenticated non-Wi-Fi authority independent of stale exact IP policy' {
        $text = Get-Content -LiteralPath $script:guardPath -Raw
        $text | Should -Match 'live_domain_authenticated_non_wifi_v1'
        $text | Should -Match 'NetworkCategory.*DomainAuthenticated'
        $text | Should -Match 'Live Windows domain authentication is stronger than the physical uplink label'
        $text | Should -Not -Match 'if \(@\(\$config\.allowedLocalIpCidrs\)\.Count -eq 0\) \{ return \$false \}'
    }

    It 'makes WAB and protected non-Wi-Fi routes explicit without duplicating admission policy' {
        $text = Get-Content -LiteralPath $script:authorityPath -Raw
        $text | Should -Match 'Import-Module \$guardPath -Force'
        $text | Should -Match "Route = 'WAB_WIFI'"
        $text | Should -Match "Route = 'DOMAIN_AUTHENTICATED_NON_WIFI'"
        $text | Should -Match 'Test-SasNorthwellWiredEvidence'
        $text | Should -Match 'hardwire/LAN'
        $text | Should -Match 'authenticated VPN'
        $text | Should -Not -Match 'GlobalProtect|AnyConnect|FortiClient|Palo Alto'
    }

    It 'classifies synthetic WAB, hardwire, and product-agnostic VPN fixtures' {
        $oldConfig = $env:SAS_NETWORK_GUARD_CONFIG
        try {
            $env:SAS_NETWORK_GUARD_CONFIG = Join-Path ([System.IO.Path]::GetTempPath()) 'sas-network-guard-nonexistent.json'
            Import-Module $script:authorityPath -Force

            $wab = Get-SasNorthwellNetworkAuthority -Ssid 'NSLIJHS-WAB-TEST' -NetworkText '' -ConnectionProfiles @()
            $wab.Allowed | Should -BeTrue
            $wab.Route | Should -Be 'WAB_WIFI'

            foreach ($alias in @('Ethernet 4','Corporate Tunnel Adapter')) {
                $profile = [pscustomobject]@{
                    InterfaceAlias=$alias
                    NetworkCategory='DomainAuthenticated'
                    IPv4Connectivity='Internet'
                    IPv6Connectivity='NoTraffic'
                    InterfaceIndex=8
                }
                $resolver = { param($index) @([pscustomobject]@{ IPAddress='10.20.30.40' }) }
                $authority = Get-SasNorthwellNetworkAuthority -Ssid 'Guest-WiFi' -NetworkText '' -ConnectionProfiles @($profile) -AddressResolver $resolver
                $authority.Allowed | Should -BeTrue
                $authority.Route | Should -Be 'DOMAIN_AUTHENTICATED_NON_WIFI'
            }
        }
        finally {
            $env:SAS_NETWORK_GUARD_CONFIG = $oldConfig
        }
    }
}
