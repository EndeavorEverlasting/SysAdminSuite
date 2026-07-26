# Cybernet AutoLogon Deployment-State Skill

## Trigger

Use this harness-scoped skill after normal repository routing when the task mentions any combination of:

- AutoLogon deployment, application, installation, testing, pilot, or live certification;
- Cybernet profile completion where AutoLogon is expected last;
- AutoLogon runtime proof after deployment;
- a field request that says the other Cybernet clinical applications are already installed and the remaining goal is AutoLogon.

This skill does not replace `.claude/skills/autologon-deployment/SKILL.md`. Normal routing still separates deployment authority from runtime authority. This procedure resolves the ordered desired-state chain after routing so a mixed request can execute the deployment stage first and then stop at the real reboot/runtime authority boundary instead of falling back to tests.

## Required inputs

- requested goal in plain language;
- target profile classification;
- one explicit target when mutation is requested;
- mutation/network authority when the goal includes apply;
- evidence or operator fact for whether the five-package Cybernet clinical core is already installed/accepted;
- runtime-proof configuration and attended reboot authority only when the goal extends beyond pre-reboot configuration.

## Procedure

1. Read `harness/api/deployment-state-registry.json` before choosing commands.
2. Resolve the desired terminal state before running any validator, dry run, preflight, transport live cert, or fixture.
3. For a Cybernet with clinical-core applications already proven installed, preserve that state. Do not reinstall them merely to reach AutoLogon.
4. For `test AutoLogon`, `deploy AutoLogon`, `apply AutoLogon`, or an AutoLogon/Cybernet `live cert` request with one authorized target, the real apply lane is `autologon-remote` (`sas autologon Remote HOST`). A fixture, Plan, transport live cert, process start, ACK, or installer exit code is not the requested result.
5. Require `autologon_kerberos_s4u_pilot_result.json` with classification `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` before saying AutoLogon was applied/configured for reboot proof.
6. The current catalog keeps canonical LocalSystem AutoLogon blocked. Do not substitute the generic six-package LocalSystem Cybernet apply for the S4U AutoLogon lane while that disposition remains true.
7. When the request includes both deployment and runtime proof, deployment comes first in the same work item. After the positive S4U artifact, stop only at the separately authorized attended reboot/automatic-sign-in observation boundary; do not return to fixture or transport testing.
8. After the attended reboot and direct automatic-sign-in observation, run `autologon-runtime-proof` from the actual AutoLogon desktop session.
9. Require `runtime-proof-summary.json` with `proof_level=TECHNICIAN_OBSERVED_LIVE_RUNTIME`, `runtime_proof=true`, and `overall_success=true` before calling runtime proof complete.
10. When the request is runtime proof only, do not infer new deployment authority. Require a correlated positive deployment artifact for the same target or classify the exact missing deployment/reboot gate.
11. On any failure, preserve the owning run artifact, report the smallest failed state transition, and repair or advance that gate. Never reset to a generic live-search loop.

## Critical artifacts

- **Pre-reboot apply:** `survey/output/runs/autologon-kerberos-s4u/<run>/autologon_kerberos_s4u_pilot_result.json`
- **Runtime proof:** `<approved runtime evidence directory>/autologon-runtime-<run>/runtime-proof-summary.json`

The first proves the package actually ran on the authorized target and established the required pre-reboot AutoLogon state. The second proves the actual AutoLogon desktop/session/application runtime behavior. Neither may substitute for the other.

## Forbidden stopping patterns

- `LIVE CERT PASS` from the harmless transport cert as the final AutoLogon result;
- `deployment_planned`, `FIXTURE_PASS`, or `KERBEROS_S4U_FIXTURE_READY` when the requested goal is live apply;
- installer exit code `0` or `3010` without the required postconditions;
- rerunning the five Cybernet core applications when accepted evidence already says they are installed;
- claiming runtime proof before a correlated positive deployment artifact plus attended reboot/sign-in observation;
- sending the operator back into hours of live searching when the repository already has the canonical next state transition.

## Expected outputs

- resolved desired state;
- ordered command IDs actually executed;
- preserved clinical-core state decision;
- S4U deployment artifact and exact classification when apply was requested;
- runtime artifact and exact proof level when runtime proof was requested and authorized;
- smallest actionable blocker only when a real authority, runtime, or product gate prevents the next state.

## Proof ceiling

This skill can enforce that AutoLogon/Cybernet field work advances through real apply and runtime artifacts rather than stopping at tests. It does not grant mutation authority, reboot a target, manufacture technician observations, or change product package behavior.
