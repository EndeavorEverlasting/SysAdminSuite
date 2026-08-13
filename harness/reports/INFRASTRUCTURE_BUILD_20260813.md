# Harness Infrastructure Build — 2026-08-13

## State

The operational harness floor is present and tracked. This sprint adds the missing `harness/README.md` fresh-agent front door and a dependency-free contract that proves the entrypoint routes to the existing harness authorities without replacing repository governance.

## Working

- Codebase orientation: `CODEBASE_MAP.md`
- Fresh-agent routing: `harness/workflows/fresh-agent-intake.yaml`
- Harness maintenance workflow: `harness/workflows/operational-harness-maintenance.yaml`
- Safe publication workflow: `harness/workflows/operational-harness-publish.yaml`
- Machine-readable inventory: `harness/api/operational-harness-manifest.json`
- Command, validator, artifact, outcome, and state registries under `harness/api/`
- Harness validators under `harness/validators/`
- Repository hooks: `.githooks/pre-commit`, `.githooks/pre-push`
- Hook installer: `scripts/install-local-harness-hooks.sh`
- Scoped harness skill: `harness/skills/harness-maintenance/SKILL.md`
- Human operator status: `docs/HARNESS_STATUS.md`
- Generated status renderer: `harness/reports/render-harness-status.py`
- Operational completeness contract: `Tests/survey/test_operational_harness_completeness_contracts.py`
- Fresh-agent entrypoint contract: `Tests/survey/test_harness_fresh_agent_entrypoint_contracts.py`

## Repaired gap

Before this sprint, the component floor existed but there was no canonical index at `harness/README.md`. A fresh agent had to infer the entry sequence across governance, the codebase map, and machine-readable manifests. The new index makes the route explicit and names the validator, artifact, outcome, hook, report, and handoff authorities.

## Known gaps / proof limits

- Git hooks remain opt-in per clone and must be installed with the tracked hook installer.
- Harness validation proves repository structure and contracts, not live runtime behavior.
- Generated or live evidence remains local/ignored and must not be committed.
- Governance remains owned by `AGENTS.md` and was intentionally not modified by this sprint.

## Validation floor

The focused validation set is:

```text
python harness/validators/validate-harness-registries.py
python harness/validators/validate-outcome-contracts.py
python harness/validators/validate-deployment-state-contracts.py
python Tests/survey/test_operational_harness_completeness_contracts.py
python Tests/survey/test_harness_fresh_agent_entrypoint_contracts.py
python Tests/survey/test_local_harness_contracts.py
bash -n .githooks/pre-commit
bash -n .githooks/pre-push
bash -n scripts/install-local-harness-hooks.sh
git diff --check
```

## Proof ceiling

Tracked harness structure, routing, validator/registry wiring, hook syntax, operator reporting, fresh-agent discoverability, and repository diff hygiene. No product behavior or live runtime proof is implied.
