#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Cybernet deployment readiness' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:entrypoint = Join-Path $repoRoot 'scripts/Invoke-SasCybernetDeploymentReadiness.ps1'
        $script:deployment = Join-Path $repoRoot 'scripts/Invoke-SasCybernetSoftwareDeployment.ps1'
        $script:fixturePath = Join-Path $repoRoot 'Tests/Fixtures/software-deployment-transport/kerberos-smb-task-ready.fixture.json'
    }

    It 'parses the readiness and full deployment PowerShell surfaces' {
        foreach ($path in @($script:entrypoint, $script:deployment)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }

    It 'executes the SMB-ready fixture without network activity or target mutation' {
        $outputRoot = Join-Path $repoRoot ('survey/output/pester-cybernet-readiness-' + [guid]::NewGuid().ToString('N'))
        $target = 'cybernet-fixture.example.test'
        try {
            $execution = & $script:entrypoint -ComputerName $target -FixtureMode -FixturePath $script:fixturePath -OutputRoot $outputRoot -PassThru

            $execution.status | Should -Be 'CYBERNET_DEPLOYMENT_READINESS_FIXTURE_READY'
            $execution.ready_for_deployment | Should -BeFalse
            $execution.transport_classification | Should -Be 'kerberos_smb_task_ready'
            $execution.selected_transport | Should -Be 'kerberos_smb_task'
            $execution.transport_preflight_complete | Should -BeTrue
            $execution.transport_authorization_proven | Should -BeTrue
            $execution.network_activity_performed | Should -BeFalse
            $execution.target_mutation_performed | Should -BeFalse
            @($execution.tested_ports).Count | Should -Be 2
            @($execution.tested_ports)[0] | Should -Be 445
            @($execution.tested_ports)[1] | Should -Be 135
            Test-Path -LiteralPath $execution.result_path -PathType Leaf | Should -BeTrue

            $stored = Get-Content -LiteralPath $execution.result_path -Raw | ConvertFrom-Json
            $stored.target_scope.identifier_emitted | Should -BeFalse
            $stored.target_scope.target_fingerprint.Length | Should -Be 64
            $stored.PSObject.Properties.Name | Should -Not -Contain 'resolved_fqdn'
            ($stored | ConvertTo-Json -Depth 16) | Should -Not -Match [regex]::Escape($target)

            $runRoot = Split-Path -Parent (Split-Path -Parent $execution.result_path)
            Test-Path -LiteralPath (Join-Path $runRoot 'artifact_registry.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $runRoot 'operator_handoff.txt') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $runRoot 'reports/english_summary.txt') -PathType Leaf | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $outputRoot) { Remove-Item -LiteralPath $outputRoot -Recurse -Force }
        }
    }

    It 'keeps the fixture result below live deployment authority' {
        $content = Get-Content -LiteralPath $script:entrypoint -Raw
        $content | Should -Match 'CYBERNET_DEPLOYMENT_READINESS_FIXTURE_READY'
        $content | Should -Match 'ready_for_deployment = \$false'
        $content | Should -Match 'target_mutation_performed = \$false'
        $content | Should -Match "TransportIntent = 'kerberos_smb_task'"
        $content | Should -Not -Match "TransportIntent = 'auto'"
        $content | Should -Not -Match '(?i)\bnmap\b|\bnaabu\b'
        $content | Should -Not -Match 'shutdown\.exe|/Create|Invoke-SasCybernetClinicalCoreDeployment|Invoke-SasAutoLogonS4URestartDeployment'
    }

    It 'runs readiness before clinical-core and AutoLogon mutation' {
        $content = Get-Content -LiteralPath $script:deployment -Raw
        $readinessIndex = $content.IndexOf('$readiness = & $readinessScript', [System.StringComparison]::Ordinal)
        $coreIndex = $content.IndexOf('$coreResult = & $coreScript', [System.StringComparison]::Ordinal)
        $autoIndex = $content.IndexOf('$autoResult = & $autoScript', [System.StringComparison]::Ordinal)
        $readinessIndex | Should -BeGreaterThan -1
        $coreIndex | Should -BeGreaterThan $readinessIndex
        $autoIndex | Should -BeGreaterThan $coreIndex
        $content | Should -Match 'CYBERNET_DEPLOYMENT_READINESS_READY'
        $content | Should -Match 'Live deployment was not started'
        $content | Should -Match 'Where-Object \{ \$_ -in @\(5985,5986\) \}'
    }
}
