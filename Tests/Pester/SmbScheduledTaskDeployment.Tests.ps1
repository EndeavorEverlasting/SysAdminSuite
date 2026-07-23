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
        $inspectorPath = Join-Path $repoRoot 'scripts/Show-SasValidatedSoftwareDeploymentResult.ps1'
        $reviewFixtureRoot = Join-Path $repoRoot ('survey/output/pester-smb-finalization-' + [guid]::NewGuid().ToString('N'))
        Import-Module $preflightModulePath -Force
        Import-Module $adapterPath -Force

        function New-FixturePreflightPath([string]$Name = 'preflight.json') {
            $fixture = Get-Content -LiteralPath $observationFixturePath -Raw | ConvertFrom-Json
            $result = SasSoftwareDeploymentTransport\New-SasSoftwareDeploymentTransportResult -Observations $fixture.observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
            $path = Join-Path $TestDrive $Name
            $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding UTF8
            return $path
        }

        function New-SmbReviewFixture([string]$Name, [string]$FinalStatus, [switch]$MissingLifecycleEvent) {
            $runRoot = Join-Path $reviewFixtureRoot $Name
            New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
            $runId = 'software-install-20000101-000000-00000000'
            $complete = $FinalStatus -eq 'COMPLETED_VALIDATED_FINALIZED'
            $validationFailure = $FinalStatus -eq 'VALIDATION_FAILED_TOOLS_REMOVED'
            $preservationFailure = $FinalStatus -eq 'REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN'
            $teardownFailure = $FinalStatus -eq 'TEARDOWN_FAILED'
            $installFailure = $FinalStatus -eq 'INSTALL_FAILED_TOOLS_REMOVED'
            $row = [pscustomobject][ordered]@{
                computer_name = 'fixture-target.example.test'
                finalization_status = $FinalStatus
                validation_before_cleanup_succeeded = (-not $validationFailure -and -not $installFailure)
                cleanup_succeeded = (-not $teardownFailure)
                requested_software_preserved_after_teardown = $complete
                repo_artifact_remaining = $teardownFailure
                error = if ($complete) { $null } else { 'synthetic bounded failure' }
            }
            $classification = if ($complete) { 'DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED' }
                elseif ($teardownFailure) { 'TEARDOWN_FAILED' }
                elseif ($preservationFailure) { 'REQUESTED_SOFTWARE_NOT_PRESERVED' }
                elseif ($validationFailure) { 'POST_INSTALL_VALIDATION_FAILED_TOOLS_REMOVED' }
                else { 'INSTALL_FAILED_TOOLS_REMOVED' }
            [pscustomobject][ordered]@{
                run_id = $runId
                package_name = 'Fixture Package'
                results = @($row)
            } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $runRoot 'software_install_summary.json') -Encoding UTF8
            [pscustomobject][ordered]@{
                run_id = $runId
                package_name = 'Fixture Package'
                classification = $classification
                deployment_complete = $complete
                target_count = 1
                completed_validated_finalized_count = [int]$complete
                install_failure_count = [int]$installFailure
                validation_failure_count = [int]$validationFailure
                teardown_failure_count = [int]$teardownFailure
                preservation_failure_count = [int]$preservationFailure
                requested_software_uninstall_performed = $false
                results = @($row)
            } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $runRoot 'software_install_finalization.json') -Encoding UTF8
            [pscustomobject][ordered]@{
                run_id = $runId
                package_name = 'Fixture Package'
                deployment_complete = $complete
                installer_hash_verified = $true
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'validated_deployment_result.json') -Encoding UTF8
            'synthetic operator handoff' | Set-Content -LiteralPath (Join-Path $runRoot 'operator_handoff.txt') -Encoding UTF8
            $events = @('run_started','target_started','target_completed','finalization_started','finalization_completed','run_completed')
            if ($MissingLifecycleEvent) { $events = @($events | Where-Object { $_ -ne 'finalization_completed' }) }
            @($events | ForEach-Object {
                [pscustomobject][ordered]@{ timestamp_utc = '2000-01-01T00:00:00Z'; event = $_; run_id = $runId } |
                    ConvertTo-Json -Compress
            }) | Set-Content -LiteralPath (Join-Path $runRoot 'software_install_events.jsonl') -Encoding UTF8
            return $runRoot
        }

        function Invoke-SmbReviewFixture([string]$RunRoot) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $inspectorPath -RunRoot $RunRoot -RequireCompleted *> $null
            return $LASTEXITCODE
        }
    }

    AfterAll {
        Remove-Module SasSoftwareDeploymentAdapter -ErrorAction SilentlyContinue
        Remove-Module SasSoftwareDeploymentTransport -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $reviewFixtureRoot) { Remove-Item -LiteralPath $reviewFixtureRoot -Recurse -Force }
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

    It 'preserves the approved empty installer-argument collection through worker generation' {
        foreach ($commandName in @('Invoke-SasSmbScheduledTaskDeployment','New-SasSmbTaskWorker')) {
            $command = Get-Command $commandName
            @($command.Parameters['InstallerArguments'].Attributes | Where-Object {
                $_ -is [Management.Automation.AllowEmptyCollectionAttribute]
            }).Count | Should -Be 1
        }

        $workerPath = Join-Path $TestDrive 'empty-arguments-worker.ps1'
        New-SasSmbTaskWorker -Path $workerPath `
            -RunId 'software-install-20000101-000000-00000000' `
            -PackageName 'Fixture Package' `
            -InstallerPath 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20000101-000000-00000000\fixture.exe' `
            -ExpectedSha256 ('0' * 64) `
            -InstallerArguments @() `
            -ValidationChecks @([pscustomobject]@{ id='fixture-file'; type='FileExists'; required=$true; path='C:\Fixture\installed.txt' }) `
            -ResultPath 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20000101-000000-00000000\worker-result.json'

        $worker = Get-Content -LiteralPath $workerPath -Raw
        $encodedConfig = [regex]::Match($worker, "FromBase64String\('(?<config>[^']+)'\)").Groups['config'].Value
        $encodedConfig | Should -Not -BeNullOrEmpty
        $config = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedConfig))) | ConvertFrom-Json
        @($config.installer_arguments).Count | Should -Be 0
        $worker | Should -Match 'if \(\$arguments\.Count -gt 0\) \{ \$start\.ArgumentList = \$arguments \}'
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

    It 'classifies success, validation, preservation, install, and teardown independently' {
        $base = Invoke-SasSmbScheduledTaskDeploymentFixture -FixtureRoot (Join-Path $TestDrive 'finalization-base') -Scenario success
        Resolve-SasSmbDeploymentFinalizationStatus -Result $base | Should -Be 'COMPLETED_VALIDATED_FINALIZED'

        $validationFailure = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $validationFailure.validation.before_payload_cleanup_succeeded = $false
        Resolve-SasSmbDeploymentFinalizationStatus -Result $validationFailure | Should -Be 'VALIDATION_FAILED_TOOLS_REMOVED'

        $preservationFailure = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $preservationFailure.validation.after_payload_cleanup_succeeded = $false
        Resolve-SasSmbDeploymentFinalizationStatus -Result $preservationFailure | Should -Be 'REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN'

        $installFailure = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $installFailure.result_retrieval.succeeded = $false
        Resolve-SasSmbDeploymentFinalizationStatus -Result $installFailure | Should -Be 'INSTALL_FAILED_TOOLS_REMOVED'

        $teardownFailure = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $teardownFailure.cleanup.task_remaining = $true
        Resolve-SasSmbDeploymentFinalizationStatus -Result $teardownFailure | Should -Be 'TEARDOWN_FAILED'
    }

    It 'runs the final evidence reviewer across SMB success and closed failure packages' {
        $cases = @(
            @{ name='success'; status='COMPLETED_VALIDATED_FINALIZED'; exit=0 },
            @{ name='validation'; status='VALIDATION_FAILED_TOOLS_REMOVED'; exit=24 },
            @{ name='preservation'; status='REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN'; exit=25 },
            @{ name='teardown'; status='TEARDOWN_FAILED'; exit=21 },
            @{ name='install'; status='INSTALL_FAILED_TOOLS_REMOVED'; exit=20 }
        )
        foreach ($case in $cases) {
            $runRoot = New-SmbReviewFixture -Name $case.name -FinalStatus $case.status
            Invoke-SmbReviewFixture -RunRoot $runRoot | Should -Be $case.exit -Because $case.name
        }
        $missing = New-SmbReviewFixture -Name 'missing-event' -FinalStatus 'COMPLETED_VALIDATED_FINALIZED' -MissingLifecycleEvent
        Invoke-SmbReviewFixture -RunRoot $missing | Should -Be 22
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
