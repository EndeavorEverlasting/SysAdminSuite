#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
Set-StrictMode -Version Latest

Describe 'Agent sprint capsule generator' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:generator = Join-Path $script:repoRoot 'tools/New-SasSprintCapsule.ps1'
        $script:schema = Join-Path $script:repoRoot 'schemas/harness/agent-sprint-capsule.schema.json'
    }

    It 'generates a registered machine-local-path-free capsule from actual Git state' {
        $capsule = & $script:generator `
            -SprintId 'capsule-fixture' `
            -Title 'Capsule fixture proof' `
            -Lane 'harness' `
            -Mission 'Exercise the canonical run context, artifact registry, and compressed handoff.' `
            -OwnedPaths @('tools/New-SasSprintCapsule.ps1','schemas/harness/agent-sprint-capsule.schema.json') `
            -ForbiddenScope @('dashboard','targets/local') `
            -PrimarySkill 'repository-sprint' `
            -AdditionalSkills @('scoped-validation') `
            -WorkflowSpec 'harness/workflows/agent-sprint-capsule.yaml' `
            -ExpectedArtifacts @('schemas/harness/agent-sprint-capsule.schema.json') `
            -Completed @('Generated and registered a fixture capsule.') `
            -Remaining @() -Blockers @() `
            -ValidationCommands @('python3 Tests/survey/test_agent_sprint_capsule_contracts.py') `
            -SkippedChecks @('No live runtime proof was required.') `
            -ProofLevel 'P6_E2E_fixture' `
            -ProofCeiling 'Fixture run-context and artifact-registration proof only.' `
            -ClaimsNotMade @('No target was contacted.','No external agent runtime was observed.') `
            -NextCommand 'git status --short' `
            -RepositorySlug 'EndeavorEverlasting/SysAdminSuite'

        $capsule.schema_version | Should -Be 'sas-agent-sprint-capsule/v2'
        $capsule.repository.slug | Should -Be 'EndeavorEverlasting/SysAdminSuite'
        $capsule.routing.primary_skill | Should -Be 'repository-sprint'
        @($capsule.routing.capability_ids).Count | Should -BeGreaterThan 0
        $capsule.capsule.output_path | Should -Not -Match '^[A-Za-z]:[\\/]'
        $capsule.capsule.output_path | Should -Not -Match '^/'

        $capsulePath = Join-Path $script:repoRoot $capsule.capsule.output_path
        $registryPath = Join-Path $script:repoRoot $capsule.capsule.artifact_registry_path
        Test-Path -LiteralPath $capsulePath | Should -BeTrue
        Test-Path -LiteralPath $registryPath | Should -BeTrue
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        @($registry.artifacts | Where-Object role -eq 'agent-sprint-capsule').Count | Should -Be 1

        $serialized = Get-Content -LiteralPath $capsulePath -Raw
        $serialized | Should -Not -Match '(?i)[A-Za-z]:[\\/]'
        $serialized | Should -Not -Match '(?i)/(home|Users|mnt/c)/'
        $serialized | Should -Not -Match '(?i)%USERPROFILE%|\$HOME'

        $runRoot = Split-Path -Parent (Split-Path -Parent $capsulePath)
        Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'rejects hierarchical owned and forbidden scope overlap' {
        {
            & $script:generator -SprintId 'overlap-fixture' -Title 'Overlap fixture' -Lane 'harness' `
                -Mission 'Reject an unsafe scope overlap before creating a run.' `
                -OwnedPaths @('harness/api') -ForbiddenScope @('harness/api/private') `
                -PrimarySkill 'repository-sprint' -WorkflowSpec 'harness/workflows/agent-sprint-capsule.yaml' `
                -ExpectedArtifacts @('harness/api/agent-routing-manifest.json') `
                -Completed @('No work.') -ValidationCommands @('python3 Tests/survey/test_agent_sprint_capsule_contracts.py') `
                -ProofLevel 'P1_static_lint' -ProofCeiling 'Static rejection proof only.' `
                -ClaimsNotMade @('No mutation occurred.') -NextCommand 'git status --short' `
                -RepositorySlug 'EndeavorEverlasting/SysAdminSuite'
        } | Should -Throw '*owned and forbidden scope overlap*'
    }

    It 'rejects machine-local text in the compressed handoff' {
        {
            & $script:generator -SprintId 'leak-fixture' -Title 'Leak fixture' -Lane 'harness' `
                -Mission 'Reject local path leakage before creating a run.' `
                -OwnedPaths @('harness/api') -ForbiddenScope @('dashboard') `
                -PrimarySkill 'repository-sprint' -WorkflowSpec 'harness/workflows/agent-sprint-capsule.yaml' `
                -ExpectedArtifacts @('harness/api/agent-routing-manifest.json') `
                -Completed @('No work.') -ValidationCommands @('python3 Tests/survey/test_agent_sprint_capsule_contracts.py') `
                -ProofLevel 'P1_static_lint' -ProofCeiling 'Static rejection proof only.' `
                -ClaimsNotMade @('No mutation occurred.') -NextCommand 'git -C C:\Users\operator\repo status' `
                -RepositorySlug 'EndeavorEverlasting/SysAdminSuite'
        } | Should -Throw '*machine-local path or secret-like value*'
    }

    It 'keeps the schema closed and machine-local-path-free' {
        $schema = Get-Content -LiteralPath $script:schema -Raw | ConvertFrom-Json
        $schema.additionalProperties | Should -BeFalse
        $schema.'$defs'.safeText.not.pattern | Should -Match 'USERPROFILE'
        $schema.'$defs'.repoPath.pattern | Should -Match 'A-Za-z'
    }
}
