#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:canary = Join-Path $script:repoRoot 'survey\sas-cybernet-canary.ps1'
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

    It 'reuses only completed fresh attempts and preserves original observation time' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match 'ReuseWithinHours = 24'
        $content | Should -Match 'Get-SasFreshCanaryEvidence'
        $content | Should -Match 'cybernet_canary_complete.json'
        $content | Should -Match 'result_sha256'
        $content | Should -Match 'Get-FileHash'
        $content | Should -Match 'ObservationTimestamp'
        $content | Should -Match ([regex]::Escape('ObservationTimestamp = [string]$fresh.ObservationTimestamp'))
        $content | Should -Match ([regex]::Escape('IdentityStatus = [string]$fresh.IdentityStatus'))
        $content | Should -Match 'FreshLocalReuse'
        $content | Should -Match 'NetworkActivityPerformed = \$false'
    }

    It 'narrows canonical preflight to TCP 135 and pins CIM to that resolved endpoint' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match ([regex]::Escape("'survey\sas-network-preflight.ps1'"))
        $content | Should -Match ([regex]::Escape("-Ports @(135) -PolicyProfile 'network_preflight'"))
        $content | Should -Not -Match '-Ports @\(135, 445\)'
        $content | Should -Match ([regex]::Escape("if ($port135 -eq 'Open')"))
        $content | Should -Match ([regex]::Escape('$identityEndpoint = if (-not [string]::IsNullOrWhiteSpace($resolved)) { $resolved } else { $candidate }'))
        $content | Should -Match ([regex]::Escape('New-CimSession -ComputerName $identityEndpoint'))
        $content | Should -Not -Match '-Credential'
    }

    It 'retains model evidence when the serial query fails and never classifies Cybernet directly' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match 'Win32_ComputerSystem'
        $content | Should -Match 'Manufacturer,Model'
        $content | Should -Match 'Win32_BIOS'
        $content | Should -Match 'IDENTITY_PARTIAL'
        $content | Should -Match 'Partial hardware identity was retained'
        $content | Should -Match 'ObservedModel'
        $content | Should -Match 'ObservedSerial'
        $content | Should -Not -Match 'CONFIRMED_CYBERNET'
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
        foreach ($marker in @('survey/sas-network-preflight.ps1','scripts/Invoke-SasNetworkAwareField.ps1','Config/low-noise-policy.json','scripts/SasLowNoisePolicy.psm1')) {
            $workflow | Should -Match ([regex]::Escape($marker))
        }
        $workflow | Should -Match 'permissions:\s*\r?\n\s*contents: read'
        $workflow | Should -Match "github.event_name == 'pull_request'"
        $workflow | Should -Match "github.event_name == 'workflow_dispatch'"
        $workflow | Should -Match ([regex]::Escape('BASE_REF: ${{ github.base_ref }}'))
        $workflow | Should -Match ([regex]::Escape('git diff --check "origin/$BASE_REF...HEAD"'))
        $workflow | Should -Not -Match ([regex]::Escape('origin/${{ github.base_ref }}'))
        $workflow | Should -Match 'HEAD\^\.\.HEAD'
    }

    It 'names Windows PowerShell as the operator terminal and rejects stealth claims' {
        $docs = Get-Content -LiteralPath $script:docs -Raw
        $docs | Should -Match 'Operator terminal: \*\*Windows PowerShell\*\*\.'
        $docs | Should -Match 'sas cybernet canary HOST01 HOST02'
        $docs | Should -Match 'not a stealth feature'
        $docs | Should -Match 'does not guarantee that monitoring will not alert'
    }
}
