# SysAdminSuite AI Harness Layer

## Purpose

The SysAdminSuite AI harness gives assisted changes a compact repo front door, progressive disclosure, scoped workflows, reusable capabilities, local-data guardrails, repeatable validation, and executable end-to-end gates.

The root instruction file is not a prompt packet. `AGENTS.md` contains universal invariants and routing only. Task procedures live in skills; stable rules used by several skills live in capabilities.

## Instruction model

```text
AGENTS.md
  -> selected .claude/skills/*/SKILL.md
      -> declared .claude/capabilities/*.md
          -> canonical schemas, workflows, scripts, and product docs
```

This keeps unrelated doctrine out of routine prompts while preserving repository-owned operating law.

## Harness surfaces

| Path | Role |
|---|---|
| `AGENTS.md` | Compact agent-agnostic invariants and skill router |
| `CLAUDE.md` | Progressive-disclosure agent front door |
| `CODEBASE_MAP.md` | Minimal context map for targeted loading |
| `.claude/skills/` | Task-specific workflows |
| `.claude/capabilities/` | Reusable atomic policy and operating capabilities |
| `harness/api/agent-capability-manifest.json` | Machine-readable skill/capability catalog |
| `schemas/harness/agent-capability-manifest.schema.json` | Fail-closed catalog schema |
| `harness/e2e/e2e-profiles.json` | Machine-readable E2E journey profiles |
| `scripts/Invoke-SasEndToEndValidation.ps1` | One-command E2E gate and result emitter |
| `.claudeignore` | AI context exclusions for local/live data and evidence |
| `.claude/agents/explorer.md` | Read-only explorer role for specific repo questions |
| `.archon/workflows/*.yaml` | Workflow templates for survey, docs, and PR validation |
| `tools/validate-ai-layer.ps1` | Offline instruction/harness validator |
| `Tests/survey/test_agent_instruction_factoring_contracts.py` | Anti-bloat and skill/capability dependency contract |
| `Tests/survey/test_agent_capability_manifest_contracts.py` | Manifest/schema/dependency contract |
| `Tests/survey/test_e2e_default_posture_contracts.py` | E2E default-posture and profile contract |

## Skills versus capabilities

A **skill** answers “how should an agent handle this kind of task?” It defines triggers, sequence, and task guardrails.

A **capability** answers “what stable rule or ability is reused across tasks?” It should be small enough to compose into several skills without copying text.

Skills must declare capability dependencies. Agents load only the selected skills and those dependencies.

The authoritative metadata catalog is:

```text
harness/api/agent-capability-manifest.json
```

Its fail-closed contract is:

```text
schemas/harness/agent-capability-manifest.schema.json
```

## End-to-end default posture

For executable or integration-affecting changes, targeted unit and contract checks are diagnostic layers. The default merge/release proof target is an applicable E2E journey through the real entrypoint, composition boundary, artifact/result path, and final classification.

The fixture-safe default profile composes:

- the real one-command synthetic harness;
- the real dashboard relay cancellation flow over loopback;
- the real dashboard relay/client abort flow over loopback.

Run it with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 -Profile default
```

See `docs/END_TO_END_TESTING_POSTURE.md`. Fixture and loopback success must not be promoted to live target or operator acceptance proof.

## Operating boundaries

The instruction layer does not replace product schemas, workflow specs, run context, artifact registry, validators, or runtime scripts. It routes agents to those authorities.

AI-assisted work remains authorized, read-only where survey or dashboard probes are involved, low-noise, scoped, bounded, local-evidence oriented, dry-run friendly, and validation-first.

## Local data boundary

The harness must not pull live target material into prompts or commits. Use tracked synthetic fixtures or samples. Keep operational evidence in ignored local paths documented by `.claudeignore`, `.gitignore`, `targets/README.md`, and `docs/LOCAL_REFERENCE_POLICY.md`.

## Validation

Run after changing agent instructions, skills, capabilities, or AI harness files:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-ai-layer.ps1
```

Run portable contracts:

```text
python Tests/survey/test_agent_instruction_factoring_contracts.py
python Tests/survey/test_agent_capability_manifest_contracts.py
python Tests/survey/test_e2e_default_posture_contracts.py
```

The validators enforce required files, safety language, skill-to-capability links, local-data exclusions, the compact `AGENTS.md` line budget, machine-readable catalog agreement, and E2E-default posture.
