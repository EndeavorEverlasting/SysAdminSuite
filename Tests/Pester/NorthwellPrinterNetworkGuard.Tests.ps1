#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:startPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:guardPath = Join-Path $script:repoRoot 'scripts\SasNetworkGuard.psm1'
}

Describe 'Northwell printer VPN network authority contract' {
    It 'gates the canonical printer launcher through the shared network guard before the engine' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match 'scripts\\SasNetworkGuard\.psm1'
        $text | Should -Match 'Import-Module \$guardModule -Force'
        $text | Should -Match 'Assert-SasNorthwellWifi'

        $guard = $text.IndexOf('Assert-SasNorthwellWifi', [StringComparison]::Ordinal)
        $engine = $text.IndexOf('& $engine @invokeParameters', [StringComparison]::Ordinal)
        $guard | Should -BeGreaterThan -1
        $engine | Should -BeGreaterThan $guard
    }

    It 'preserves offline WhatIf planning without weakening live mapping' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match 'if \(-not \$WhatIf\)'
        $text | Should -Match '\$invokeParameters\.WhatIf = \$true'
    }

    It 'uses live DomainAuthenticated non-Wi-Fi authority independent of stale exact IP policy' {
        $text = Get-Content -LiteralPath $script:guardPath -Raw
        $text | Should -Match 'live_domain_authenticated_non_wifi_v1'
        $text | Should -Match 'NetworkCategory.*DomainAuthenticated'
        $text | Should -Match 'Live Windows domain authentication is stronger than the physical uplink label'
        $text | Should -Not -Match 'if \(@\(\$config\.allowedLocalIpCidrs\)\.Count -eq 0\) \{ return \$false \}'
        $text | Should -Not -Match '(?i)Intel.*Ethernet|AnyConnect|GlobalProtect|FortiClient'
    }
}
