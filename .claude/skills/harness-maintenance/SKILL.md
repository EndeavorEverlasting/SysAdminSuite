# Harness Maintenance Skill

## Trigger

Use this skill when the task explicitly owns repository harness infrastructure: codebase maps, harness workflows, validator registries, artifact registries, hooks, scoped skills, operator reports, harness schemas, or harness CI.

Do not use this skill to change product behavior, deployment logic, device profiles, credentials, secrets, or the root governance contract in `AGENTS.md`.

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
7. Inspect only the harness components implicated by the requested change.

## Procedure

### 1. Inspect

- Identify existing authorities before creating new files.
- Confirm every requested harness component is either present and complete or has one concrete gap.
- Treat generated output, operator evidence, machine-local paths, and live data as untracked unless the artifact registry explicitly says otherwise.

### 2. Implement

- Prefer extending the existing operational manifest and registries over creating parallel authorities.
- Keep codebase maps factual and point to canonical entrypoints instead of embedding large implementation narratives.
- Keep workflow stages ordered and fail closed at unresolved routing, validation, or evidence boundaries.
- Hooks must run local/offline proof only; they must not contact product targets or perform deployment mutation.
- Operator reports must separate working state, known gaps, validation commands, and proof ceiling.

### 3. Validate

Always run the focused harness floor first:

```text
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
python Tests/survey/test_local_harness_contracts.py
git diff --check
```

Then select additional validators from `harness/api/harness-validator-registry.json` based on changed surfaces. Run the broad offline floor when the focused checks pass:

```text
bash tests/survey/run_offline_survey_tests.sh
```

Run full Pester, managed tests, build, or E2E only when the changed surface or declared proof ceiling requires them.

### 4. Failure handling

- Stop at the first failed proof boundary.
- Classify the failure as structure, schema/registry, hook/CI wiring, text policy, dependency, integration, or runtime.
- Repair the smallest owning harness component.
- Rerun the failed validator before broader validation.
- Never weaken a validator merely to make the harness green.

### 5. Commit and publish

- Name every changed file.
- Use an isolated branch or worktree when unrelated work exists.
- Do not force-push or mutate `main` directly.
- When remote publication is authorized, follow `harness/workflows/operational-harness-publish.yaml` and open/update one PR.

## Expected outputs

- tracked harness component changes
- passing focused completeness and registry checks
- broader validation results when required
- commit SHA
- push/PR evidence when authorized
- exact next command that advances the first remaining unproven gate

## Proof ceiling

This skill can prove repository harness structure, routing, registries, hooks, CI wiring, documentation, and static/build contract status. It cannot by itself prove product behavior, target reachability, deployment success, reboot behavior, application behavior, or technician acceptance.
