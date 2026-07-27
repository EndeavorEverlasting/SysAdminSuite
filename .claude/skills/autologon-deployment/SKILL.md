# AutoLogon Deployment Skill

Use this skill for AutoLogon planning, authorized field deployment, canonical SYSTEM qualification separation, and optional post-deployment runtime proof. Routing selects a lane; it never grants target, change, network, reboot, write-probe, or credential authority.

## Capability dependencies

- [AutoLogon Deployment Orchestration](../../capabilities/autologon-deployment-orchestration.md)
- [AutoLogon Runtime Proof](../../capabilities/autologon-runtime-proof.md)
- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [End-to-End Testing](../../capabilities/end-to-end-testing.md)
- [Field Command Design](../../capabilities/field-command-design.md)

## Canonical references

- Current field desired-state authority: [`harness/api/deployment-state-registry.json`](../../../harness/api/deployment-state-registry.json)
- Current command authority: [`harness/api/harness-command-registry.json`](../../../harness/api/harness-command-registry.json)
- Current artifact authority: [`harness/api/harness-artifact-registry.json`](../../../harness/api/harness-artifact-registry.json)
- Current field deployment workflow: [`harness/workflows/cybernet-autologon-deployment-state.yaml`](../../../harness/workflows/cybernet-autologon-deployment-state.yaml)
- Frozen historical proof classifications: [`harness/workflows/autologon-proof-contract-floor.yaml`](../../../harness/workflows/autologon-proof-contract-floor.yaml)
- Full field deployment entrypoint: [`Deploy-CybernetSoftware.cmd`](../../../Deploy-CybernetSoftware.cmd)
- AutoLogon-only field entrypoint: [`scripts/Invoke-SasAutoLogonS4URestartDeployment.ps1`](../../../scripts/Invoke-SasAutoLogonS4URestartDeployment.ps1)
- Canonical SYSTEM qualification entrypoint: [`Qualify-AutoLogonSystemPackage.cmd`](../../../Qualify-AutoLogonSystemPackage.cmd)
- Signed-in runtime entrypoint: [`scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`](../../../scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1)
- Current-token access entrypoint: [`scripts/Invoke-SasAutoLogonSessionAccessProof.ps1`](../../../scripts/Invoke-SasAutoLogonSessionAccessProof.ps1)

## Workflow

1. Read `harness/api/deployment-state-registry.json` before selecting any AutoLogon command. Resolve the requested terminal state before running diagnostics or tests.
2. Classify the request as `autologon.plan`, current field deployment, explicit canonical SYSTEM qualification, or post-deployment `autologon.session_access_proof` / `autologon.technician_runtime_proof`.
3. For planning, remain offline and non-mutating. Identify the registered command, required authority, critical artifact, and highest reachable proof classification.
4. For current field deployment, load the deployment-orchestration capability. If the five clinical-core applications are already proven installed/accepted, preserve them and use `sas autologon Remote HOST`. Otherwise use `sas cybernet Deploy HOST` for the five clinical applications followed by AutoLogon last.
5. Treat `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` only as an internal pre-reboot gate. Current field deployment is not complete until the required restart cycle is observed and the registered restart-complete artifact is positive.
6. Canonical LocalSystem AutoLogon remains a distinct qualification lane while `canonical_system_install_enabled=false`. An explicit SYSTEM-qualification request may use `Qualify-AutoLogonSystemPackage.cmd`; never substitute that blocked LocalSystem lane for current S4U field deployment and never auto-promote a candidate.
7. For runtime proof, load the runtime-proof capability only after a correlated restart-complete deployment artifact for the same target exists. Never route runtime proof through field deployment or make runtime proof a prerequisite that delays product deployment.
8. Keep package execution, restart-cycle observation, automatic sign-in, current-token access, application readiness, observed behavior, and operator acceptance as separate claims.
9. Store operator-local evidence under ignored run roots. Never request, store, render, or commit password data, `DefaultPassword`, live hostnames, account identifiers, private package paths, or raw corporate evidence.
10. Use the generic field-workflow and end-to-end-validation skills for launcher design and composed validation; do not copy their procedures or product implementation into this skill.

## Inputs and outputs

- Planning input: intended operation and proof target. Output: lane, registered command, required gates, critical artifact, and proof ceiling.
- Field deployment input: one explicit authorized Cybernet target, target/change authority, current network/preflight state, and evidence of whether the clinical core is already installed/accepted. Output: `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` or `CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED` through the registered deployment artifact.
- SYSTEM qualification input: a closed approved candidate request and qualification authority. Output: qualification-only evidence; never production enablement by itself.
- Runtime input: correlated restart-complete deployment evidence, non-secret runtime configuration, actual signed-in session, expected-account rule, explicit paths, and technician observations. Output: session-access and technician-runtime results under their frozen classifications.

## Forbidden conditions

- No package disposable-VM routing, prompt-owned installer logic, direct legacy WinRM delegation, gate bypass, automatic lane escalation, credential collection, or tracked live evidence.
- Do not route ordinary field deployment through `scripts/Invoke-SasAutoLogonDeployment.ps1` while canonical SYSTEM installation remains blocked.
- Do not reinstall a proven/accepted clinical core merely to reach AutoLogon.
- A pre-reboot S4U result, installer exit code, process start, command ACK, fixture, Plan, or transport live cert is never restart-complete deployment proof.
- A restart-complete deployment result is not direct automatic-sign-in or application-behavior proof. Runtime proof remains separate and optional unless explicitly requested.

## Validation and proof ceiling

Run `python3 Tests/survey/test_autologon_agent_harness_contracts.py`, `python harness/validators/validate-deployment-state-contracts.py`, and the shared agent manifest, routing, factoring, and AI-layer validators. These checks prove deterministic repository routing and instruction boundaries only; they do not prove target contact, installation, restart, automatic sign-in, current-token access, application behavior, or operator acceptance.
