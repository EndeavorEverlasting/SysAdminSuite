# H+H consumer handoff — SAS firmware evidence event producer

Date: 2026-10-03
Producer repository: `EndeavorEverlasting/SysAdminSuite`
Consumer repository: `EndeavorEverlasting/nyc-hh-fieldops-lab` (do not mutate from this lane)

## Producer contract

| Field | Value |
| --- | --- |
| Schema ID | `hh-cc-reader-firmware-event/v1` |
| Producer module | `harness/api/hh_cc_reader_firmware_event.py` |
| Launcher | `Export-HHCCReaderFirmwareEvent.cmd --input BUNDLE_JSON [--output OUT]` |
| JSON Schema | `schemas/harness/hh-cc-reader-firmware-event.schema.json` |
| Producer contract version | `1` |
| Producer repository | `EndeavorEverlasting/SysAdminSuite` |

## Golden interoperability fixtures

| Path | Role |
| --- | --- |
| `docs/examples/hh-cc-reader-firmware-event.golden.json` | Sanitized successful final-runtime event specimen |
| `docs/examples/hh-cc-reader-firmware-event.blocked-progress.json` | Sanitized blocked/progress specimen (`BASELINE_INCOMPLETE`) |
| `docs/examples/hh-cc-reader-firmware-event.bundle.golden.json` | Synthetic receipt bundle that regenerates the golden event |

These fixtures contain **no** live Kiosk4 serial/MAC/IPv4.

## Event identity / idempotency

`event_id = hh-cc-fw-evt-` + first 32 hex chars of SHA-256(`schema|evidence_fingerprint`).

`evidence_fingerprint` is SHA-256 over canonical JSON of:

- schema, event_class, execution_run_id, target_logical_ref;
- identity binding (serial/MAC/proof state/probe match);
- baseline proof state;
- observed starting / governed target / resulting firmware;
- forward / restore / final operation results;
- proof ceiling;
- per-receipt content fingerprints and states.

Not included: wall-clock export time, tracker revision, spreadsheet sync state, company-share state, publication attempt count.

Identical canonical evidence → same `event_id`. Material receipt change → different `event_id`.

## Proof-ceiling rule

Exporter derives proof ceiling from receipts only. It never invents firmware and never promotes a stronger ceiling than evidence supports. Explicit over-claiming `event_class` fails closed.

## Publication isolation

`publication_dependency` is always:

```json
{
  "tracker_required": false,
  "google_drive_required": false,
  "onedrive_required": false,
  "downstream_repo_required": false
}
```

Producer input rejecting publication/tracker/Drive/OneDrive fields prevents those systems from rewriting execution truth.

## Required consumer fail-closed behaviors

H+H consumer must:

1. validate schema/version and required evidence references;
2. treat identical `event_id` as idempotent (no duplicate completion);
3. keep publication state orthogonal to SAS `proof_ceiling` / execution disposition;
4. retain publication failure/conflict as publication state without invalidating upstream firmware proof;
5. not mutate tracker merely because an event exists — H+H completion eligibility remains H+H-governed;
6. keep private operational data out of Git/client-safe artifacts;
7. treat company-share projection as a manual downstream step, not an availability dependency;
8. pin producer schema + integrated SAS SHA so schema drift fails closed.

## Validation command

```bat
python Tests/survey/test_hh_cc_reader_firmware_event_contracts.py
python Tests/survey/test_hh_cc_reader_firmware_roundtrip_contracts.py
```

## Live canary (orthogonal)

Current live Kiosk4 proof ceiling remains independently:

`UNIQUE_TARGET_RESOLVED` with `BASELINE_INCOMPLETE` (missing live `current_firmware_value`) and management authority `BLOCKED_AUTHORITY` / `CREDENTIAL_GATE`.

This producer contract does not claim live firmware deployment.
