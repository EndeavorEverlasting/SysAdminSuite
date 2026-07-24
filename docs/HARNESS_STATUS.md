# SysAdminSuite Operational Harness Status

## Current state

The repository has an operational harness floor for fresh-agent intake, workflow selection, canonical command selection, scoped validation, artifact production, local hooks, English reporting, and next-agent handoff. `harness/api/operational-harness-manifest.json` is the machine-readable component inventory; this report is the human-readable view.

## Working

- **Fresh-agent intake:** `harness/workflows/fresh-agent-intake.yaml` gives a new agent one ordered path from governance and Git preservation through orientation, routing, execution, validation, artifacts, and handoff.
- **Repository orientation:** `AGENTS.md` remains the unchanged P00 governance authority and `CODEBASE_MAP.md` remains the canonical repository map.
- **Command authority:** `harness/api/harness-command-registry.json` records canonical harness validation, tests, managed build, dashboard run/build, Cybernet plan/apply, and remote AutoLogon commands with mutation/network classifications.
- **Harness registry integrity:** `harness/validators/validate-harness-registries.py` checks component tracking, registry structure, tracked schemas, canonical source paths, fresh-agent workflow wiring, scoped procedure wiring, artifacts, and report rendering.
- **Registry schemas:** command, validator, artifact, and central operational manifests have tracked Draft 2020-12 schemas under `schemas/harness/`.
- **Validator selection:** `harness/api/harness-validator-registry.json` records commands, changed-surface scopes, blocking posture, escalation, and exact proof boundaries.
- **Scoped harness procedure:** `harness/skills/harness-maintenance.md` owns harness-only extensions outside the `.claude/skills/` P00 governance router and explicitly excludes product behavior, secrets, destructive cleanup, and `AGENTS.md` mutation.
- **Workflow specs:** `harness/workflows/operational-harness-maintenance.yaml` defines pickup, routing, implementation, validation, failure repair, commit, and handoff. Remote publication remains isolated in `operational-harness-publish.yaml`.
- **Artifacts:** `harness/api/harness-artifact-registry.json` identifies tracked authorities and generated/local artifacts, generators, naming, and live-data boundaries.
- **Hooks:** `.githooks/pre-commit` and `.githooks/pre-push` run registry integrity in addition to the existing focused/offline harness floor and text policy.
- **Operator reports:** `harness/reports/render-harness-status.py` renders a current English registry/path view without changing tracked documentation.
- **Harness CI:** `.github/workflows/harness-registry-integrity.yml` validates registry schemas, registry integrity, completeness, report rendering, hook syntax, and whitespace; the existing `harness-infrastructure.yml` retains its broader Windows handoff/Pester floor.
- **Cross-lane preservation:** the shared offline runner retains `Tests/survey/test_autologon_s4u_path_budget_contracts.py` from the current AutoLogon field fix before running the new harness registry validator.

## Repaired boundary

The pre-existing harness already had a core codebase map, maintenance/publish workflows, artifact registry, hooks, completeness contract, status report, run context, scoped validation skills, and CI. The remaining inference gaps were canonical validator selection, canonical build/test/deploy commands, deterministic fresh-agent intake, machine-validated registry schemas, a harness-only maintenance procedure, and a generated operator status view. Those gaps are now represented as tracked harness components rather than tribal knowledge.

The first harness-maintenance procedure was initially placed under `.claude/skills/`; the existing AI-layer validator correctly rejected that because `.claude/skills/` is governed by the P00 capability manifest and `AGENTS.md` router. The procedure was moved to `harness/skills/` instead of expanding into forbidden governance scope.

## Known gaps and proof limits

- Repository hooks are tracked but must be enabled once per clone with `bash scripts/install-local-harness-hooks.sh`.
- The generated status renderer proves current registry/path inventory; it does not prove validators were executed unless their output is separately recorded.
- Static and fixture passes do not prove live target reachability, deployment success, application behavior, reboot behavior, or technician acceptance.
- Generated run evidence remains local under ignored `survey/output/` roots and must not be committed.

## Operator validation

Focused harness floor:

```powershell
python .\harness\validators\validate-harness-registries.py
python .\Tests\survey\test_operational_harness_completeness_contracts.py
python .\scripts\check-repo-text-policy.py --commit HEAD
python .\Tests\survey\test_local_harness_contracts.py
git diff --check
```

English operator view:

```powershell
python .\harness\reports\render-harness-status.py
```

Broader offline floor after focused checks pass:

```bash
bash tests/survey/run_offline_survey_tests.sh
```

## Expected result

A complete harness reports all required components present and tracked, validates registry integrity and schemas, proves hook/CI wiring and command/artifact authorities, and exits with:

```text
PASS: harness registry integrity
PASS: operational harness completeness
```
