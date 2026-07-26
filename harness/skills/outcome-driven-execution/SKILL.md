# Outcome-Driven Execution

## Trigger

Use this harness-scoped skill when the requested result is an artifact, build, runtime, repair, deployment, live certification, or runtime proof and the work contains validators, dry runs, plans, preflights, fixture proof, transport certification, or other intermediate gates that could otherwise become artificial stopping points.

Do not route this skill through the root `.claude/skills` governance router. It is a harness execution procedure used after the normal repository route is already selected.

## Required inputs

- repository root and current branch/worktree;
- requested goal in plain language;
- owned and forbidden scope;
- explicit target and target profile when the selected workflow needs them;
- target-mutation or network authorization when required;
- existing-state evidence when already-installed software should be preserved;
- proof ceiling and any genuine external blocker already known.

## Procedure

1. Read `harness/api/harness-outcome-registry.json` and the command, validator, and artifact registries.
2. For AutoLogon, Cybernet, live-cert, deployment, or runtime-proof requests, also read `harness/api/deployment-state-registry.json` and `harness/skills/cybernet-autologon-deployment-state/SKILL.md`.
3. Resolve the requested goal and desired product/runtime state before executing an intermediate validator.
4. Select the smallest command chain that can prove that state.
5. Treat validators, dry runs, plans, preflights, fixture proof, and harmless transport live certs as admission gates.
6. Require every successful admission gate to emit or resolve a registered artifact. A green console message by itself is insufficient.
7. If the requested goal remains unproven and the registry names a same-turn continuation, execute it immediately when it is safe, authorized, dependency-satisfied, and available to the agent.
8. Do not hand a safe executable continuation back to the operator merely because a test passed.
9. For `test AutoLogon`, `deploy AutoLogon`, or AutoLogon/Cybernet `live cert` with one authorized Cybernet target and mutation authority, the requested state is real AutoLogon apply through `autologon-remote`; do not stop at fixture, WhatIf, preflight, or transport `LIVE CERT PASS`.
10. When the five Cybernet clinical-core applications are already proven installed/accepted, preserve them instead of reinstalling them merely to reach AutoLogon.
11. When deployment and runtime proof are requested together, require the real S4U deployment artifact first, then stop only at the genuine attended reboot/direct sign-in observation gate before actual-session runtime proof. Do not reset to more admission testing.
12. Preserve explicit confirmation, credentials, physical access, protected runtime, attended reboot, and target-mutation gates. Those are real blockers, not excuses to bypass.
13. On failure, produce or preserve the owning artifact/evidence, classify the smallest failed boundary, repair inside owned scope when possible, and rerun that boundary.
14. Stop only with one of the terminal outcomes allowed by the outcome registry: artifact created, build artifact created, runtime started, product deployed, runtime proven, or blocked with an exact actionable external gate.

## Forbidden stopping patterns

- `tests passed` with the requested deployment/build/artifact/runtime state still unproven;
- `here is the next command` when the agent can safely run that command itself;
- `send me the logs` when the repo already produced a canonical artifact the agent can resolve;
- `wait for CI` as the final action when another safe local/remote proof step is available;
- asking the operator to repeat inspection, path resolution, branch selection, or log collection the harness can perform;
- treating a dry run, plan, fixture, transport live cert, launcher start, process presence, installer exit code, or command acknowledgment as the requested product outcome;
- treating `LIVE CERT PASS` as AutoLogon deployment when the requested state requires `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING`;
- blindly reinstalling a proven Cybernet clinical core to get to AutoLogon;
- claiming runtime proof without the actual-session runtime artifact and `TECHNICIAN_OBSERVED_LIVE_RUNTIME`.

## Expected outputs

- requested goal and desired state;
- ordered command IDs executed;
- admission artifacts produced;
- terminal outcome and highest proven state;
- canonical final artifact or deployment/runtime evidence path;
- exact blocker owner/action/artifact only when a real external gate remains;
- proof ceiling actually reached.

## Proof ceiling

This procedure enforces progress through repository-owned executable gates and binds AutoLogon/Cybernet field intent to real deployment/runtime artifacts. It does not manufacture authorization, perform an unauthorized reboot, manufacture technician observation, or elevate static/dry-run evidence into runtime or deployment proof.
