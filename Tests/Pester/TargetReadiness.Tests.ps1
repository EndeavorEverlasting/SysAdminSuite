#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Test-TargetReadiness script' {
    BeforeAll {
        $script:scriptPath = Join-Path $PSScriptRoot '..' '..' 'scripts' 'powershell' 'Test-TargetReadiness.ps1'
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
        $results = @(& $script:scriptPath -Target 'localhost' -OutputRoot $outRoot)

        $results | Should -Not -BeNullOrEmpty
        $results[0].target | Should -Be 'localhost'
        $results[0].checks | Should -Not -BeNullOrEmpty
        ($results[0].checks | Select-Object -ExpandProperty status) | Should -Contain 'Pass'
        Remove-Item -LiteralPath $outRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'parses CSV targets with common column names' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-readiness-csv-' + [guid]::NewGuid().Guid)
        New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
        $csvPath = Join-Path $tmpDir 'targets.csv'
        @(
            [pscustomobject]@{ Target = 'localhost' },
            [pscustomobject]@{ ComputerName = 'example.invalid' }
        ) | Export-Csv -LiteralPath $csvPath -NoTypeInformation

        $results = @(& $script:scriptPath -TargetsCsv $csvPath -OutputRoot $tmpDir)

        ($results | Measure-Object).Count | Should -Be 2
        ($results.target) | Should -Contain 'localhost'
        ($results.target) | Should -Contain 'example.invalid'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns structured statuses for unreachable targets without crashing batch' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-readiness-unreach-' + [guid]::NewGuid().Guid)
        New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
        $csvPath = Join-Path $tmpDir 'targets.csv'
        @([pscustomobject]@{ Target = 'example.invalid' }) | Export-Csv -LiteralPath $csvPath -NoTypeInformation

        $results = @(& $script:scriptPath -TargetsCsv $csvPath -OutputRoot $tmpDir)

        $results | Should -Not -BeNullOrEmpty
        $results[0].overall_status | Should -Match 'Ready|PartiallyReady|NotReady|Unknown'
        foreach ($check in $results[0].checks) {
            $check.status | Should -Match 'Pass|Fail|NotChecked|Error'
            $check.PSObject.Properties.Name | Should -Contain 'details'
            $check.PSObject.Properties.Name | Should -Contain 'error_message'
        }
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
