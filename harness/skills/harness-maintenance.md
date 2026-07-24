# Harness Maintenance Procedure

## Trigger
Use this scoped harness procedure when the task explicitly owns repository harness infrastructure: maps, workflows, validator/command/artifact registries, hooks, scoped harness procedures, operator reports, harness schemas, or harness CI.

Do not use it to change product behavior, deployment logic, device profiles, secrets, or the root governance contract in `AGENTS.md`.

## Required inputs
- repository root and current branch
- owned scope and forbidden scope
- expected harness artifacts
- requested proof ceiling
- current Git/PR evidence when available

## Load order
1. Read `AGENTS.md` without modifying it.
2. Preserve current Git state and unrelated work.
3. Read `CODEBASE_MAP.md`.
4. Read `harness/api/operational-harness-manifest.json`.
5. Read `harness/workflows/fresh-agent-intake.yaml` and `harness/workflows/operational-harness-maintenance.yaml`.
6. Read `harness/api/harness-command-registry.json`, `harness/api/harness-validator-registry.json`, and `harness/api/harness-artifact-registry.json`.
7. Inspect only harness components implicated by the task.

## Procedure
### 1. Inspect
- Reuse existing authorities before creating new ones.
- Identify one concrete gap for each missing/incomplete requested component.
- Keep generated output, operator evidence, machine-local paths, and live data untracked unless the artifact registry explicitly says otherwise.

### 2. Implement
- Extend the operational manifest and registries rather than creating parallel authorities.
- Keep maps factual and point to canonical entrypoints.
- Fail closed at unresolved routing, validation, or evidence boundaries.
- Hooks run local/offline proof only and never contact product targets.
- Operator reports separate working state, gaps, validation, and proof ceiling.
- Do not place harness-only procedures under `.claude/skills/` unless P00 governance explicitly adds them to the root router.

### 3. Validate
Always run the focused floor first:

```text
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
python Tests/survey/test_local_harness_contracts.py
git diff --check
```

Then select additional checks from `harness/api/harness-validator-registry.json`. After focused checks pass:

```text
bash tests/survey/run_offline_survey_tests.sh
```

Run full Pester, managed tests/build, or E2E only when the changed surface or proof ceiling requires it.

### 4. Failure handling
- Stop at the first failed proof boundary.
- Classify it as structure, schema/registry, hook/CI wiring, text policy, dependency, integration, or runtime.
- Repair the smallest owning harness component.
- Rerun the failed validator before broader validation.
- Never weaken a validator merely to make the harness green.

### 5. Commit and publish
- Name every changed file.
- Use an isolated branch/worktree when unrelated work exists.
- Do not force-push or mutate `main` directly.
- Follow `harness/workflows/operational-harness-publish.yaml` for authorized remote publication.

## Expected outputs
- tracked harness component changes
- passing focused completeness and registry checks
- broader validation results when required
- commit SHA
- push/PR evidence
- exact next command advancing the first unproven gate

## Proof ceiling
This procedure proves repository harness structure, routing, registries, schemas, hooks, CI wiring, documentation, and static/build-contract status. It does not prove product behavior, target reachability, deployment success, reboot behavior, application behavior, or technician acceptance.
