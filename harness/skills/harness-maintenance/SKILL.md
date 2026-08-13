# Harness Maintenance Skill

## Trigger

Use this skill when the task explicitly owns repository harness infrastructure: codebase maps, harness workflows, command/validator/artifact/outcome/deployment-state registries, hooks, scoped skills, operator reports, harness schemas, or harness CI.

Do not use this skill to change product behavior, deployment logic, device profiles, credentials, secrets, or the root governance contract in `AGENTS.md`.

## Required inputs

- repository root and current branch
- owned scope and forbidden scope
- expected harness artifacts
- requested goal and proof ceiling
- current Git/PR evidence when available

## Load order

1. Read `AGENTS.md` without modifying it.
2. Preserve current Git state and unrelated work.
3. If current remote behavior matters or an expected tracked surface is missing, read `harness/workflows/repository-freshness-before-launch.yaml`; do not contact the remote until repository-network authority is explicit.
4. Read `CODEBASE_MAP.md`.
5. Read `harness/api/operational-harness-manifest.json`.
6. Read `harness/workflows/fresh-agent-intake.yaml` and `harness/workflows/operational-harness-maintenance.yaml`.
7. Read `harness/api/harness-command-registry.json`, `harness/api/harness-validator-registry.json`, `harness/api/harness-artifact-registry.json`, `harness/api/harness-outcome-registry.json`, and `harness/api/deployment-state-registry.json`.
8. Read `harness/workflows/outcome-driven-execution.yaml` when validators, dry runs, plans, preflights, fixtures, or transport live certs could become artificial stopping points.
9. Read `harness/workflows/cybernet-autologon-deployment-state.yaml` and `harness/skills/cybernet-autologon-deployment-state/SKILL.md` when AutoLogon/Cybernet desired-state behavior is being changed.
10. Inspect only the harness components implicated by the requested change.

## Procedure

### 1. Inspect

- Identify existing authorities before creating new files.
- Confirm every requested harness component is either present and complete or has one concrete gap.
- Treat generated output, operator evidence, machine-local paths, and live data as untracked unless the artifact registry explicitly says otherwise.
- Resolve the user's requested terminal goal before choosing validation so the harness can distinguish an admission test from the actual deliverable.
- For deployment-oriented harness work, resolve desired product/runtime state and compare it to current product truth without modifying product files.
- Treat repository freshness as a prerequisite to absence claims: fetching a remote ref does not update the checked-out branch or worktree.
- A freshness trigger does not grant repository-network or branch-update authority. If repository-network authority is absent, stop before fetch with the exact blocked action.
- Never update the default branch solely because it is clean and behind. Preserve it in an isolated worktree unless default-branch update authority is explicit.
- A clean owned non-default branch may use fast-forward-only convergence only when branch-update authority is explicit; otherwise use an isolated worktree.
- Never invent an alternate launcher, validator, or workflow because a path is missing from a stale executing tree; check the authorized refreshed intended commit first.

### 2. Implement

- Prefer extending the existing operational manifest and registries over creating parallel authorities.
- Keep codebase maps factual and point to canonical entrypoints instead of embedding large implementation narratives.
- Keep workflow stages ordered and fail closed at unresolved routing, repository-freshness, authorization, validation, product-truth, or evidence boundaries.
- Hooks must not contact product targets or perform deployment mutation.
- Pre-push repository-freshness proof must run against the exact pushed ref-update commit, not a dirty live worktree or staged-only state.
- Operator reports must separate working state, desired-state behavior, known gaps, validation commands, outcome continuation, and proof ceiling.
- Every canonical command must have an outcome contract. A validation/dry-run/build/plan success must resolve a registered artifact; deployment-oriented plans must name the continuation that advances an authorized deployment goal.
- AutoLogon/Cybernet desired-state rules must be checked against the tracked package catalogs and real product entrypoints so weaker agents cannot mistake transport proof for application or regress to a blocked LocalSystem lane.

### 3. Validate

Always run the focused harness floor first:

```text
python harness/validators/validate-harness-registries.py
python harness/validators/validate-repository-freshness-contracts.py
python harness/validators/validate-outcome-contracts.py
python harness/validators/validate-deployment-state-contracts.py
python Tests/survey/test_operational-harness-completeness-contracts.py
python Tests/survey/test_local-harness-contracts.py
git diff --check
```

Then select additional validators from `harness/api/harness-validator-registry.json` based on changed surfaces. Run the broad offline floor when the focused checks pass:

```text
bash tests/survey/run_offline_survey_tests.sh
```

Run full Pester, managed tests, build, or E2E only when the changed surface or declared proof ceiling requires them.

A passing validator is supporting evidence. When the requested goal remains unproven and `harness/api/harness-outcome-registry.json` or `harness/api/deployment-state-registry.json` names the next safe, authorized, dependency-satisfied state transition, execute that continuation rather than ending with the pass result.

### 4. Failure handling

- Stop at the first failed proof boundary.
- Classify the failure as repository-freshness, authorization, structure, schema/registry, outcome/continuation, deployment-state/product-truth, hook/CI wiring, text policy, dependency, integration, or runtime.
- Repair the smallest owning harness component.
- Rerun the failed validator before broader validation.
- Never weaken a validator merely to make the harness green.
- When the blocker is genuinely external, record the exact blocker owner, dependency, executable action, and artifact/proof the action will produce.

### 5. Commit and publish

- Name every changed file.
- Use an isolated branch or worktree when unrelated work exists.
- Do not force-push or mutate `main` directly without explicit default-branch update authority.
- When remote publication is authorized, follow `harness/workflows/operational-harness-publish.yaml` and open/update one PR.
- Do not treat PR creation, CI status display, or a validator pass as the terminal user outcome when safe executable work remains inside the requested goal.

## Expected outputs

- tracked harness component changes
- passing focused repository-freshness, registry, outcome, deployment-state, and completeness checks
- broader validation results when required
- commit SHA
- push/PR evidence when authorized
- requested goal, desired state when applicable, and registered terminal outcome
- exact next command only when a real remaining gate prevents further safe execution

## Proof ceiling

This skill can prove authorized repository selection, harness structure, routing, registries, desired-state contracts, outcome contracts, hooks, CI wiring, documentation, and static/build contract status. It cannot by itself prove product behavior, target reachability, deployment success, reboot behavior, application behavior, or technician acceptance.
