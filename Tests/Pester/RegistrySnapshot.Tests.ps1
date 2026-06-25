#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Describe 'Get-RegistrySnapshot Script' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:scriptPath = [System.IO.Path]::Combine($repoRoot, 'scripts', 'powershell', 'Get-RegistrySnapshot.ps1')
    }

    It 'script exists' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
    }

    It 'has comment-based help synopsis' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw
        $content | Should -Match '\.SYNOPSIS'
        $content | Should -Match '\.DESCRIPTION'
        $content | Should -Match 'Safety notes'
    }

    It 'accepts localhost invocation with narrow key and parses output' {
        $tempPath = Join-Path $env:TEMP "registry-snapshot-test-$([guid]::NewGuid().ToString()).json"
        $null = & $script:scriptPath -Target localhost -RegistryPath 'HKLM:\SOFTWARE\Microsoft' -ExcludePattern '*\DoesNotMatch*' -OutputPath $tempPath
        $result = Get-Content -LiteralPath $tempPath -Raw | ConvertFrom-Json
        $result | Should -Not -BeNullOrEmpty
        $result.target.scope | Should -Be 'localhost'
        @($result.entries).Count | Should -BeGreaterOrEqual 1
        @($result.entries)[0].PSObject.Properties.Name | Should -Contain 'key_path'
        @($result.entries)[0].PSObject.Properties.Name | Should -Contain 'access_status'
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    It 'creates output JSON when OutputPath is supplied' {
        $tempPath = Join-Path $env:TEMP "registry-snapshot-test-$([guid]::NewGuid().ToString()).json"
        $null = & $script:scriptPath -Target localhost -RegistryPath 'HKLM:\SOFTWARE\Microsoft' -OutputPath $tempPath

        Test-Path -LiteralPath $tempPath | Should -BeTrue
        $parsed = Get-Content -LiteralPath $tempPath -Raw | ConvertFrom-Json
        $parsed.schema_version | Should -Not -BeNullOrEmpty
        $parsed.entries | Should -Not -BeNullOrEmpty

        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    It 'handles missing paths without fatal crash' {
        $tempPath = Join-Path $env:TEMP "registry-snapshot-test-$([guid]::NewGuid().ToString()).json"
        $null = & $script:scriptPath -Target localhost -RegistryPath 'HKLM:\SOFTWARE\DefinitelyMissingPath_ForRegistrySnapshotTests' -OutputPath $tempPath
        $result = Get-Content -LiteralPath $tempPath -Raw | ConvertFrom-Json
        @($result.entries | Where-Object { $_.access_status -eq 'NotFound' }).Count | Should -BeGreaterThan 0
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    It 'accepts exclude patterns array' {
        $tempPath = Join-Path $env:TEMP "registry-snapshot-test-$([guid]::NewGuid().ToString()).json"
        $null = & $script:scriptPath -Target localhost -RegistryPaths 'HKLM:\SOFTWARE\Microsoft' -ExcludePatterns '*\Volatile*','*\RecentDocs*' -OutputPath $tempPath
        $result = Get-Content -LiteralPath $tempPath -Raw | ConvertFrom-Json
        $result.summary.PSObject.Properties.Name | Should -Contain 'excluded'
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    It 'does not include forbidden write or remoting commands' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw
        $forbidden = @(
            'Set-ItemProperty','New-ItemProperty','Remove-ItemProperty',
            'reg add','reg delete','reg import','reg restore',
            'Start-Service RemoteRegistry','Stop-Service RemoteRegistry','Set-Service RemoteRegistry',
            'Enable-PSRemoting','Start-Process .*msi','msiexec'
        )

        foreach ($term in $forbidden) {
            $content | Should -Not -Match [regex]::Escape($term)
        }
    }
}
