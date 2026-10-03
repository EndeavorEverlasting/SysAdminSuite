# Kiosk4 Round-Trip Evidence Map (R0)

Date: 2026-10-02
Status: R0 complete / R1 not locked
Parent plan: docs/HH_CC_READER_FIRMWARE_ROUNDTRIP_BATCH_PLAN.md
Parent program: docs/HH_CC_READER_REMOTE_OPERATIONS_PROGRAM.md
Branch floor at map authoring: `origin/main` @ `409f267c`

## Purpose

Make tracker wiring and Kiosk4 evidence ownership explicit before any firmware mutation.
This map is not BASELINE_LOCKED and does not authorize mutation.

**Governance:** tracked source must not contain live serials, MACs, IPv4s, credentials, or private Drive object IDs. Correlate the experimental reader through private/local evidence indexes at runtime.

## Operational tracker (canonical)

| Surface | Private evidence reference | Role |
| --- | --- | --- |
| CC Reader Technician Dashboard | `PRIVATE_EVIDENCE:cc-reader-technician-dashboard-current` | Human-facing operational authority |
| Findings Log | `PRIVATE_EVIDENCE:cc-reader-baseline-findings-log-current` | Baseline findings authority |
| Rolling baseline receipt | `PRIVATE_EVIDENCE:kiosk4-rolling-baseline-receipt-20260930` | Prior R1 attempt ledger |

Do not create a second tracker. Repository artifacts are adapters/receipts only.

## Tracker/source baseline candidate (not live-proved)

Recovered operator-local candidate fields remain outside Git. Runtime binding uses a private evidence packet such as:

```text
%TEMP%\hh-cc-kiosk4-private-target.json
```

Required private fields (names only in tracked source):

| Field | Tracked representation | Proof ceiling |
| --- | --- | --- |
| source name / alias | `Kiosk4` (alias label only) | tracker/source candidate label |
| source serial / CC identity | `PRIVATE_FIELD:source_serial` | private evidence only |
| model | PAX A80 | model class only |
| source MAC | `PRIVATE_FIELD:expected_mac` | private evidence only |
| source firmware/application | `PRIVATE_FIELD:observed_firmware` | must be re-observed live |
| Active Outdated | `PRIVATE_FIELD:active_outdated` | tracker classification candidate |
| source status | historical snapshot only | must not be promoted to present tense |
| governed target | from `selection.default_target` in firmware policy | SETTLED_POLICY |

## Explicitly rejected identity leakage

| Specimen | Rule |
| --- | --- |
| READERUNK legacy specimen IP/MAC pair documented in the round-trip plan | Must never be attributed to Kiosk4 |
| Agent runtime NIC observations | AGENT_RUNTIME_CONTEXT only; not field-workstation proof |

## Prior R1 attempt summary (private receipt)

RUN_ID class `KIOSK4__BASELINE` remains `BASELINE=IN_PROGRESS` in private evidence.

Settled from that private receipt class:

- Admin unlock path proved on prior Kiosk4 stills
- Netstat START_TEST satisfied by prior Kiosk4 provenance (do not restage for header behavior)
- `REMOTE_ENDPOINT_CANDIDATE=NONE`
- Workstation exact-name / ARP / passive exact-MAC discovery exhausted without recovering live IPv4
- Canonical `Probe-HHCCReader.cmd` was correctly not invoked without an exact IPv4

Still open for BASELINE_LOCKED:

- live Kiosk4 IPv4
- live MAC corroboration via MAC-gated probe
- live firmware/build re-observation
- Netstat BASELINE (+ POST_TEST if still missing) for a current RUN_ID
- management-plane bind (P5-C and later)

## Current P5 evidence-state (this continuation)

| Gate | State |
| --- | --- |
| P5-A evaluate | IMPLEMENTED_VALIDATED / integrated |
| P5-B normalize | IMPLEMENTED_VALIDATED / integrated |
| External packet | `%TEMP%\hh-cc-p5-packet-fill.json` |
| Authority result | `RESULT_BLOCKED_AUTHORITY` / `next_gate=AUTHORIZED_READONLY_SESSION` |
| Authenticated PFCC session | `INTERACTIVE_AUTH_REQUIRED` |
| Invented live values | `False` |
| Axia Gateway | login page only |
| Browser-saved PFCC credentials usable by agent | none confirmed |

## Round-trip readiness seams (repository)

Executable offline contracts (no device mutation):

- `harness/api/hh_cc_reader_firmware_roundtrip.py`
- `Evaluate-HHCCReaderFirmwareRoundtrip.cmd`
- `Normalize-HHCCReaderFirmwareBatch.cmd`
- `docs/examples/hh-cc-reader-firmware-batch.example.csv`

These prove identity fail-closed, baseline requirements, restore-path gating, rollback compare, and batch-row normalization. They cannot prove live Kiosk4 identity or firmware mutation.

## Next useful actions (ordered)

1. Operator: authenticate PFCC / Control Center (P5-C) and fill live packet observations without inventing values.
2. Operator/field: capture current Kiosk4 Network/Ethernet identity into the private evidence packet (`PRIVATE_FIELD:live_ipv4`, `PRIVATE_FIELD:expected_mac`).
3. From the technician field PC on the reader network:

```bat
Probe-HHCCReader.cmd <PRIVATE_LIVE_IPV4> <PRIVATE_EXPECTED_MAC>
```

4. Freeze baseline through the round-trip seam only after identity correlation is unique.
5. Complete P5 PROVEN_PATH + RESTORE_PATH_PROVED before any forward firmware mutation.
