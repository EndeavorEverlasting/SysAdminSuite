# SysAdminSuite Operational Harness Status

## Current state

The repository has an operational harness floor for fresh-agent intake, task routing, requested-goal and desired-state resolution, canonical command selection, scoped validation, artifact production, same-turn continuation, local hooks, English reporting, and next-agent handoff. The machine-readable component authority is `harness/api/operational-harness-manifest.json`; this report is the human-readable view.

## Working

- **Fresh-agent intake:** `harness/workflows/fresh-agent-intake.yaml` gives a new agent one ordered path from governance and Git preservation through requested-goal/desired-state resolution, route selection, execution, validation, artifact resolution, outcome continuation, and handoff.
- **Repository orientation:** `AGENTS.md` remains the unchanged P00 governance authority and `CODEBASE_MAP.md` routes agents to the smallest relevant surface plus canonical build/test/deploy/runtime commands.
- **Command authority:** `harness/api/harness-command-registry.json` records canonical build, test, run, full Cybernet software deployment, AutoLogon-only restart-complete deployment, and optional actual-session runtime-proof entrypoints together with mutation/network classifications.
- **Outcome authority:** `harness/api/harness-outcome-registry.json` requires every canonical command to resolve a registered success artifact or terminal outcome, including `product_deployed` and `runtime_proven`, and records same-turn continuations when the requested goal remains unproven.
- **Deployment-state authority:** `harness/api/deployment-state-registry.json` binds AutoLogon/Cybernet `test`, `live cert`, `deploy`, and `runtime proof` wording to explicit desired states and critical artifacts instead of allowing a diagnostic pass to masquerade as application.
- **Harness registry integrity:** `harness/validators/validate-harness-registries.py` checks manifest components, tracked registry schemas, command/outcome/deployment-state wiring, fresh-agent workflow wiring, harness-scoped skills, artifact roles, and the report renderer.
- **Outcome contract integrity:** `harness/validators/validate-outcome-contracts.py` rejects tests-only, status-only, command-printed-only, wait-for-next-chat, and operator-repeats-agent-work endpoints.
- **Deployment-state integrity:** `harness/validators/validate-deployment-state-contracts.py` cross-checks desired-state routing against the current approved AutoLogon package disposition, Cybernet package-set ordering, S4U apply engine, restart-complete wrappers, command/outcome registries, and critical artifacts.
- **Registry schemas:** command, validator, artifact, outcome, and deployment-state registries each have a tracked Draft 2020-12 schema under `schemas/harness/`; the operational manifest retains its Draft 2020-12 schema.
- **Scoped harness skills:** `harness/skills/harness-maintenance/SKILL.md`, `harness/skills/outcome-driven-execution/SKILL.md`, and `harness/skills/cybernet-autologon-deployment-state/SKILL.md` extend execution behavior without modifying the P00 `.claude/skills/` router.
- **Local/remote boundary:** `harness/workflows/operational-harness-maintenance.yaml` remains network-free; operator-approved Git push and pull-request publication are isolated in `harness/workflows/operational-harness-publish.yaml`.
- **Run context and artifacts:** `harness/api/harness-artifact-registry.json` identifies the five-package clinical-core stage, internal S4U pre-reboot gate, restart-complete AutoLogon result, restart-complete full Cybernet software result, and optional actual-session runtime proof as distinct proof objects.
- **Hooks:** `.githooks/pre-commit` and `.githooks/pre-push` run registry, outcome, and deployment-state validators so a lesser model cannot publish a command chain that terminates at a meaningless green step.
- **Harness CI:** `.github/workflows/harness-registry-integrity.yml` and `.github/workflows/harness-infrastructure.yml` validate deployment-state schema/contracts in addition to the existing harness floor; the focused registry workflow is also triggered by the real full-deploy and AutoLogon restart surfaces.
- **Repository text policy:** `.gitattributes` and `scripts/check-repo-text-policy.py` retain canonical LF storage and no-trailing-whitespace enforcement without destructive rewriting of historical launchers.

## Outcome-driven execution

`harness/workflows/outcome-driven-execution.yaml` changes the stopping rule for agents:

- **Tests passed is not task completion** when the requested artifact or deployment state is still unproven.
- Dry runs, plans, preflights, fixture E2E, and harmless transport live certs are admission gates when the desired state is live application.
- If the requested goal remains unproven and a safe, authorized, dependency-satisfied continuation exists, the agent executes it instead of handing the operator another command to paste.
- Terminal outcomes distinguish restart-complete `product_deployed` from optional `runtime_proven` so a diagnostic or pre-reboot state cannot be promoted to completed deployment.
- Target authorization, current administrative identity, protected network access, and real runtime observation remain genuine gates where applicable.

