#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:canary = Join-Path $script:repoRoot 'survey\sas-cybernet-canary.ps1'
    $script:filter = Join-Path $script:repoRoot 'survey\sas-filter-windows-pc-signature.py'
    $script:profiles = Join-Path $script:repoRoot 'survey\naabu_profiles.json'
    $script:runtimeProfiles = Join-Path $script:repoRoot 'Config\cybernet-naabu-profiles.json'
    $script:launcher = Join-Path $script:repoRoot 'scripts\Invoke-SasUniversalField.ps1'
    $script:networkAware = Join-Path $script:repoRoot 'scripts\Invoke-SasNetworkAwareField.ps1'
    $script:installer = Join-Path $script:repoRoot 'scripts\Install-SasUniversalFieldLauncher.ps1'
    $script:docs = Join-Path $script:repoRoot 'docs\CYBERNET_LOW_NOISE_CANARY.md'
    $script:workflow = Join-Path $script:repoRoot '.github\workflows\cybernet-low-noise-canary.yml'
}

Describe 'Cybernet low-noise identity canary' {
    It 'keeps all PowerShell entrypoints parseable' {
        foreach ($path in @($script:canary, $script:launcher, $script:networkAware, $script:installer)) {
            $path | Should -Exist
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    It 'hard-caps explicit scope and refuses broad target syntax' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match ([regex]::Escape('$MaxTargets = 5'))
        $content | Should -Match 'CYBERNET_CANARY_SCOPE_EXCEEDED'
        $content | Should -Match 'CIDRs, ranges, wildcards, and subnet discovery are refused'
        $content | Should -Match ([regex]::Escape('$candidate -match ''[/*?\[\]]'''))
        $content | Should -Not -Match 'nmap\s+-s'
        $content | Should -Not -Match 'naabu'
    }

    It 'reuses only completed evidence from the current dual-port schema' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match 'ReuseWithinHours = 24'
        $content | Should -Match 'Get-SasFreshCanaryEvidence'
        $content | Should -Match 'cybernet_canary_complete.json'
        $content | Should -Match 'result_sha256'
        $content | Should -Match 'Get-FileHash'
        $content | Should -Match 'ObservationTimestamp'
        $content | Should -Match ([regex]::Escape("$row.PSObject.Properties['Port445']"))
        $content | Should -Match ([regex]::Escape("$row.PSObject.Properties['PcSignatureStatus']"))
        $content | Should -Match ([regex]::Escape('ObservationTimestamp = [string]$fresh.ObservationTimestamp'))
        $content | Should -Match 'FreshLocalReuse'
        $content | Should -Match 'NetworkActivityPerformed = \$false'
    }

    It 'requires the minimal dual-port PC signature before any CIM session' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match ([regex]::Escape("'survey\sas-network-preflight.ps1'"))
        $content | Should -Match ([regex]::Escape("-Ports @(135,445) -PolicyProfile 'network_preflight'"))
        $content | Should -Match ([regex]::Escape("$port135 -eq 'Open' -and $port445 -eq 'Open'"))
        $content | Should -Match 'WINDOWS_PC_SIGNATURE_MATCH'
        $content | Should -Match 'WINDOWS_PC_SIGNATURE_NOT_MATCHED'
        $signature = $content.IndexOf("$pcSignatureStatus -eq 'WINDOWS_PC_SIGNATURE_MATCH'")
        $session = $content.IndexOf('New-CimSession -ComputerName $identityEndpoint')
        $signature | Should -BeGreaterThan -1
        $session | Should -BeGreaterThan $signature
        $content | Should -Not -Match '-Credential'
        $content | Should -Not -Match '9100'
        $content | Should -Not -Match '5985'
        $content | Should -Not -Match '5986'
    }

    It 'proves Windows client workstation class before hardware metadata' {
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
        $content | Should -Match 'WORKSTATION_CLASS_UNRESOLVED_METADATA_SKIPPED'
        $content | Should -Match 'manufacturer/model/serial queries were skipped'
    }

    It 'retains partial workstation hardware evidence and never classifies Cybernet directly' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match 'Manufacturer,Model'
        $content | Should -Match 'SerialNumber'
        $content | Should -Match 'IDENTITY_PARTIAL'
        $content | Should -Match 'Partial hardware identity was retained'
        $content | Should -Match 'ObservedModel'
        $content | Should -Match 'ObservedSerial'
        $content | Should -Not -Match 'CONFIRMED_CYBERNET'
    }

    It 'ships a local-only two-port scanner evidence filter and matching generated profile' {
        $script:filter | Should -Exist
        $filter = Get-Content -LiteralPath $script:filter -Raw
        $filter | Should -Match ([regex]::Escape('REQUIRED_PORTS = {135, 445}'))
        $filter | Should -Match 'performs no network activity'

        $doctrine = Get-Content -LiteralPath $script:profiles -Raw | ConvertFrom-Json
        $runtime = Get-Content -LiteralPath $script:runtimeProfiles -Raw | ConvertFrom-Json
        $doctrine.profiles.windows_pc_signature_json.ports | Should -Be '135,445'
        $doctrine.profiles.windows_pc_signature_json.pipelineFollowup | Should -BeFalse
        $runtime.profiles.windows_pc_signature_json.ports | Should -Be '135,445'
        $runtime.profiles.windows_pc_signature_json.outputFormat | Should -Be 'json'
        $runtime.profiles.windows_pc_signature_json.pipelineFollowup | Should -BeFalse
    }

    It 'validates the canary shape before any network transition and uses the protected mutex' {
        $networkAware = Get-Content -LiteralPath $script:networkAware -Raw
        $networkAware | Should -Match 'Test-SasCybernetShapeForNetworkTransition'
        $networkAware | Should -Match 'Test-SasCanaryTargetForNetworkTransition'
        $networkAware | Should -Match ([regex]::Escape('$values.Count -gt 6'))
        $networkAware | Should -Match ([regex]::Escape("if ($mode -eq 'canary')"))
        $networkAware | Should -Match 'Global\\SysAdminSuite.NetworkIntent.v1'
    }

    It 'routes through the cwd-independent universal front door and guards stale runtimes' {
        $launcher = Get-Content -LiteralPath $script:launcher -Raw
        $installer = Get-Content -LiteralPath $script:installer -Raw
        $launcher | Should -Match ([regex]::Escape('sas cybernet canary HOST01 HOST02 ...'))
        $launcher | Should -Match ([regex]::Escape('Join-Path $controllerRoot ''survey\sas-cybernet-canary.ps1'''))
        $installer | Should -Match ([regex]::Escape("'survey\sas-cybernet-canary.ps1'"))
        $installer | Should -Match 'sourceCanaryHash'
        $installer | Should -Match 'canonicalCanaryHash'
        $installer | Should -Match 'MACHINE_RUNTIME_REFRESH_REQUIRED'
    }

    It 'reruns when directly owned dependencies change and hardens whitespace validation' {
        $workflow = Get-Content -LiteralPath $script:workflow -Raw
        foreach ($marker in @(
            'survey/sas-network-preflight.ps1',
            'scripts/Invoke-SasNetworkAwareField.ps1',
            'Config/low-noise-policy.json',
            'scripts/SasLowNoisePolicy.psm1',
            'survey/naabu_profiles.json',
            'Config/cybernet-naabu-profiles.json',
            'survey/sas-filter-windows-pc-signature.py',
            'Tests/survey/test_windows_pc_signature_filter.py'
        )) {
            $workflow | Should -Match ([regex]::Escape($marker))
        }
        $workflow | Should -Match 'permissions:\s*\r?\n\s*contents: read'
        $workflow | Should -Match "github.event_name == 'pull_request'"
        $workflow | Should -Match "github.event_name == 'workflow_dispatch'"
        $workflow | Should -Match ([regex]::Escape('BASE_REF: ${{ github.base_ref }}'))
        $workflow | Should -Match ([regex]::Escape('git diff --check "origin/$BASE_REF...HEAD"'))
        $workflow | Should -Not -Match ([regex]::Escape('origin/${{ github.base_ref }}'))
        $workflow | Should -Match 'HEAD\^\.\.HEAD'
        $workflow | Should -Match 'sas-generate-naabu-runtime-profiles.sh --check'
        $workflow | Should -Match 'test_windows_pc_signature_filter.py'
    }

    It 'documents a professional staged funnel without live identifiers or stealth claims' {
        $docs = Get-Content -LiteralPath $script:docs -Raw
        $docs | Should -Match 'Operator terminal: \*\*Windows PowerShell\*\*\.'
        $docs | Should -Match 'sas cybernet canary HOST01 HOST02'
        $docs | Should -Match 'windows_pc_signature_json'
        $docs | Should -Match 'sas-filter-windows-pc-signature.py'
        $docs | Should -Match '135.*445'
        $docs | Should -Match 'ProductType.*1'
        $docs | Should -Match 'printers'
        $docs | Should -Match 'access points'
        $docs | Should -Match 'not a stealth feature'
        $docs | Should -Match 'does not guarantee that monitoring will not alert'
        $docs | Should -Not -Match 'WNH\d+OPR\d+'
        $docs | Should -Not -Match 'WPJ\d+OPR\d+'
    }
}
