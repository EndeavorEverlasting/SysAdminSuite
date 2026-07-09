# SysAdminSuite Agent Coordination

This is the central coordination board for SysAdminSuite harness, survey, dashboard, and evidence work.

Read this before changing shared sprint files.

## Agent lanes

| Agent | Lane | Owns | Does not own |
|---|---|---|---|
| Agent A | Harness / Evidence / Git / PR | harness validation, artifact registry, PR readiness | feature implementation outside harness |
| Agent B | Survey Runtime / Target State | survey workflow contracts, target-state classification | dashboard launcher behavior |
| Agent C | Dashboard / Local Runner | dashboard entrypoints, local wrappers, launcher surfaces | survey truth classification |
| Agent D | Docs / Atlas / Routing Board | docs index, plans, handoffs, coordination | certifying behavior without evidence |
| Agent E | Data Hygiene | fixture boundaries, local-output policy, generated-artifact hygiene | unrelated feature rewrites |

## Hard rules

- Do not commit live source data, generated run output, credentials, large logs, or local machine junk.
- Do not claim PASS from stale artifacts.
- Do not delete PowerShell files or label them dead unless the user explicitly asks.
- Do not replace active Windows PowerShell tooling with Bash.
- Do not run network probes from planner or renderer phases.
- If evidence is partial, say partial.

## Active sprint map

| Branch / PR | Role | Current relationship |
|---|---|---|
| `main` | Product baseline | Base branch for implementation PRs |
| PR #142 | Executable AI harness foundation | Active harness branch for English reports, run context, workflow specs, wrappers, and docs |

## Ownership matrix

| Path | Primary owner | Notes |
|---|---|---|
| `scripts/Render-SasEnglishReport.ps1` | Agent A | Renderer must stay local-artifact only |
| `scripts/SasRunContext.psm1` | Agent A | Run context and artifact registry helpers |
| `scripts/validate-sysadmin-harness.ps1` | Agent A | Synthetic no-live-data validator |
| `survey/workflows/` | Agent B | Static workflow contracts |
| `dashboard/` | Agent C | Dashboard surfaces and samples |
| root `Run-*.cmd` wrappers | Agent C | Human click surfaces |
| `docs/launch-and-doc-index.md` | Agent D | Start-here index |
| `docs/handoff/` | Agent D | Routing and handoff board |
| `survey/fixtures/` | Agent E | Synthetic fixture boundary |
| `survey/output/`, `survey/artifacts/` | Agent E | Generated local output boundary |

## Evidence rules

- Fixtures are tracked only when synthetic.
- Generated run output is local unless deliberately sanitized.
- A report is not a PASS by itself; PASS requires the matching validator or test result.
- If local validation cannot run, name the skipped command and reason.

## Current next target

Stabilize PR #142 locally:

```bash
git diff --check
bash Tests/bash/test_english_log_artifact_contracts.sh
bash Tests/bash/test_sysadmin_harness_validator_contracts.sh
```

Then run:

```powershell
.\scripts\validate-sysadmin-harness.ps1
```
