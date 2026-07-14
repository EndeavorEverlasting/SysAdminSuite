#Requires -Version 5.1
<#
.SYNOPSIS
    Generates a self-contained agent sprint capsule for AI agent handoff.

.DESCRIPTION
    Emits a single chat-ready JSON that gives an AI agent everything it needs
    to enter a bounded repo sprint in a new chat. Validates inputs against
    rejection rules and writes the capsule to runs/capsules/.

.PARAMETER SprintId
    Kebab-case sprint identifier (e.g. 'agent-sprint-capsule').

.PARAMETER RepoRoot
    Absolute path to the repository root.

.PARAMETER BranchName
    Kebab-case branch name for this sprint.

.PARAMETER WorktreePath
    Absolute path to the isolated worktree. Must not be a shared path.

.PARAMETER OwnedPaths
    Array of repo-relative paths this sprint owns.

.PARAMETER ForbiddenScope
    Array of repo-relative paths forbidden to this sprint.

.PARAMETER Dependencies
    Array of upstream sprint IDs this sprint depends on.

.PARAMETER PrimarySkill
    Primary skill ID from the capability manifest.

.PARAMETER SkillPaths
    Array of repo-relative skill file paths to load.

.PARAMETER LoadOrder
    Ordered array of skill IDs to load.

.PARAMETER RequiredCapabilities
    Array of capability IDs required by this sprint.

.PARAMETER CapabilityPaths
    Array of repo-relative capability file paths.

.PARAMETER ValidationCommands
    Hashtable with keys: schema_validate, pester, ai_layer_validate, contract.

.PARAMETER ProofCeiling
    Proof ceiling level (e.g. 'P4_unit_test').

.PARAMETER OutputRoot
    Override output directory. Defaults to <RepoRoot>/runs/capsules/.

.EXAMPLE
    New-SasSprintCapsule -SprintId 'agent-sprint-capsule' -RepoRoot 'C:\repo' `
        -BranchName 'feat/agent-sprint-capsule' -WorktreePath 'C:\worktrees\repo' `
        -OwnedPaths @('tools/New-SasSprintCapsule.ps1','schemas/harness/agent-sprint-capsule.schema.json') `
        -ForbiddenScope @('scripts/SasRunContext.psm1') `
        -PrimarySkill 'repository-sprint' `
        -SkillPaths @('.claude/skills/repository-sprint/SKILL.md') `
        -LoadOrder @('repository-sprint') `
        -RequiredCapabilities @('repository-evidence','proof-and-checkpointing') `
        -CapabilityPaths @('.claude/capabilities/repository-evidence.md') `
        -ValidationCommands @{ schema_validate=''; pester=''; ai_layer_validate=''; contract='' } `
        -ProofCeiling 'P4_unit_test'
