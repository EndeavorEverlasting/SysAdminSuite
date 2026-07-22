#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Harmless software deployment transport live certification' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'scripts/SasSoftwareDeploymentLiveCert.psm1'
        $script:entrypoint = Join-Path $repoRoot 'scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1'
        $script:preflightFixture = Join-Path $repoRoot 'Tests/Fixtures/software-deployment-transport/kerberos-smb-task-ready.fixture.json'
        $script:scenarioPath = Join-Path $repoRoot 'Tests/Fixtures/software-deployment-transport-live-cert/scenarios.json'
        Import-Module $script:modulePath -Force
    }

    AfterAll {
        Remove-Module SasSoftwareDeploymentLiveCert -ErrorAction SilentlyContinue
    }

    It 'accepts only one FQDN and exposes no credential, installer, package, or command payload parameter' {
        Test-SasLiveCertFqdn -ComputerName 'transport-node.example.test' | Should -BeTrue
        Test-SasLiveCertFqdn -ComputerName 'transport-node' | Should -BeFalse
        $command = Get-Command -Name $script:entrypoint
        foreach ($forbidden in @('Credential','Password','Username','InstallerPath','PackagePath','ArgumentList','Command','ScriptBlock','Transport')) {
            $command.Parameters.Keys | Should -Not -Contain $forbidden
        }
        $command.Parameters.Keys | Should -Contain 'AllowNetworkActivity'
        $command.Parameters.Keys | Should -Contain 'AllowTargetMutation'
    }

    It 'generates a nonce-bound harmless worker without a software execution primitive' {
        $workerPath = Join-Path $TestDrive 'worker.ps1'
        New-SasLiveCertWorker -Path $workerPath -RunId 'transport-live-cert-20000101-000000-00000000' -Nonce ('a' * 32) -ResultPath 'C:\ProgramData\SysAdminSuite\TransportLiveCert\fixture\worker-result.json'
        $worker = Get-Content -LiteralPath $workerPath -Raw
        $worker | Should -Match 'S-1-5-18'
        $worker | Should -Match 'harmless_payload_only'
        $worker | Should -Match 'software_installation_performed'
        $worker | Should -Not -Match 'Start-Process|msiexec|\.msi|\.exe|Invoke-Expression|DownloadFile|WebClient'
    }

    It 'rejects a worker result with the wrong nonce or a software-install claim' {
        $base = [pscustomobject]@{
            schema_version = 'sas-software-deployment-transport-live-cert-worker-result/v1'
            run_id = 'transport-live-cert-20000101-000000-00000000'
            nonce = ('a' * 32)
            execution_identity_sid = 'S-1-5-18'
            executed_as_system = $true
            harmless_payload_only = $true
            software_installation_performed = $false
            completed = $true
            error = $null
        }
        { Test-SasLiveCertWorkerResult -Result $base -RunId $base.run_id -Nonce ('b' * 32) } | Should -Throw
        $base.software_installation_performed = $true
        { Test-SasLiveCertWorkerResult -Result $base -RunId $base.run_id -Nonce $base.nonce } | Should -Throw
        $base.software_installation_performed = $false
        $base.executed_as_system = 'true'
        { Test-SasLiveCertWorkerResult -Result $base -RunId $base.run_id -Nonce $base.nonce } | Should -Throw
    }

    It 'simulates the complete bounded fixture matrix with zero network and target mutation claims' {
        $scenarios = Get-Content -LiteralPath $script:scenarioPath -Raw | ConvertFrom-Json
        foreach ($scenario in @($scenarios.scenarios)) {
            $fixtureRoot = Join-Path $TestDrive ([string]$scenario.id)
            $lifecycle = Invoke-SasSoftwareDeploymentTransportLiveCertFixture `
                -FixtureRoot $fixtureRoot `
                -Scenario ([string]$scenario.id) `
                -RunId 'transport-live-cert-20000101-000000-00000000'
            $lifecycle.status | Should -Be ([string]$scenario.expected_status) -Because $scenario.id
            $lifecycle.cleanup.zero_remnants_verified | Should -Be ([bool]$scenario.expected_zero_remnants) -Because $scenario.id
            $lifecycle.network_activity_performed | Should -BeFalse -Because $scenario.id
            $lifecycle.target_mutation_performed | Should -BeFalse -Because $scenario.id
            $lifecycle.fallback_attempted | Should -BeFalse -Because $scenario.id
            $lifecycle.execution.software_installation_performed | Should -BeFalse -Because $scenario.id
            $lifecycle.execution.harmless_payload_only | Should -BeTrue -Because $scenario.id
        }
    }

    It 'executes the success fixture through the run context and emits the closed source result' {
        $outputRoot = Join-Path $repoRoot ('survey/output/pester-live-cert-' + [guid]::NewGuid().ToString('N'))
        $freshPreflight = Join-Path $TestDrive 'preflight.json'
        Copy-Item -LiteralPath $script:preflightFixture -Destination $freshPreflight
        try {
            $execution = & $script:entrypoint `
                -FixtureMode `
                -FixtureScenario success `
                -PreflightResultPath $freshPreflight `
                -OutputRoot $outputRoot `
                -PassThru
            $execution.disposition | Should -Be 'CONTRACT FIXTURE ONLY'
            $execution.lifecycle_status | Should -Be 'certified'
            $execution.result.network_activity_performed | Should -BeFalse
            $execution.result.target_mutation_performed | Should -BeFalse
            $execution.result.certification.task_created | Should -BeTrue
            $execution.result.certification.executed_as_system | Should -BeTrue
            $execution.result.certification.result_retrieved | Should -BeTrue
            $execution.result.certification.task_deleted | Should -BeTrue
            $execution.result.certification.staging_deleted | Should -BeTrue
            $execution.result.certification.zero_remnants_verified | Should -BeTrue
            $execution.result.certification.software_installation_performed | Should -BeFalse
            Test-Path -LiteralPath $execution.result_path -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $execution.artifact_registry_path -Raw | ConvertFrom-Json).artifacts.Count | Should -Be 3
        }
        finally {
            if (Test-Path -LiteralPath $outputRoot) { Remove-Item -LiteralPath $outputRoot -Recurse -Force }
        }
    }
}
