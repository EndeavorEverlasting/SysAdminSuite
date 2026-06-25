#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Test-TargetReadiness script' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:scriptPath = [System.IO.Path]::Combine($repoRoot, 'scripts', 'powershell', 'Test-TargetReadiness.ps1')
        $script:scriptPath = (Resolve-Path -LiteralPath $script:scriptPath -ErrorAction Stop).Path
    }

    It 'exists' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
    }

    It 'contains comment-based help sections' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw
        $content | Should -Match '\.SYNOPSIS'
        $content | Should -Match '\.DESCRIPTION'
        $content | Should -Match '\.PARAMETER\s+Target'
        $content | Should -Match '\.EXAMPLE'
        $content | Should -Match 'Safety'
    }

    It 'can run localhost mode without remote dependency' {
        $outRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-readiness-' + [guid]::NewGuid().Guid)
        $jsonPath = Join-Path $outRoot 'readiness.json'
        $csvPath = Join-Path $outRoot 'readiness.csv'
        $null = & $script:scriptPath -Target 'localhost' -OutputRoot $outRoot -OutputJson $jsonPath -OutputCsv $csvPath
        Test-Path -LiteralPath $jsonPath | Should -BeTrue
        Test-Path -LiteralPath $csvPath | Should -BeTrue
        $jsonText = Get-Content -LiteralPath $jsonPath -Raw
        $jsonText | Should -Match 'localhost'
        $jsonText | Should -Match 'overall_status|checks'
        Remove-Item -LiteralPath $outRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'parses CSV targets with common column names' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-readiness-csv-' + [guid]::NewGuid().Guid)
        New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
        $csvPath = Join-Path $tmpDir 'targets.csv'
        $jsonPath = Join-Path $tmpDir 'readiness.json'
        $outCsvPath = Join-Path $tmpDir 'readiness.csv'
        @(
            [pscustomobject]@{ Target = 'localhost'; ComputerName = '' },
            [pscustomobject]@{ Target = ''; ComputerName = 'example.invalid' }
        ) | Export-Csv -LiteralPath $csvPath -NoTypeInformation

        $null = & $script:scriptPath -TargetsCsv $csvPath -OutputRoot $tmpDir -OutputJson $jsonPath -OutputCsv $outCsvPath
        $jsonText = Get-Content -LiteralPath $jsonPath -Raw
        $jsonText | Should -Match 'localhost'
        $jsonText | Should -Match 'example.invalid'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns structured statuses for unreachable targets without crashing batch' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-readiness-unreach-' + [guid]::NewGuid().Guid)
        New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
        $csvPath = Join-Path $tmpDir 'targets.csv'
        $jsonPath = Join-Path $tmpDir 'readiness.json'
        $outCsvPath = Join-Path $tmpDir 'readiness.csv'
        @([pscustomobject]@{ Target = 'example.invalid' }) | Export-Csv -LiteralPath $csvPath -NoTypeInformation

        $null = & $script:scriptPath -TargetsCsv $csvPath -OutputRoot $tmpDir -OutputJson $jsonPath -OutputCsv $outCsvPath
        $jsonText = Get-Content -LiteralPath $jsonPath -Raw
        $jsonText | Should -Match 'example.invalid'
        $jsonText | Should -Match 'Ready|PartiallyReady|NotReady|Unknown'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'does not contain forbidden registry or remoting mutation commands' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw
        @(
            'Set-ItemProperty',
            'New-ItemProperty',
            'Remove-ItemProperty',
            'reg add',
            'reg delete',
            'Enable-PSRemoting',
            'Set-Service\s+RemoteRegistry',
            'Start-Service\s+RemoteRegistry',
            'Stop-Service\s+RemoteRegistry'
        ) | ForEach-Object {
            $content | Should -Not -Match $_
        }
    }
}
