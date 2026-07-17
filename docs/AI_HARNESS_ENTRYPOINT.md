# SysAdminSuite Repo-Local AI Harness Entry Point

This document is the operational index for a fresh agent entering SysAdminSuite. Prompts are inputs to the harness; they are not the harness itself. Application behavior remains in scripts, services, schemas, launchers, and tests.

## Fresh-agent sequence

1. Read `AGENTS.md` for universal rules and source precedence.
2. Read `CODEBASE_MAP.md` to find the smallest product and validation surface.
3. Match exact task signals in `harness/api/agent-routing-manifest.json`. Conflicting or unknown primary signals fail closed to `repository-sprint`; additive safety guards may compose.
4. For a `skill` target, load the selected `.claude/skills/*/SKILL.md` file and only its declared capability dependencies. For a `harness_operation` target, collect every declared required input and apply the input mapping from its registered workflow before invoking the repo-owned entrypoint.
5. Inspect Git, worktrees, open PRs, generated-output policy, and the current implementation before mutating anything.
6. Select an existing workflow spec and product entrypoint. Do not move product logic into a prompt, skill, or trigger.
7. Create or reuse the canonical run context when the workflow emits evidence.
8. Register generated artifacts, run targeted diagnostics, the applicable E2E journey, and broader gates.
9. Render English/operator outputs from structured artifacts.
10. Compress the final state into a schema-backed sprint capsule when another agent or chat must continue.

## Harness inventory

| Surface | Authority | Status |
|---|---|---|
| Repo agent rules | `AGENTS.md`, `CLAUDE.md` | Implemented |
| Codebase map | `CODEBASE_MAP.md` | Implemented |
| Skill/capability catalog | `harness/api/agent-capability-manifest.json` | Implemented and manifest-driven |
| Deterministic task routing | `harness/api/agent-routing-manifest.json` | Implemented; routes only, never authorizes mutation |
| AgentSwitchboard GNHF compatibility | `harness/api/agentswitchboard-gnhf-external-contract.json` | Implemented as an exact external version/blob pin; no runtime code copied |
| Scoped skills | `.claude/skills/*/SKILL.md` | Implemented |
| Reusable capabilities | `.claude/capabilities/*.md` | Implemented |
| Workflow specs | `.archon/workflows/`, `survey/workflows/`, `harness/workflows/` | Implemented by lane |
| Run context | `scripts/SasRunContext.psm1` | Implemented |
| Artifact registry | `sas-artifact-registry/v1` through `SasRunContext.psm1` | Implemented |
| Harness API | `harness/api/sas-harness-api.json` | Implemented |
| Validators | `tools/validate-ai-layer.ps1`, contract suites, Pester, E2E workflows | Implemented |
| Local hooks | `scripts/install-local-harness-hooks.sh`, `docs/LOCAL_DEVELOPMENT_HARNESS.md` | Optional and implemented |
| Read-only explorer | `.claude/agents/explorer.md` | Implemented as scoped guidance |
| Local MCP servers | `mcp/local/servers.json` | Planned; catalog entries are not runtime proof |
| English/operator reports | `scripts/Render-SasEnglishReport.ps1`, `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md` | Implemented for structured artifacts |
| Final handoff compression | `tools/New-SasSprintCapsule.ps1`, `schemas/harness/agent-sprint-capsule.schema.json` | Implemented |

The GNHF adoption seam routes explicit compile-only, local execute, environment Plan, and registered overnight workflow signals through `.claude/skills/gnhf-prompt-adoption/SKILL.md`. SysAdminSuite owns its request scope, workflow selection, validation, result ingestion, and capsule. AgentSwitchboard owns GNHF schemas, prompt compilation/runtime contracts, workstation setup, launch, and local runtime evidence.

## Canonical run and artifact shape

`New-SasRunContext` creates an ignored local run under `runs/<workflow-id>/<run-id>/` or an approved survey output root:

```text
request.json
context.json
plan.json
plan.md
actions/
artifacts/
evidence/
reports/
review/
summary.json
artifact_registry.json
operator_handoff.txt
```

Use `Register-SasArtifact` for every generated artifact that downstream validation, reporting, or handoff depends on. Do not create a second run-context or registry implementation for an agent adapter.

## Routing contract

The routing manifest declares deterministic signals, target skill or harness operation, required inputs, outputs, preconditions, guardrails, validators, owner, and proof ceiling. Skill routes load skill and capability instructions. Harness-operation routes must collect the operation's complete required-input set and translate it through the workflow's `input_mapping`; they do not silently invent defaults.

Routing rules:

- explicit user lane wins;
- additive safety guards may compose with one primary route;
- equal-priority primary conflicts fail closed to `repository-sprint`;
- unknown signals fall back to `repository-sprint` for evidence-led classification;
- no trigger authorizes Git destruction, network activity, target mutation, or a higher proof claim.

## Validation order

Use the smallest diagnostic first, then the composed gate:

```text
python3 Tests/survey/test_agent_instruction_factoring_contracts.py
python3 Tests/survey/test_agent_capability_manifest_contracts.py
python3 Tests/survey/test_agent_routing_manifest_contracts.py
python3 Tests/survey/test_agent_sprint_capsule_contracts.py
python3 Tests/survey/test_agentswitchboard_gnhf_prompt_adoption_contracts.py
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/validate-ai-layer.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-Pester5Suite.ps1 -TestPath Tests/Pester/SprintCapsule.Tests.ps1
bash tests/survey/run_offline_survey_tests.sh
```

Executable or integration-affecting work still requires the applicable product E2E profile and final-head CI. These harness checks do not convert static evidence into runtime or operator acceptance.

## Final handoff compression

Generate the handoff after coherent work is committed or at a truthful checkpoint:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SasSprintCapsule.ps1 `
  -SprintId 'bounded-sprint-id' `
  -Title 'Bounded sprint title' `
  -Lane 'harness' `
  -Mission 'State the repository-grounded mission.' `
  -OwnedPaths @('repo/relative/path') `
  -ForbiddenScope @('other/repo/path') `
  -PrimarySkill 'repository-sprint' `
  -WorkflowSpec 'harness/workflows/agent-sprint-capsule.yaml' `
  -ExpectedArtifacts @('repo/relative/artifact') `
  -Completed @('State what is committed.') `
  -ValidationCommands @('python3 Tests/survey/test_agent_sprint_capsule_contracts.py') `
  -ProofLevel 'P6_E2E_fixture' `
  -ProofCeiling 'State the highest evidence actually reached.' `
  -ClaimsNotMade @('State the higher claims that remain unproven.') `
  -NextCommand 'git status --short'
```

The generator reads actual Git state, resolves skill dependencies from the capability manifest, uses the canonical run context, registers the capsule, and writes a compact English `operator_handoff.txt`. The capsule contains repository-relative paths only. The ignored run context may contain machine-local paths needed for local operation; do not paste that context into a new chat.

## Known traps

- Historical plans, PR bodies, and chat handoffs are lower authority than current repository state.
- A new skill without a manifest entry is invalid; the validator compares disk, manifests, and human routers.
- A trigger is routing metadata, not implementation or authorization.
- `mcp/local/servers.json` currently describes planned servers. Do not claim MCP runtime proof from the catalog.
- Do not open ignored live evidence merely because an agent can see the filesystem.
- Do not represent static package analysis, fixture E2E, command ACK, or launcher success as live product acceptance.
- Do not commit generated run directories, runtime evidence, private package contents, credentials, hostnames, serials, or machine-local paths.
