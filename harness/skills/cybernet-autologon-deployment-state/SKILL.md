# Cybernet AutoLogon Deployment-State Skill

## Trigger

Use this harness-scoped skill after normal repository routing when the task mentions any combination of:

- AutoLogon deployment, application, installation, testing, pilot, or live certification;
- Cybernet software deployment or profile completion where AutoLogon is expected last;
- AutoLogon runtime proof after deployment;
- a field request that says the other Cybernet clinical applications are already installed and the remaining goal is AutoLogon.

This skill resolves the ordered desired-state chain after routing. It prevents an agent from substituting fixtures, transport certification, dry runs, or a pre-reboot registry state for the requested deployment.

## Required inputs

- requested goal in plain language;
- target profile classification;
- one explicit authorized target when mutation is requested;
- mutation/network authority when the goal includes deployment;
- evidence or operator fact for whether the five-package Cybernet clinical core is already installed/accepted;
- the five operator-confirmed package source paths recorded in `harness/api/deployment-state-registry.json`;
- runtime-proof configuration only when a higher proof ceiling is explicitly requested after deployment.

## Procedure

1. Read `harness/api/deployment-state-registry.json` before choosing commands.
2. Verify every entry under `operator_confirmed_profile_sources` against `configs/software-packages/windows-native-package-sets.json`; fail closed on a package id, source folder, entrypoint, or enabled-state mismatch.
3. Resolve the desired terminal state before running any validator, dry run, preflight, transport live cert, or fixture.
4. For a full Cybernet software deployment, use `sas cybernet Deploy HOST`. The five clinical applications run first, **AutoLogon is last**, and the required target restart is part of the same deployment transaction.
5. For a Cybernet whose five clinical-core applications are already proven installed/accepted, preserve them. Do not reinstall them merely to reach AutoLogon. Use `sas autologon Remote HOST`.
6. For `test AutoLogon`, `deploy AutoLogon`, `apply AutoLogon`, or an AutoLogon/Cybernet `live cert` request with one authorized target and mutation authority, execute the real deployment lane. A fixture, Plan, transport live cert, process start, ACK, installer exit code, or pre-reboot classification is not the requested result.
7. The S4U engine may emit `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` internally. Treat it only as the apply gate. **Do not stop there.**
8. AutoLogon deployment completes only when `autologon_s4u_deployment_result.json` reports `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED`, `automatic_reboot_performed=true`, `restart_offline_observed=true`, and `restart_online_observed=true`.
9. Full Cybernet software deployment completes only when `cybernet_software_deployment_result.json` reports `CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED`, with AutoLogon last and the restart cycle observed.
10. The current catalog keeps canonical LocalSystem AutoLogon blocked. Do not substitute the historical six-package LocalSystem Cybernet apply for the S4U AutoLogon lane while that disposition remains true.
11. Runtime proof is optional higher-ceiling evidence. It does **not** delay deployment completion. Run `autologon-runtime-proof` only when the request explicitly requires runtime proof after restart-complete deployment.
12. When runtime proof is requested, require the correlated restart-complete deployment artifact for the same target, then run the proof from the actual AutoLogon desktop session and require `TECHNICIAN_OBSERVED_LIVE_RUNTIME` with `runtime_proof=true` and `overall_success=true`.
13. On any failure, preserve the owning run artifact, report the smallest failed state transition, and repair or advance that gate. Never reset to hours of live searching or repeated harmless tests.

## Critical artifacts

- **Internal pre-reboot apply gate:** `survey/output/runs/autologon-kerberos-s4u/<run>/autologon_kerberos_s4u_pilot_result.json`
- **AutoLogon deployment completion:** `survey/output/runs/autologon-s4u-deployment/<run>/autologon_s4u_deployment_result.json`
- **Full Cybernet software deployment completion:** `survey/output/runs/cybernet-software-deployment/<run>/cybernet_software_deployment_result.json`
- **Optional runtime proof:** `<approved runtime evidence directory>/autologon-runtime-<run>/runtime-proof-summary.json`

The pre-reboot S4U artifact proves the package established the required state before restart. It is not deployment completion. The restart-complete artifacts prove the software deployment state. Runtime proof is a separate optional higher ceiling.

## Forbidden stopping patterns

- `LIVE CERT PASS` from the harmless transport cert as the final deployment result;
- `deployment_planned`, `FIXTURE_PASS`, or `KERBEROS_S4U_FIXTURE_READY` when the requested goal is live deployment;
- `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` as final AutoLogon deployment completion;
- installer exit code `0` or `3010` without required postconditions and restart;
- rerunning the five Cybernet core applications when accepted evidence already says they are installed;
- forcing runtime proof before deployment can be considered complete;
- sending the operator back into hours of live searching when the repository already has the canonical next state transition.

## Expected outputs

- resolved desired state;
- ordered command IDs actually executed;
- preserved clinical-core state decision;
- restart-complete deployment artifact and exact classification when deployment was requested;
- optional runtime artifact and exact proof level only when runtime proof was explicitly requested;
- smallest actionable blocker only when a real authority, runtime, or product gate prevents the next state.

## Proof ceiling

This skill can enforce that AutoLogon/Cybernet field work advances through real target mutation and the required restart instead of stopping at tests. It does not grant mutation authority, manufacture automatic-sign-in observations, or change vendor package behavior. Runtime proof remains separate and optional after deployment completion.
