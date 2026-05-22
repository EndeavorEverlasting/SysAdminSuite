# Replit Full Harvest Index

## Purpose

Preserve Replit-origin branch concepts and changed files in a quarantine lane before product cleanup.

This branch is not a product merge branch.

It is an extraction archive used to decide what should later be promoted into clean implementation branches.

## Doctrine

- Do not merge quarantined files directly into product paths without review.
- Do not collapse Bash-on-Windows into Linux defaults.
- Do not delete, truncate, or deprecate PowerShell files.
- Treat old branches as references, not automatic merge sources.
- Promote only reviewed files or logic into clean implementation lanes.
- Keep generated outputs, real hostnames, serials, MACs, users, rooms, departments, and locations out of product commits.

## Base

- Base ref: `origin/main`
- Base commit: `679bba2`

## Harvested Branches

- `audit-deployment-2026-05-02`
- `codex/add-it-tools-for-printer-mapping-and-testing`
- `consolidate/v2.0`
- `delta/v1.0.0`
- `demo/v2.1`
- `docs/2026-05-03-bash-windows-runtime-contract`
- `docs/billing-pipeline-directional-use-cases`
- `docs/convergence-compatibility-contract-2026-05-22`
- `docs/wab-test-readiness-2026-05-22`
- `docs/wab-test-readiness-main-2026-05-22`
- `experimental/qrtasks-safe-defaults`
- `explore-networks`
- `feat/mapping-fetchmap-20251009-1029`
- `feat/printer-mapping-20251003-1349`
- `feat/printer-mapping-r164`
- `feature/2026-04-27-maintenance-status-harness`
- `feature/2026-04-29-neuron-maintenance-tooling`
- `feature/2026-04-29-neuron-software-reference`
- `feature/2026-04-30-bash-sysadminsuite-neuron-merge`
- `feature/2026-04-30-neuron-tooling-test-readiness`
- `feature/2026-05-03-bash-field-survey-scripts`
- `feature/2026-05-21-live-serial-probe`
- `feature/2026-05-21-live-serial-probe-main-sync`
- `feature/initial-upload`
- `feature/nmap-cybernet-target-audit`
- `harvest/2026-05-22-neuron-tooling-from-pr6`
- `LPW003ASI037-Repo`
- `sprint/2026-05-03-docs-shell-contract`
- `unit-tests/repo-health-and-bom-compliance`

## Branch Triage Notes

### Highest-priority product extraction

- `feature/2026-05-21-live-serial-probe`
- `feature/nmap-cybernet-target-audit`
- `harvest/2026-05-22-neuron-tooling-from-pr6`

### Current documentation / convergence branches

- `docs/convergence-compatibility-contract-2026-05-22`
- `docs/wab-test-readiness-2026-05-22`
- `docs/wab-test-readiness-main-2026-05-22`

### Likely already partially absorbed

- `feature/2026-05-03-bash-field-survey-scripts`
- `docs/2026-05-03-bash-windows-runtime-contract`
- `sprint/2026-05-03-docs-shell-contract`

### Separate workflow lanes

- `docs/billing-pipeline-directional-use-cases`

## Promotion Rule

Nothing from `replit-harvest/` should be copied into product paths unless reviewed and promoted in a separate small commit.

This harvest branch answers: “What exists?”

Implementation branches answer: “What deserves to become product?”

## Completion Statement

This branch is the quarantine extraction of remote Replit-origin branch deltas plus local workspace inventory.

After this branch is pushed, Replit is no longer the place we rely on to remember the work.
