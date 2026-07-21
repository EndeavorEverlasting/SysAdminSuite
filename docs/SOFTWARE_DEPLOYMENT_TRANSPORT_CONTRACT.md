# Software deployment transport contract floor

This document is the authority boundary for selecting, certifying, and reporting a SysAdminSuite software-deployment transport. It freezes interfaces for later implementation work; it does not implement a transport, contact a target, create a task, install software, or grant mutation authority.

## Frozen v1 interfaces

| Interface | Frozen identifier |
|---|---|
| Preflight result schema | `sas-software-deployment-transport-result/v1` |
| Public proof receipt schema | `sas-software-deployment-transport-receipt/v1` |
| Read-only preflight operation | `software_install.transport_preflight` |
| Harmless live-cert operation | `software_install.transport_live_cert` |
| Local proof-ingest operation | `software_install.transport_proof_ingest` |

The schemas live under `schemas/harness/`; operation registration lives in `harness/api/sas-harness-api.json`; orchestration mapping lives in `harness/workflows/software-deployment-transport.yaml`.

## Closed preflight classifications

- `winrm_ready`: a WinRM endpoint is reachable and a session is authorized.
- `kerberos_smb_task_ready`: every declared Kerberos, SMB, RPC, administrative-share, Schedule-service, and scheduled-task read prerequisite is satisfied.
- `transport_reachable_authorization_denied`: a declared transport boundary is reachable but the current runtime identity is not authorized.
- `no_supported_transport`: the bounded observations completed and neither supported transport is reachable and authorized.
- `inconclusive`: required observations are missing, timed out, malformed, or contradictory.

Reachability and authorization are separate observations. A reachable port is never sufficient authorization proof.

## Fail-closed selection

WinRM unavailability does not block evaluation or selection of Kerberos-authenticated SMB plus Remote Task Scheduler. Kerberos/SMB/Task Scheduler readiness requires all of these observations:

1. DNS resolution succeeded.
2. The source posture is domain joined and reports a TGT Boolean without ticket bytes.
3. A CIFS service ticket was issued without persisting ticket material.
4. TCP 445 and TCP 135 are reachable.
5. `ADMIN$` read access is authorized.
6. The remote Schedule service query succeeds and reports running.
7. The scheduled-task read query succeeds.

HTTP and HOST service-ticket outcomes and TCP 5985/5986 remain independent observations. No operation may guess a transport, silently fall back, or switch transports after mutation begins.

## Observation and decision boundary

The result schema keeps DNS, identity/TGT summary, HTTP/HOST/CIFS ticket outcomes, four TCP observations, WinRM session authorization, administrative-share authorization, Schedule-service status, and scheduled-task query status under `observations`. Selection, reason codes, and fallback prohibitions live separately under `decision`.

Preflight results always set `target_mutation_performed` to false. They cannot claim task creation, SYSTEM execution, result retrieval, cleanup, software installation, or operator acceptance. Sanitized fixtures additionally set `network_activity_performed` and `live_runtime` to false.

## Public receipt boundary

The receipt binds a future operator-local live-cert result by lowercase SHA-256 and byte length. The source evidence remains operator-local and is not copied into public output. The closed receipt rejects hostname, username, Kerberos ticket bytes, credentials, package paths, machine-local paths, and raw evidence.

A `live_cert_pass` receipt requires operator confirmation and affirmative proof that the harmless task was created, ran as SYSTEM, returned a result, was deleted, had its staging removed, and left zero run-scoped remnants. It also requires `software_installation_performed` to remain false.

Sanitized fixtures can prove only the contract. They can never become live certification proof.

## Operation authority

- `software_install.transport_preflight` is read-only toward targets. Its future implementation may perform bounded network reads only after explicit operator authorization.
- `software_install.transport_live_cert` is separately mutation-gated, limited to one authorized target and a harmless run-scoped task, and cannot install software.
- `software_install.transport_proof_ingest` is local-only and hashes source evidence in place.
- `software_install.operator_execute` declares a schema-valid transport result as an input. The validated PowerShell front door does not consume this contract yet, so it remains WinRM-specific and cannot claim cross-transport selection. The SMB/Task Scheduler Bash controller is intentionally supported as a compatibility adapter behind its existing gate; it must not guess or switch transport after mutation begins.

These registrations define interfaces, not permission. Application behavior remains authoritative in repository scripts and modules until a later bounded implementation sprint makes the validated front door consume the frozen decision.

## Application and staging compatibility boundary

| Surface | Current authority | Target staging boundary |
|---|---|---|
| Validated PowerShell front door | `scripts/Invoke-SasValidatedSoftwareDeployment.ps1` delegates to `scripts/Invoke-SasSoftwareInstall.ps1` | `C:\ProgramData\SysAdminSuite\SoftwareInstall\<run_id>` only when `CopyThenInstall` is requested |
| SMB/Task Scheduler compatibility controller | `bash/apps/sas-install-apps.sh` | `C:\ProgramData\SysAdminSuite\AppInstall\<run_id>` for its worker, package payload, result, and task lifecycle |

The roots are intentionally distinct compatibility boundaries. Cleanup must validate and remove only the selected transport's run-scoped root. Neither adapter may inspect, reuse, or delete the other adapter's staging root.

## Evidence and proof ceiling

Tracked fixtures use synthetic, identifier-free observations and documentation-only values. Raw corporate evidence, target names, usernames, ticket caches, package paths, and local run artifacts must remain in ignored operator-local evidence roots.

P01 reaches schema, sanitized fixture, harness registration, validator, and CI proof. It does not prove transport implementation, live network behavior, scheduled-task creation, SYSTEM execution, result retrieval, teardown, software installation, or application acceptance.