## AutoLogon / Cybernet desired-state execution

This is the critical field behavior the harness now enforces.

The tracked product truth says the current AutoLogon package is install-enabled, but canonical **LocalSystem** AutoLogon remains blocked after the no-argument installer returned success without establishing `AutoAdminLogon=1`. Therefore the historical generic six-package LocalSystem Cybernet apply is **not** a substitute for the current field deployment composition.

For one authorized Cybernet:

1. **Full software deployment is one field transaction.** `sas cybernet Deploy HOST` deploys the five `cybernet-clinical-core` applications first, applies AutoLogon last through S4U, then automatically restarts the same target and waits for the previously proven SMB service to leave and return.
2. **Already-proven clinical core is preserved.** If the five clinical applications are already installed/accepted, skip their reinstall and use `sas autologon Remote HOST` for AutoLogon-only deployment.
3. **`test AutoLogon`, `deploy AutoLogon`, or AutoLogon/Cybernet `live cert` with mutation authority means real deployment.** Fixture E2E and transport-only `LIVE CERT PASS` remain admission evidence, not the requested result.
4. **The pre-reboot S4U result is internal only.** `autologon_kerberos_s4u_pilot_result.json` with `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` proves the package established the required pre-reboot state; the agent must continue to restart.
5. **AutoLogon-only deployment completes after restart.** `autologon_s4u_deployment_result.json` must report `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED`, `automatic_reboot_performed=true`, `restart_offline_observed=true`, and `restart_online_observed=true`.
6. **Full Cybernet software deployment completes after restart.** `cybernet_software_deployment_result.json` must report `CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED`, with AutoLogon last and the restart cycle observed.
7. **Runtime proof is optional higher-ceiling evidence.** When explicitly requested after deployment, run the actual-session runtime proof and require `TECHNICIAN_OBSERVED_LIVE_RUNTIME`, `runtime_proof=true`, and `overall_success=true`. Runtime proof must not delay deployment completion.

The critical state chain is therefore:

```text
full deployment:
clinical_core_ready
        -> autologon_pre_reboot_configured
           [internal S4U gate]
        -> autologon_restart_completed
           [AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED]
        -> cybernet_software_deployed
           [CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED]

when clinical core is already proven:
autologon_pre_reboot_configured
        -> autologon_restart_completed

optional higher ceiling:
autologon_restart_completed
        -> autologon_runtime_proven
           [TECHNICIAN_OBSERVED_LIVE_RUNTIME]
```

## Repaired boundary

The earlier harness removed the general “tests passed, now give the operator a command” failure mode, but still allowed the pre-reboot S4U state and an externally deferred reboot to sit between the technician and a usable AutoLogon deployment.

The current deployment-state registry, restart-complete S4U wrapper, full Cybernet software orchestrator, schemas, workflow, skill, validators, command/artifact/outcome registries, technician guidance, hooks, and CI wiring close that gap without weakening the blocked canonical SYSTEM AutoLogon disposition.

An earlier harness-maintenance procedure was deliberately kept outside `.claude/skills/` because that directory belongs to the P00 capability manifest/router. The same boundary remains intact here.

## Known gaps and proof limits

- Repository hooks are tracked but must be enabled once per clone with `bash scripts/install-local-harness-hooks.sh`.
- The generated status renderer proves registry/path/product-truth wiring only; it does not imply that a live target was contacted.
- Static and fixture passes still do not prove a live deployment or restart; the harness prevents those lower proofs from being mislabeled.
- A restart-complete deployment artifact proves the restart cycle, not that a human visually observed automatic sign-in. Direct automatic-sign-in/application behavior remains the optional runtime-proof ceiling.
- Deployment-state execution cannot invent target authorization, administrative access, protected network access, or physical/runtime observation.
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

A complete harness reports every required component as present and tracked, validates registry/outcome/deployment-state integrity and all tracked manifest/registry schemas, proves restart-complete desired-state execution plus same-turn continuation, hook and CI wiring, command/artifact authorities and line-ending policy, and exits with:

```text
PASS: harness registry integrity
PASS: outcome-driven harness contracts
PASS: deployment-state harness contracts
PASS: operational harness completeness
```
