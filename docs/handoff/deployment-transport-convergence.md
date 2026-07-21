# Deployment transport convergence ledger

```text
[SAS | P08 convergence | scope: repository/PR floor | proof: fixture and CI only]
```

## Purpose

This handoff records the preserved deployment-transport contributions, canonical authorities, compatibility boundaries, and unresolved proof gates. It is public-safe: it contains no live hostname, username, package path, credential, ticket material, or raw evidence.

## P01-P07 preservation ledger

| Sprint contribution | Repository evidence | Disposition |
|---|---|---|
| P01 contract floor | PR #242, frozen result and receipt schemas, sanitized fixtures, API operations, workflow, contracts, and CI | Preserved on the P08 convergence branch; source PR remains open until the convergence PR lands. |
| P02 preflight | The frozen `software_install.transport_preflight` operation exists. No runnable producer that emits `sas-software-deployment-transport-result/v1` was present on `main` or an identified P02 head. | Contract preserved; implementation remains an explicit blocker and is not invented during closeout. |
| P03 application transport | PR #229 is merged. PR #238 adds approved package sets and fixes to the existing SMB/Task Scheduler controller. | Merged #229 behavior retained; unique #238 work preserved on the convergence branch. |
| P04 E2E and proof ingestion | PR #177 established default E2E, PR #180 established validated finalization, and PR #232 established production-proof ingestion. | Already on `main`; retained without duplicating their authorities. |
| P05 agent harness | PR #151 established the software-install harness. PR #174 and PR #224 established skill/capability routing. PR #237 factors E2E procedure into the project skill. | Merged harness/routing retained; unique #237 factoring reconciled with current governance and preserved on the convergence branch. |
| P06 operator documentation | PR #233 published the Task Scheduler tutorial and PR #234 published the one-target floor handoff/index. | Already on `main`; terminology and navigation are repaired by P08. |
| P07 terminal receipt | No public-safe P07 receipt, digest, or terminal classification was present in tracked files, source PRs, or the supplied sprint material. | Raw evidence was not accessed. Digest and classification remain `unavailable`; receipt-continuity proof is blocked until a schema-valid public receipt is supplied. |

No source branch is deleted by P08. A source PR may be closed as superseded only after its unique work is present on `main`.

## Canonical authorities

| Concern | Canonical authority | Current limit |
|---|---|---|
| Transport result | `schemas/harness/software-deployment-transport-result.schema.json` | Contract only until a runnable preflight producer is integrated. |
| Public receipt | `schemas/harness/software-deployment-transport-receipt.schema.json` | Binds operator-local evidence by SHA-256 without copying it. |
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

PR #241 and all other non-transport PRs are unrelated to this convergence lane and must not be mutated by P08.

## Merge readiness blockers

1. A runnable preflight producer is not present for `sas-software-deployment-transport-result/v1`.
2. The validated front door does not consume and enforce a schema-valid transport decision.
3. No public-safe P07 receipt was available, so its digest and terminal classification cannot be verified.
4. Source PRs #237, #238, and #242 must remain open until this preserved convergence head is merged.

These blockers prevent claiming one fully implemented cross-transport controller or P07 receipt continuity. They do not invalidate the preserved schema, fixture E2E, existing transport-specific implementations, or CI proof.

## Proof ceiling

P08 can prove repository preservation, authority consistency, parser/contracts, synthetic SMB fixture E2E, default fixture/loopback E2E in CI, agent-routing validation, documentation contracts, and final-head CI. It does not prove a new live target, fleet rollout, package installation, business acceptance, or the missing P07 receipt.
