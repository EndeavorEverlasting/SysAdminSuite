# Deployment transport convergence ledger

```text
[SAS | P08 convergence | scope: repository/PR floor | proof: fixture, CI, and public-safe one-target receipt continuity]
```

## Purpose

This handoff records the preserved deployment-transport contributions, canonical authorities, compatibility boundaries, and unresolved proof gates. It is public-safe: it contains no live hostname, username, package path, credential, ticket material, or raw evidence.

## P01-P07 preservation ledger

| Sprint contribution | Repository evidence | Disposition |
|---|---|---|
| P01 contract floor | PR #242, frozen result and receipt schemas, sanitized fixtures, API operations, workflow, contracts, and CI | Landed on `main`; the frozen contract remains the authority for later producers and ingest. |
| P02 preflight | PR #244 added the runnable `software_install.transport_preflight` producer for `sas-software-deployment-transport-result/v1`. | Implemented on `main` as a read-only, intent-scoped preflight; it does not prove target mutation. |
| P03 application transport | PR #229 is merged, and PR #246 added the first-class PowerShell Kerberos SMB/Task Scheduler adapter behind the validated deployment front door. | Merged on `main`; `Auto` and explicit `SmbScheduledTask` consume fresh P02 results before mutation, while WinRM remains separately selectable. |
| P04 E2E and proof ingestion | PR #177 established default E2E, PR #180 established validated finalization, and PR #232 established production-proof ingestion. | Already on `main`; retained without duplicating their authorities. |
| P05 agent harness | PR #151 established the software-install harness. PR #174 and PR #224 established skill/capability routing. PR #237 factored E2E procedure into the project skill. | Merged harness/routing retained; #237's unique four-file factoring was conflict-repaired and merged through PR #248 before #237 was closed as superseded. |
| P06 operator documentation | PR #233 published the Task Scheduler tutorial and PR #234 published the one-target floor handoff/index. | Already on `main`; terminology and navigation are repaired by P08. |
| P07 terminal receipt | PR #249 implements `software_install.transport_proof_ingest`, the closed live-cert source schema, a sanitized fixture, and the public-safe receipt wrapper. | Merged on `main`. An operator-confirmed receipt now records `live_cert_pass` at proof level `live_transport_execution_and_cleanup`; only its digest, byte length, classification, and privacy status are retained here. Raw evidence was not committed. |
| Harmless live-cert producer | PR #250 added `scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1`, the one-target SMB certification lifecycle, and deterministic failure fixtures. | Merged on `main`. One separately authorized harmless run reached `LIVE CERT PASS`, executed as SYSTEM, retrieved its result before teardown, and verified task/staging deletion and zero remnants. It installed no software. |

No source branch is deleted by P08. A source PR may be closed as superseded only after its unique work is present on `main`.

## Canonical authorities

| Concern | Canonical authority | Current limit |
|---|---|---|
| Transport result | `schemas/harness/software-deployment-transport-result.schema.json` and `scripts/Test-SasSoftwareDeploymentTransport.ps1` | Runnable read-only preflight; no mutation proof. |
| Public receipt | `schemas/harness/software-deployment-transport-receipt.schema.json` and `scripts/Invoke-SasTransportProofIngest.ps1` | Binds a schema-valid operator-local source by SHA-256 without copying it; public-safe `live_cert_pass` continuity is recorded below. |
| Live-cert source | `schemas/harness/software-deployment-transport-live-cert-result.schema.json` and `scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1` | Closed source contract and harmless producer; private lifecycle evidence remains operator-local and absent from tracked files. |
| Selection operations | `harness/api/sas-harness-api.json` and `harness/workflows/software-deployment-transport.yaml` | Registration grants no network or mutation authority. |
| Transport adapter | `scripts/SasSoftwareDeploymentAdapter.psm1` | Owns closed P02 ingestion, pre-mutation selection, the SMB worker/lifecycle, and fixture execution. |
| Validated deployment front door | `scripts/Invoke-SasValidatedSoftwareDeployment.ps1` | Consumes P02 decisions for `Auto` and `SmbScheduledTask`, rejects mixed/fallback execution, and retains explicit WinRM selection. |
| WinRM application adapter | `scripts/Invoke-SasSoftwareInstall.ps1` | Uses `C:\ProgramData\SysAdminSuite\SoftwareInstall\<run_id>` only for explicit staging. |
| Bash compatibility wrapper/controller | `bash/apps/sas-install-apps.sh` | `--request` delegates to the validated PowerShell front door without `--allow-legacy`; the older list/package/package-set controller remains intentionally supported behind its compatibility gate and uses `C:\ProgramData\SysAdminSuite\AppInstall\<run_id>`. |
| Agent routing | `AGENTS.md`, `harness/api/agent-routing-manifest.json`, and `.claude/skills/end-to-end-validation/SKILL.md` | Triggers route only; they grant no target authority. |
| E2E profile | `harness/e2e/e2e-profiles.json` | Registers the synthetic SMB/Task Scheduler lifecycle plus the existing fixture/loopback journeys; no live target proof. |
| Operator documentation | `docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md` and `docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md` | Documents canonical pre-mutation selection, adapter boundaries, and the retained compatibility controller. |

