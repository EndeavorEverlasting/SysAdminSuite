# AutoLogon Runtime Proof Capability

## Contract

Route post-reboot AutoLogon session and application proof only to repository-owned entrypoints running in the actual signed-in AutoLogon session.

## Inputs and preconditions

- Require a non-secret runtime configuration, the expected-account rule, explicit bounded access paths, and technician observation inputs.
- Require the reboot and automatic sign-in to have already occurred and be separately observed; this capability does not initiate either action.
- Require current-session identity match before access or application behavior can pass.

## Outputs and ceiling

- Consume `autologon.session_access_proof` from `Invoke-SasAutoLogonSessionAccessProof.ps1` and `autologon.technician_runtime_proof` from `Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`.
- Preserve deployment history, reboot observation, automatic sign-in, current-token access, application readiness, observed behavior, and operator confirmation as distinct evidence flags and classifications.
- Only the frozen source-evidence contract with every required flag and operator confirmation can support `acceptance_proven`; repository routing alone proves none of them.

## Guardrails

- Never route a runtime-proof request to admin deployment, remote PowerShell, a service, a scheduled task, or the disposable package-VM lane.
- Default to no network and no mutation. Any bounded share access or disposable write probe requires the entrypoint's explicit inputs and authority, with immediate marker cleanup.
- Never accept credentials, impersonate an account, infer human attribution, or expose paths, directory entries, account identifiers, or raw operator-local evidence.
- Fixture results remain contract-only and cannot be promoted to live runtime proof.

## Authority

- `scripts/Invoke-SasAutoLogonSessionAccessProof.ps1`
- `scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`
- `docs/AUTOLOGON_SESSION_ACCESS_PROOF.md`
- `docs/AUTOLOGON_TECHNICIAN_RUNTIME_PROOF.md`
- `harness/workflows/autologon-proof-contract-floor.yaml`

## Used by

- `.claude/skills/autologon-deployment/SKILL.md`
