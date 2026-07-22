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

    It 'keeps the batch default in request-only Plan mode' {
        $text = Get-Content -LiteralPath (Join-Path $script:hardwareRoot 'Invoke-CybernetBatchConfiguration.ps1') -Raw
        $text | Should -Match "\[string\]\$Mode\s*=\s*'Plan'"
        $text | Should -Match "Apply requires -AllowTargetMutation"
        $text | Should -Match "com_mutation_performed = \$false"
    }

    It 'uses the tracked JSON splat runner for child-process composition' {
        $batch = Get-Content -LiteralPath (Join-Path $script:hardwareRoot 'Invoke-CybernetBatchConfiguration.ps1') -Raw
        $runner = Get-Content -LiteralPath (Join-Path $script:hardwareRoot 'Invoke-CybernetStage.ps1') -Raw
        $batch | Should -Match 'Invoke-CybernetStage\.ps1'
        $batch | Should -Match 'parameter_document'
        $runner | Should -Match '& \$ScriptPath @parameters'
    }
}
