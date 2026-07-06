# SysAdminSuite AI Harness Layer

## Purpose

The SysAdminSuite AI harness layer gives future AI-assisted changes a clear repo front door, scoped workflow templates, local-data guardrails, and repeatable validation. It implements the next small slice from `docs/HARNESS_COMPLETION_PLAN.md` without duplicating the English report renderer or run-context implementation planned there.

## Added harness surfaces

| Path | Role |
|---|---|
| `CLAUDE.md` | Agent-facing repo rules and workflow loop |
| `CODEBASE_MAP.md` | Minimal context map for targeted file loading |
| `.claudeignore` | AI context exclusions for local/live data and evidence |
| `.claude/skills/scoped-validation/SKILL.md` | Bounded validation selection guidance |
| `.claude/skills/live-data-guard/SKILL.md` | Guardrails for local data and operator evidence |
| `.claude/skills/survey-low-noise/SKILL.md` | Survey doctrine for low-noise reachability validation |
| `.claude/agents/explorer.md` | Read-only explorer role for specific repo questions |
| `.archon/workflows/*.yaml` | Lightweight workflow templates for survey, docs, and PR validation |
| `tools/validate-ai-layer.ps1` | Offline static validator for the AI harness layer |

## Operating boundaries

This layer is documentation, configuration, and validation only. It does not change survey runtime scripts, probing logic, Nmap/Naabu behavior, AD lookup behavior, dashboard UI behavior, printer mapping runtime behavior, or PowerShell runtime scripts.

AI-assisted work should remain authorized, read-only where survey or dashboard probes are involved, low-noise, scoped, bounded, local-evidence oriented, dry-run friendly, and validation-first.

## Local data boundary

The harness must not pull live target material into prompts or commits. Protected material includes workbooks, live target CSVs, host lists, serial lists, MAC exports, scan output, Nmap/Naabu logs, dashboard exports, ZIP bundles, local evidence, user-profile paths, and operator-local reference paths or names.

Use tracked synthetic fixtures or samples when examples are needed. Keep operational evidence in ignored local paths documented by `.claudeignore`, `.gitignore`, `targets/README.md`, and `docs/LOCAL_REFERENCE_POLICY.md`.

## Validation

Run the AI layer validator after changing these files:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-ai-layer.ps1
```

The validator is offline and static. It checks required files, required safety phrases, excluded local/evidence paths, workflow YAML presence, and unsafe wording in harness docs.

## Follow-up from PR #140

The later implementation should build the English report renderer and run-context artifacts described in `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md`. That future slice should render reports from structured JSON and artifact registries instead of making narrative text a separate source of truth.
