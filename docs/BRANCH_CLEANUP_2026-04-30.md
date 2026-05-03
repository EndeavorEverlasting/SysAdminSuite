# Branch Cleanup Plan - 2026-04-30

## Purpose

Clean up the active SysAdminSuite branch/PR posture without losing useful historical work.

The rule: **label before deletion, harvest before merge, test before promotion.**

## Current PR posture

| PR | Branch | State | Action |
|---:|---|---|---|
| #3 | `feature/2026-04-29-neuron-maintenance-tooling` | Draft, mergeable | Supersede with April 30 branch after test-readiness updates. Keep as parent checkpoint until April 30 PR is open. |

## Active branches

| Branch | Classification | Action |
|---|---|---|
| `main` | Production baseline | Protect. Merge only reviewed/tested work. |
| `feature/2026-04-30-neuron-tooling-test-readiness` | Active test-readiness branch | Current working branch. Contains April 29 maintenance tooling plus test/readiness docs. |
| `feature/2026-04-29-neuron-maintenance-tooling` | Superseded checkpoint | Keep until April 30 PR is merged, then delete. |
| `feature/2026-04-29-neuron-software-reference` | Active harvest candidate | Rebuild/cherry-pick onto fresh `main` or April 30 branch after maintenance tooling is stable. Do not merge while diverged. |
| `feature/2026-04-27-maintenance-status-harness` | Historical harvest branch | Do not merge raw. Harvest specific files only. It contains useful Neuron inventory and maintenance status work but is diverged. |

## Historical branches

These should not be deleted blindly. Tag or preserve until their unique value is checked.

| Branch | Label | Notes |
|---|---|---|
| `consolidate/v2.0` | `historical/consolidation` | Older consolidation branch. Behind main. Safe delete candidate once confirmed fully absorbed. |
| `feature/initial-upload` | `historical/bootstrap` | Early version/release-management material. Harvest only if needed. |
| `LPW003ASI037-Repo` | `historical/field-dump` | Large legacy field dump. Contains old printer, OCR, sandbox, and environment setup artifacts. Do not merge raw. |
| `delta/v1.0.0` | `historical/release-line` | Legacy release line. Preserve until version history is understood. |
| `demo/v2.1` | `historical/demo` | Demo branch. Delete only after checking whether it contains unique demo assets. |
| `experimental/qrtasks-safe-defaults` | `historical/experiment` | QRTasks safety experiment. Harvest safety defaults if not already included. |
| `explore-networks` | `historical/exploration` | Network exploration branch. Harvest only. |
| `feat/mapping-fetchmap-20251009-1029` | `historical/printer-mapping` | Mapping feature branch. Likely superseded by main, but verify before deletion. |
| `feat/printer-mapping-20251003-1349` | `historical/printer-mapping` | Mapping feature branch. Likely superseded by main, but verify before deletion. |
| `feat/printer-mapping-r164` | `historical/printer-mapping` | Mapping feature branch. Likely superseded by main, but verify before deletion. |
| `unit-tests/repo-health-and-bom-compliance` | `historical/tests` | Check whether tests were absorbed. Preserve until test coverage comparison is done. |
| `codex/add-it-tools-for-printer-mapping-and-testing` | `merged/pr-1` | Head branch for merged PR #1. Delete candidate if no longer needed. |

## Cleanup sequence

1. Open April 30 PR from `feature/2026-04-30-neuron-tooling-test-readiness` to `main`.
2. Close or supersede PR #3 only after April 30 PR is confirmed open.
3. Run local test pass:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1
powershell.exe -File .\QRTasks\Invoke-TechTask.ps1 -Task ?
powershell.exe -File .\QRTasks\Get-NeuronMaintenanceSnapshot.ps1 -OutDir .\GetInfo\Output\QRTasks
```

4. Merge April 30 PR if tests are clean.
5. Rebuild Neuron software-reference branch from updated `main`.
6. Harvest useful files from the April 27 branch manually.
7. Delete only branches proven to be fully merged or superseded.

## Deletion candidates after verification

```text
codex/add-it-tools-for-printer-mapping-and-testing
consolidate/v2.0
feature/2026-04-29-neuron-maintenance-tooling
```

## Do-not-delete-yet list

```text
feature/2026-04-29-neuron-software-reference
feature/2026-04-27-maintenance-status-harness
LPW003ASI037-Repo
feature/initial-upload
unit-tests/repo-health-and-bom-compliance
```

These branches are messy, but messy does not mean worthless. Treat them like an evidence locker, not a trash pile.
