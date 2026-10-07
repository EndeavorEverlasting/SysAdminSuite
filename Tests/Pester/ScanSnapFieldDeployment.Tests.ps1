#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'ScanSnap deterministic field deployment' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $scanRoot = Join-Path $repoRoot 'Config\SoftwareDeploy\ScanSnap'
        $fieldScript = Join-Path $scanRoot 'Invoke-ScanSnapFieldDeployment.ps1'
        $preflightCmd = Join-Path $scanRoot 'Preflight-ScanSnap-Field.cmd'
        $deployCmd = Join-Path $scanRoot 'Deploy-ScanSnap-Field.cmd'
        $legacyCmd = Join-Path $scanRoot 'Deploy-ScanSnap.cmd'
        $workflowPath = Join-Path $scanRoot 'field-deployment.workflow.json'
        $adapterPath = Join-Path $repoRoot 'scripts\SasSoftwareDeploymentAdapter.psm1'
        Import-Module $adapterPath -Force
    }

    AfterAll {
        Remove-Module SasSoftwareDeploymentAdapter -ErrorAction SilentlyContinue
    }

    It 'keeps field execution behind two simple controller entrypoints' {
        Test-Path -LiteralPath $preflightCmd -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $deployCmd -PathType Leaf | Should -BeTrue

        $preflight = Get-Content -LiteralPath $preflightCmd -Raw
        $deploy = Get-Content -LiteralPath $deployCmd -Raw
        $preflight | Should -Match 'Invoke-ScanSnapFieldDeployment\.ps1'
        $preflight | Should -Match '-PreflightOnly'
        $deploy | Should -Match 'Invoke-ScanSnapFieldDeployment\.ps1'
        $deploy | Should -Not -Match '-PreflightOnly'

        $legacy = Get-Content -LiteralPath $legacyCmd -Raw
        $legacy | Should -Match '/FIELDPREFLIGHT'
        $legacy | Should -Match 'Preflight-ScanSnap-Field\.cmd'
        $legacy | Should -Match '/FIELD'
        $legacy | Should -Match 'Deploy-ScanSnap-Field\.cmd'
    }

    It 'parses the field orchestrator without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($fieldScript, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'reuses canonical network, transport, and deployment owners' {
        $field = Get-Content -LiteralPath $fieldScript -Raw
        foreach ($fragment in @(
            'SasNorthwellNetworkAuthority.psm1',
            'Assert-SasNorthwellNetwork',
            'Test-SasSoftwareDeploymentTransport.ps1',
            'TransportIntent = ''kerberos_smb_task''',
            'Resolve-SasSoftwareDeploymentTransport',
            'Invoke-SasSmbScheduledTaskDeployment'
        )) {
            $field | Should -Match ([regex]::Escape($fragment))
        }

        $field | Should -Not -Match '(?i)Get-Credential|ConvertFrom-SecureString|Invoke-Command|Enter-PSSession|New-PSSession'
        $field | Should -Not -Match '(?i)SendKeys|AppActivate|UIAutomation|/IT\b'
    }

    It 'binds target identity before transport and refuses the retired target' {
        $field = Get-Content -LiteralPath $fieldScript -Raw
        $field | Should -Match 'Resolve-ExactTargetFqdn'
        $field | Should -Match 'GetHostEntry'
        $field | Should -Match 'Test-SasDeploymentFqdn'
        $field | Should -Match 'LPW003ASI105'
        $field | Should -Match 'SCANSNAP_ALIAS_MISMATCH'
    }

    It 'keeps all human release confirmation on the Admin Box' {
        $field = Get-Content -LiteralPath $fieldScript -Raw
        $field | Should -Match "Read-Host 'ADMIN BOX CONFIRMATION - type DEPLOY SCANSNAP exactly'"
        $field | Should -Match "-cne 'DEPLOY SCANSNAP'"
        $field | Should -Match 'CANCELLED_BEFORE_MUTATION'
        $field | Should -Not -Match '(?i)/IT\b'
    }

    It 'freezes process identity through cached metadata and PID-delta evidence' {
        $workerPath = Join-Path $TestDrive 'scansnap-worker.ps1'
        $hint = [pscustomobject]@{
            name = 'VendorInstaller.exe'
            executable_leaf = 'VendorInstaller.exe'
            file_version = '1.2.3.4'
        }
        $workerArgs = @{
            Path = $workerPath
            RunId = 'software-install-20000101-000000-00000000'
            PackageName = 'ScanSnap'
            InstallerPath = 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20000101-000000-00000000\fixture.exe'
            ExpectedSha256 = ('0' * 64)
            InstallerArguments = @('/quiet')
            ValidationChecks = @([pscustomobject]@{ id='scansnap-file'; type='FileExists'; required=$true; path='C:\Program Files\ScanSnap\fixture.exe' })
            ProcessIdentityHint = $hint
            ResultPath = 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20000101-000000-00000000\worker-result.json'
        }
        New-SasSmbTaskWorker @workerArgs

        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($workerPath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0

        $worker = Get-Content -LiteralPath $workerPath -Raw
        foreach ($fragment in @(
            'Get-CimInstance Win32_Process',
            'process_identity_hint_json',
            'baseline_count',
            'post_launch_count',
            'delta_count',
            'cached_metadata',
            'pid_delta_child',
            'Test-SasSelectedProcessStillMatches'
        )) {
            $worker | Should -Match ([regex]::Escape($fragment))
        }

        $encodedConfig = [regex]::Match($worker, "FromBase64String\('(?<config>[^']+)'\)").Groups['config'].Value
        $config = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedConfig))) | ConvertFrom-Json
        $cached = [string]$config.process_identity_hint_json | ConvertFrom-Json
        $cached.name | Should -Be 'VendorInstaller.exe'
        $cached.executable_leaf | Should -Be 'VendorInstaller.exe'
        $cached.file_version | Should -Be '1.2.3.4'
    }

    It 'keeps qualified package truth machine-local across repository refreshes' {
        $field = Get-Content -LiteralPath $fieldScript -Raw
        $binder = Get-Content -LiteralPath (Join-Path $scanRoot 'Bind-ScanSnapPackage.ps1') -Raw
        $gitignore = Get-Content -LiteralPath (Join-Path $repoRoot '.gitignore') -Raw

        $field | Should -Match 'package\.local\.manifest\.json'
        $binder | Should -Match 'Join-Path \$packageRoot ''package\.local\.manifest\.json'''
        $gitignore | Should -Match 'Config/SoftwareDeploy/ScanSnap/package\.local\.manifest\.json'
    }

    It 'waits an identity-bound installer family rather than trusting root PID exit' {
        $workerPath = Join-Path $TestDrive 'scansnap-family-worker.ps1'
        $workerArgs = @{
            Path = $workerPath
            RunId = 'software-install-20000101-000000-00000000'
            PackageName = 'ScanSnap'
            InstallerPath = 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20000101-000000-00000000\fixture.exe'
            ExpectedSha256 = ('0' * 64)
            InstallerArguments = @('/quiet')
            ValidationChecks = @([pscustomobject]@{ id='scansnap-file'; type='FileExists'; required=$true; path='C:\Program Files\ScanSnap\fixture.exe' })
            ResultPath = 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20000101-000000-00000000\worker-result.json'
        }
        New-SasSmbTaskWorker @workerArgs
        $worker = Get-Content -LiteralPath $workerPath -Raw

        foreach ($fragment in @(
            'command_line_matches_installer',
            'familyIdentityById',
            'creation_utc',
            'Installer process family timed out',
            'Test-SasInstallerProcessIdentity -ProcessRow $row[0] -Identity $familyIdentityById[$pid]'
        )) {
            $worker | Should -Match ([regex]::Escape($fragment))
        }
    }

    It 'keeps the field workflow machine-readable and fail-closed' {
        $workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $workflow.schema_version | Should -Be 'sas-scansnap-field-workflow/v1'
        $workflow.owners.network_authority | Should -Be 'scripts/SasNorthwellNetworkAuthority.psm1'
        $workflow.network_rules.ordinary_wifi_may_coexist_with_domain_authenticated_non_wifi | Should -BeTrue
        $workflow.network_rules.transport_fallback_after_mutation | Should -BeFalse
        $workflow.operator_confirmation.location | Should -Be 'Admin Box only'
        $workflow.operator_confirmation.target_side_confirmation | Should -BeFalse
        $workflow.process_identity.target_gui_automation | Should -BeFalse
        @($workflow.fail_closed) | Should -Contain 'transport not kerberos_smb_task_ready'
    }
}
