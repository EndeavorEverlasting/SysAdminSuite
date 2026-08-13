# SysAdminSuite Harness

This directory is the operational harness front door for a fresh agent working in SysAdminSuite.

The repository-root governance authority remains `AGENTS.md`. This file does not replace governance; it tells an agent how to enter the tracked harness, select the smallest workflow, validate its work, resolve artifacts, and hand off without loading the whole repository.

## Fresh-agent sequence

1. Read `../AGENTS.md` and preserve the current Git/worktree state.
2. When current remote behavior matters, or an expected tracked launcher/validator/workflow is missing locally, use `workflows/repository-freshness-before-launch.yaml` before interpreting the worktree as repository truth.
3. Read `../CODEBASE_MAP.md` and this file to identify the smallest relevant harness surface.
4. Use `api/agent-routing-manifest.json` for task routing. Unknown or conflicting task signals fail closed to the repository-sprint skill.
5. For harness-only maintenance, use `skills/harness-maintenance/SKILL.md` and `workflows/operational-harness-maintenance.yaml`.
6. Select validators from `api/harness-validator-registry.json`; do not substitute a convenient check for the validator that owns the changed contract.
7. Resolve produced evidence through `api/harness-artifact-registry.json` and command success/continuation through `api/harness-outcome-registry.json`.
8. Render the human-readable harness state with `reports/render-harness-status.py` when an operator summary is needed.
9. Hand off with the tracked sprint capsule/handoff surfaces named in `api/operational-harness-manifest.json`.

## Repository freshness rule

Fetching a remote ref does **not** update the checked-out branch or files in the current worktree. In particular, fetching `origin/main` does not update local `main`.

If a tracked launcher or other expected surface appears to be missing, do not invent a replacement from a stale checkout. Refresh the intended remote ref, compare local `HEAD` with the fetched commit, and then:

- use a **fast-forward-only** update when the current branch is clean, owned, and strictly behind;
- use an **isolated worktree** at the fetched commit when the current worktree is dirty, diverged, or separately owned;
- verify the expected path in the selected executing tree before reconstructing any command or workflow.

This rule is enforced by `validators/validate-repository-freshness-contracts.py` and documented in `reports/REPOSITORY_FRESHNESS_STATUS.md`.

## Component map

| Need | Canonical surface |
|---|---|
| Repository orientation | `../CODEBASE_MAP.md` |
| Repository freshness before command selection | `workflows/repository-freshness-before-launch.yaml` |
| Machine-readable harness inventory | `api/operational-harness-manifest.json` |
| Task routing | `api/agent-routing-manifest.json` |
| Canonical commands | `api/harness-command-registry.json` |
| Validator selection | `api/harness-validator-registry.json` |
| Artifact locations/generators | `api/harness-artifact-registry.json` |
| Success outcomes/continuations | `api/harness-outcome-registry.json` |
| Deployment desired state | `api/deployment-state-registry.json` |
| Fresh-agent intake | `workflows/fresh-agent-intake.yaml` |
| Harness-only implementation | `workflows/operational-harness-maintenance.yaml` |
| Safe publication | `workflows/operational-harness-publish.yaml` |
| Harness maintenance skill | `skills/harness-maintenance/SKILL.md` |
| Completeness validator | `../Tests/survey/test_operational_harness_completeness_contracts.py` |
| Registry validator | `validators/validate-harness-registries.py` |
| Repository freshness validator | `validators/validate-repository-freshness-contracts.py` |
| Outcome validator | `validators/validate-outcome-contracts.py` |
| Deployment-state validator | `validators/validate-deployment-state-contracts.py` |
| Human-readable status | `../docs/HARNESS_STATUS.md` |
| Repository freshness incident/status | `reports/REPOSITORY_FRESHNESS_STATUS.md` |
| Generated English status | `reports/render-harness-status.py` |
| Git hooks | `../.githooks/pre-commit`, `../.githooks/pre-push` |
| Hook installer | `../scripts/install-local-harness-hooks.sh` |

## Minimum harness validation

Run from the repository root:

```text
python harness/validators/validate-harness-registries.py
python harness/validators/validate-repository-freshness-contracts.py
python harness/validators/validate-outcome-contracts.py
python harness/validators/validate-deployment-state-contracts.py
python Tests/survey/test_operational_harness_completeness_contracts.py
python Tests/survey/test_local_harness_contracts.py
git diff --check
```

Escalate to the broader offline suite when the changed component participates in shared survey/runtime contracts:

```text
bash tests/survey/run_offline_survey_tests.sh
```

## Known traps

- Do not modify `AGENTS.md` during a harness-infrastructure sprint; governance is a separate lane.
- Do not mistake a successful `git fetch` for an updated executing worktree; fetching does not update the checked-out branch.
- Do not infer that an expected tracked launcher is absent from the repository until it has been checked at the refreshed intended commit.
- Do not change product/runtime behavior to make a harness validator green.
- Do not run deployment or target-mutation commands merely to validate harness structure.
- Do not commit generated run evidence or machine-local output.
- Do not treat a dry run, fixture pass, parser pass, or successful validator as proof of live deployment/runtime behavior.
- Do not force-push or clean/reset another agent's worktree. Use an isolated worktree when ownership is unclear.
- Do not stop at a green admission gate when a safe, authorized continuation is still required by the requested outcome; follow the outcome registry.

## Artifact and handoff discipline

Generated artifacts must be resolved from `api/harness-artifact-registry.json`. Tracked registry/schema/report files may be committed; live or workflow-dependent evidence stays in ignored run roots.

A clean handoff names the repository, branch, owned and forbidden scope, changed files, exact validators actually run, proof ceiling, commit SHA, push/PR state, repository freshness classification when relevant, remaining blocker or gap, and one exact next command when safe unproven work remains.

## Proof ceiling

The harness can prove tracked structure, repository selection, routing, registry/schema integrity, validator wiring, hook/CI integration, artifact/outcome contracts, and human-readable reporting. Harness validation alone does not prove product behavior, target contact, software deployment, restart success, or live runtime acceptance.
