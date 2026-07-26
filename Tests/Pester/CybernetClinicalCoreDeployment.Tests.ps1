#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:deploymentScript = Join-Path $script:repoRoot 'scripts\Invoke-SasCybernetClinicalCoreDeployment.ps1'
    $script:deploymentCmd = Join-Path $script:repoRoot 'Deploy-CybernetClinicalCore.cmd'
    $script:portableLauncher = Join-Path $script:repoRoot 'scripts\SasPortableLauncher.ps1'
    $script:packageSetPath = Join-Path $script:repoRoot 'configs\software-packages\windows-native-package-sets.json'
}

Describe 'Cybernet clinical-core deployment surface' {
    It 'parses the deployment PowerShell cleanly' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:deploymentScript,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'pins the exact deployable five-package set and excludes AutoLogon' {
        $catalog = Get-Content -LiteralPath $script:packageSetPath -Raw | ConvertFrom-Json
        $core = @($catalog.package_sets | Where-Object id -eq 'cybernet-clinical-core')
        $auto = @($catalog.package_sets | Where-Object id -eq 'cybernet-autologon-only')
        $core.Count | Should -Be 1
        @($core[0].package_ids) -join '|' | Should -Be 'allscripts-eehr-shortcut-uai-2-2|epic-downtime-guide-shortcut-1-0|nuance-dragon-medical-one-2025|hyland-fos-epic-integration-23-1-33-1000|bca'
        @($core[0].package_ids) | Should -Not -Contain 'autologon'
        $auto.Count | Should -Be 1
        @($auto[0].package_ids) -join '|' | Should -Be 'autologon'
        $autologon = @($catalog.packages | Where-Object id -eq 'autologon')
        $autologon.Count | Should -Be 1
        $autologon[0].canonical_system_install_enabled | Should -BeFalse
    }

    It 'requires explicit deployment authority and runs dry proof before live execution' {
        $text = Get-Content -LiteralPath $script:deploymentScript -Raw
        $text | Should -Match 'Deploy requires both -AllowTargetMutation and -ConfirmDeployment'
        $text | Should -Match '--dry-run'
        $text.IndexOf('--dry-run') | Should -BeLessThan $text.IndexOf('LIVE CLINICAL CORE DEPLOYMENT')
        $text | Should -Match 'Confirm-SasNorthwellNetwork.ps1'
        $text | Should -Match '\$env:SKIP_NMAP\s*=\s*''1'''
        $text | Should -Match 'CLINICAL_CORE_DEPLOYMENT_COMPLETED'
        $text | Should -Match 'do not blindly rerun'
    }

    It 'keeps AutoLogon separate and never reboots' {
        $text = Get-Content -LiteralPath $script:deploymentScript -Raw
        $text | Should -Match 'autologon_included\s*=\s*\$false'
        $text | Should -Match 'sas autologon Remote \$target'
        $text | Should -Match 'automatic_reboot_performed\s*=\s*\$false'
        $text | Should -Not -Match 'Restart-Computer'
        $text | Should -Not -Match 'shutdown.exe'
    }

    It 'exposes one direct portable deploy command' {
        $cmd = Get-Content -LiteralPath $script:deploymentCmd -Raw
        $launcher = Get-Content -LiteralPath $script:portableLauncher -Raw
        $cmd | Should -Match 'Mode Deploy'
        $cmd | Should -Match 'AllowTargetMutation -ConfirmDeployment'
        $launcher | Should -Match 'sas cybernet Deploy HOST'
        $launcher | Should -Match 'Deploy-CybernetClinicalCore.cmd'
        $launcher | Should -Match 'Hardware-only Cybernet apply'
    }
}