#>
function New-SasSprintCapsule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]*$')]
        [string]$SprintId,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9._/-]*$')]
        [string]$BranchName,

        [Parameter(Mandatory = $true)]
        [string]$WorktreePath,

        [Parameter(Mandatory = $true)]
        [string[]]$OwnedPaths,

        [Parameter(Mandatory = $true)]
        [string[]]$ForbiddenScope,

        [string[]]$Dependencies = @(),

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]*$')]
        [string]$PrimarySkill,

        [Parameter(Mandatory = $true)]
        [string[]]$SkillPaths,

        [Parameter(Mandatory = $true)]
        [string[]]$LoadOrder,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredCapabilities,

        [Parameter(Mandatory = $true)]
        [string[]]$CapabilityPaths,

        [Parameter(Mandatory = $true)]
        [hashtable]$ValidationCommands,

        [Parameter(Mandatory = $true)]
        [ValidateSet('P0_schema_validation','P1_static_lint','P2_unit_proof','P3_integration','P4_unit_test','P5_smoke','P6_E2E_fixture','P7_E2E_live','P8_runtime')]
        [string]$ProofCeiling,

        [string]$OutputRoot
    )

    $ErrorActionPreference = 'Stop'
    $generatorVersion = '1.0.0'
    $schemaVersion = 'sas-agent-sprint-capsule/v1'
    $now = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

    # --- Rejection: shared worktree (before path resolution) ---
    $sharedMarkers = @('.git', 'survey', 'targets', 'logs')
    $normalizedWorktree = $WorktreePath -replace '\\', '/'
    foreach ($marker in $sharedMarkers) {
        $sep = if ($normalizedWorktree -match '/') { '/' } else { '\' }
        $pattern = "(?:^|[\\/])" + [regex]::Escape($marker) + "(?:[\\/]|$)"
        if ($normalizedWorktree -match $pattern) {
            throw "REJECT: Worktree path appears to be under a shared directory '$marker'. Isolated worktree required."
        }
    }

    # --- Rejection: owned/forbidden overlap ---
    $ownedSet = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($p in $OwnedPaths) { [void]$ownedSet.Add($p) }

    $forbiddenSet = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($p in $ForbiddenScope) { [void]$forbiddenSet.Add($p) }

    foreach ($p in $OwnedPaths) {
        if ($forbiddenSet.Contains($p)) {
            throw "REJECT: Path '$p' appears in both owned_paths and forbidden_scope."
        }
    }

    # --- Rejection: local-path leakage ---
    $localPathPattern = '^[A-Za-z]:[/\\]|^/[a-z]'
    foreach ($p in $OwnedPaths) {
        if ($p -match $localPathPattern) {
            throw "REJECT: Owned path '$p' contains a local/absolute path. Use repo-relative paths only."
        }
    }
    foreach ($p in $ForbiddenScope) {
        if ($p -match $localPathPattern) {
            throw "REJECT: Forbidden scope '$p' contains a local/absolute path. Use repo-relative paths only."
        }
    }

    # --- Rejection: validation commands required ---
    $requiredCommands = @('schema_validate', 'pester', 'ai_layer_validate', 'contract')
    foreach ($cmd in $requiredCommands) {
        if (-not $ValidationCommands.ContainsKey($cmd) -or
            [string]::IsNullOrWhiteSpace($ValidationCommands[$cmd])) {
            throw "REJECT: Validation command '$cmd' is missing or empty. All validation commands are required."
        }
    }

    # --- Rejection: dependency cycle detection ---
    if ($Dependencies.Count -gt 0) {
        $depSet = [System.Collections.Generic.HashSet[string]]::new($Dependencies)
        if ($depSet.Contains($SprintId)) {
            throw "REJECT: Sprint '$SprintId' lists itself as a dependency (cycle)."
        }
    }

    # --- Rejection: proof ceiling levels must be non-empty ---
    $validLevels = @(
        'P0_schema_validation','P1_static_lint','P2_unit_proof','P3_integration',
        'P4_unit_test','P5_smoke','P6_E2E_fixture','P7_E2E_live','P8_runtime'
    )
    $ceilingIndex = [Array]::IndexOf($validLevels, $ProofCeiling)
    if ($ceilingIndex -lt 0) {
        throw "REJECT: Proof ceiling '$ProofCeiling' is not a valid level."
    }
    $allowedLevels = $validLevels[0..$ceilingIndex]

    # --- Resolve paths (after rejection checks) ---
    $RepoRoot = (Get-Item -LiteralPath $RepoRoot -ErrorAction Stop).FullName
    $WorktreePath = (Get-Item -LiteralPath $WorktreePath -ErrorAction Stop).FullName

    # --- Build capsule ---
    $capsuleId = "$SprintId-capsule"

    if (-not $OutputRoot) {
        $OutputRoot = Join-Path $RepoRoot 'runs' 'capsules'
    }
    if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
        New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
    }
    $outputPath = Join-Path $OutputRoot "$capsuleId.json"

    $capsule = [ordered]@{
        schema_version = $schemaVersion
        schema_path    = 'schemas/harness/agent-sprint-capsule.schema.json'
        capsule        = [ordered]@{
            capsule_id        = $capsuleId
            generated_at      = $now
            output_path       = $outputPath
            generator_version = $generatorVersion
        }
        sprint         = [ordered]@{
            sprint_id     = $SprintId
            repo_root     = $RepoRoot
            sprint_skill  = $PrimarySkill
            skill_md_path = $SkillPaths[0]
        }
        branch         = [ordered]@{
            branch_name         = $BranchName
            worktree_path       = $WorktreePath
            is_isolated_worktree = $true
        }
        scope          = [ordered]@{
            owned_paths     = @($OwnedPaths)
            forbidden_scope = @($ForbiddenScope)
            dependencies    = @($Dependencies)
        }
        skills         = [ordered]@{
            primary_skill = $PrimarySkill
            skill_paths   = @($SkillPaths)
            load_order    = @($LoadOrder)
        }
        capabilities   = [ordered]@{
            required_capabilities = @($RequiredCapabilities)
            capability_paths      = @($CapabilityPaths)
        }
        preflight      = [ordered]@{
            git_state         = [ordered]@{
                clean        = $true
                branch_count = 1
                detached     = $false
            }
            host_eligibility  = [ordered]@{
                policy_path = 'Config/host-eligibility-policy.json'
                status      = 'not_required'
            }
            artifacts         = [ordered]@{
                manifest_path = 'harness/api/agent-capability-manifest.json'
                schema_path   = 'schemas/harness/agent-capability-manifest.schema.json'
            }
        }
        validation     = [ordered]@{
            schema_validate_command    = $ValidationCommands['schema_validate']
            pester_command             = $ValidationCommands['pester']
            ai_layer_validate_command  = $ValidationCommands['ai_layer_validate']
            contract_command           = $ValidationCommands['contract']
        }
        proof_ceiling  = [ordered]@{
            level  = $ProofCeiling
            levels = @($allowedLevels)
        }
        adapters       = [ordered]@{
            opencode     = [ordered]@{
                root_instruction  = 'AGENTS.md'
                capsule_source    = $outputPath
                skill_load_method = 'progressive_disclosure_from_skill_router'
            }
            antigravity  = [ordered]@{
                capsule_source    = $outputPath
                skill_load_method = 'progressive_disclosure_from_skill_router'
            }
        }
    }

    $json = $capsule | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($outputPath, $json, [System.Text.UTF8Encoding]::new($false))

    return $capsule
}
