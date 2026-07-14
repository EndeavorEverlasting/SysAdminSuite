#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scannerPath = Join-Path $script:repoRoot 'scripts\Get-SasLocalPackageInventory.ps1'
    $script:schemaPath = Join-Path $script:repoRoot 'schemas\harness\local-package-inventory.schema.json'
    $script:fixturePath = Join-Path $script:repoRoot 'Tests\Fixtures\local-package-inventory.fixture.json'
}

Describe 'Local Package Inventory Evidence Floor' {
    It 'parses cleanly' {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($script:scannerPath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'contains no installer or remote-execution primitive' {
        $content = Get-Content -LiteralPath $script:scannerPath -Raw
        $content | Should -Not -Match '(?i)\bStart-Process\b'
        $content | Should -Not -Match '(?i)\bInvoke-Expression\b'
        $content | Should -Not -Match '(?i)\bInvoke-Command\b'
        $content | Should -Not -Match '(?i)\bmsiexec(?:\.exe)?\b'
    }

    It 'requires an explicit scan root outside fixture mode' {
        { & $script:scannerPath } | Should -Throw '*ScanPath is required*'
    }

    It 'does not assign a machine-local default scan path' {
        $content = Get-Content -LiteralPath $script:scannerPath -Raw
        $content | Should -Not -Match '(?m)\[string\]\$ScanPath\s*='
    }

    It 'does not promote observed or conventional switches into approved installer arguments' {
        $content = Get-Content -LiteralPath $script:scannerPath -Raw
        $content | Should -Not -Match '@\("/qn"\s*,\s*"/norestart"\)'
        $fixture = Get-Content -LiteralPath $script:fixturePath -Raw | ConvertFrom-Json
        @($fixture.packages | Where-Object { $null -ne $_.installer_arguments }).Count | Should -Be 0
    }

    It 'emits only redacted scan-root identities' {
        $fixture = & $script:scannerPath -FixtureOnly
        $fixture.scan_root | Should -Be 'fixture-only'
        $fixtureJson = ConvertTo-Json $fixture -Depth 12
        Test-Json -Json $fixtureJson -SchemaFile $script:schemaPath | Should -BeTrue
    }

    It 'uses only safe relative fixture paths' {
        $fixture = Get-Content -LiteralPath $script:fixturePath -Raw | ConvertFrom-Json
        foreach ($package in $fixture.packages) {
            $package.relative_path | Should -Not -Match '^[A-Za-z]:'
            $package.relative_path | Should -Not -Match '^[/\\]{2}'
            $package.relative_path | Should -Not -Match '(^|[/\\])\.\.([/\\]|$)'
        }
    }

    It 'does not fabricate a signature or unattended argument for the AutoLogon fixture' {
        $fixture = Get-Content -LiteralPath $script:fixturePath -Raw | ConvertFrom-Json
        $autoLogon = @($fixture.packages | Where-Object { $_.classification -eq 'requires_physical_cybernet' })
        $autoLogon.Count | Should -Be 1
        $autoLogon[0].authenticode.status | Should -Be 'NotSigned'
        $autoLogon[0].authenticode.signer | Should -BeNullOrEmpty
        $autoLogon[0].installer_arguments | Should -BeNullOrEmpty
    }

    It 'keeps real output paths relative to the supplied scan root' {
        $content = Get-Content -LiteralPath $script:scannerPath -Raw
        $content | Should -Match "scan_root = 'operator-local-reference'"
        $content | Should -Match 'Get-SafeRelativePath'
    }
}
