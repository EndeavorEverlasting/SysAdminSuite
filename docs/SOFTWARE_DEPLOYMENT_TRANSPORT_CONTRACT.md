# Software deployment transport contract floor

This document is the authority boundary for selecting, certifying, and reporting a SysAdminSuite software-deployment transport. The frozen v1 schemas remain unchanged. The read-only preflight implementation is now present; live certification, software execution, and public proof ingestion remain separately gated.

Low-noise execution and target-user visibility are defined in [`SOFTWARE_DEPLOYMENT_LOW_NOISE.md`](SOFTWARE_DEPLOYMENT_LOW_NOISE.md).

## Frozen-floor history and current status

P01 was deliberately a contract-only floor: it **does not implement a transport**, and its evidence **does not prove transport implementation**. P02 now implements only the bounded read-only preflight behind those unchanged interfaces. It does not implement live certification or software execution.

Application behavior remains authoritative in repository scripts and modules until a later bounded controller-integration sprint explicitly consumes the frozen transport result.

## Frozen v1 interfaces

| Interface | Frozen identifier |
|---|---|
| Preflight result schema | `sas-software-deployment-transport-result/v1` |
| Public proof receipt schema | `sas-software-deployment-transport-receipt/v1` |
| Read-only preflight operation | `software_install.transport_preflight` |
| Harmless live-cert operation | `software_install.transport_live_cert` |
| Local proof-ingest operation | `software_install.transport_proof_ingest` |

The schemas live under `schemas/harness/`; operation registration lives in `harness/api/sas-harness-api.json`; orchestration mapping lives in `harness/workflows/software-deployment-transport.yaml`.

The implementation front door is `scripts/Test-SasSoftwareDeploymentTransport.ps1`. It composes:

- `scripts/SasSoftwareDeploymentTransport.psm1` for the frozen classifier and explicit broad discovery;
- `scripts/SasSoftwareDeploymentLowNoise.psm1` for intent-scoped collection;
- `scripts/SasLowNoisePolicy.psm1` for canonical low-noise context;
- `scripts/SasRunContext.psm1` for ignored artifacts and registry output.

## Closed preflight classifications

- `winrm_ready`: a WinRM endpoint is reachable and a session is authorized.
- `kerberos_smb_task_ready`: every declared Kerberos, SMB, RPC, administrative-share, Schedule-service, and scheduled-task read prerequisite is satisfied.
- `transport_reachable_authorization_denied`: a declared transport boundary is reachable but the current runtime identity is not authorized.
- `no_supported_transport`: the bounded observations completed and neither supported transport is reachable and authorized.
- `inconclusive`: required observations are missing, timed out, malformed, or contradictory.

Reachability and authorization are separate observations. A reachable port is never sufficient authorization proof.

## Intent-scoped low-noise selection

The default `TransportIntent` is `kerberos_smb_task`, matching the proven Windows-native Cybernet deployment path. It requests only the CIFS ticket and stages observations in this order:

1. local domain/TGT and one-FQDN DNS state;
2. TCP 445;
3. `ADMIN$` read authorization;
4. TCP 135 only after `ADMIN$` authorization;
5. Schedule service query;
6. one reserved nonexistent task-name query without enumerating the task library.

An explicit `winrm` intent requests only the HTTP ticket, tests 5985, tests 5986 only when needed, and opens one bounded read-only PSSession.

`auto` retains broad discovery across both supported transports. It is explicit and is never substituted after a narrow failure without a recorded reason.

## Fail-closed selection

WinRM unavailability does not block evaluation or selection of Kerberos-authenticated SMB plus Remote Task Scheduler. Kerberos/SMB/Task Scheduler readiness requires all of these observations:

1. DNS resolution succeeded.
2. The source posture is domain joined and reports a TGT Boolean without ticket bytes.
3. A CIFS service ticket was issued without persisting ticket material.
4. TCP 445 is reachable.
5. `ADMIN$` read access is authorized.
6. TCP 135 is reachable.
7. The remote Schedule service query succeeds and reports running.
8. The named scheduled-task read query proves authorization.

No operation may guess a transport, silently fall back, switch transports after mutation begins, broaden ports after a narrow failure, or treat task enumeration as a harmless default.

## Observation and decision boundary

The result schema retains DNS, identity/TGT summary, HTTP/HOST/CIFS ticket outcomes, four TCP observations, WinRM session authorization, administrative-share authorization, Schedule-service status, and scheduled-task query status under `observations`. An intent-scoped run leaves irrelevant observations explicitly unrequested or untested rather than omitting schema fields.

Selection, reason codes, and fallback prohibitions live separately under `decision`.

Preflight results always set `target_mutation_performed` to false. They cannot claim task creation, SYSTEM execution, result retrieval, cleanup, software installation, or operator acceptance. Sanitized fixtures additionally set `network_activity_performed` and `live_runtime` to false.

Every run also emits `low_noise_context.json`, which records the canonical policy identity and exact effective port subset.
## Public receipt boundary

The receipt binds a future operator-local live-cert result by lowercase SHA-256 and byte length. The source evidence remains operator-local and is not copied into public output. The closed receipt rejects hostname, username, Kerberos ticket bytes, credentials, package paths, machine-local paths, and raw evidence.

A `live_cert_pass` receipt requires operator confirmation and affirmative proof that the harmless task was created, ran as SYSTEM, returned a result, was deleted, had its staging removed, and left zero run-scoped remnants. It also requires `software_installation_performed` to remain false.

Sanitized fixtures can prove only the contract. They can never become live certification proof.

## Operation authority

- `software_install.transport_preflight` is read-only toward targets and requires explicit network acknowledgement for live mode.
- `software_install.transport_live_cert` is separately mutation-gated, limited to one authorized target and a harmless run-scoped task, and cannot install software.
- `software_install.transport_proof_ingest` is local-only and hashes source evidence in place.
- `software_install.operator_execute` declares a schema-valid transport result as an input. Canonical-controller integration remains a later bounded sprint.

These registrations define interfaces, not permission.

## Evidence and proof ceiling

Tracked fixtures use synthetic, identifier-free observations. Raw corporate evidence, target names, usernames, ticket caches, package paths, and local run artifacts must remain in ignored operator-local evidence roots.

The current implementation reaches parser, unit/contract, sanitized fixture, schema, run-context, artifact-registry, low-noise-context, and CI proof. It does not prove live corporate-network traffic, scheduled-task creation, SYSTEM execution, result retrieval, teardown, software installation, absence of vendor UI, or application acceptance.
