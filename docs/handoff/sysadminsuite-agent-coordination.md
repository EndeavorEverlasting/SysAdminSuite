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
- Do not contact a Cybernet for BCA install proof until the merge floor in `docs/handoff/bca-one-target-runtime-floor.md` is satisfied or an exact-SHA exception is recorded.

## Active sprint map

| Branch / PR | Role | Current relationship |
|---|---|---|
| `main` | Product baseline | Base branch for implementation PRs |
| PR #229 | Windows-native SMB/Task Scheduler BCA install path | Primary implementation floor for one-target Cybernet BCA runtime proof |
| PR #233 | Cybernet software-deployment tutorial | Stacked on #229; land after #229 |
| `docs/handoff/bca-one-target-runtime-floor.md` | Runtime-floor gate | Dependency and proof-boundary record for the next live sprint |

Historical note: PR #142 harness-foundation work remains provenance for English-report / run-context surfaces and is not the current BCA runtime blocker.

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
- Installer exit codes and task ACK are not application-behavior proof.

## Current next target

1. Keep PR #229 merge-ready (non-draft, green checks, mergeable into `main`).
2. Merge #229 when merge authority is present.
3. Retarget or merge PR #233 after #229.
4. Only then run the one-target Admin-VM → Cybernet BCA live proof from an approved controller.

Local static checks for this coordination update:

```bash
git diff --check
git status --short
```

Live Cybernet contact remains out of scope for this board update.
