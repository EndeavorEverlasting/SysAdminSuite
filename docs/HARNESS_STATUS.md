# SysAdminSuite Operational Harness Status

## Current state

The repository has an operational harness floor for fresh-agent intake, task routing, requested-goal and desired-state resolution, canonical command selection, scoped validation, artifact production, same-turn continuation, local hooks, English reporting, and next-agent handoff. The machine-readable component authority is `harness/api/operational-harness-manifest.json`; this report is the human-readable view.

## Working

- **Fresh-agent intake:** `harness/workflows/fresh-agent-intake.yaml` gives a new agent one ordered path from governance and Git preservation through requested-goal/desired-state resolution, route selection, execution, validation, artifact resolution, outcome continuation, and handoff.
- **Repository orientation:** `AGENTS.md` remains the unchanged P00 governance authority and `CODEBASE_MAP.md` routes agents to the smallest relevant surface plus canonical build/test/deploy/runtime commands.
- **Command authority:** `harness/api/harness-command-registry.json` records canonical build, test, run, Cybernet plan/apply, remote AutoLogon S4U apply, and actual-session AutoLogon runtime-proof entrypoints together with mutation/network classifications.
- **Outcome authority:** `harness/api/harness-outcome-registry.json` requires every canonical command to resolve a registered success artifact or terminal outcome, including `runtime_proven`, and records same-turn continuations when the requested goal remains unproven.
- **Deployment-state authority:** `harness/api/deployment-state-registry.json` binds AutoLogon/Cybernet `test`, `live cert`, `deploy`, and `runtime proof` wording to explicit desired states and critical artifacts instead of allowing a diagnostic pass to masquerade as application.
- **Harness registry integrity:** `harness/validators/validate-harness-registries.py` checks manifest components, tracked registry schemas, command/outcome/deployment-state wiring, fresh-agent workflow wiring, harness-scoped skills, artifact roles, and the report renderer.
- **Outcome contract integrity:** `harness/validators/validate-outcome-contracts.py` rejects tests-only, status-only, command-printed-only, wait-for-next-chat, and operator-repeats-agent-work endpoints.
- **Deployment-state integrity:** `harness/validators/validate-deployment-state-contracts.py` cross-checks desired-state routing against the current approved AutoLogon package disposition, Cybernet package-set separation, real S4U apply script, real runtime-proof script, command/outcome registries, and critical artifacts.
- **Registry schemas:** command, validator, artifact, outcome, and deployment-state registries each have a tracked Draft 2020-12 schema under `schemas/harness/`; the operational manifest retains its Draft 2020-12 schema.
- **Scoped harness skills:** `harness/skills/harness-maintenance/SKILL.md`, `harness/skills/outcome-driven-execution/SKILL.md`, and `harness/skills/cybernet-autologon-deployment-state/SKILL.md` extend execution behavior without modifying the P00 `.claude/skills/` router.
- **Local/remote boundary:** `harness/workflows/operational-harness-maintenance.yaml` remains network-free; operator-approved Git push and pull-request publication are isolated in `harness/workflows/operational-harness-publish.yaml`.
- **Run context and artifacts:** `harness/api/harness-artifact-registry.json` now identifies both the S4U pre-reboot deployment artifact and the actual-session runtime proof artifact as separate critical proof objects.
- **Hooks:** `.githooks/pre-commit` and `.githooks/pre-push` run registry, outcome, and deployment-state validators so a lesser model cannot publish a command chain that terminates at a meaningless green step.
- **Harness CI:** `.github/workflows/harness-registry-integrity.yml` and `.github/workflows/harness-infrastructure.yml` validate deployment-state schema/contracts in addition to the existing harness floor.
- **Repository text policy:** `.gitattributes` and `scripts/check-repo-text-policy.py` retain canonical LF storage and no-trailing-whitespace enforcement without destructive rewriting of historical launchers.

## Outcome-driven execution

`harness/workflows/outcome-driven-execution.yaml` changes the stopping rule for agents:

- **Tests passed is not task completion** when the requested artifact, deployment, or runtime state is still unproven.
- Dry runs, plans, preflights, fixture E2E, and harmless transport live certs are admission gates when the desired state is live application.
- If the requested goal remains unproven and a safe, authorized, dependency-satisfied continuation exists, the agent executes it instead of handing the operator another command to paste.
- Terminal outcomes now distinguish `product_deployed` from `runtime_proven` so merely starting an application or applying registry state cannot be promoted to runtime behavior proof.
- Explicit credentials, target-mutation consent, attended reboot authority, direct sign-in observation, protected runtime access, and technician acceptance remain genuine gates.

