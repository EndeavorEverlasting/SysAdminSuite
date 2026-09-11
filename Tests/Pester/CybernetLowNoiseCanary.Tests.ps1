#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:probeCmd = Join-Path $script:repoRoot 'Probe-Cybernet.cmd'
    $script:canary = Join-Path $script:repoRoot 'survey\sas-cybernet-canary.ps1'
    $script:filter = Join-Path $script:repoRoot 'survey\sas-filter-windows-pc-signature.py'
    $script:signatureRunner = Join-Path $script:repoRoot 'survey\sas-run-windows-pc-signature.sh'
    $script:profiles = Join-Path $script:repoRoot 'survey\naabu_profiles.json'
    $script:runtimeProfiles = Join-Path $script:repoRoot 'Config\cybernet-naabu-profiles.json'
    $script:refresh = Join-Path $script:repoRoot 'scripts\Refresh-SasOperatorCommand.ps1'
    $script:networkGuard = Join-Path $script:repoRoot 'scripts\SasNetworkGuard.psm1'
    $script:docs = Join-Path $script:repoRoot 'docs\CYBERNET_LOW_NOISE_CANARY.md'
    $script:identifierPolicy = Join-Path $script:repoRoot 'docs\CYBERNET_IDENTIFIER_POLICY.md'
    $script:startHere = Join-Path $script:repoRoot 'START-HERE-CYBERNET-NEURON-SURVEY.md'
    $script:workflow = Join-Path $script:repoRoot '.github\workflows\cybernet-low-noise-canary.yml'
}

