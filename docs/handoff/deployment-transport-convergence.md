# Deployment transport convergence ledger

```text
[SAS | P08 convergence | scope: repository/PR floor | proof: fixture and CI only]
```

## Purpose

This handoff records the preserved deployment-transport contributions, canonical authorities, compatibility boundaries, and unresolved proof gates. It is public-safe: it contains no live hostname, username, package path, credential, ticket material, or raw evidence.

## P01-P07 preservation ledger

| Sprint contribution | Repository evidence | Disposition |
|---|---|---|
| P01 contract floor | PR #242, frozen result and receipt schemas, sanitized fixtures, API operations, workflow, contracts, and CI | Landed on `main`; the frozen contract remains the authority for later producers and ingest. |
| P02 preflight | PR #244 added the runnable `software_install.transport_preflight` producer for `sas-software-deployment-transport-result/v1`. | Implemented on `main` as a read-only, intent-scoped preflight; it does not prove target mutation. |
| P03 application transport | PR #229 is merged, and PR #246 promoted the existing Kerberos SMB/Task Scheduler controller. | Application transport is present, but it is not a substitute for the harmless live-cert producer. |
| P04 E2E and proof ingestion | PR #177 established default E2E, PR #180 established validated finalization, and PR #232 established production-proof ingestion. | Already on `main`; retained without duplicating their authorities. |
| P05 agent harness | PR #151 established the software-install harness. PR #174 and PR #224 established skill/capability routing. PR #237 factors E2E procedure into the project skill. | Merged harness/routing retained; unique #237 factoring reconciled with current governance and preserved on the convergence branch. |
| P06 operator documentation | PR #233 published the Task Scheduler tutorial and PR #234 published the one-target floor handoff/index. | Already on `main`; terminology and navigation are repaired by P08. |
| P07 terminal receipt | PR #249 implements `software_install.transport_proof_ingest`, the closed live-cert source schema, a sanitized fixture, and the public-safe receipt wrapper. | Merged on `main`. No public live receipt exists until the harmless producer runs successfully on a separately authorized target and its operator-local result is reviewed and ingested. Raw evidence was not accessed. |
| Harmless live-cert producer | `scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1` implements the one-target SMB certification lifecycle and deterministic failure fixtures. | Repository implementation complete; no live target was contacted and no live certification is claimed. |

No source branch is deleted by P08. A source PR may be closed as superseded only after its unique work is present on `main`.

## Canonical authorities

| Concern | Canonical authority | Current limit |
|---|---|---|
| Transport result | `schemas/harness/software-deployment-transport-result.schema.json` and `scripts/Test-SasSoftwareDeploymentTransport.ps1` | Runnable read-only preflight; no mutation proof. |
| Public receipt | `schemas/harness/software-deployment-transport-receipt.schema.json` and `scripts/Invoke-SasTransportProofIngest.ps1` | Binds a schema-valid operator-local source by SHA-256 without copying it; no public live receipt exists yet. |
| Live-cert source | `schemas/harness/software-deployment-transport-live-cert-result.schema.json` and `scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1` | Closed source contract and harmless producer implemented; live evidence remains operator-gated and absent from tracked files. |
| Selection operations | `harness/api/sas-harness-api.json` and `harness/workflows/software-deployment-transport.yaml` | Registration grants no network or mutation authority. |
| Validated deployment front door | `scripts/Invoke-SasValidatedSoftwareDeployment.ps1` | Currently delegates to the WinRM implementation and does not consume the transport decision. |
| WinRM application adapter | `scripts/Invoke-SasSoftwareInstall.ps1` | Uses `C:\ProgramData\SysAdminSuite\SoftwareInstall\<run_id>` only for explicit staging. |
| SMB/Task Scheduler compatibility adapter | `bash/apps/sas-install-apps.sh` | Intentionally supported behind its retained compatibility gate; uses `C:\ProgramData\SysAdminSuite\AppInstall\<run_id>`. |
| Agent routing | `AGENTS.md`, `harness/api/agent-routing-manifest.json`, and `.claude/skills/end-to-end-validation/SKILL.md` | Triggers route only; they grant no target authority. |
| E2E profile | `harness/e2e/e2e-profiles.json` | Registers the synthetic SMB/Task Scheduler lifecycle plus the existing fixture/loopback journeys; no live target proof. |
| Operator documentation | `docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md` and `docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md` | Documents current split without claiming cross-transport execution. |

## Compatibility and fail-closed boundary

- WinRM and Kerberos/SMB/Task Scheduler are supported decisions; WinRM is not universally canonical.
- The Bash controller is an intentionally supported transport-specific compatibility adapter, not the cross-transport selector or validated front door.
- Its historical `--allow-legacy` switch is a compatibility gate, not a transport classification or authorization grant.
- The validated PowerShell front door remains the canonical request, hash, finalization, and result-presentation surface, but it is WinRM-specific until it consumes the v1 transport decision.
- No adapter may fall back after mutation starts.
- The two target staging roots are deliberately separate. Each adapter validates and removes only its own run-scoped root.

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
| #237 | open, conflicting with current governance | Unique E2E skill factoring preserved and conflict-repaired on P08; do not close until P08 lands. |
| #238 | open draft, mergeable | Unique package-set work preserved on P08; do not close until P08 lands. |
| #242 | open draft, mergeable | Complete P01 floor preserved on P08; do not close until P08 lands. |
| #243 | merged | P08 convergence is now on `main`; this ledger is repaired by P07 instead of treating sprint numbers as a linear merge order. |
| #249 | merged | Receipt ingest is retained on `main`; live receipt continuity remains blocked only by the absent separately authorized operator-local run and confirmation. |

PR #241 and all other non-transport PRs are unrelated to this convergence lane and must not be mutated by P08.

## Merge readiness blockers

1. The validated software-install front door does not yet consume and enforce a schema-valid transport decision.
2. No public-safe live receipt is available until the harmless producer runs on one separately authorized target, the operator reviews its local lifecycle evidence, and the closed result is explicitly confirmed and ingested.

These blockers prevent claiming one fully implemented cross-transport controller or live P07 receipt continuity. They do not invalidate the runnable P02 preflight, harmless SMB live-cert producer, P07 receipt ingest, preserved schemas, fixture E2E, existing transport-specific implementations, or CI proof.

## Proof ceiling

The convergence, harmless live-cert, and P07 fixture gates can prove repository preservation, authority consistency, parser/contracts, schema-valid sanitized producer and ingest behavior, the bounded failure matrix, synthetic SMB fixture E2E, default fixture/loopback E2E in CI, agent-routing validation, and documentation contracts. They do not prove a new live target, actual harmless scheduled-task execution, cleanup on a target, a public live receipt, fleet rollout, package installation, or business acceptance.
