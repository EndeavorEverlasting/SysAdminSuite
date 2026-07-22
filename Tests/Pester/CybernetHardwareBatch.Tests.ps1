#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:hardwareRoot = Join-Path $script:repoRoot 'Hardware\Cybernet'
    $script:batchScript = Join-Path $script:hardwareRoot 'Invoke-CybernetBatchConfiguration.ps1'
    $script:engine = (Get-Process -Id $PID).Path
    $script:paths = @(
        'CybernetHardware.Common.psm1',
        'Invoke-CybernetStage.ps1',
        'Invoke-CybernetBatchConfiguration.ps1',
        'Disable-PrivacyButton.ps1',
        'Enable-PrivacyButton.ps1',
        'Set-NoSleep.ps1',
        'Set-PowerButtonDoNothing.ps1',
        'COM-Port-Check.ps1',
        'PostInstall-Validation.ps1'
    ) | ForEach-Object { Join-Path $script:hardwareRoot $_ }
}

BeforeEach {
    $script:testOutputRoot = Join-Path $script:repoRoot ('survey\output\cybernet-hardware-pester-' + [guid]::NewGuid().ToString('N'))
}

AfterEach {
    if ($script:testOutputRoot -and (Test-Path -LiteralPath $script:testOutputRoot)) {
        Remove-Item -LiteralPath $script:testOutputRoot -Recurse -Force
    }
}

Describe 'Cybernet hardware batch PowerShell surfaces' {
    It 'parses every tracked module and script' {
        foreach ($path in $script:paths) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $path,
                [ref]$tokens,
                [ref]$errors
            ) | Out-Null
            @($errors).Count | Should -Be 0 -Because $path
        }
    }

    It 'classifies exact COM shapes without mutating state' {
        Import-Module (Join-Path $script:hardwareRoot 'CybernetHardware.Common.psm1') -Force
        Get-SasCybernetComClassification -Ports COM1,COM2,COM3,COM4 | Should -Be 'COM_PORTS_READY'
        Get-SasCybernetComClassification -Ports COM3,COM4,COM5,COM6 | Should -Be 'COM_AUTOFIX_ELIGIBLE_LOCAL_ONLY'
        Get-SasCybernetComClassification -Ports COM1,COM3 | Should -Be 'COM_PORT_REVIEW_REQUIRED'
    }

    It 'executes the complete Apply workflow in fixture mode without network or mutation' {
        $console = @(& $script:engine -NoProfile -File $script:batchScript `
            -Mode Apply `
            -ComputerName 'CYBERNET-FIXTURE-01' `
            -FixtureMode `
            -OutputRoot $script:testOutputRoot 2>&1 | ForEach-Object { $_.ToString() })
        $LASTEXITCODE | Should -Be 0 -Because ($console -join "`n")

        $summaryPath = Get-ChildItem -LiteralPath $script:testOutputRoot -Filter 'cybernet_batch_configuration_summary.json' -File -Recurse |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        $summaryPath | Should -Not -BeNullOrEmpty
        $result = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.status | Should -Be 'APPLIED_AND_VALIDATED'
        $result.fixture_mode | Should -BeTrue
        $result.network_activity_performed | Should -BeFalse
        $result.target_mutation_performed | Should -BeFalse
        $result.com_mutation_performed | Should -BeFalse
        @($result.stages).Count | Should -Be 4
        @($result.stages | Where-Object exit_code -ne 0).Count | Should -Be 0
    }

    It 'keeps Plan request-only' {
        $console = @(& $script:engine -NoProfile -File $script:batchScript `
            -Mode Plan `
            -ComputerName 'CYBERNET-FIXTURE-01' `
            -OutputRoot $script:testOutputRoot 2>&1 | ForEach-Object { $_.ToString() })
        $LASTEXITCODE | Should -Be 0 -Because ($console -join "`n")

        $summaryPath = Get-ChildItem -LiteralPath $script:testOutputRoot -Filter 'cybernet_batch_configuration_summary.json' -File -Recurse |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        $summaryPath | Should -Not -BeNullOrEmpty
        $result = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.status | Should -Be 'PLAN_READY'
        $result.network_activity_performed | Should -BeFalse
        $result.target_mutation_performed | Should -BeFalse
    }
}
