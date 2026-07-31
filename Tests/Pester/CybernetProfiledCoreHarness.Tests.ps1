#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Cybernet profiled clinical-core operator harness' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:changedPowerShell = @(
            'scripts/Install-SasPortableLauncher.ps1',
            'scripts/Invoke-SasCybernetDeploymentReadiness.ps1',
            'scripts/Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1',
            'scripts/Invoke-SasCybernetCoreRecovery.ps1',
            'scripts/Refresh-SasOperatorCommand.ps1',
            'scripts/SasOperatorSession.psm1',
            'scripts/SasPortableLauncher.ps1',
            'scripts/Show-SasOperatorContext.ps1',
            'scripts/Show-SasOperatorEvidence.ps1',
            'scripts/Test-SasCybernetClinicalCoreSources.ps1'
        )
    }

    It 'parses every changed PowerShell operator surface' {
        foreach ($relative in $script:changedPowerShell) {
            $path = Join-Path $script:repoRoot $relative
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue -Because $relative
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0 -Because "$relative must parse cleanly: $(@($errors | ForEach-Object Message) -join '; ')"
        }
    }

    It 'keeps operator session state outside the repository' {
        $session = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/SasOperatorSession.psm1') -Raw
        $session | Should -Match '\$env:LOCALAPPDATA'
        $session | Should -Match 'operator-session\.json'
        $session | Should -Match 'field-ready\*'
        $session | Should -Not -Match 'WPJ075OPR046'
        $session | Should -Not -Match 'pa_rperez26'
    }

    It 'routes refresh to Guest and Core/Recover to protected Northwell' {
        $launcher = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/SasPortableLauncher.ps1') -Raw
        $core = Get-Content -LiteralPath (Join-Path $script:repoRoot 'Deploy-CybernetProfiledClinicalCore.cmd') -Raw
        $launcher | Should -Match 'NETWORK REQUIRED: GUEST / INTERNET'
        $launcher | Should -Match 'sas cybernet Core HOST'
        $launcher | Should -Match 'sas cybernet Recover HOST'
        $core | Should -Match 'NETWORK REQUIRED: PROTECTED NORTHWELL'
    }

    It 'streams Core output, preserves child exit codes, and bounds nested readiness paths' {
        $launcher = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/SasPortableLauncher.ps1') -Raw
        $core = Get-Content -LiteralPath (Join-Path $script:repoRoot 'Deploy-CybernetProfiledClinicalCore.cmd') -Raw
        $readiness = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/Invoke-SasCybernetDeploymentReadiness.ps1') -Raw
        $launcher | Should -Match '\| Out-Host'
        $core | Should -Match 'endlocal & exit /b %EXITCODE%'
        $core | Should -Not -Match 'for %%#'
        $readiness | Should -Match 'transportOutputRoot'
        $readiness | Should -Match 'survey\\output\\t'
        $readiness | Should -Match 'OutputRoot = \$transportOutputRoot'
        $readiness | Should -Not -Match 'OutputRoot = \(Join-Path \$context\.run_root ''transport''\)'
    }

    It 'preflights all sources before target access or mutation' {
        $deployment = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1') -Raw
        $preflight = $deployment.IndexOf('& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $preflightPath')
        $sourcesReady = $deployment.IndexOf('[3/7] SOURCES READY 5/5')
        $adminAccess = $deployment.IndexOf('$adminRoot="\\$target\ADMIN$"')
        $targetCreate = $deployment.IndexOf('New-Item -ItemType Directory -Path $remoteRunUnc')
        $preflight | Should -BeGreaterThan -1
        $sourcesReady | Should -BeGreaterThan $preflight
        $adminAccess | Should -BeGreaterThan $sourcesReady
        $targetCreate | Should -BeGreaterThan $adminAccess
    }

    It 'models Nuance-style bundle drift without guessing a replacement file' {
        $preflight = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/Test-SasCybernetClinicalCoreSources.ps1') -Raw
        $preflight | Should -Match 'all_files_recursive_from_approved_bundle_folder'
        $preflight | Should -Match 'inventory_drift'
        $preflight | Should -Match 'missing_files'
        $preflight | Should -Match 'unexpected_files'
        $preflight | Should -Match 'reported_not_silently_ignored'
        $preflight | Should -Not -Match '\\C\$'
        $preflight | Should -Not -Match '\\ADMIN\$'
    }

    It 'preserves disabled AutoLogon and observational Imprivata' {
        $deployment = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1') -Raw
        $deployment | Should -Match "expected_autologon_state='disabled_preserve_only'"
        $deployment | Should -Match 'expected_autologon_enabled=\$false'
        $deployment | Should -Match 'AutoLogon precondition mismatch'
        $deployment | Should -Match 'managed_by_this_run=\$false'
        $deployment | Should -Match 'observational/external state only'
        $deployment | Should -Match 'startup_type'
        $deployment | Should -Not -Match 'shutdown\.exe'
    }

    It 'records checkpoints and exact bounded recovery' {
        $deployment = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1') -Raw
        $recovery = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/Invoke-SasCybernetCoreRecovery.ps1') -Raw
        foreach ($marker in @('[1/7] NETWORK READY','[2/7] TARGET LOCKED','[3/7] SOURCES READY 5/5','[4/7] TARGET STAGING HASH VERIFIED','[5/7] SYSTEM INSTALL RUNNING','[6/7] BEFORE/AFTER PROFILE CAPTURED','[7/7] CLEANUP VERIFIED')) {
            $deployment | Should -Match ([regex]::Escape($marker))
        }
        $deployment | Should -Match 'worker_checkpoint\.json'
        $deployment | Should -Match 'SysAdminSuite-CybernetCore-\$runId'
        $recovery | Should -Match '\[regex\]::Escape\(\$RunId\)'
        $recovery | Should -Match 'worker_result_recovered\.json'
        $recovery | Should -Match 'Remove-Item -LiteralPath \$remoteRunUnc'
    }
}
