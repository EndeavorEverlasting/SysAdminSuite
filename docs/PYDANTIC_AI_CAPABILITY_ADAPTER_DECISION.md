# Pydantic AI Capability Adapter Decision

## Status

Accepted as architecture guidance for future integration work.

## Purpose

SysAdminSuite may borrow useful ideas from external agent frameworks such as Pydantic AI, especially capability packaging, progressive disclosure, lifecycle hooks, and bounded code execution. Those ideas must fit inside the existing repo-local harness instead of replacing it.

The harness remains the operating system for agent work. A prompt or external framework is only an input or adapter layer.

## Decision

SysAdminSuite does not migrate to Pydantic AI as the controlling architecture.

If a Pydantic AI integration is added later, it must consume the existing SysAdminSuite harness surfaces and produce the same evidence, validators, reports, and handoff artifacts as the native path.

## Repo-local authority

The authoritative SysAdminSuite chain remains:

```text
request
  -> repo rules and codebase map
  -> workflow selection
  -> scope and mutation gates
  -> run context
  -> bounded actions
  -> structured events and raw logs
  -> artifact registry
  -> validators
  -> English report
  -> compressed handoff and next decision
```

The following surfaces stay authoritative:

| Harness responsibility | Repo-local surface |
|---|---|
| Agent rules | `AGENTS.md`, `CLAUDE.md`, `.claude/skills/` |
| Codebase map | `CODEBASE_MAP.md` |
| Workflow specs | `.archon/workflows/`, `survey/workflows/` |
| Run context | `scripts/SasRunContext.psm1` |
| Artifact registry | `schemas/harness/artifact-registry.schema.json` |
| Validators | `scripts/Invoke-SasHarnessContracts.ps1`, `scripts/validate-sysadmin-harness.ps1` |
| Local hooks | `.githooks/` |
| Scoped skills | `.claude/skills/` |
| Code intelligence | `mcp/local/servers.json` |
| Operator reports | `scripts/Render-SasEnglishReport.ps1`, operator report schema |
| Handoff compression | `docs/handoff/`, `summary.json`, `next_action` |
| Prompts | Workflow launch artifacts only |

## Capability mapping

Use this mapping when translating external framework language into SysAdminSuite-native work:

| External concept | SysAdminSuite-native interpretation |
|---|---|
| Capability | Workflow plus scoped skill plus allowed tools plus hooks plus validators |
| Progressive disclosure | Catalog metadata that loads only the workflow and tool details needed for the request |
| Lifecycle hooks | Mutation gates, preflight checks, deny rules, escalation rules, and validator gates |
| Tool execution | Approved command rendering or bounded process execution inside the run context |
| Code execution sandbox | Optional adapter only, never a bypass around the run context or artifact registry |
| Agent handoff | Structured report plus `summary.json` plus `next_action` |

## Required boundaries

Future Pydantic AI or capability-oriented work must follow these rules:

1. Do not create a second run-context implementation.
2. Do not create a second artifact registry.
3. Do not replace workflow specs with prompt text.
4. Do not let an adapter choose mutations outside workflow-owned scope.
5. Do not mix raw logs and structured evidence into one ambiguous artifact.
6. Do not bypass `scripts/Invoke-SasHarnessContracts.ps1` or `scripts/validate-sysadmin-harness.ps1`.
7. Do not claim runtime proof from static docs or framework setup alone.
8. Do not perform live probing, deployment, or target mutation in an adapter prototype.
9. Do not weaken Bash-on-Windows and PowerShell preservation rules in `AGENTS.md`.
10. Do not commit generated runtime evidence or machine-local files.

## Safe implementation order

Capability-oriented work should proceed in this order:

1. Add or verify capability metadata against existing workflow specs.
2. Add fixture-only mutation-gate checks.
3. Add or reuse bounded process execution only after the action is workflow-approved.
4. Register raw logs and structured results separately.
5. Run existing harness validators.
6. Render the English report from registered artifacts.
7. Emit the compressed handoff and next action.
8. Only then test a Pydantic AI adapter against the harmless fixture path.

## Acceptance test for any future adapter

A future Pydantic AI adapter is acceptable only if a clean checkout can prove that the adapter:

1. Finds the governing repo rules.
2. Uses the codebase map.
3. Selects a repo-local workflow.
4. States owned and forbidden scope.
5. Creates the canonical run context.
6. Executes only permitted fixture actions.
7. Writes raw logs separately from structured evidence.
8. Registers every artifact.
9. Runs the correct validators.
10. Produces the same operator-readable report as the native path.
11. Emits a compact handoff with proof level, gaps, Git state, and next action.

If the adapter cannot satisfy this test, leave Pydantic AI as a research note and continue using the native SysAdminSuite harness path.

## Non-goals

This decision does not implement Pydantic AI.

This decision does not add live network activity, deployment behavior, software installation behavior, or target mutation.

This decision does not modify `scripts/SasRunContext.psm1`, validators, workflow specs, or report rendering behavior.

## Next implementation lane

The next safe lane is a fixture-backed capability catalog that reads existing workflow specs and emits a metadata summary without executing live actions.
