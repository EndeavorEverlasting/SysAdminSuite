#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Offline contract tests for the Neuron maintenance snapshot QR task.

.DESCRIPTION
    These tests intentionally avoid live network dependency. They validate the
    script contract, safety posture, and dispatcher registration so the tool can
    move toward field testing without accidentally introducing destructive behavior.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $snapshotPath = Join-Path $repoRoot 'QRTasks\Get-NeuronMaintenanceSnapshot.ps1'
    $dispatcherPath = Join-Path $repoRoot 'QRTasks\Invoke-TechTask.ps1'
    $baselinePath = Join-Path $repoRoot 'Config\Neuron\baselines\default.neuron.json'
    $docPath = Join-Path $repoRoot 'docs\NeuronMaintenanceTools.md'
}

Describe 'Get-NeuronMaintenanceSnapshot.ps1 -- script contract' {
    BeforeAll {
        $script:snapshotContent = Get-Content -Path $snapshotPath -Raw
    }

    It 'Script file exists' {
        $snapshotPath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($snapshotPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Defaults to read-only collection' {
        $script:snapshotContent | Should -Match 'ReadOnlyDefault\s*=\s*\$true'
        $script:snapshotContent | Should -Match '\[switch\]\$ReleaseRenew'
        $script:snapshotContent | Should -Match '\[switch\]\$AllowNetworkReset'
    }

    It 'Blocks release/renew unless AllowNetworkReset is supplied' {
        $script:snapshotContent | Should -Match 'if\s*\(\$ReleaseRenew\)'
        $script:snapshotContent | Should -Match 'if\s*\(-not\s+\$AllowNetworkReset\)'
        $script:snapshotContent | Should -Match 'Release/Renew was requested, but -AllowNetworkReset was not supplied'
    }

    It 'Captures the main maintenance-console inspired sections' {
        foreach ($section in @(
            'Host Identity',
            'Ping Checks: Server / Follower / VPN',
            'IP Configuration',
            'Routes',
            'Selected Service Checks',
            'All Services',
            'Firewall Profiles',
            'NetStat',
            'Wireless Profiles',
            'Wireless Interfaces',
            'Wireless Networks'
        )) {
            $script:snapshotContent | Should -Match [regex]::Escape($section)
        }
    }

    It 'Writes text and JSON artifacts' {
        $script:snapshotContent | Should -Match 'Set-Content\s+-LiteralPath\s+\$textPath'
        $script:snapshotContent | Should -Match 'ConvertTo-Json\s+-Depth\s+8'
        $script:snapshotContent | Should -Match 'Set-Content\s+-LiteralPath\s+\$jsonPath'
    }

    It 'Keeps optional network scan behind IncludeNetworkScan' {
        $script:snapshotContent | Should -Match '\[switch\]\$IncludeNetworkScan'
        $script:snapshotContent | Should -Match 'if\s*\(\$IncludeNetworkScan\)'
        $script:snapshotContent | Should -Match 'arp -a'
    }
}

Describe 'QR task dispatcher registration -- NeuronMaintenance' {
    BeforeAll {
        $script:dispatcherContent = Get-Content -Path $dispatcherPath -Raw
    }

    It 'Registers the NeuronMaintenance task name' {
        $script:dispatcherContent | Should -Match 'NeuronMaintenance\s*=\s*''Get-NeuronMaintenanceSnapshot\.ps1'''
    }

    It 'Keeps QR payload design as pointer, not embedded script' {
        $script:dispatcherContent | Should -Match 'QR = pointer, not payload'
        $script:dispatcherContent | Should -Match 'TaskTimeoutSec'
    }
}

Describe 'Neuron maintenance baseline and documentation' {
    It 'Baseline config exists' {
        $baselinePath | Should -Exist
    }

    It 'Baseline config is valid JSON' {
        { Get-Content -Path $baselinePath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Documentation exists' {
        $docPath | Should -Exist
    }

    It 'Documentation includes survey and remote emulation intent' {
        $doc = Get-Content -Path $docPath -Raw
        $doc | Should -Match 'survey'
        $doc | Should -Match 'remote'
        $doc | Should -Match 'maintenance'
    }
}