## Compatibility and fail-closed boundary

- WinRM and Kerberos/SMB/Task Scheduler are supported decisions; WinRM is not universally canonical.
- The Bash surface is a compatibility wrapper: `--request` delegates to the canonical PowerShell front door, while the older list/package/package-set controller remains intentionally supported behind a compatibility gate.
- Its historical `--allow-legacy` switch is a compatibility gate, not a transport classification or authorization grant.
- The validated PowerShell front door is the canonical request, transport-selection, hash, application, finalization, and result-presentation surface.
- No adapter may fall back after mutation starts.
- The application, compatibility-controller, and harmless-certification staging boundaries are explicit. Each surface validates and removes only its own run-scoped root.
- Canonical application adapters use `C:\ProgramData\SysAdminSuite\SoftwareInstall\<run_id>`; the compatibility controller uses `C:\ProgramData\SysAdminSuite\AppInstall\<run_id>`; harmless certification uses `C:\ProgramData\SysAdminSuite\TransportLiveCert\<run_id>`.

## PR disposition ledger

| PR | State at P08 intake | P08 disposition |
|---|---|---|
| #151 | merged | Retained as the software-install harness foundation. |
| #177 | merged | Retained as default fixture/loopback E2E authority. |
| #180 | merged | Retained as validated finalization authority. |
| #229 | merged | Retained as the existing SMB/Task Scheduler implementation. |
| #232 | merged | Retained as production-proof ingestion authority. |
| #233 | merged | Retained as operator tutorial authority. |
| #234 | merged | Retained and linked to this convergence handoff. |
| #237 | closed, not merged | Superseded only after its unique four-file E2E factoring was conflict-repaired and merged through #248; source branch retained. |
| #238 | closed, not merged | Superseded only after its package-set catalog, controller, fixtures, documentation, and CI work were reconciled and merged through #243; source branch retained. |
| #242 | merged | Retained as the complete P01 frozen contract floor. |
| #243 | merged | Retained as the initial convergence and package-set preservation merge; this closeout repairs its now-stale receipt and authority statements. |
| #244 | merged | Retained as the runnable P02 preflight implementation. |
| #246 | merged | Retained as the canonical PowerShell SMB/Task Scheduler application transport. |
| #247 | merged | Retained as the intent-scoped low-noise preflight integration. P02 remains read-only and does not claim task creation. |
| #248 | merged | Retained as the governance-safe preservation of #237's E2E skill factoring. |
| #249 | merged | Retained as the P07 public-safe receipt ingest. |
| #250 | merged | Retained as the harmless one-target live-cert producer; its public-safe receipt continuity is recorded below. |

The P08 intake audit found no open PRs. Any later non-transport PR is unrelated to this convergence lane and must not be mutated by P08.

## Public-safe P07 receipt continuity

The operator-confirmed receipt records only these non-identifying facts:

- outcome: `live_cert_pass`;
- proof level: `live_transport_execution_and_cleanup`;
- reason: `execution_and_cleanup_proven`;
- SHA-256 digest: `b84911668ec92d1f1285d2a603aa93fd1a8344e9725e0a1ab643b22a6d841a8b`;
- source size: `1598` bytes;
- operator confirmed: `true`;
- privacy clean: `true`.

The receipt contains no hostname, username, target path, credential, ticket material, or raw lifecycle evidence. It certifies one harmless Kerberos SMB scheduled-task lifecycle only. The P02 named-task read query remains a read-only readiness observation; task creation authority and cleanup are proven only by the separately gated live-cert lifecycle or by an actual deployment result.

## Merge readiness

No repository-convergence or receipt-continuity blocker remains. Final merge still requires the convergence branch's focused validators, fixture E2E, default E2E, documentation and agent-routing contracts, broad Pester, final-head CI, and unresolved-review audit to be green. The one-target receipt is not fleet authorization and does not replace package-specific installation or acceptance proof.

## Proof ceiling

The convergence floor can prove repository preservation, one canonical authority chain, parser/contracts, schema-valid sanitized producer and ingest behavior, the bounded failure matrix, synthetic SMB fixture E2E, default fixture/loopback E2E, agent-routing validation, documentation contracts, CI, and continuity to one operator-confirmed harmless live-cert receipt. The receipt proves one run-scoped Kerberos SMB scheduled-task execution and cleanup; it does not prove a new P08 live run, WinRM certification, fleet readiness, package installation, package-specific validation, application acceptance, or business acceptance.
