#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Describe 'Compare-RegistrySnapshots script' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:scriptPath = [System.IO.Path]::Combine($repoRoot, 'scripts', 'powershell', 'Compare-RegistrySnapshots.ps1')
    }

    It 'exists' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
    }

    It 'contains comment-based help sections' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw
        $content | Should -Match '\.SYNOPSIS'
        $content | Should -Match '\.DESCRIPTION'
        $content | Should -Match '\.PARAMETER BeforeSnapshotPath'
        $content | Should -Match '\.EXAMPLE'
    }

    It 'does not include forbidden registry mutation or remote registry commands' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw
        @(
            'Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg add','reg delete','reg import','reg restore',
            'Start-Service RemoteRegistry','Stop-Service RemoteRegistry','Set-Service RemoteRegistry','Enable-PSRemoting',
            'Start-Process .*msi','msiexec','winget install','choco install'
        ) | ForEach-Object {
            $content | Should -Not -Match $_
        }
    }

    It 'classifies value changes and applies rules and writes outputs' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("registry-diff-test-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        $beforePath = Join-Path $tempRoot 'before.json'
        $afterPath = Join-Path $tempRoot 'after.json'
        $rulesPath = Join-Path $tempRoot 'rules.json'
        $outJson = Join-Path $tempRoot 'out.json'
        $outCsv = Join-Path $tempRoot 'out.csv'

        $before = [pscustomobject]@{ target = 'LAB-PC-001'; entries = @(
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'DeleteMe'; value_type = 'String'; value_data = 'A'; value_data_kind = 'text'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'ModifyMe'; value_type = 'String'; value_data = 'Before'; value_data_kind = 'text'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKCU\Software\RecentDocs'; value_name = 'MRU1'; value_type = 'String'; value_data = 'old'; value_data_kind = 'text'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'ExpectedSetting'; value_type = 'DWord'; value_data = 0; value_data_kind = 'number'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'SuspiciousToggle'; value_type = 'DWord'; value_data = 0; value_data_kind = 'number'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'CandidateSetting'; value_type = 'String'; value_data = 'Off'; value_data_kind = 'text'; access_status = 'ok' }
        ) }
        $after = [pscustomobject]@{ target = 'LAB-PC-001'; entries = @(
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'CreateMe'; value_type = 'String'; value_data = 'B'; value_data_kind = 'text'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'ModifyMe'; value_type = 'String'; value_data = 'After'; value_data_kind = 'text'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKCU\Software\RecentDocs'; value_name = 'MRU1'; value_type = 'String'; value_data = 'new'; value_data_kind = 'text'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'ExpectedSetting'; value_type = 'DWord'; value_data = 1; value_data_kind = 'number'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'SuspiciousToggle'; value_type = 'DWord'; value_data = 1; value_data_kind = 'number'; access_status = 'ok' },
            [pscustomobject]@{ key_path = 'HKLM\Software\ExampleVendor\ExampleApp'; value_name = 'CandidateSetting'; value_type = 'String'; value_data = 'On'; value_data_kind = 'text'; access_status = 'ok' }
        ) }
        $rules = [pscustomobject]@{ expected_change_rules = @([pscustomobject]@{ id = 'expected-1'; key_path_regex = 'ExampleApp'; value_name_regex = 'ExpectedSetting'; reason = 'Installer sets expected setting' }); noise_patterns = @([pscustomobject]@{ id = 'noise-1'; key_path_regex = 'RecentDocs'; reason = 'Volatile MRU noise' }); suspicious_change_rules = @([pscustomobject]@{ id = 'susp-1'; value_name_regex = 'SuspiciousToggle'; reason = 'Unexpected security toggle' }); remediation_candidate_rules = @([pscustomobject]@{ id = 'rem-1'; value_name_regex = 'CandidateSetting'; reason = 'Candidate for post-install hardening' }) }

        $before | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $beforePath -Encoding UTF8
        $after | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $afterPath -Encoding UTF8
        $rules | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rulesPath -Encoding UTF8

        $resultRaw = & $script:scriptPath -BeforeSnapshotPath $beforePath -AfterSnapshotPath $afterPath -SoftwareId 'EXAMPLE-SOFTWARE-ID' -ExpectedRulesPath $rulesPath -WatchlistPath $rulesPath -OutputJson $outJson -OutputCsv $outCsv
        $result = $resultRaw | ConvertFrom-Json

        $result.summary.total_changes | Should -BeGreaterThan 0
        $result.summary.created_values | Should -BeGreaterThan 0
        $result.summary.deleted_values | Should -BeGreaterThan 0
        $result.summary.modified_values | Should -BeGreaterThan 0
        $result.summary.noise_changes | Should -BeGreaterThan 0
        $result.summary.expected_changes | Should -BeGreaterThan 0
        ($result.summary.suspicious_changes + $result.summary.remediation_candidates) | Should -BeGreaterThan 0

        Test-Path -LiteralPath $outJson | Should -BeTrue
        Test-Path -LiteralPath $outCsv | Should -BeTrue

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
