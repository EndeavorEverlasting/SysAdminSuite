#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Software deployment transport preflight' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'scripts/SasSoftwareDeploymentTransport.psm1'
        $script:entrypoint = Join-Path $repoRoot 'scripts/Test-SasSoftwareDeploymentTransport.ps1'
        $script:fixtureRoot = Join-Path $repoRoot 'Tests/Fixtures/software-deployment-transport'
        Import-Module $script:modulePath -Force

        function Read-TransportFixture([string]$Name) {
            Get-Content -LiteralPath (Join-Path $script:fixtureRoot $Name) -Raw | ConvertFrom-Json
        }

        function Copy-TransportObservations([object]$Value) {
            $Value | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        }
    }

    AfterAll {
        Remove-Module SasSoftwareDeploymentTransport -ErrorAction SilentlyContinue
    }

    It 'classifies every complete SMB prerequisite as kerberos_smb_task_ready' {
        $fixture = Read-TransportFixture 'kerberos-smb-task-ready.fixture.json'
        $result = New-SasSoftwareDeploymentTransportResult -Observations $fixture.observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'kerberos_smb_task_ready'
        $result.decision.selected_transport | Should -Be 'kerberos_smb_task'
    }

    It 'classifies an authorized WinRM session independently as winrm_ready' {
        $fixture = Read-TransportFixture 'winrm-ready.fixture.json'
        $result = New-SasSoftwareDeploymentTransportResult -Observations $fixture.observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'winrm_ready'
        $result.decision.selected_transport | Should -Be 'winrm'
    }

    It 'fails closed when only DNS is observed' {
        $fixture = Read-TransportFixture 'inconclusive.fixture.json'
        $observations = Copy-TransportObservations $fixture.observations
        $observations.dns.timed_out = $false
        $observations.dns.resolved = $true
        $observations.dns.address_count = 1
        $result = New-SasSoftwareDeploymentTransportResult -Observations $observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'inconclusive'
        $result.proof.preflight_complete | Should -BeFalse
    }

    It 'classifies a complete all-closed port observation when 445 is closed as no_supported_transport' {
        $fixture = Read-TransportFixture 'kerberos-smb-task-ready.fixture.json'
        $observations = Copy-TransportObservations $fixture.observations
        foreach ($name in @('port_5985', 'port_5986', 'port_445', 'port_135')) {
            $observations.tcp.$name.tested = $true
            $observations.tcp.$name.reachable = $false
            $observations.tcp.$name.timed_out = $false
        }
        $result = New-SasSoftwareDeploymentTransportResult -Observations $observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'no_supported_transport'
    }

    It 'does not select SMB when 135 is closed even if 445 is reachable' {
        $fixture = Read-TransportFixture 'kerberos-smb-task-ready.fixture.json'
        $observations = Copy-TransportObservations $fixture.observations
        $observations.tcp.port_135.reachable = $false
        $result = New-SasSoftwareDeploymentTransportResult -Observations $observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'inconclusive'
        $result.decision.selected_transport | Should -Be 'none'
    }

    It 'distinguishes inaccessible ADMIN share authorization from reachability' {
        $fixture = Read-TransportFixture 'authorization-denied.fixture.json'
        $result = New-SasSoftwareDeploymentTransportResult -Observations $fixture.observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'transport_reachable_authorization_denied'
    }

    It 'distinguishes Schedule service denial from reachability' {
        $fixture = Read-TransportFixture 'kerberos-smb-task-ready.fixture.json'
        $observations = Copy-TransportObservations $fixture.observations
        $observations.schedule_service.running = $false
        $observations.schedule_service.authorization_denied = $true
        $result = New-SasSoftwareDeploymentTransportResult -Observations $observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'transport_reachable_authorization_denied'
    }

    It 'distinguishes scheduled-task read-query denial from reachability' {
        $fixture = Read-TransportFixture 'kerberos-smb-task-ready.fixture.json'
        $observations = Copy-TransportObservations $fixture.observations
        $observations.scheduled_task_query.succeeded = $false
        $observations.scheduled_task_query.authorization_denied = $true
        $result = New-SasSoftwareDeploymentTransportResult -Observations $observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'transport_reachable_authorization_denied'
    }

    It 'fails a timed-out observation closed to inconclusive' {
        $fixture = Read-TransportFixture 'kerberos-smb-task-ready.fixture.json'
        $observations = Copy-TransportObservations $fixture.observations
        $observations.tcp.port_445.reachable = $false
        $observations.tcp.port_445.timed_out = $true
        $result = New-SasSoftwareDeploymentTransportResult -Observations $observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $result.decision.classification | Should -Be 'inconclusive'
        $result.decision.reason_codes | Should -Contain 'observation_timeout'
    }

    It 'accepts only FQDN live target input' {
        Test-SasFqdn -ComputerName 'transport-node.example.test' | Should -BeTrue
        Test-SasFqdn -ComputerName 'transport-node' | Should -BeFalse
        Test-SasFqdn -ComputerName 'bad name.example.test' | Should -BeFalse
    }

    It 'exposes an optional runtime-only PSCredential and no interactive prompt' {
        $command = Get-Command -Name $script:entrypoint
        $command.Parameters['Credential'].ParameterType.FullName | Should -Be 'System.Management.Automation.PSCredential'
        $content = Get-Content -LiteralPath $script:entrypoint -Raw
        $content | Should -Not -Match 'Get-Credential'
        $content | Should -Not -Match 'ConvertFrom-SecureString|ConvertTo-SecureString'
    }

    It 'executes the SMB-ready fixture through the run context without network activity' {
        $fixturePath = Join-Path $script:fixtureRoot 'kerberos-smb-task-ready.fixture.json'
        $outputRoot = Join-Path $repoRoot ('survey/output/pester-transport-' + [guid]::NewGuid().ToString('N'))
        try {
            $execution = & $script:entrypoint -FixtureMode -FixturePath $fixturePath -OutputRoot $outputRoot -PassThru
            $execution.result.decision.classification | Should -Be 'kerberos_smb_task_ready'
            $execution.result.network_activity_performed | Should -BeFalse
            $execution.result.target_mutation_performed | Should -BeFalse
            Test-Path -LiteralPath $execution.result_path -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $execution.english_summary_path -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $execution.artifact_registry_path -Raw | ConvertFrom-Json).artifacts.Count | Should -Be 3
        }
        finally {
            if (Test-Path -LiteralPath $outputRoot) { Remove-Item -LiteralPath $outputRoot -Recurse -Force }
        }
    }

    It 'does not leak ticket bytes, target identifiers, usernames, credentials, or raw faults' {
        $fixture = Read-TransportFixture 'kerberos-smb-task-ready.fixture.json'
        $result = New-SasSoftwareDeploymentTransportResult -Observations $fixture.observations -EvidenceClass sanitized_fixture -NetworkActivityPerformed $false
        $json = $result | ConvertTo-Json -Depth 12
        $json | Should -Not -Match '(?i)hostname|username|credential|session[_ ]?key|ticket[_ ]?cache|raw[_ ]?(xml|fault)'
        $result.target_scope.identifier_emitted | Should -BeFalse
        $result.observations.identity.ticket_bytes_emitted | Should -BeFalse
    }
}
