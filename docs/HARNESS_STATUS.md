# SysAdminSuite Operational Harness Status

## Current state

The repository has an operational harness floor for fresh-agent intake, task routing, canonical command selection, scoped validation, artifact production, local hooks, English reporting, and next-agent handoff. The machine-readable component authority is `harness/api/operational-harness-manifest.json`; this report is the human-readable view.

## Working

- **Fresh-agent intake:** `harness/workflows/fresh-agent-intake.yaml` gives a new agent one ordered path from governance and Git preservation through orientation, route selection, execution, validation, artifact resolution, and handoff.
- **Repository orientation:** `AGENTS.md` remains the unchanged P00 governance authority and `CODEBASE_MAP.md` routes agents to the smallest relevant surface plus canonical build/test/deploy commands.
- **Command authority:** `harness/api/harness-command-registry.json` records canonical build, test, run, Cybernet plan/apply, and remote AutoLogon entrypoints together with mutation/network classifications.
- **Harness registry integrity:** `harness/validators/validate-harness-registries.py` checks manifest components, tracked registry schemas, validator/command registries, fresh-agent workflow wiring, harness-maintenance skill wiring, artifact roles, and the report renderer.
- **Registry schemas:** the command, validator, and artifact registries each have a tracked Draft 2020-12 schema under `schemas/harness/`; the operational manifest retains its Draft 2020-12 schema.
- **Validator selection:** `harness/api/harness-validator-registry.json` records validator commands, changed-surface scope, blocking posture, escalation, and exact proof boundaries.
- **Scoped harness skill:** `harness/skills/harness-maintenance/SKILL.md` owns harness-only extensions outside the `.claude/skills/` P00 router and explicitly excludes product behavior, secrets, destructive cleanup, and `AGENTS.md` mutation.
- **Local/remote boundary:** `harness/workflows/operational-harness-maintenance.yaml` remains network-free; operator-approved Git push and pull-request publication are isolated in `harness/workflows/operational-harness-publish.yaml`.
- **Run context and artifacts:** `scripts/SasRunContext.psm1` creates bounded run roots, per-run artifact registries, reports, review paths, and operator handoffs. `harness/api/harness-artifact-registry.json` names tracked and generated artifact roles.
- **Validation:** dependency-free Python contracts, Pester suites, Bash syntax checks, schemas, manifests, dedicated workflows, managed tests, and default E2E profiles are indexed by the validator registry.
- **Hooks:** `.githooks/pre-commit` runs registry integrity before the focused contract floor and blocks generated/private evidence; `.githooks/pre-push` runs the broad offline floor, registry integrity, and destination-commit text validation.
- **Harness CI:** `.github/workflows/harness-registry-integrity.yml` validates all four manifest/registry schemas, registry integrity, completeness, report rendering, hook/offline-runner syntax, and whitespace whenever registry-facing harness files change.
- **Reports and handoff:** `harness/reports/render-harness-status.py` generates a current human registry/path view, while `tools/New-SasSprintCapsule.ps1` provides compressed next-agent handoffs.
- **Cross-lane preservation:** the broad offline runner retains `Tests/survey/test_autologon_s4u_path_budget_contracts.py`, so this harness sprint cannot silently regress the already-merged field long-path fix.
- **Repository text policy:** `.gitattributes` classifies CMD/BAT, shell/fixture files, JSONL, and binaries without forcing Windows worktree rewrites. `scripts/check-repo-text-policy.py` independently enforces canonical LF bytes and no trailing whitespace in every changed Git text blob.

## Repaired boundary

The pre-existing operational harness already contained the core map, maintenance/publish workflows, artifact registry, hooks, completeness contract, status report, run context, scoped validation skills, and CI. A fresh agent still had to infer which validator to run, where canonical build/test/deploy commands lived, and which workflow owned harness-only changes. The validator registry, command registry, fresh-agent workflow, fail-closed registry schemas, scoped harness skill, and generated status renderer close those inference gaps without changing product behavior or the root governance contract.

An earlier implementation attempted to place the harness-maintenance procedure under `.claude/skills/`. The existing AI-layer validator correctly rejected that because `.claude/skills/` belongs to the P00 capability manifest and `AGENTS.md` router. The procedure now lives under `harness/skills/` instead, preserving the forbidden governance boundary.

A prior push-only whitespace check reported every line of a Windows CMD file as trailing whitespace because the Git blob contained CRLF bytes. The harness continues to validate bytes stored in Git without forcing checkout conversion. Four historical CRLF launchers remain preserved byte-for-byte until product work legitimately changes them: `Run-CybernetComPortQrPack.cmd`, `Run-FieldHotfixesGui.cmd`, `Start-CybernetSurveyTutorial.cmd`, and `survey/sas-reg-query.cmd`.

## Known gaps and proof limits

- Existing historical blobs are not rewritten wholesale; the text-policy validator applies when a text file is changed and blocks noncanonical stored bytes.
- Repository hooks are tracked but must be enabled once per clone with `bash scripts/install-local-harness-hooks.sh`.
- The generated status renderer proves registry/path inventory only; it does not imply that validators ran in the current checkout.
- Static and fixture passes do not prove live target reachability, deployment success, application behavior, reboot behavior, or technician acceptance.
- Generated run evidence remains local under ignored `survey/output/` roots and must not be committed.

## Operator validation

Run the focused harness floor from the repository root:

```powershell
python .\harness\validators\validate-harness-registries.py
python .\Tests\survey\test_operational_harness_completeness_contracts.py
python .\scripts\check-repo-text-policy.py --commit HEAD
python .\Tests\survey\test_local_harness_contracts.py
git diff --check
```

Render the English registry/path view without changing tracked files:

```powershell
python .\harness\reports\render-harness-status.py
```

Run the broader offline floor when the focused checks pass:

```bash
bash tests/survey/run_offline_survey_tests.sh
```

## Expected result

A complete harness reports every required component as present and tracked, validates registry integrity and all four tracked manifest/registry schemas, proves hook and CI wiring, confirms command/artifact authorities and line-ending policy, and exits with both:

```text
PASS: harness registry integrity
PASS: operational harness completeness
```
