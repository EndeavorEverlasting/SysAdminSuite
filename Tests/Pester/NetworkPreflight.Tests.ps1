#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:preflight = Join-Path $script:repoRoot 'survey\sas-network-preflight.ps1'
    $script:targetsDir = Join-Path $script:repoRoot 'targets\local\pester-network-preflight'
    $script:outputDir = Join-Path $script:repoRoot 'survey\output\pester-network-preflight'
    $script:pwsh = (Get-Process -Id $PID).Path
}

BeforeEach {
    Remove-Item -LiteralPath $script:targetsDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:outputDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $script:targetsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $script:outputDir | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:targetsDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:outputDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'sas-network-preflight.ps1 executable behavior' {
    It 'parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:preflight, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'stops without probing when no target file is selected and prints candidate guidance' {
        $output = & $script:pwsh -NoProfile -ExecutionPolicy Bypass -File $script:preflight 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'No -TargetFile was provided. Stopping without probing.'
        ($output -join "`n") | Should -Match 'targets[/\\]local'
        ($output -join "`n") | Should -Match 'logs[/\\]targets'
        ($output -join "`n") | Should -Match 'Run in Windows PowerShell'
    }

    It 'runs against a codified targets/local CSV and writes codified survey output' {
        $targetCsv = Join-Path $script:targetsDir 'approved_targets.csv'
        @'
HostName,Identifier,IdentifierType,Source
127.0.0.1,SERIAL-LOCALHOST-001,Serial,pester
'@ | Set-Content -LiteralPath $targetCsv -Encoding UTF8

        & $script:preflight -TargetFile $targetCsv -Ports 1 -OutputDirectory $script:outputDir

        $csv = Get-ChildItem -LiteralPath $script:outputDir -Filter 'network_preflight_*.csv' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        $csv | Should -Not -BeNullOrEmpty
        $rows = @(Import-Csv -LiteralPath $csv.FullName)
        $rows.Count | Should -Be 1
        $rows[0].Target | Should -Be '127.0.0.1'
        $rows[0].SourceFile | Should -Match 'targets[/\\]local[/\\]pester-network-preflight'
        $csv.FullName | Should -Match 'survey[/\\]output[/\\]pester-network-preflight'
    }

    It 'does not silently probe serial-only Identifier rows without an explicit host/IP type' {
        $targetCsv = Join-Path $script:targetsDir 'serial_only.csv'
        @'
Identifier,IdentifierType,Source
CYB123456789,Serial,pester
WNH999SERIAL,Serial,pester
'@ | Set-Content -LiteralPath $targetCsv -Encoding UTF8

        { & $script:preflight -TargetFile $targetCsv -Ports 1 -OutputDirectory $script:outputDir } |
            Should -Throw -ExpectedMessage '*Serial-only rows must be normalized or enriched*'

        $generated = @(Get-ChildItem -LiteralPath $script:outputDir -Filter 'network_preflight_*.csv' -ErrorAction SilentlyContinue)
        $generated.Count | Should -Be 0
    }

    It 'accepts Identifier only when the row explicitly marks it as host or IP evidence' {
        $targetCsv = Join-Path $script:targetsDir 'explicit_identifier_host.csv'
        @'
Identifier,IdentifierType,Source
127.0.0.1,IPAddress,pester
'@ | Set-Content -LiteralPath $targetCsv -Encoding UTF8

        & $script:preflight -TargetFile $targetCsv -Ports 1 -OutputDirectory $script:outputDir

        $csv = Get-ChildItem -LiteralPath $script:outputDir -Filter 'network_preflight_*.csv' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        $rows = @(Import-Csv -LiteralPath $csv.FullName)
        $rows.Count | Should -Be 1
        $rows[0].Target | Should -Be '127.0.0.1'
    }

    It 'rejects target files outside codified intake roots by default' {
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-network-preflight-outside-{0}.txt' -f ([Guid]::NewGuid().ToString('N')))
        try {
            '127.0.0.1' | Set-Content -LiteralPath $outside -Encoding UTF8
            { & $script:preflight -TargetFile $outside -Ports 1 -OutputDirectory $script:outputDir } |
                Should -Throw -ExpectedMessage '*outside codified intake roots*'
        }
        finally {
            Remove-Item -LiteralPath $outside -Force -ErrorAction SilentlyContinue
        }
    }
}
