#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:deploymentScript = Join-Path $script:repoRoot 'scripts\Invoke-SasCybernetClinicalCoreDeployment.ps1'
    $script:deploymentCmd = Join-Path $script:repoRoot 'Deploy-CybernetClinicalCore.cmd'
    $script:fullDeploymentScript = Join-Path $script:repoRoot 'scripts\Invoke-SasCybernetSoftwareDeployment.ps1'
    $script:fullDeploymentCmd = Join-Path $script:repoRoot 'Deploy-CybernetSoftware.cmd'
    $script:portableLauncher = Join-Path $script:repoRoot 'scripts\SasPortableLauncher.ps1'
    $script:packageSetPath = Join-Path $script:repoRoot 'configs\software-packages\windows-native-package-sets.json'
}

Describe 'Cybernet clinical-core and full software deployment surfaces' {
    It 'parses both deployment PowerShell surfaces cleanly' {
        foreach ($path in @($script:deploymentScript,$script:fullDeploymentScript)) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    It 'pins the five-package core and requires AutoLogon last in the full profile' {
        $catalog = Get-Content -LiteralPath $script:packageSetPath -Raw | ConvertFrom-Json
        $core = @($catalog.package_sets | Where-Object id -eq 'cybernet-clinical-core')
        $full = @($catalog.package_sets | Where-Object id -eq 'cybernet-clinical-workstation')
        $core.Count | Should -Be 1
        $full.Count | Should -Be 1
        @($core[0].package_ids) -join '|' | Should -Be 'allscripts-eehr-shortcut-uai-2-2|epic-downtime-guide-shortcut-1-0|nuance-dragon-medical-one-2025|hyland-fos-epic-integration-23-1-33-1000|bca'
        @($core[0].package_ids) | Should -Not -Contain 'autologon'
        @($full[0].package_ids)[-1] | Should -Be 'autologon'
    }

    It 'keeps the clinical-core dry admission gate before live core execution' {
        $text = Get-Content -LiteralPath $script:deploymentScript -Raw
        $text | Should -Match 'Deploy requires both -AllowTargetMutation and -ConfirmDeployment'
        $text | Should -Match '--dry-run'
        $text.IndexOf('--dry-run') | Should -BeLessThan $text.IndexOf('LIVE CLINICAL CORE DEPLOYMENT')
        $text | Should -Match 'CLINICAL_CORE_DEPLOYMENT_COMPLETED'
    }

    It 'makes the portable deploy surface full-profile, AutoLogon-last, and restart-complete' {
        $full = Get-Content -LiteralPath $script:fullDeploymentScript -Raw
        $cmd = Get-Content -LiteralPath $script:fullDeploymentCmd -Raw
        $launcher = Get-Content -LiteralPath $script:portableLauncher -Raw
        $full | Should -Match 'Invoke-SasCybernetClinicalCoreDeployment.ps1'
        $full | Should -Match 'Invoke-SasAutoLogonS4URestartDeployment.ps1'
        $full | Should -Match 'AutoLogon must be the final software step'
        $full | Should -Match 'CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED'
        $cmd | Should -Match 'AllowTargetMutation -ConfirmDeployment'
        $launcher | Should -Match 'Deploy-CybernetSoftware.cmd'
        $launcher | Should -Match 'restart included'
        $launcher | Should -Match 'Hardware-only Cybernet apply'
    }
}
