# Executable AI Harness Foundation Plan

## Purpose

Turn SysAdminSuite AI harness doctrine into a local executable loop with synthetic fixtures, readable reports, artifact registries, workflow specs, and repeatable validation.

## Current implementation slice

PR #142 owns this first slice:

- English report renderer
- run context helpers
- minimal schemas
- synthetic serial and network report fixtures
- lightweight workflow specs
- synthetic harness validator
- root command wrappers
- launch and coordination docs

## Local loop

```text
request
  -> source fixture
  -> local evidence fixture
  -> summary JSON
  -> artifact registry
  -> English report
  -> validator matrix
  -> next action
```

## Required commands

```bash
git diff --check
bash Tests/bash/test_english_log_artifact_contracts.sh
bash Tests/bash/test_sysadmin_harness_validator_contracts.sh
```

```powershell
.\scripts\validate-sysadmin-harness.ps1
```

## Output paths

| Purpose | Path |
|---|---|
| English reports | `survey/output/english-log/` |
| Harness validator output | `survey/output/harness-validator/` |
| Run context output | `survey/output/runs/` |
| Synthetic fixtures | `survey/fixtures/english-log/` |
| Workflow specs | `survey/workflows/` |
| Schemas | `schemas/harness/` |

## Not in this slice

- no MCP server implementation
- no automatic hook rewriting
- no live survey execution
- no dashboard rewrite

## Next slice candidates

1. Move schemas under `harness/schemas/` or add compatibility mirrors.
2. Add fixture-backed workflow-spec validator.
3. Add dashboard viewer for operator reports and artifact registries.
4. Add local reference-cache docs for Archon and helpline without committing the external repositories.
5. Add path-scoped agent rule files after the command surface stabilizes.
