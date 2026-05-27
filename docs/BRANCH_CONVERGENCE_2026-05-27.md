# SysAdminSuite Branch Convergence Ledger - 2026-05-27

## Purpose

Authoritative record of branch and PR posture after remote-first convergence. Supersedes the 2026-05-22 ledger for open-work decisions.

Control issue: [#13](https://github.com/EndeavorEverlasting/SysAdminSuite/issues/13)

Operator workflow: [REMOTE_WORKFLOW.md](REMOTE_WORKFLOW.md)

## Current main

| Field | Value |
|-------|--------|
| HEAD (short) | `955563e` (post-convergence; verify with `git rev-parse --short origin/main`) |
| Notable on main | Hostname availability (#33), remote workflow ledger (#34), Neuron runtime PS (#35), `deployment-audit/nmap` (#36), registry install-diff (integrated), survey nmap baseline (#24) |

Always verify: `git fetch origin && git rev-parse --short origin/main`

## Open pull requests

| PR | Branch | Lane |
|----|--------|------|
| (pending) | `feature/autologon-workstation-assessment` | Auto-logon remote batch + HTML dashboard |

New work branches from `origin/main` only. Do not stack unrelated features on an open PR branch.

## Recently settled (convergence sprint)

| PR | Status | Classification |
|----|--------|----------------|
| #34 | merged | `absorbed_in_main` — REMOTE_WORKFLOW + this ledger |
| #35 | merged | `absorbed_in_main` — Neuron runtime PS harvest (replaces #32) |
| #36 | merged | `absorbed_in_main` — `deployment-audit/nmap` (replaces #10) |
| #32 | closed | `superseded` by #35 |
| #10 | closed | `superseded` by #36 |
| #25–#31 | closed | `absorbed_in_main` — registry stack already on `main` via integration branch |
| #33 | merged | `absorbed_in_main` — numeric hostname availability (`survey/sas-hostname-availability.py`, etc.) |
| #7 | merged | `absorbed_in_main` — deployment audit / transport |
| #21 | merged | `absorbed_in_main` — identity resolver + `sas-ad-identity-export.ps1` |
| #24 | merged | `absorbed_in_main` — nmap baseline (survey layer) |
| #6 | closed (draft) | `superseded` — see [PR6_HARVEST_PLAN.md](PR6_HARVEST_PLAN.md); delivered via #35 |
| #16 | closed | `historical_checkpoint_only` — harvest PR6 attempt |
| #12 | closed | `superseded_by_main_direct_patch` — live serial probe on main |

## Branch classifications

| Branch | Classification | Action |
|--------|----------------|--------|
| `feature/hostname-availability-opr` | `absorbed_in_main` | Delete remote after PR #33 merge confirmed |
| `audit-deployment-2026-05-02` | `absorbed_in_main` | Safe to delete remote |
| `feature/2026-05-21-live-serial-probe` | `superseded_by_main_direct_patch` | Safe to delete remote |
| `feature/2026-05-21-live-serial-probe-main-sync` | `historical_checkpoint_only` | Safe to delete remote |
| `feature/2026-04-30-neuron-tooling-test-readiness` | `superseded` | Safe to delete remote (PR #35 merged) |
| `feature/2026-05-03-bash-field-survey-scripts` | `absorbed_in_main` | Safe to delete remote (PR #9) |
| `docs/2026-05-03-bash-windows-runtime-contract` | `absorbed_in_main` | Safe to delete remote (PR #8) |
| `feature/nmap-cybernet-target-audit` | `superseded` | Safe to delete remote (PR #36 merged) |
| `feature/nmap-cybernet-audit-v2` | `absorbed_in_main` | Delete remote after #36 merge |
| `codex/create-documentation-for-registry-install-diff-pipeline` | `superseded` | Delete after consolidated registry PR merges |
| `codex/add-json-schemas-and-example-configs` | `superseded` | Same |
| `codex/implement-target-readiness-checks-for-pipeline` | `superseded` | Same |
| `codex/implement-registry-snapshot-capture-layer` | `superseded` | Same |
| `codex/implement-registry-snapshot-comparison-script` | `superseded` | Same |
| `codex/implement-tracked-installer-runner` | `superseded` | Same |
| `codex/build-orchestrator-and-bash-wrapper-for-pipeline` | `superseded` | Same |
| `harvest/neuron-runtime-current-main-v2` | `superseded` | Safe to delete remote (PR #35 merged) |
| `feature/neuron-runtime-harvest-2026-05-27` | `absorbed_in_main` | Delete remote after #35 merge |
| `feature/bash-windows-field-survey-v1` | `likely_absorbed_in_main` | Compare then delete |
| `feature/initial-upload` | `historical_checkpoint_only` | Tag optional; delete when convenient |
| `feature/2026-04-27-maintenance-status-harness` | `needs_harvest` | Review once; low priority |
| `feature/2026-04-29-neuron-maintenance-tooling` | `superseded` | Payload via PR #32 |
| `feature/2026-04-29-neuron-software-reference` | `superseded` | Payload via PR #32 |
| `feature/2026-04-30-bash-sysadminsuite-neuron-merge` | `historical_checkpoint_only` | Do not use as base |
| `docs/billing-pipeline-directional-use-cases` | `needs review` | Separate from this sprint |
| `sprint/2026-05-03-docs-shell-contract` | `needs review` | Compare to main docs |

## Registry stack consolidation order

When building `feature/registry-install-diff-consolidated` from `origin/main`, merge or cherry-pick in this order:

1. `codex/create-documentation-for-registry-install-diff-pipeline`
2. `codex/add-json-schemas-and-example-configs`
3. `codex/implement-target-readiness-checks-for-pipeline`
4. `codex/implement-registry-snapshot-capture-layer`
5. `codex/implement-registry-snapshot-comparison-script`
6. `codex/implement-tracked-installer-runner`
7. `codex/build-orchestrator-and-bash-wrapper-for-pipeline`

## Archive tags

Pattern: `archive/<branch-safe-name>-2026-05-27`

Create before deleting a branch when the branch represented non-trivial work.

## Non-negotiables

- Branch only from current `origin/main`.
- Do not merge PR #6 or PR #10 as-is.
- Do not delete branches until classified here or in a supersede PR comment.
- No live operational identifiers in the public repo.

## Prior ledger

[BRANCH_CONVERGENCE_2026-05-22.md](BRANCH_CONVERGENCE_2026-05-22.md) remains for historical context; this file is the active record.
