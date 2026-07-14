#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'New-SasSprintCapsule' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:modulePath = Join-Path $repoRoot 'tools/New-SasSprintCapsule.ps1'
        . $script:modulePath
    }

    BeforeEach {
        $script:tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-capsule-' + [guid]::NewGuid().Guid)
        $script:repoDir = Join-Path $script:tmpRoot 'repo'
        $script:worktreeDir = Join-Path $script:tmpRoot 'worktrees' 'test-sprint'
        New-Item -Path (Join-Path $script:repoDir 'targets') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:repoDir 'survey') -ItemType Directory -Force | Out-Null
        New-Item -Path $script:worktreeDir -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:repoDir '.claude' 'skills' 'repository-sprint') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:repoDir 'targets' 'README.md') -Encoding UTF8 -Value '# targets'
        Set-Content -LiteralPath (Join-Path $script:repoDir '.claude' 'skills' 'repository-sprint' 'SKILL.md') -Encoding UTF8 -Value '# skill'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'generates a valid capsule with correct schema version and structure' {
        $capsule = New-SasSprintCapsule `
            -SprintId 'test-sprint' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/test-sprint' `
            -WorktreePath $script:worktreeDir `
            -OwnedPaths @('tools/Test-ScriptHealth.ps1') `
            -ForbiddenScope @('scripts/SasRunContext.psm1') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                pester            = 'pwsh -NoProfile -Command Invoke-Pester'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_contract.py'
            } `
            -ProofCeiling 'P4_unit_test'

        $capsule.schema_version | Should -Be 'sas-agent-sprint-capsule/v1'
        $capsule.schema_path | Should -Be 'schemas/harness/agent-sprint-capsule.schema.json'
        $capsule.capsule.capsule_id | Should -Be 'test-sprint-capsule'
        $capsule.capsule.generator_version | Should -Be '1.0.0'
        $capsule.sprint.sprint_id | Should -Be 'test-sprint'
        $capsule.branch.branch_name | Should -Be 'feat/test-sprint'
        $capsule.branch.is_isolated_worktree | Should -BeTrue
        $capsule.scope.owned_paths | Should -Contain 'tools/Test-ScriptHealth.ps1'
        $capsule.scope.forbidden_scope | Should -Contain 'scripts/SasRunContext.psm1'
        $capsule.skills.primary_skill | Should -Be 'repository-sprint'
        $capsule.capabilities.required_capabilities | Should -Contain 'repository-evidence'
        $capsule.proof_ceiling.level | Should -Be 'P4_unit_test'
        $capsule.proof_ceiling.levels | Should -Contain 'P0_schema_validation'
        $capsule.proof_ceiling.levels | Should -Contain 'P4_unit_test'
        $capsule.proof_ceiling.levels | Should -Not -Contain 'P5_smoke'
        $capsule.adapters.opencode.root_instruction | Should -Be 'AGENTS.md'
        $capsule.adapters.antigravity.skill_load_method | Should -Be 'progressive_disclosure_from_skill_router'
    }

    It 'writes capsule JSON to runs/capsules/' {
        $capsule = New-SasSprintCapsule `
            -SprintId 'file-output-test' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/file-output-test' `
            -WorktreePath $script:worktreeDir `
            -OwnedPaths @('tools/Test-ScriptHealth.ps1') `
            -ForbiddenScope @('scripts/SasRunContext.psm1') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                pester            = 'pwsh -NoProfile -Command Invoke-Pester'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_contract.py'
            } `
            -ProofCeiling 'P4_unit_test'

        $outputPath = Join-Path $script:repoDir 'runs' 'capsules' 'file-output-test-capsule.json'
        Test-Path -LiteralPath $outputPath | Should -BeTrue
        $onDisk = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $onDisk.schema_version | Should -Be 'sas-agent-sprint-capsule/v1'
        $onDisk.capsule.capsule_id | Should -Be 'file-output-test-capsule'
    }

    It 'rejects worktree under a shared directory' {
        $sharedDir = Join-Path $script:repoDir 'survey' 'output'
        New-Item -Path $sharedDir -ItemType Directory -Force | Out-Null

        { New-SasSprintCapsule `
            -SprintId 'dirty-test' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/dirty-test' `
            -WorktreePath $sharedDir `
            -OwnedPaths @('tools/Test-ScriptHealth.ps1') `
            -ForbiddenScope @('scripts/SasRunContext.psm1') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                pester            = 'pwsh -NoProfile -Command Invoke-Pester'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_contract.py'
            } `
            -ProofCeiling 'P4_unit_test'
        } | Should -Throw '*shared directory*'
    }

    It 'rejects path in both owned and forbidden scope' {
        { New-SasSprintCapsule `
            -SprintId 'dup-test' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/dup-test' `
            -WorktreePath $script:worktreeDir `
            -OwnedPaths @('tools/Test-ScriptHealth.ps1') `
            -ForbiddenScope @('tools/Test-ScriptHealth.ps1') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                pester            = 'pwsh -NoProfile -Command Invoke-Pester'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_contract.py'
            } `
            -ProofCeiling 'P4_unit_test'
        } | Should -Throw '*both owned_paths and forbidden_scope*'
    }

    It 'rejects absolute Windows path in owned_paths' {
        { New-SasSprintCapsule `
            -SprintId 'leak-test' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/leak-test' `
            -WorktreePath $script:worktreeDir `
            -OwnedPaths @('C:\Users\test\script.ps1') `
            -ForbiddenScope @('scripts/SasRunContext.psm1') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                pester            = 'pwsh -NoProfile -Command Invoke-Pester'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_contract.py'
            } `
            -ProofCeiling 'P4_unit_test'
        } | Should -Throw '*local/absolute path*'
    }

    It 'rejects missing validation command' {
        { New-SasSprintCapsule `
            -SprintId 'no-cmd-test' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/no-cmd-test' `
            -WorktreePath $script:worktreeDir `
            -OwnedPaths @('tools/Test-ScriptHealth.ps1') `
            -ForbiddenScope @('scripts/SasRunContext.psm1') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_contract.py'
            } `
            -ProofCeiling 'P4_unit_test'
        } | Should -Throw '*pester*missing*'
    }

    It 'rejects self-referencing dependency' {
        { New-SasSprintCapsule `
            -SprintId 'self-ref-test' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/self-ref-test' `
            -WorktreePath $script:worktreeDir `
            -OwnedPaths @('tools/Test-ScriptHealth.ps1') `
            -ForbiddenScope @('scripts/SasRunContext.psm1') `
            -Dependencies @('self-ref-test') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                pester            = 'pwsh -NoProfile -Command Invoke-Pester'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_contract.py'
            } `
            -ProofCeiling 'P4_unit_test'
        } | Should -Throw '*cycle*'
    }

    It 'creates output directory when it does not exist' {
        $customOutput = Join-Path $script:tmpRoot 'custom' 'capsule' 'output'
        $capsule = New-SasSprintCapsule `
            -SprintId 'mkdir-test' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/mkdir-test' `
            -WorktreePath $script:worktreeDir `
            -OwnedPaths @('tools/Test-ScriptHealth.ps1') `
            -ForbiddenScope @('scripts/SasRunContext.psm1') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                pester            = 'pwsh -NoProfile -Command Invoke-Pester'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_contract.py'
            } `
            -ProofCeiling 'P4_unit_test' `
            -OutputRoot $customOutput

        Test-Path -LiteralPath $customOutput -PathType Container | Should -BeTrue
        $outputFile = Join-Path $customOutput 'mkdir-test-capsule.json'
        Test-Path -LiteralPath $outputFile | Should -BeTrue
    }

    It 'capsule output matches valid fixture structure' {
        $capsule = New-SasSprintCapsule `
            -SprintId 'agent-sprint-capsule' `
            -RepoRoot $script:repoDir `
            -BranchName 'feat/agent-sprint-capsule' `
            -WorktreePath $script:worktreeDir `
            -OwnedPaths @('tools/New-SasSprintCapsule.ps1','schemas/harness/agent-sprint-capsule.schema.json') `
            -ForbiddenScope @('scripts/SasRunContext.psm1','harness/api/agent-capability-manifest.json') `
            -PrimarySkill 'repository-sprint' `
            -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
            -LoadOrder @('repository-sprint') `
            -RequiredCapabilities @('repository-evidence','proof-and-checkpointing') `
            -CapabilityPaths @('.claude/capabilities/repository-evidence.md','.claude/capabilities/proof-and-checkpointing.md') `
            -ValidationCommands @{
                schema_validate   = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                pester            = 'pwsh -NoProfile -Command "Invoke-Pester -Path Tests/Pester/SprintCapsule.Tests.ps1 -Output Detailed"'
                ai_layer_validate = 'pwsh -NoProfile -File tools/validate-ai-layer.ps1'
                contract          = 'python3 Tests/survey/test_agent_sprint_capsule_contracts.py'
            } `
            -ProofCeiling 'P4_unit_test' `
            -OutputRoot ([System.IO.Path]::GetTempPath())

        $capsule.scope.dependencies | Should -Be @()
        $capsule.skills.load_order | Should -Be @('repository-sprint')
        $capsule.preflight.git_state.clean | Should -BeTrue
        $capsule.preflight.host_eligibility.status | Should -Be 'not_required'
    }
}
