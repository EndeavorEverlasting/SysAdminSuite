#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:hardwareRoot = Join-Path $script:repoRoot 'Hardware\Cybernet'
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
        $outputRoot = Join-Path $TestDrive 'cybernet-hardware'
        $scriptPath = Join-Path $script:hardwareRoot 'Invoke-CybernetBatchConfiguration.ps1'
        $result = & $scriptPath `
            -Mode Apply `
            -ComputerName 'CYBERNET-FIXTURE-01' `
            -FixtureMode `
            -OutputRoot $outputRoot

        $result.status | Should -Be 'APPLIED_AND_VALIDATED'
        $result.fixture_mode | Should -BeTrue
        $result.network_activity_performed | Should -BeFalse
        $result.target_mutation_performed | Should -BeFalse
        $result.com_mutation_performed | Should -BeFalse
        @($result.stages).Count | Should -Be 4
        @($result.stages | Where-Object exit_code -ne 0).Count | Should -Be 0
        Test-Path -LiteralPath $result.summary_path | Should -BeTrue
    }

    It 'keeps Plan request-only' {
        $outputRoot = Join-Path $TestDrive 'cybernet-plan'
        $result = & (Join-Path $script:hardwareRoot 'Invoke-CybernetBatchConfiguration.ps1') `
            -Mode Plan `
            -ComputerName 'CYBERNET-FIXTURE-01' `
            -OutputRoot $outputRoot

        $result.status | Should -Be 'PLAN_READY'
        $result.network_activity_performed | Should -BeFalse
        $result.target_mutation_performed | Should -BeFalse
    }
}
