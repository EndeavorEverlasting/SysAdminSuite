# AutoLogon Deployment Skill

Use this skill for AutoLogon planning, authorized canonical deployment orchestration, and post-reboot proof planning. Routing selects a lane; it never grants target, change, network, reboot, write-probe, or credential authority.

## Capability dependencies

- [AutoLogon Deployment Orchestration](../../capabilities/autologon-deployment-orchestration.md)
- [AutoLogon Runtime Proof](../../capabilities/autologon-runtime-proof.md)
- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [End-to-End Testing](../../capabilities/end-to-end-testing.md)
- [Field Command Design](../../capabilities/field-command-design.md)

## Canonical references

- Frozen operations and proof classifications: [`harness/workflows/autologon-proof-contract-floor.yaml`](../../../harness/workflows/autologon-proof-contract-floor.yaml)
- Deployment and pilot sequence: [`docs/AUTOLOGON_DEPLOYMENT_WORKFLOW.md`](../../../docs/AUTOLOGON_DEPLOYMENT_WORKFLOW.md)
- Admin deployment entrypoint: [`scripts/Invoke-SasAutoLogonDeployment.ps1`](../../../scripts/Invoke-SasAutoLogonDeployment.ps1)
- Signed-in runtime entrypoint: [`scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`](../../../scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1)
- Current-token access entrypoint: [`scripts/Invoke-SasAutoLogonSessionAccessProof.ps1`](../../../scripts/Invoke-SasAutoLogonSessionAccessProof.ps1)

## Workflow

1. Classify the request as `autologon.plan`, `autologon.admin_deploy`, or post-reboot `autologon.session_access_proof` / `autologon.technician_runtime_proof`.
2. Fail closed to repository-sprint intake when deployment and runtime-proof signals are mixed or the requested identity, authority, or proof target is ambiguous.
3. For planning, remain offline and non-mutating. Identify required inputs, entrypoints, gates, artifacts, teardown, and the highest reachable proof classification.
4. For admin deployment, load the deployment-orchestration capability and route only to `Invoke-SasAutoLogonDeployment.ps1`. Require explicit target and change authority before allowing its mutation gate.
5. For runtime proof, load the runtime-proof capability and route only to the actual signed-in-session entrypoints. Never route runtime proof through admin deployment.
6. Keep state transition, deployment execution, reboot observation, automatic sign-in, current-token access, application readiness, observed behavior, and operator acceptance as separate claims.
7. Store all operator-local evidence under the ignored run root. Never request, store, render, or commit password data, `DefaultPassword`, live hostnames, account identifiers, private package paths, or raw corporate evidence.
8. Use the generic field-workflow and end-to-end-validation skills for launcher design and composed validation; do not copy their procedures here.

## Inputs and outputs

- Planning input: intended operation and proof target. Output: lane, required gates, canonical entrypoints, expected artifacts, and proof ceiling.
- Admin input: explicit approved targets plus non-secret package, authorization, change, preflight, and policy references. Output: canonical deployment result and operator-local handoff.
- Runtime input: non-secret runtime configuration, actual signed-in session, expected-account rule, explicit paths, and technician observations. Output: session-access and technician-runtime results under their frozen classifications.

## Forbidden conditions

- No package disposable-VM routing, prompt-owned installer logic, direct legacy WinRM delegation, gate bypass, implicit reboot, automatic lane escalation, credential collection, or tracked live evidence.
- An admin deployment result is never post-reboot runtime proof. A runtime-proof request never authorizes deployment.

## Validation and proof ceiling

Run `python3 Tests/survey/test_autologon_agent_harness_contracts.py` and the shared agent manifest, routing, factoring, and AI-layer validators. These checks prove deterministic repository routing and instruction boundaries only; they do not prove target contact, installation, reboot, automatic sign-in, current-token access, application behavior, or operator acceptance.
