# SysAdminSuite AI Harness Layer

## Purpose

The SysAdminSuite AI harness gives assisted changes a compact repo front door, progressive disclosure, scoped workflows, reusable capabilities, local-data guardrails, and repeatable validation.

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
| `harness/api/agent-capability-manifest.json` | Machine-readable capability and skill catalog |
| `schemas/harness/agent-capability-manifest.schema.json` | Fail-closed catalog shape |
| `.claudeignore` | AI context exclusions for local/live data and evidence |
| `.claude/agents/explorer.md` | Read-only explorer role for specific repo questions |
| `.archon/workflows/*.yaml` | Workflow templates for survey, docs, and PR validation |
| `tools/validate-ai-layer.ps1` | Offline instruction/harness validator |
| `Tests/survey/test_agent_instruction_factoring_contracts.py` | Anti-bloat and Markdown composition contract |
| `Tests/survey/test_agent_capability_manifest_contracts.py` | Machine-readable manifest integrity and wiring contract |

## Skills versus capabilities

A **skill** answers “how should an agent handle this kind of task?” It defines triggers, sequence, and task guardrails.

A **capability** answers “what stable rule or ability is reused across tasks?” It should be small enough to compose into several skills without copying text.

Skills must declare capability dependencies. Agents load only the selected skills and those dependencies.

## Machine-readable capability manifest

`harness/api/agent-capability-manifest.json` is the harness-facing catalog for progressive disclosure. It records:

- stable capability and skill IDs;
- capability versions;
- repository-relative Markdown paths;
- applicable lanes;
- default network and target-mutation posture;
- control-plane or gated-target execution modes;
- canonical authority paths;
- validators;
- exact skill-to-capability dependencies.

The manifest does not replace Markdown operating law, workflow specifications, schemas, run context, or runtime implementations. It gives validators and future adapters a deterministic catalog without requiring them to scrape prose or preload every instruction file.

The existing harness API exposes this catalog through the local-read contract `agent_capability.catalog.read` in `harness/api/sas-harness-api.json`. That operation reads metadata only; it does not execute a skill, create a second run context, contact targets, or mutate state.

The schema is `schemas/harness/agent-capability-manifest.schema.json`. Both catalog and schema are tracked product contracts. Runtime evidence and machine-local state never belong in either file.

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

Run the dependency-free factoring and manifest contracts on every platform:

```text
python Tests/survey/test_agent_instruction_factoring_contracts.py
python Tests/survey/test_agent_capability_manifest_contracts.py
```

The validators enforce required files, safety language, Markdown and machine-readable dependency agreement, referenced path existence, local-data exclusions, and the compact `AGENTS.md` line budget.
