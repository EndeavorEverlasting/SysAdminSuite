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
| `main` at `d7f75da` | Product baseline | Current convergence head |
| PR #229 | Windows-native SMB/Task Scheduler BCA install path | Merged to `main` 2026-07-20 |
| PR #233 | Cybernet software-deployment tutorial | Merged to `main` 2026-07-20 (retargeted, validated) |
| PR #235 | Low-noise port-fallback contract floor | Merged to `main` (`dfb637e`) |
| PR #236 | Low-noise port-fallback application integration | Merged to `main` (`d7f75da`) |
| PR #234 | BCA and low-noise convergence coordination | This PR; records final landed SHAs and proof levels |
| PR #144 | Historical low-noise port-policy (draft) | Closed as superseded by #235/#236; branch preserved |
| `docs/handoff/bca-one-target-runtime-floor.md` | Runtime-floor gate | Updated with final merge SHAs and proof levels |

## Current next target

1. ~~Keep PR #229 merge-ready.~~ Done. Merged.
2. ~~Merge #229.~~ Done.
3. ~~Retarget and merge #233.~~ Done.
4. ~~Merge Sprint 1 contract floor (#235).~~ Done.
5. ~~Merge Sprint 2 application integration (#236).~~ Done.
6. ~~Close PR #144 as superseded.~~ Done.
7. Merge PR #234 (this PR) after final validation.
8. One-target Admin-VM → Cybernet BCA live proof from an approved controller remains separately authorized.