Describe 'Cybernet low-noise CMD identity probe' {
    It 'ships the CMD-first technician front door' {
        $script:probeCmd | Should -Exist
        $cmd = Get-Content -LiteralPath $script:probeCmd -Raw
        $cmd | Should -Match 'Question: Is each explicit candidate a Windows client workstation'
        $cmd | Should -Match 'model \+ serial for approved Cybernet-reference comparison'
        $cmd | Should -Match '135 \+ 445 open\s+= metadata candidate only'
        $cmd | Should -Match 'ProductType = 1\s+= Windows client workstation only'
        $cmd | Should -Match 'Cybernet confirmed\s+= only after approved reference comparison'
        $cmd | Should -Match 'Usage: Probe-Cybernet\.cmd HOST01'
    }

    It 'refreshes current main before any canary target contact and re-enters the sealed CMD' {
        $cmd = Get-Content -LiteralPath $script:probeCmd -Raw
        $refresh = $cmd.IndexOf('Invoke-SasNetworkAwareField.ps1" refresh')
        $reentry = $cmd.IndexOf('call "C:\SASAL\Probe-Cybernet.cmd"')
        $canary = $cmd.IndexOf('survey\sas-cybernet-canary.ps1" %*')
        $refresh | Should -BeGreaterThan -1
        $reentry | Should -BeGreaterThan $refresh
        $canary | Should -BeGreaterThan $reentry
        $cmd | Should -Match 'SAS_CYBERNET_PROBE_REFRESHED=1'
        $cmd | Should -Match 'set "SAS_EXIT=!ERRORLEVEL!"'
        $cmd | Should -Match 'endlocal & exit /b %SAS_EXIT%'
        $cmd | Should -Not -Match '(?i)git\s+(pull|fetch|reset|checkout)'
    }

    It 'uses the repository-owned refresh transaction rather than Git in the caller worktree' {
        $refresh = Get-Content -LiteralPath $script:refresh -Raw
        $refresh | Should -Match ([regex]::Escape('$operatorStateRoot = Join-Path $env:LOCALAPPDATA ''SysAdminSuite'''))
        $refresh | Should -Match ([regex]::Escape('$syncCache = Join-Path $operatorStateRoot ''sync-cache'''))
        $refresh | Should -Match ([regex]::Escape('$preferredFieldReady = Join-Path $operatorStateRoot ''field-ready'''))
        $refresh | Should -Match "@\('fetch','--no-tags','--prune','origin'"
        $refresh | Should -Match 'origin/\$refreshBranch'
        $refresh | Should -Match 'No target contact or target mutation occurs in this script\.'
        $refresh | Should -Match 'GUEST_INTERNET'
    }

    It 'hard-caps explicit canary scope and refuses broad target syntax' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match ([regex]::Escape('$MaxTargets = 5'))
        $content | Should -Match 'CYBERNET_CANARY_SCOPE_EXCEEDED'
        $content | Should -Match 'CIDRs, ranges, wildcards, and subnet discovery are refused'
        $content | Should -Not -Match 'nmap\s+-s'
        $content | Should -Not -Match 'naabu'
    }

    It 'reuses only completed evidence with every field the reuse path reads' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        foreach ($marker in @(
            'ReuseWithinHours = 24',
            'cybernet_canary_complete.json',
            'result_sha256',
            'Get-FileHash',
            'ObservationTimestamp',
            "'Port135','Port445'",
            "'PcSignatureStatus','WorkstationStatus','ObservedOperatingSystem'",
            'FreshLocalReuse',
            'NetworkActivityPerformed = $false'
        )) {
            $content | Should -Match ([regex]::Escape($marker))
        }
    }

    It 'requires the minimal dual-port PC signature before a CIM session' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match ([regex]::Escape("-Ports @(135,445) -PolicyProfile 'network_preflight'"))
        $content | Should -Match ([regex]::Escape('$port135 -eq ''Open'' -and $port445 -eq ''Open'''))
        $signature = $content.IndexOf('$pcSignatureStatus -eq ''WINDOWS_PC_SIGNATURE_MATCH''')
        $session = $content.IndexOf('New-CimSession -ComputerName $identityEndpoint')
        $signature | Should -BeGreaterThan -1
        $session | Should -BeGreaterThan $signature
        $content | Should -Not -Match '-Credential'
        foreach ($port in @('9100','5985','5986')) { $content | Should -Not -Match $port }
    }

    It 'proves Windows client class before hardware metadata and fails closed on no OS instance' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $os = $content.IndexOf('Win32_OperatingSystem')
        $productType = $content.IndexOf('ProductType')
        $computer = $content.IndexOf('Win32_ComputerSystem')
        $bios = $content.IndexOf('Win32_BIOS')
        $os | Should -BeGreaterThan -1
        $productType | Should -BeGreaterThan $os
        $computer | Should -BeGreaterThan $productType
        $bios | Should -BeGreaterThan $computer
        $content | Should -Match ([regex]::Escape('if ([int]$os.ProductType -eq 1)'))
        $content | Should -Match 'WINDOWS_CLIENT_WORKSTATION_CONFIRMED'
        $content | Should -Match 'NON_WORKSTATION_OS_METADATA_SKIPPED'
        $content | Should -Match 'Win32_OperatingSystem returned no instance'
        $content | Should -Match 'WORKSTATION_CLASS_UNRESOLVED_METADATA_SKIPPED'
    }

    It 'retains partial hardware evidence and never classifies Cybernet directly' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match 'Manufacturer,Model'
        $content | Should -Match 'SerialNumber'
        $content | Should -Match 'IDENTITY_PARTIAL'
        $content | Should -Match 'ObservedModel'
        $content | Should -Match 'ObservedSerial'
        $content | Should -Not -Match 'CONFIRMED_CYBERNET'
    }

    It 'ships a local-only dual-port filter and zero-retry bounded signature profile' {
        $script:filter | Should -Exist
        $script:signatureRunner | Should -Exist
        $filter = Get-Content -LiteralPath $script:filter -Raw
        $runner = Get-Content -LiteralPath $script:signatureRunner -Raw
        $filter | Should -Match ([regex]::Escape('REQUIRED_PORTS = {135, 445}'))
        $filter | Should -Match 'looks_json'
        $filter | Should -Match 'performs no network activity'
        $runner | Should -Match ([regex]::Escape('args=(-list "$LIST" -p "$ports" -silent -ec'))
        $runner | Should -Match ([regex]::Escape('-retries "$retries"'))
        $runner | Should -Match ([regex]::Escape('-rate "$rate"'))
        $runner | Should -Match 'Metadata collection: NONE'

        $doctrine = Get-Content -LiteralPath $script:profiles -Raw | ConvertFrom-Json
        $runtime = Get-Content -LiteralPath $script:runtimeProfiles -Raw | ConvertFrom-Json
        $doctrine.profiles.windows_pc_signature_json.ports | Should -Be '135,445'
        $doctrine.profiles.windows_pc_signature_json.retries | Should -Be 0
        $doctrine.profiles.windows_pc_signature_json.defaultRate | Should -Be 50
        $doctrine.profiles.windows_pc_signature_json.pipelineFollowup | Should -BeFalse
        $runtime.profiles.windows_pc_signature_json.ports | Should -Be '135,445'
        $runtime.profiles.windows_pc_signature_json.retries | Should -Be 0
        $runtime.profiles.windows_pc_signature_json.defaultRate | Should -Be 50
        $runtime.profiles.windows_pc_signature_json.pipelineFollowup | Should -BeFalse
    }

    It 'accepts approved WAB or DomainAuthenticated non-Wi-Fi protected posture' {
        $guard = Get-Content -LiteralPath $script:networkGuard -Raw
        $guard | Should -Match 'NSLIJHS-WAB'
        $guard | Should -Match 'DomainAuthenticated'
        $guard | Should -Match 'non-Wi-Fi VPN/LAN'
        $guard | Should -Match 'Assert-SasNorthwellWifi'
    }

    It 'documents CMD as the primary identity route without lowering the proof ceiling' {
        foreach ($path in @($script:docs,$script:startHere)) {
            $body = Get-Content -LiteralPath $path -Raw
            $body | Should -Match 'Probe-Cybernet\.cmd'
            $body | Should -Match 'approved Cybernet hardware reference'
            $body | Should -Match 'ProductType=1|ProductType = 1'
        }
        $policy = Get-Content -LiteralPath $script:identifierPolicy -Raw
        $policy | Should -Match 'population-first, signature-gated, and hardware-confirmed'
        $policy | Should -Not -Match 'Use Nmap-derived evidence as the primary identity source'
    }

    It 'reruns focused CI when the CMD or any direct probe owner changes' {
        $workflow = Get-Content -LiteralPath $script:workflow -Raw
        foreach ($marker in @(
            'Probe-Cybernet.cmd',
            'survey/sas-cybernet-canary.ps1',
            'survey/sas-network-preflight.ps1',
            'scripts/Refresh-SasOperatorCommand.ps1',
            'scripts/SasNetworkGuard.psm1',
            'Tests/survey/test_cybernet_probe_cmd_contracts.py',
            'START-HERE-CYBERNET-NEURON-SURVEY.md',
            'docs/CYBERNET_LOW_NOISE_CANARY.md'
        )) {
            $workflow | Should -Match ([regex]::Escape($marker))
        }
        $workflow | Should -Match 'python Tests/survey/test_cybernet_probe_cmd_contracts.py'
        $workflow | Should -Match 'sas-generate-naabu-runtime-profiles.sh --check'
        $workflow | Should -Match 'test_windows_pc_signature_filter.py'
        $workflow | Should -Match 'git diff --check'
    }
}
