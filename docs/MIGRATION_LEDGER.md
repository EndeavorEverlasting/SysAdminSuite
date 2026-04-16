# MIGRATION LEDGER

## Purpose
This ledger records branch-by-branch reconciliation decisions for the v3 rebuild so the implementation can proceed from validated assumptions instead of inherited drift.

## Baseline Decision
- Baseline for new rebuild work: `main`
- Rationale: newest maintained branch and current consolidated posture.

## Branch Comparison Ledger

### `main`
- Status vs `main`: baseline.
- Preserve: active consolidated assumptions and current runtime behavior.
- Notes:
  - Offline/non-AD compatibility remains a first-class requirement.
  - Dry-run safety remains a first-class requirement.
  - Current QR dispatcher behavior in `QRTasks/Invoke-TechTask.ps1` includes timeout enforcement, interruption cleanup, and `NeuronTrace` task mapping.

### `experimental/qrtasks-safe-defaults`
- Status vs `main`: contains unique commits not present in `main`.
- Unique functionality to preserve:
  - Fallback script-root resolution strategy for QR task dispatch when primary share/root is unavailable.
  - Local-first resilience pathing for QR task script execution.
- Preserve selectively:
  - Keep fallback path resolution concept.
  - Do not regress `main` timeout controls, interruption cleanup, or task map breadth.

### `unit-tests/repo-health-and-bom-compliance`
- Status vs `main`: behind `main`; no unique commits to retain for rebuild baseline.
- Unique functionality to preserve: none.
- Decision: no merge/cherry-pick required for v3 baseline.

### `demo/v2.1`
- Status vs `main`: behind `main`; no unique commits to retain for rebuild baseline.
- Unique functionality to preserve: none.
- Decision: no merge/cherry-pick required for v3 baseline.

### `consolidate/v2.0`
- Status vs `main`: historical consolidation branch; no unique commits to retain for rebuild baseline.
- Unique functionality to preserve: none.
- Decision: do not use as base branch.

## Preservation Rules for Rebuild Start
- Start implementation from `main`.
- Harvest fallback script-root resolution behavior from `experimental/qrtasks-safe-defaults`.
- Preserve from current `main` QR dispatcher:
  - task map breadth (including `NeuronTrace`)
  - timeout controls
  - interruption cleanup behavior

## Audit Note
This ledger is the branch-truth source for v3 foundation tasks and should be updated if branch deltas change in future audits.
