#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:canary = Join-Path $script:repoRoot 'survey\sas-cybernet-canary.ps1'
    $script:launcher = Join-Path $script:repoRoot 'scripts\Invoke-SasUniversalField.ps1'
    $script:installer = Join-Path $script:repoRoot 'scripts\Install-SasUniversalFieldLauncher.ps1'
    $script:docs = Join-Path $script:repoRoot 'docs\CYBERNET_LOW_NOISE_CANARY.md'
}

Describe 'Cybernet low-noise identity canary' {
    It 'keeps all PowerShell entrypoints parseable' {
        foreach ($path in @($script:canary, $script:launcher, $script:installer)) {
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

    It 'reuses fresh complete identity evidence before any live probe' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match 'ReuseWithinHours = 24'
        $content | Should -Match 'FreshLocalReuse'
        $content | Should -Match 'NetworkActivityPerformed = \$false'
        $content | Should -Match 'Reused complete identity evidence'
    }

    It 'uses only the canonical 135 and 445 preflight subset and one earned DCOM identity session' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match ([regex]::Escape("'survey\sas-network-preflight.ps1'"))
        $content | Should -Match ([regex]::Escape("-Ports @(135, 445) -PolicyProfile 'network_preflight'"))
        $content | Should -Match ([regex]::Escape('if ($port135 -eq ''Open'')'))
        $content | Should -Match ([regex]::Escape('New-CimSessionOption -Protocol Dcom'))
        $content | Should -Match 'no retry performed'
        $content | Should -Not -Match '-Credential'
    }

    It 'collects both model and serial without promoting them directly to Cybernet classification' {
        $content = Get-Content -LiteralPath $script:canary -Raw
        $content | Should -Match 'Win32_ComputerSystem'
        $content | Should -Match 'Manufacturer,Model'
        $content | Should -Match 'Win32_BIOS'
        $content | Should -Match 'SerialNumber'
        $content | Should -Match 'ObservedModel'
        $content | Should -Match 'ObservedSerial'
        $content | Should -Not -Match 'CONFIRMED_CYBERNET'
    }

    It 'routes through the cwd-independent sas front door and guards stale runtimes' {
        $launcher = Get-Content -LiteralPath $script:launcher -Raw
        $installer = Get-Content -LiteralPath $script:installer -Raw
        $launcher | Should -Match ([regex]::Escape('sas cybernet canary HOST01 HOST02 ...'))
        $launcher | Should -Match ([regex]::Escape('Join-Path $controllerRoot ''survey\sas-cybernet-canary.ps1'''))
        $launcher | Should -Match 'Cybernet low-noise canary for'
        $installer | Should -Match ([regex]::Escape("'survey\sas-cybernet-canary.ps1'"))
        $installer | Should -Match 'MACHINE_RUNTIME_REFRESH_REQUIRED'
    }

    It 'names Windows PowerShell as the operator terminal and rejects stealth claims' {
        $docs = Get-Content -LiteralPath $script:docs -Raw
        $docs | Should -Match 'Operator terminal: \*\*Windows PowerShell\*\*'
        $docs | Should -Match 'sas cybernet canary HOST01 HOST02'
        $docs | Should -Match 'not a stealth feature'
        $docs | Should -Match 'does not guarantee that monitoring will not alert'
    }
}
