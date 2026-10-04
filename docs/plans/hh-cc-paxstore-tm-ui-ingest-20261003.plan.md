# P95 PAXSTORE Terminal Management UI Ingest Sprint Plan

Status: ACCEPTED EXECUTION PLAN
Date: 2026-10-03
Canonical owner: this file (also reflected in `docs/HH_CC_READER_FIRMWARE_OBSERVATION_PROGRAM.md`)
Floor: `origin/main` containing PR #480 PAXSTORE OpenAPI observe seam

## Owned scope

- Terminal Management UI observation ingest seam feeding existing `freeze_baseline`
- `AUTHORIZED_ACCESS_SETUP_REQUIRED` disposition when `SAS_PAXSTORE_ESTATE_AUTHORITY=OWNED_ADMINISTERING`
- UI/API parity comparator
- Observation program + live-execution-boundary next_action updates
- Command/artifact registry wiring and focused contract tests

## Forbidden scope

- Firmware push / mutation APIs
- PFCC / AirViewer / ADB / generic network scan lanes
- Committing live private captures or secrets
- Inventing campaign version mapping from numeric similarity
- Unrelated neuron-tooling or other open PR work

## Phase map

1. **PROTOTYPE (this sprint)** — UI ingest + disposition remap + parity + docs; integrate to `main`.
2. **LIVE UI BASELINE (successor)** — operator TM capture for serial `1240473751` → ingest `--freeze` → `BASELINE_LOCKED`.
3. **ESI + PARITY (successor)** — enable External System Integration; bind `SAS_PAXSTORE_*`; Observe CMD; UI/API parity; package/restore disposition.
4. **CONTROLLED DEPLOY (later)** — only after baseline + package mapping + mutation authority + restore disposition.

## Validation

- `python -m pytest Tests/survey/test_hh_cc_reader_paxstore_terminal_observe_contracts.py Tests/survey/test_hh_cc_reader_paxstore_ui_observation_contracts.py Tests/survey/test_hh_cc_reader_live_execution_boundary_contracts.py -q`
- Prove no network on missing-credential paths; prove freeze on fixture success.

## Proof ceiling

Repository prototypes do not prove live Installed Firmware, ESI enablement, or `.260522` deployment.
