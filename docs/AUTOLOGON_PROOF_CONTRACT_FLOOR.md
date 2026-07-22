# AutoLogon Proof Contract Floor

This document freezes the machine-readable boundary for AutoLogon planning, canonical administrator deployment, state proof, current-token session access, post-reboot technician runtime proof, operator-local source evidence, and public-safe receipt ingest.

The floor is a repository contract. Canonical administrator deployment and the dedicated fixture E2E now implement parts of it, but the floor itself grants no network, target, installer, reboot, sign-in, file-access, application, or acceptance authority.

## Frozen operation IDs

| Operation ID | Authority | Canonical output | Implementation state |
|---|---|---|---|
| `autologon.plan` | Local request validation only | `autologon_deployment_result.json` | Routing frozen; current application represents the plan as `deployment_planned` in the admin-deploy result |
| `autologon.admin_deploy` | Explicitly authorized administrator deployment | `autologon_deployment_result.json` | Implemented through the validated Kerberos/SMB scheduled-task front door |
| `autologon.state_proof` | Bounded read-only state collection | `autologon_state_proof_result.json` | Canonical result emitted by administrator deployment |
| `autologon.session_access_proof` | Actual AutoLogon session, explicit paths | `autologon_session_access_proof.json` | v2 emitter alignment pending |
| `autologon.technician_runtime_proof` | Approved post-reboot runtime observation | `autologon_technician_runtime_proof.json` | v2 emitter alignment pending |
| `autologon.proof_receipt_ingest` | Local source hashing and receipt rendering | `autologon_proof_receipt.json` | Sanitized fixture producer implemented; live operator-evidence ingest remains pending |

These IDs are frozen at `v1`. A later application sprint may implement them but must not invent synonyms.

## Existing emission ledger

Repository inspection found the following existing and migrated AutoLogon objects. Legacy runtime objects remain operator-local inputs until an application-owned migration emits their frozen canonical versions.

| Existing object | Existing version | Current emitter | Frozen destination or disposition |
|---|---|---|---|
| Historical deployment summary | `sas-autologon-deployment-summary/v1` | Superseded historical emitter | Retained only as migration-ledger history; canonical runs emit the deployment result below |
| Deployment result | `sas-autologon-deployment-result/v1` | `Invoke-SasAutoLogonDeployment.ps1` | Canonical emission implemented |
| Final-step gate result | No `schema_version`; `gate_version` is `1.0.0` | `Invoke-SasAutoLogonFinalStepGate.ps1` | Migrate to `sas-autologon-final-step-gate-result/v1` |
| State snapshot | `sas-autologon-state-snapshot/v1` | `Invoke-SasAutoLogonStateDelta.ps1` | Retain as an internal source artifact |
| State delta | `sas-autologon-state-delta/v1` | `Invoke-SasAutoLogonStateDelta.ps1` | Normalized by canonical deployment into `sas-autologon-state-proof-result/v1` |
| State run manifest | `sas-autologon-state-delta-run/v1` | `Invoke-SasAutoLogonStateDelta.ps1` | Retain as run context during migration |
| State summary | `sas-autologon-state-delta-summary/v1` | `Invoke-SasAutoLogonStateDelta.ps1` | Normalized by canonical deployment into `sas-autologon-state-proof-result/v1` |
| State launcher operator state | `sas-autologon-state-delta-operator-state/v1` | `Start-SasAutoLogonStateDelta.ps1` | Remains launcher-local; not a proof result |
| File-access snapshot | `sas-autologon-file-access-snapshot/v1` | `Invoke-SasAutoLogonFileAccessPosture.ps1` | Inventoried; not renamed by this sprint |
| File-access delta | `sas-autologon-file-access-delta/v1` | `Invoke-SasAutoLogonFileAccessPosture.ps1` | Inventoried; not renamed by this sprint |
| File-access run manifest | `sas-autologon-file-access-run/v1` | `Invoke-SasAutoLogonFileAccessPosture.ps1` | Inventoried; not renamed by this sprint |
| File-access summary | `sas-autologon-file-access-summary/v1` | `Invoke-SasAutoLogonFileAccessPosture.ps1` | Inventoried; not renamed by this sprint |
| Session-access proof | `sas-autologon-session-access-proof/v1` | `Invoke-SasAutoLogonSessionAccessProof.ps1` | Explicit migration to frozen `v2` |
| Runtime configuration | `sas-autologon-technician-runtime-config/v1` | Operator-local input example | Retained as configuration, not classified as proof |
| Technician runtime proof | `sas-autologon-technician-runtime-proof/v1` | `Invoke-SasAutoLogonTechnicianRuntimeProof.ps1` | Explicit migration to frozen post-reboot `v2` |

No existing public contract is renamed in place. Canonical deployment writes separate normalized results; session-access and technician-runtime v1 outputs remain separate migration inputs because they do not carry every classification, privacy, reboot, sign-in, and proof-ceiling field required by the frozen floor.

## Schema and artifact boundary

The canonical schemas are under `schemas/harness/autologon-*.schema.json`. Artifact roles and filenames are closed by `harness/api/autologon-artifact-types.json`. Every runtime producer must use `scripts/SasRunContext.psm1`, create the canonical run-context files, and register each durable artifact in `artifact_registry.json`.

All deployment, gate, state, session, runtime, and source-evidence artifacts are operator-local. They stay under the ignored runtime root and may contain sensitive operational context. The only public-safe artifact is `autologon_proof_receipt.json`.

The receipt is a closed object. Besides its schema version, it retains only:

- source-evidence SHA-256 digest;
- source-evidence byte length;
- classification;
- proof level;
- reason codes;
- operator confirmation;
- privacy status.

The ingest operation hashes the source evidence in place. It never copies the source object, target identifier, account identifier, package path, machine-local path, or raw observation into the receipt.

## Proof classifications and ceilings

Fixture classifications contain `fixture` or `contract_only` and are limited to `sanitized_fixture_contract`. Fixture flags for network activity, target mutation, scheduled-task execution, installer execution, reboot, automatic sign-in, current-token access, and application behavior remain false.

`deployment_succeeded` can prove only authorized execution through the canonical Kerberos SMB scheduled-task front door plus result retrieval and cleanup. It does not prove reboot, automatic sign-in, file access, or application behavior.

`confirmed_state_transition` proves a before/after state delta only. It does not prove reboot, automatic sign-in, current-token access, human attribution, or application behavior.

`session_access_confirmed` requires the expected account and current-token access in the actual AutoLogon session. It does not by itself prove deployment history, reboot, or application behavior.

`technician_observed_live_runtime` requires separately observed reboot, automatic sign-in, expected-account match, session access, application start/readiness, and technician-confirmed behavior. Only a source-evidence object with every deployment and runtime flag true, plus operator confirmation, may classify as `acceptance_proven`.

The public receipt preserves that classification but is continuity evidence, not the raw proof. Reviewers must verify the receipt digest against the retained operator-local source before relying on it.

## Validation

Run the focused dependency-free contract validator:

```bash
python3 Tests/survey/test_autologon_proof_contract_floor_contracts.py
```

The validator covers JSON parsing, schema structure, fixture validity, operation IDs, artifact registration, privacy rejection, proof ceilings, CI registration, and migration-ledger continuity. Optional `jsonschema` validation runs automatically when that package is available.
