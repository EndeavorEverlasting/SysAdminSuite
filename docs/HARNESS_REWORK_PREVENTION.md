# Harness Rework Prevention

This document is the human-readable companion to `harness/api/rework-prevention-registry.json`. It captures repeat-failure controls without embedding live targets, operator usernames, secrets, or machine-local evidence.

## What is enforced

- **Evidence before retry.** A failed or interrupted run is inspected before another mutating run starts. Unknown cleanup is treated as unproven.
- **Terminal independence.** CMD or PowerShell is diagnostic metadata, not workflow state. Repository-owned launchers own the transaction.
- **Explicit network routing.** Network-sensitive commands state and verify the required network class before execution and stop early on the wrong network.
- **Source readiness before target mutation.** Multi-package operations prove every source first. Bundle drift is recorded as data instead of being patched by guessing filenames.
- **Transactional ownership.** Stage, execute, retrieve, profile, cleanup, and final evidence remain inside one tracked run owner.
- **Run-scoped recovery.** Recovery touches only exact run-owned resources, retrieves available checkpoints/results first, verifies cleanup, and preserves already-proven completed work.
- **Checkpoint and exit-code integrity.** Stable proof boundaries are written during long operations and wrappers propagate nonzero child exits.
- **Focused validation.** Changed-surface validators run before broad suites. Unrelated baseline failures are classified rather than becoming side quests.

## Known failure classes

The registry currently captures these recurring failure classes:

1. stale installed operator launcher;
2. Windows drive/path assumption in portable tooling;
3. empty evidence-list binder/collection failure;
4. dispatcher or wrapper hiding a child failure behind exit zero;
5. unexpected Git Bash, Python, shell-variable, or shell-fragment dependency in a Windows-native lane;
6. package-catalog drift inside an approved bundle;
7. target mutation beginning before all required sources are ready;
8. cleanup escaping the owning transaction into an interactive fragment;
9. operator context reacclimation after terminal/network/conversation changes;
10. diagnostic side-quest expansion while the owning changed-surface gate remains unproven.

Each failure class maps to one or more controls in `harness/api/rework-prevention-registry.json`; a fresh agent should use that mapping before inventing a new repair strategy.

## Fresh-agent recovery sequence

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, and the rework-prevention registry.
2. Inspect Git/PR state and the latest run/session evidence.
3. Recover the last proven checkpoint, cleanup state, completed work, target/profile/lane, and next required network.
4. If cleanup is uncertain, use exact run-scoped recovery before retry.
5. If the operation consumes multiple sources, complete source preflight before target mutation.
6. Execute only the canonical repository-owned workflow/launcher.
7. Run the smallest owning validator first; broaden only after changed-surface proof is green.
8. Hand off the exact next command/action, required environment, expected artifact, and completion gate.

## Exact validator

```text
python harness/validators/validate-rework-prevention-contracts.py
```

The focused harness floor then continues with:

```text
python harness/validators/validate-harness-registries.py
python harness/validators/validate-outcome-contracts.py
python harness/validators/validate-deployment-state-contracts.py
python Tests/survey/test_operational_harness_completeness_contracts.py
python Tests/survey/test_local_harness_contracts.py
git diff --check
```

## What remains outside this harness proof

These contracts prove that repeat-failure rules are present, wired, and internally consistent. They do **not** prove that a protected package source currently contains expected files, that a target is reachable, that a deployment succeeded, that cleanup succeeded on a real endpoint, that a reboot occurred, or that a technician accepted the result. Those require their lane-specific runtime artifacts.
