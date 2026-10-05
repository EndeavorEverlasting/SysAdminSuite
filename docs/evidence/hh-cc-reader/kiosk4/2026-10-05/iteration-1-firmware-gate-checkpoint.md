# Kiosk4 Firmware Gate — Iteration 1 Checkpoint

Date: 2026-10-05
Repository: EndeavorEverlasting/SysAdminSuite
Disposition: `WAITING_ON_EXTERNAL_OBSERVATION`
Current gate: `BASELINE_LOCKED`

## Purpose

Persist the reviewed Iteration-1 outcome so temporary local JSON and chat status pings are not the only continuity surface. This file is intentionally sanitized: private reader identifiers, credentials, session data, and private evidence URLs remain outside Git.

## Provider-verified floor

- SysAdminSuite PR #495 is merged to `main` as `4aa474946f283882874d837673c3bb964fd879d1`.
- Validated PR head: `356cb06c34351bcf84ca37125e37cb1290927f28`.
- Observed hosted workflows on that exact head completed successfully:
  - H&H CC Reader Firmware Policy Contracts
  - Survey doctrine
  - Pester
  - AutoLogon Field Path Regression
  - AutoLogon Field Path Windows Parse
  - Agent behavior evals
- CodeRabbit commit status: success.

## Current typed state

| Item | State | Meaning |
| --- | --- | --- |
| Kiosk4 identity | `UNIQUE_TARGET_RESOLVED` | Same private device identity is established |
| Local menu/input exploration | `CLOSED` | Not the firmware path; do not replay |
| Observation-surface inventory | `DONE` | Read-only surface order is established |
| Capture contract | `READY` | Fail-closed operator-minimal capture is integrated |
| Synthetic classifier sensitivity | `VALIDATED` | Positive and negative fixtures are integrated on PR #495 |
| `current_firmware_value` | `UNOBSERVED` | No authoritative labeled current value exists yet |
| Version domain | `VERSION_DOMAIN_UNRESOLVED` | Planning strings are not a live bind |
| `BASELINE_LOCKED` | `false` | Blocked only on authoritative live observation |
| Restore | `HARNESS_GATE_PROVEN_LIVE_RESTORE_UNKNOWN` | Deployment recovery story is not ready |
| `mutation_authorized` | `false` | Production mutation remains gated |

## Observation order

Use exactly one authorized read-only observation path for the same private Kiosk4 identity:

1. Payment Fusion Control Center / IngEstate terminal-management detail when authorized.
2. Same-device Settings -> Software versions if the management plane is unavailable; do not reopen the AxiaMed menu crawl.
3. PAXSTORE Terminal Management UI / OpenAPI only when entitlement to that plane is evidenced.

Rejected as the next gate: AxiaMed burger-menu crawl, App Store marketplace work, LAN probing, tracker/history as firmware authority, and any firmware push or settings mutation.

## Capture contract

Record only the observable and provenance-bound fields required by `sas-hh-cc-reader-kiosk4-version-evidence-capture/v1`:

```text
source_surface
observed_at
identity_binding_reference
evidence_reference
labeled_observations[].section
labeled_observations[].field_heading
labeled_observations[].value
```

Keep private identities and raw evidence outside Git.

## Next success transition

```text
authorized labeled installed-version observation
  -> validate capture
  -> Classify-HHCCReaderVersionDomain
  -> domain-bound current_firmware_value
  -> Evaluate-HHCCReaderFirmwareRoundtrip baseline
  -> BASELINE_LOCKED or exact fail-closed blocker
```

## Temporary-source continuity

The originating Cursor sprint reported additional local receipts under `%TEMP%` for observation surfaces, evidence sweep, version/package analysis, control-plane mapping, rollback, boundaries, and Iteration 0/1 rollups. Those files are local-only evidence and were not read by this provider-only lane. Their task-relevant conclusions are distilled here; this checkpoint does not claim byte-level persistence of those temporary files.

## Proof ceiling

No live installed firmware value, package ownership, live restore mechanism, mutation authority, firmware push, deployment, or post-deployment result is claimed here.

## P82 operator-completion addendum — 2026-10-05

The operator reports that the authorized read-only Kiosk4 observation is **finished**.

P82 state:

- **HYPOTHESIS:** one same-device authorized read-only observation is sufficient to produce a classifier-ready labeled capture and decide the baseline gate.
- **BUILD:** PR #495 supplied the fail-closed capture/classifier seam; PR #496 retired stale menu/input routing.
- **MEASURE:** the operator reports the field observation completed, but the new private capture/result is not present in Git or connected Drive readback from this runtime.
- **CRITIQUE:** completion of the physical/provider action and ingestion of its evidence are separate states. Repeating the observation simply because the private local artifact has not crossed runtimes would destroy useful continuity.
- **DECIDE:** preserve the completed observation and recover its local evidence first. Do not promote a firmware value or `BASELINE_LOCKED` until classifier and baseline receipts prove those states.

Typed transition:

```text
WAITING_ON_EXTERNAL_OBSERVATION
  -> OBSERVATION_REPORTED_EVIDENCE_INGEST_PENDING
  -> VERSION_DOMAIN_CLASSIFIED
  -> BASELINE_LOCKED | exact fail-closed blocker
```

The expected first local private capture is `%TEMP%\hh-cc-kiosk4-labeled-firmware-observation.json`. Registered ignored H&H firmware receipts under `survey/output/hh-cc-reader/` are alternate recovery evidence. These private artifacts must not be copied into Git.

## P07 local-recovery addendum — 2026-10-05

Local runtime recovered the canonical private capture and ran the classifier/baseline owners without copying identity into Git.

Measured typed result:

| Item | State |
| --- | --- |
| Capture file | Recovered at `%TEMP%\hh-cc-kiosk4-labeled-firmware-observation.json` |
| Capture schema | `sas-hh-cc-reader-kiosk4-version-evidence-capture/v1` |
| `capture_state` | `AWAITING_FIELD_OBSERVATION` |
| `labeled_observations` | empty (count 0) |
| Classifier | fail-closed; `primary_observation` null; `VERSION_DOMAIN_UNRESOLVED` |
| Identity | `UNIQUE_TARGET_RESOLVED` (existing private receipt; unchanged) |
| Baseline evaluator | `BASELINE_INCOMPLETE` |
| `missing_fields` | `current_firmware_value` only |
| `mutation_authorized` | `false` |
| Fixture PAXSTORE observe | rejected as live current (`credential_state=FIXTURE`) |

Operator-reported field completion did not populate the governed capture. Local reconstruction from other `%TEMP%` / worktree receipts found no non-empty `labeled_observations[].value` for this contract.

Typed transition:

```text
OBSERVATION_REPORTED_EVIDENCE_INGEST_PENDING
  -> LOCAL_CAPTURE_RECOVERED_EMPTY
  -> fill labeled capture on an authorized read-only surface
  -> Classify-HHCCReaderVersionDomain
  -> Evaluate-HHCCReaderFirmwareRoundtrip baseline
  -> BASELINE_LOCKED | exact fail-closed blocker
```
