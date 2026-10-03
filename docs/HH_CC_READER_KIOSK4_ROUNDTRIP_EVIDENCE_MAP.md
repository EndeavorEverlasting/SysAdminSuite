# Kiosk4 Round-Trip Evidence Map (R0)

Date: 2026-10-02
Status: R0 complete / R1 not locked
Parent plan: docs/HH_CC_READER_FIRMWARE_ROUNDTRIP_BATCH_PLAN.md
Parent program: docs/HH_CC_READER_REMOTE_OPERATIONS_PROGRAM.md
Branch floor at map authoring: `origin/main` @ `409f267c`

## Purpose

Make tracker wiring and Kiosk4 evidence ownership explicit before any firmware mutation.
This map is not BASELINE_LOCKED and does not authorize mutation.

## Operational tracker (canonical)

| Surface | Location | Readable to this agent runtime | Role |
| --- | --- | --- | --- |
| CC Reader Technician Dashboard | Drive file `CC_Reader_Technician_Dashboard_CURRENT_2026-09-21.xlsx` (id `14MQcGtdSR10Q2oe3MOJDFzSk0TDUm_-F`) | No (`readable=false` under current Drive grant) | Human-facing operational authority |
| Findings Log | Drive spreadsheet id `1E2c7vawypgxXaV19ri_6uwaPLtVRJzq1aRomMxf7xnU` | Not verified this pass | Baseline findings authority |
| Rolling baseline receipt | Drive doc `20260930_2211 — Kiosk4 Rolling Baseline Execution Receipt — IN_PROGRESS` (id `1EIT-ahfWPrup6k6uMttgNDutMIrEb3pWN-t2uugDHZc`) | Yes | Prior R1 attempt ledger |

Do not create a second tracker. Repository artifacts are adapters/receipts only.

## Tracker/source baseline candidate (not live-proved)

Recovered into the round-trip plan from the existing dashboard/source inventory:

| Field | Candidate value | Proof ceiling |
| --- | --- | --- |
| source name / alias | Kiosk4 | tracker/source candidate only |
| source serial / CC identity | 1240473751 | tracker/source candidate only |
| model | PAX A80 | tracker/source candidate only |
| source MAC | C8:40:52:3C:93:BA | tracker/source candidate; passive capture later found no usable frame |
| source firmware/application | 2.0.15.260410 | historical inventory snapshot; must be re-observed live |
| Active Outdated | Yes | tracker classification candidate |
| source status | offline (historical snapshot) | must not be promoted to present-tense offline |
| governed target | 2.0.15.260522 | SETTLED_POLICY via firmware policy |

## Explicitly rejected identity leakage

| Specimen | Values | Rule |
| --- | --- | --- |
| READERUNK legacy | 10.217.101.192 / C8:40:52:3C:54:B6 | Must never be attributed to Kiosk4 |
| Agent runtime NIC | Wi-Fi ~192.168.1.8x/24 observed on Cursor host | AGENT_RUNTIME_CONTEXT only; not field-workstation proof |

## Prior R1 attempt summary (Drive receipt)

RUN_ID `20260930_2211__KIOSK4__BASELINE` remains `BASELINE=IN_PROGRESS`.

Settled from that receipt:

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
| Axia Gateway | login page only (`https://gateway.paymentfusion.com/ui/Account/Login`) |
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
2. Operator/field: capture current Kiosk4 Network/Ethernet identity (IPv4 + MAC) on-device, or recover exact lease for `C8:40:52:3C:93:BA` from an already-authorized DHCP surface.
3. From the technician field PC on the reader network:

```bat
Probe-HHCCReader.cmd <LIVE_IPV4> C8-40-52-3C-93-BA
```

4. Freeze baseline through the round-trip seam only after identity correlation is unique.
5. Complete P5 PROVEN_PATH + RESTORE_PATH_PROVED before any forward firmware mutation.
