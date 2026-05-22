# SysAdminSuite Branch Convergence Ledger - 2026-05-22

## Purpose

This ledger records the active branch-convergence posture for SysAdminSuite.

Goal: converge divergent branches once, preserve useful records, tag or document branch states, close stale PRs, and merge only clean current work into `main`.

## Control Issue

Issue #13 controls this sprint:

- `Converge divergent branches, tag records, and retire stale PRs`
- https://github.com/EndeavorEverlasting/SysAdminSuite/issues/13

## Current Main Posture

`main` has recent Replit-origin commits plus direct-main live serial probe/dashboard commits.

Known recent direct-main live serial probe commits:

| Commit | Purpose |
|---|---|
| `4702f3b` | Added `survey/sas-live-serial-probe.sh` |
| `42b4893` | Added glowing live serial probe dashboard renderer |
| `bac4a5c` | Added live serial probe sprint guide |
| `15a439d` | Added sample manifest fixture |
| `1dce45a` | Added sample identity fixture |
| `6812c32` | Added live serial probe contract test |
| `fd70e57` | Added field bootstrap helper for repo root and pull |
| `95efd9d` | Clarified repo root and pull workflow in live serial probe docs |

## Completed Records

### Issue #11

Closed as completed.

Purpose: live workstation serial probe and unreachable triage.

Result: implemented directly on `main` after PR #12 proved polluted/non-mergeable.

### PR #12

Closed, not merged.

Reason: branch carried useful live serial probe/dashboard work but was contaminated by earlier runtime/documentation branch history and was not a clean merge candidate.

Replacement: direct-main commits listed above.

## Pull Request Posture

| PR | Status | Decision |
|---|---|---|
| #7 | merged | Bash deployment audit and transport hardening. Treat as merged historical foundation. |
| #8 | merged | Bash-on-Windows runtime contract. Re-check current `main` for payload because later `main` movement may have obscured/duplicated it. |
| #9 | merged | Bash-on-Windows field survey scripts. Re-check current `main` for payload because later `main` movement may have obscured/duplicated it. |
| #12 | closed, not merged | Superseded by direct-main live serial probe/dashboard patch. Do not reopen unless direct-main patch is abandoned. |
| #6 | open, draft, stale | Do not merge as-is. Harvest useful Neuron tooling into a fresh branch from current `main`, then supersede PR #6. |
| #3 | closed, not merged | Historical checkpoint only. Superseded by PR #6 unless proven otherwise. |
| #4 | merged into intermediate feature branch | Historical input to Neuron tooling lineage. Verify whether useful payload reached current `main`. |
| #5 | closed, not merged | Superseded historical checkpoint. Do not merge. |

## Known Branches Requiring Review

| Branch | Preliminary Classification | Action |
|---|---|---|
| `feature/bash-windows-field-survey-v1` | needs review | Compare to `main`; classify. |
| `feature/initial-upload` | historical_checkpoint_only | Tag or ledger as early state; likely safe to retire after review. |
| `feature/nmap-cybernet-target-audit` | needs review | Compare to `main`; harvest only if not absorbed by PR #7/main. |
| `feature/2026-04-27-maintenance-status-harness` | needs_harvest | Check for display harness files not already absorbed. |
| `feature/2026-04-29-neuron-maintenance-tooling` | historical/needs_harvest | Source branch for Neuron maintenance payload; likely superseded by PR #6. |
| `feature/2026-04-29-neuron-software-reference` | historical/needs_harvest | Source branch for software reference payload; likely superseded by PR #6. |
| `feature/2026-04-30-bash-sysadminsuite-neuron-merge` | historical_checkpoint_only | Intermediate merge branch; do not use as base. |
| `feature/2026-04-30-neuron-tooling-test-readiness` | active_harvest_candidate | Head of PR #6. Harvest into fresh branch from current `main`; do not merge directly. |
| `feature/2026-05-03-bash-field-survey-scripts` | likely_superseded | Merged via PR #9 but verify current `main` contains payload. |
| `feature/2026-05-21-live-serial-probe` | superseded_by_main_direct_patch | PR #12 closed; useful payload applied directly to `main`. |
| `feature/2026-05-21-live-serial-probe-main-sync` | historical_failed_cleanup_attempt | Safe to retire after ledger/tag; no active payload expected. |
| `audit-deployment-2026-05-02` | likely_absorbed_in_main | Merged via PR #7; verify no unmerged residue. |
| `docs/billing-pipeline-directional-use-cases` | needs review | Unrelated docs branch; compare and decide separately. |
| `docs/2026-05-03-bash-windows-runtime-contract` | likely_superseded | Merged via PR #8 but verify current `main` contains payload. |
| `sprint/2026-05-03-docs-shell-contract` | needs review | Check for duplicate/superseded runtime docs. |

## Required Convergence Workflow

1. Record current `main` HEAD SHA.
2. For each branch above, run compare against current `main`.
3. Assign final classification:
   - `absorbed_in_main`
   - `superseded_by_main_direct_patch`
   - `needs_harvest`
   - `historical_checkpoint_only`
   - `safe_to_delete_after_tag`
   - `active_merge_candidate`
4. For PR #6:
   - inspect changed file list and diff
   - harvest useful files into a fresh branch from current `main`
   - run tests locally
   - open a new clean PR if useful payload remains
   - close PR #6 as superseded once replacement PR/ledger exists
5. For stale branches:
   - create tag or ledger record first
   - then delete/retire only after confirming payload is absorbed or rejected
6. Update README/docs after final `main` posture is known.

## Suggested Tag Pattern

If GitHub tag creation is available, use:

```text
archive/<branch-safe-name>-2026-05-22
```

Examples:

```text
archive/feature-2026-05-21-live-serial-probe-2026-05-22
archive/feature-2026-04-30-neuron-tooling-test-readiness-2026-05-22
```

If tag creation is unavailable, use this ledger as the durable archive record.

## Non-Negotiables

- Do not merge PR #6 blindly.
- Do not use stale branches as base branches.
- Do not delete branches until useful payload is merged, tagged, or explicitly recorded as rejected.
- Do not let direct-main patches remain undocumented.
- Keep generated artifacts, live hostnames, MACs, serials, locations, and trackers out of the public repo.

## Final Principle

No more branch soup.

Harvest what lives. Tag what mattered. Close what is dead. Merge only what is clean.
