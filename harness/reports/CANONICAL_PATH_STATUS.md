# Canonical Path Status

## Current state

SysAdminSuite now has one machine-readable path owner at `harness/api/canonical-path-registry.json`. Path selection is distinct from repository freshness, product installation, and operator-entrypoint proof.

## Working

- Normal Windows development resolves to `%USERPROFILE%\Desktop\Dev\SysAdminSuite`.
- Admin Box repository maintenance uses the same canonical development checkout rather than adopting an AppData acquisition clone.
- Parallel or collision-isolated writers use `%LOCALAPPDATA%\SysAdminSuite\worktrees` as the temporary worktree root.
- `%LOCALAPPDATA%\SysAdminSuite\closeout-entry-*` is explicitly classified as ephemeral acquisition only.
- The Admin Box AutoLogon production/use runtime is `C:\SASAL` and requires its own seal/manifest currentness proof.
- Real operator execution remains owned by `harness/api/operator-execution-route-registry.json`; path resolution does not replace command or product authority.
- Remote `main` containment, canonical development currentness, production/use currentness, and operator-entrypoint observation are four independent proof states.

## Repaired boundary

A current GitHub branch or a freshly cloned AppData checkout can contain a tracked file while the actual development checkout or installed runtime still lacks it. The harness now forbids promoting that repository fact into workstation deployment proof.

The path contract also records a PowerShell handoff trap exposed in field use: `if { ... }` and its `else { ... }` must be submitted as one parsed block. A standalone later `else` is not valid PowerShell control flow.

## What is not proven

- This report does not prove the current canonical development checkout exists on a particular workstation.
- It does not prove `C:\SASAL` was refreshed to a particular commit.
- It does not prove the installed `sas` shim or a field launcher observes the intended runtime.
- It does not prove a live AutoLogon, Cybernet, printer, survey, or other product outcome.

Those require the owning freshness, updater/seal, execution-route, and product evidence respectively.

## Validation

```text
python harness/validators/validate-canonical-path-contracts.py
python Tests/survey/test_canonical_path_harness_completeness.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

Expected focused result:

```text
PASS: canonical path harness contracts
PASS: canonical path harness completeness
```
