# AutoLogon Runtime Proof Capability

## Contract

Route optional higher-ceiling AutoLogon session and application proof only to repository-owned entrypoints running in the actual signed-in AutoLogon session after restart-complete field deployment.

## Inputs and preconditions

- Require a correlated restart-complete deployment artifact for the same target: `autologon_s4u_deployment_result.json` with `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` or the full `cybernet_software_deployment_result.json` with `CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED`.
- Require direct observation that automatic sign-in occurred before using the signed-in session as runtime proof; remote SMB offline/online restart observation is not a substitute for that visual/session fact.
- Require a non-secret runtime configuration, the expected-account rule, explicit bounded access paths, and technician observation inputs.
- Require current-session identity match before access or application behavior can pass.
- This capability never delays or completes product deployment; deployment is already complete at the registered restart-complete state.

## Outputs and ceiling

- Consume `autologon.session_access_proof` from `Invoke-SasAutoLogonSessionAccessProof.ps1` and `autologon.technician_runtime_proof` from `Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`.
- Require `TECHNICIAN_OBSERVED_LIVE_RUNTIME`, `runtime_proof=true`, and `overall_success=true` for the current higher-ceiling runtime state.
- Preserve deployment history, restart observation, automatic sign-in, current-token access, application readiness, observed behavior, and operator confirmation as distinct evidence flags and classifications.
- Repository routing alone proves none of those runtime observations.

## Guardrails

- Never route a runtime-proof request to field deployment, canonical SYSTEM qualification, remote PowerShell, a service, a scheduled task, or the disposable package-VM lane.
- Default to no network and no mutation. Any bounded share access or disposable write probe requires the entrypoint's explicit inputs and authority, with immediate marker cleanup.
- Never accept credentials, impersonate an account, infer human attribution, or expose paths, directory entries, account identifiers, or raw operator-local evidence.
- Fixture results remain contract-only and cannot be promoted to live runtime proof.
- Process launch or command ACK is not observed application behavior.

## Authority

- `harness/api/deployment-state-registry.json`
- `harness/api/harness-artifact-registry.json`
- `scripts/Invoke-SasAutoLogonSessionAccessProof.ps1`
- `scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`
- `docs/AUTOLOGON_SESSION_ACCESS_PROOF.md`
- `docs/AUTOLOGON_TECHNICIAN_RUNTIME_PROOF.md`
- `harness/workflows/cybernet-autologon-deployment-state.yaml`
- `harness/workflows/autologon-proof-contract-floor.yaml`

## Used by

- `.claude/skills/autologon-deployment/SKILL.md`
