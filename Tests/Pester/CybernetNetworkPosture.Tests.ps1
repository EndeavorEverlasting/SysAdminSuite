#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Cybernet network posture gate' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:postureScript = Join-Path $repoRoot 'scripts/Test-CybernetNetworkPosture.ps1'
        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-network-posture-' + [guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        $script:configPath = Join-Path $script:tempRoot 'guard.json'
        $script:emptyConfigPath = Join-Path $script:tempRoot 'empty-guard.json'
        $script:networkTextPath = Join-Path $script:tempRoot 'ipconfig.txt'
        @{
            allowedDnsSuffixes = @('wired.example.invalid')
            allowedWindowsDomains = @()
            allowedLocalIpCidrs = @('192.0.2.0/24')
            allowedGatewayCidrs = @('192.0.2.1/32')
            allowedDnsServerCidrs = @('198.51.100.0/24')
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:configPath -Encoding UTF8
        @{
            allowedDnsSuffixes = @()
            allowedWindowsDomains = @()
            allowedLocalIpCidrs = @()
            allowedGatewayCidrs = @()
            allowedDnsServerCidrs = @()
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:emptyConfigPath -Encoding UTF8
        @(
            'Windows IP Configuration'
            'Ethernet adapter Ethernet:'
            '   Connection-specific DNS Suffix  . : wired.example.invalid'
            '   IPv4 Address. . . . . . . . . . . : 192.0.2.25(Preferred)'
            '   Default Gateway . . . . . . . . . : 192.0.2.1'
            '   DNS Servers . . . . . . . . . . . : 198.51.100.10'
        ) | Set-Content -LiteralPath $script:networkTextPath -Encoding UTF8
    }

    AfterAll {
        Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'accepts approved Wi-Fi without target activity' {
        $output = Join-Path $script:tempRoot 'wifi.json'
        $result = & $script:postureScript -Ssid 'NSLIJHS-WAB-Test' -NetworkTextPath $script:networkTextPath -GuardConfigPath $script:configPath -OutputPath $output -NoExitCode
        $result.classification | Should -Be 'OK_NETWORK_POSTURE'
        $result.allowed_for_target_preflight | Should -BeTrue
        $result.network_activity_performed | Should -BeFalse
        $result.target_mutation_performed | Should -BeFalse
        (Get-Content -LiteralPath $output -Raw | ConvertFrom-Json).classification | Should -Be 'OK_NETWORK_POSTURE'
    }

    It 'accepts approved wired evidence without target activity' {
        $output = Join-Path $script:tempRoot 'wired.json'
        $result = & $script:postureScript -Ssid 'unknown' -NetworkTextPath $script:networkTextPath -GuardConfigPath $script:configPath -OutputPath $output -NoExitCode
        $result.classification | Should -Be 'OK_NETWORK_POSTURE'
        $result.wired_approved | Should -BeTrue
    }

    It 'classifies an unapproved Wi-Fi segment without probing targets' {
        $output = Join-Path $script:tempRoot 'guest.json'
        $result = & $script:postureScript -Ssid 'Guest-WiFi' -NetworkTextPath $script:networkTextPath -GuardConfigPath $script:emptyConfigPath -OutputPath $output -NoExitCode
        $result.classification | Should -Be 'ENVIRONMENT_BLOCKED_GUEST_NETWORK'
        $result.allowed_for_target_preflight | Should -BeFalse
        $result.network_activity_performed | Should -BeFalse
    }
}
