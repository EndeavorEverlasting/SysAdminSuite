#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'SasRunContext module' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'scripts/SasRunContext.psm1'
        $script:rendererPath = Join-Path $repoRoot 'scripts/Render-SasEnglishReport.ps1'
        Import-Module $script:modulePath -Force
    }

    It 'creates run ids with prefix and timestamp' {
        $id = New-SasRunId -Prefix 'target-reduction' -Timestamp ([datetime]'2026-07-07T21:00:00Z')
        $id | Should -Match '^target-reduction-20260707-210000-[a-f0-9]{8}$'
    }

    It 'validates workflow ids and rejects traversal' {
        Test-SasWorkflowId -WorkflowId 'serial-to-preflight' | Should -BeTrue
        Test-SasWorkflowId -WorkflowId '../serial-to-preflight' | Should -BeFalse
        Test-SasWorkflowId -WorkflowId 'serial/to/preflight' | Should -BeFalse
    }

    It 'creates the canonical local run context and registry under workflow/run id' {
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-run-context-' + [guid]::NewGuid().Guid)
        $repoRoot = Join-Path $tmpRoot 'repo'
        New-Item -Path (Join-Path $repoRoot 'survey/output/runs') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $repoRoot 'targets') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repoRoot 'targets/README.md') -Encoding UTF8 -Value '# targets'

        $context = New-SasRunContext `
            -WorkflowId 'serial-to-preflight' `
            -RunId 'run-20260707-210000-abc123ef' `
            -RepoRoot $repoRoot `
            -Survey `
            -RequestSummary 'fixture request' `
            -SourceArtifact 'Tests/fixtures/harness/request.json'

        (Split-Path -Leaf $context.run_root) | Should -Be 'run-20260707-210000-abc123ef'
        (Split-Path -Leaf (Split-Path -Parent $context.run_root)) | Should -Be 'serial-to-preflight'
        Test-Path -LiteralPath $context.workflow_root | Should -BeTrue

        foreach ($relative in @(
            'request.json',
            'context.json',
            'plan.json',
            'plan.md',
            'actions',
            'artifacts',
            'evidence',
            'reports',
            'review',
            'summary.json',
            'operator_handoff.txt',
            'artifact_registry.json'
        )) {
            Test-Path -LiteralPath (Join-Path $context.run_root $relative) | Should -BeTrue
        }

        { New-SasRunContext -WorkflowId 'serial-to-preflight' -RunId 'run-20260707-210000-abc123ef' -RepoRoot $repoRoot -Survey } | Should -Throw

        $second = New-SasRunContext `
            -WorkflowId 'serial-to-preflight' `
            -RunId 'run-20260707-210001-def456ab' `
            -RepoRoot $repoRoot `
            -Survey
        $second.run_root | Should -Not -Be $context.run_root

        $registry = Get-Content -LiteralPath $context.artifact_registry_path -Raw | ConvertFrom-Json
        $registry.schema_version | Should -Be 'sas-artifact-registry/v1'
        $registry.workflow_id | Should -Be 'serial-to-preflight'
        $registry.run_id | Should -Be 'run-20260707-210000-abc123ef'

        $entry = Register-SasArtifact `
            -RegistryPath $context.artifact_registry_path `
            -Role 'source-request' `
            -Path 'Tests/fixtures/harness/request.json' `
            -Tracked $true `
            -LiveData $false `
            -Description 'fixture request artifact' `
            -SourceArtifact 'operator request' `
            -NetworkActivity 'No network activity performed.'

        $entry.role | Should -Be 'source-request'
        $entry.tracked | Should -BeTrue
        $entry.live_data | Should -BeFalse
        $entry.contains_live_data | Should -BeFalse
        $entry.generated | Should -BeFalse

        $updated = Get-Content -LiteralPath $context.artifact_registry_path -Raw | ConvertFrom-Json
        @($updated.artifacts).Count | Should -Be 1
        $updated.artifacts[0].network_activity | Should -Be 'No network activity performed.'

        $reportPath = Join-Path $context.directories.reports 'run-context-report.md'
        Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'report' -Path $reportPath -Generated $true -Description 'English report derived from synthetic run context.' | Out-Null
        [ordered]@{
            workflow_id = $context.workflow_id
            run_id = $context.run_id
            request_summary = 'Render a synthetic run-context report.'
            source_artifacts = @('Tests/fixtures/harness/request.json')
            loaded_evidence_artifacts = @()
            planner_name = 'SasRunContext.Tests'
            planner_version = 'fixture/v1'
            network_activity_performed = $false
            low_noise_policy_version = '1.1'
            started_at = '2026-07-07T21:00:00Z'
            finished_at = '2026-07-07T21:00:01Z'
            operator_handoff_path = $context.operator_handoff_path
            summary_json_path = $context.summary_path
            report_markdown_path = $reportPath
            next_action = 'Review the synthetic report.'
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $context.summary_path -Encoding UTF8

        & $script:rendererPath -SummaryJson $context.summary_path -ArtifactRegistry $context.artifact_registry_path -Template 'audit' -OutputPath $reportPath
        Test-Path -LiteralPath $reportPath | Should -BeTrue
        (Get-Content -LiteralPath $reportPath -Raw) | Should -Match 'The source-request artifact at'

        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'derives safe run ids from numeric and long workflow ids' {
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-run-context-prefix-' + [guid]::NewGuid().Guid)
        $repoRoot = Join-Path $tmpRoot 'repo'
        New-Item -Path (Join-Path $repoRoot 'survey/output/runs') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $repoRoot 'targets') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repoRoot 'targets/README.md') -Encoding UTF8 -Value '# targets'

        $numeric = New-SasRunContext -WorkflowId '2026-rollout' -RepoRoot $repoRoot -Survey
        $numeric.run_id | Should -Match '^run-2026-rollout-\d{8}-\d{6}-[a-f0-9]{8}$'

        $long = New-SasRunContext -WorkflowId 'serial-to-preflight-with-a-very-long-workflow-name-for-contracts' -RepoRoot $repoRoot -Survey
        ($long.run_id -split '-\d{8}-\d{6}-')[0].Length | Should -BeLessOrEqual 32

        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'rejects non-local output roots unless explicitly overridden' {
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-run-context-deny-' + [guid]::NewGuid().Guid)
        $repoRoot = Join-Path $tmpRoot 'repo'
        New-Item -Path (Join-Path $repoRoot 'survey') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $repoRoot 'targets') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repoRoot 'targets/README.md') -Encoding UTF8 -Value '# targets'

        { Assert-SasLocalOutputRoot -RepoRoot $repoRoot -OutputRoot (Join-Path $tmpRoot 'outside') } | Should -Throw
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
