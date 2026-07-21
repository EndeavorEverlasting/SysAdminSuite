#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Canonical SMB scheduled-task deployment adapter' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $adapterPath = Join-Path $repoRoot 'scripts/SasSoftwareDeploymentAdapter.psm1'
        $preflightModulePath = Join-Path $repoRoot 'scripts/SasSoftwareDeploymentTransport.psm1'
        $observationFixturePath = Join-Path $repoRoot 'Tests/Fixtures/software-deployment-transport/kerberos-smb-task-ready.fixture.json'
        $scenarioPath = Join-Path $repoRoot 'Tests/Fixtures/smb-scheduled-task-deployment/scenarios.json'
        $schemaPath = Join-Path $repoRoot 'schemas/harness/smb-scheduled-task-deployment-result.schema.json'
        Import-Module $preflightModulePath -Force
        Import-Module $adapterPath -Force

        function New-FixturePreflightPath([string]$Name = 'preflight.json') {
            $fixture = Get-Content -LiteralPath $observationFixturePath -Raw | ConvertFrom-Json
            $result = SasSoftwareDeploymentTransport\New-SasSoftwareDeploymentTransportResult -Observations $fixture.observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
            $path = Join-Path $TestDrive $Name
            $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding UTF8
            return $path
        }
    }

    AfterAll {
        Remove-Module SasSoftwareDeploymentAdapter -ErrorAction SilentlyContinue
        Remove-Module SasSoftwareDeploymentTransport -ErrorAction SilentlyContinue
    }

    It 'selects SmbScheduledTask from a fresh internally consistent P02 fixture' {
        $path = New-FixturePreflightPath
        $decision = Resolve-SasSoftwareDeploymentTransport -Transport Auto -PreflightResultPath $path -AllowFixturePreflight
        $decision.selected_transport | Should -Be 'SmbScheduledTask'
        $decision.preflight_consumed | Should -BeTrue
        $decision.selected_before_mutation | Should -BeTrue
        $decision.fallback_after_mutation_permitted | Should -BeFalse
    }

    It 'rejects a stale P02 result before mutation' {
        $path = New-FixturePreflightPath 'stale.json'
        (Get-Item -LiteralPath $path).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-31)
        { Resolve-SasSoftwareDeploymentTransport -Transport Auto -PreflightResultPath $path -PreflightMaxAgeMinutes 15 -AllowFixturePreflight } |
            Should -Throw '*stale*'
    }

    It 'rejects an inconsistent P02 decision before mutation' {
        $path = New-FixturePreflightPath 'inconsistent.json'
        $result = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $result.decision.selected_transport = 'winrm'
        $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding UTF8
        { Resolve-SasSoftwareDeploymentTransport -Transport Auto -PreflightResultPath $path -AllowFixturePreflight } |
            Should -Throw '*inconsistent*'
    }

    It 'requires exact FQDN targets for the SMB adapter' {
        Test-SasDeploymentFqdn -ComputerName 'fixture-target.example.test' | Should -BeTrue
        Test-SasDeploymentFqdn -ComputerName 'fixture-target' | Should -BeFalse
    }

    It 'has no credential, password, user, or secret parameter surface' {
        $command = Get-Command Invoke-SasSmbScheduledTaskDeployment
        foreach ($name in @('Credential','Password','User','Secret','SmbPass','SmbUser')) {
            $command.Parameters.Keys | Should -Not -Contain $name
        }
        { Invoke-SasSmbScheduledTaskDeployment -Password 'forbidden' } | Should -Throw
    }

    It 'generates a target-side hash and SYSTEM-verifying worker without automatic reboot' {
        $workerPath = Join-Path $TestDrive 'worker.ps1'
        New-SasSmbTaskWorker -Path $workerPath `
            -RunId 'software-install-20000101-000000-00000000' `
            -PackageName 'Fixture Package' `
            -InstallerPath 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20000101-000000-00000000\fixture.exe' `
            -ExpectedSha256 ('0' * 64) `
            -InstallerArguments @('/quiet') `
            -ValidationChecks @([pscustomobject]@{ id='fixture-file'; type='FileExists'; required=$true; path='C:\Fixture\installed.txt' }) `
            -ResultPath 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20000101-000000-00000000\worker-result.json'
        $worker = Get-Content -LiteralPath $workerPath -Raw
        foreach ($fragment in @('Get-FileHash','S-1-5-18','target_hash_verified','result_complete','3010','validation_after_payload_cleanup')) {
            $worker | Should -Match ([regex]::Escape($fragment))
        }
        $worker | Should -Not -Match 'Restart-Computer|shutdown\.exe|Get-Credential|ConvertFrom-SecureString'
    }

    It 'simulates every bounded failure and success fixture with closed cleanup and fallback state' {
        $scenarios = Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json
        $required = @((Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json).required)
        foreach ($scenario in @($scenarios.scenarios)) {
            $fixtureRoot = Join-Path $TestDrive ([string]$scenario.id)
            $result = Invoke-SasSmbScheduledTaskDeploymentFixture -FixtureRoot $fixtureRoot -Scenario ([string]$scenario.id)
            [string]$result.status | Should -Be ([string]$scenario.expected_status) -Because $scenario.id
            $result.fallback_attempted | Should -BeFalse -Because $scenario.id
            $result.network_activity_performed | Should -BeFalse -Because $scenario.id
            foreach ($property in $required) { $result.PSObject.Properties.Name | Should -Contain $property -Because $scenario.id }

            if ([string]$scenario.expected_status -eq 'cleanup_failed') {
                ($result.cleanup.task_remaining -or $result.cleanup.run_root_remaining) | Should -BeTrue -Because $scenario.id
            }
            elseif ([string]$scenario.expected_status -ne 'failed_before_staging') {
                $result.cleanup.task_remaining | Should -BeFalse -Because $scenario.id
                $result.cleanup.run_root_remaining | Should -BeFalse -Because $scenario.id
            }
        }
    }
}