## AutoLogon / Cybernet desired-state execution

This is the critical field behavior the harness now enforces.

The tracked product truth says the current AutoLogon package is install-enabled, but canonical **LocalSystem** AutoLogon remains blocked after the no-argument installer returned success without establishing `AutoAdminLogon=1`. Therefore a generic six-package LocalSystem Cybernet apply is **not** a substitute for the current AutoLogon field lane.

For one authorized Cybernet:

1. **Already-proven clinical core is preserved.** If the five `cybernet-clinical-core` applications are already installed/accepted, the harness says to skip their reinstall rather than regress or waste field time.
2. **`test AutoLogon`, `deploy AutoLogon`, or AutoLogon/Cybernet `live cert` with mutation authority means real apply.** The current apply command is `sas autologon Remote HOST`, not fixture E2E or transport-only `LIVE CERT PASS`.
3. **Pre-reboot deployment is not proven by exit code.** It requires `autologon_kerberos_s4u_pilot_result.json` with classification `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING`.
4. **Deployment + runtime proof remains one ordered work item.** Once the positive S4U artifact exists, the next genuine gate is a separately authorized attended reboot with direct observation of automatic sign-in—not another round of admission tests.
5. **Runtime proof runs from the actual AutoLogon desktop.** The canonical runtime artifact is `runtime-proof-summary.json`; completion requires `proof_level=TECHNICIAN_OBSERVED_LIVE_RUNTIME`, `runtime_proof=true`, and `overall_success=true`.
6. **Runtime-proof-only wording does not invent deployment authority.** It requires a correlated positive pre-reboot deployment artifact for the same target before runtime proof begins.

The critical state chain is therefore:

```text
clinical_core_ready (reuse when already proven)
        -> autologon_pre_reboot_configured
           [sas autologon Remote HOST]
           [KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING]
        -> separately authorized attended reboot + direct automatic-sign-in observation
        -> autologon_runtime_proven
           [runtime-proof-summary.json]
           [TECHNICIAN_OBSERVED_LIVE_RUNTIME]
```

## Repaired boundary

The earlier harness removed the general “tests passed, now give the operator a command” failure mode, but it still lacked a product-state model for AutoLogon/Cybernet. That allowed weaker agents to confuse a harmless live cert, fixture pass, plan, or installer process result with the user’s real goal: AutoLogon applied on the Cybernet and then proven at runtime.

The deployment-state registry, schema, workflow, skill, validator, command/artifact/outcome extensions, hooks, and CI wiring close that gap without changing `AGENTS.md` or product code.

An earlier harness-maintenance procedure was deliberately kept outside `.claude/skills/` because that directory belongs to the P00 capability manifest/router. The same boundary remains intact here.

## Known gaps and proof limits

- Repository hooks are tracked but must be enabled once per clone with `bash scripts/install-local-harness-hooks.sh`.
- The generated status renderer proves registry/path/product-truth wiring only; it does not imply that a live target was contacted.
- Static and fixture passes still do not prove deployment, reboot, automatic sign-in, application behavior, or technician acceptance; the new harness prevents those lower proofs from being mislabeled.
- Deployment-state execution cannot invent target authorization, attended reboot authority, physical observation, credentials, or protected runtime access.
- Clinical-core software may be skipped only when its installed/accepted state is actually proven or explicitly supplied by the operator; the harness does not guess that state.
- Generated run evidence remains operator-local and must not be committed.

## Operator validation

Run the focused harness floor from the repository root:

```powershell
python .\harness\validators\validate-harness-registries.py
python .\harness\validators\validate-outcome-contracts.py
python .\harness\validators\validate-deployment-state-contracts.py
python .\Tests\survey\test_operational_harness_completeness_contracts.py
python .\scripts\check-repo-text-policy.py --commit HEAD
python .\Tests\survey\test_local_harness_contracts.py
git diff --check
```

Render the English registry/state view without changing tracked files:

```powershell
python .\harness\reports\render-harness-status.py
```

Run the broader offline floor after the focused checks:

```bash
bash tests/survey/run_offline_survey_tests.sh
```

## Expected result

A complete harness reports every required component as present and tracked, validates registry/outcome/deployment-state integrity and all six tracked manifest/registry schemas, proves desired-state execution plus same-turn continuation, hook and CI wiring, command/artifact authorities and line-ending policy, and exits with:

```text
PASS: harness registry integrity
PASS: outcome-driven harness contracts
PASS: deployment-state harness contracts
PASS: operational harness completeness
```
