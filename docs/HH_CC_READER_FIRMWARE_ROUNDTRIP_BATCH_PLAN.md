# H&H CC Reader Firmware Round-Trip and Batch Plan

Date: 2026-10-02
Status: P04 execution plan
Repository: EndeavorEverlasting/SysAdminSuite
Parent program: docs/HH_CC_READER_REMOTE_OPERATIONS_PROGRAM.md

## Purpose

Prove one known H&H PAX A80 end to end before scaling:

1. lock the exact reader baseline;
2. classify that exact reader for remediation using the governed firmware policy and current tracker evidence;
3. prove restoration to the starting firmware/state before the first mutation;
4. update the one reader to the governed target;
5. verify the update;
6. restore the exact starting firmware/state;
7. verify restoration;
8. preserve machine-readable and human-readable receipts;
9. only then graduate the same contracts into spreadsheet/CSV batch execution.

A successful forward update without a successful restoration does not close the experiment.

## Existing operational tracker remains canonical

Do not create a second CC-reader tracker.

The existing CC_Reader_Technician_Dashboard_CURRENT.xlsx in the operator's H&H Drive workspace remains the human-facing operational surface. Its existing structures are inputs and outputs to the firmware tooling:

- Settings: governed target firmware and campaign-level settings.
- Device Work Queue: exact device/location work and operator lifecycle state.
- Ticket Batches / progress-batch fields: human-facing grouping for execution.
- Device Matrix: source identity, current firmware, Active Outdated, Firmware Updated?, completion date/by, and observed result fields.
- existing identity columns such as hostname, source serial, CC identifier, site code, and MAC when available.

New repository/runtime artifacts are adapters, plans, or receipts. They are not parallel operational authorities.

The tooling must preserve the dashboard's stable device identity and reconcile results back to the same logical row/device after execution.

## Current fleet baseline already present in the tracker

The current dashboard evidence set carries:

- total inventory: 715 A80 rows;
- active-outdated scope: 657;
- already-current population: 36;
- remote-first candidates: 485;
- field / owner validation: 138;
- shipped review: 34;
- current governed target in Settings: 2.0.15.260522;
- campaign ticket: INC007576091.

These counts describe the existing operational inventory. They do not authorize batch mutation.

## Kiosk4 baseline identity rule

The experimental reader is referred to as Kiosk4, but mutation is forbidden until current evidence binds that label to the physical/management-plane reader.

Do not reuse the older READERUNK specimen values 10.217.101.192 / C8:40:52:3C:54:B6 as Kiosk4 identity. Those values are historical reader evidence and the later rolling-baseline receipt explicitly did not attribute them to Kiosk4.

The later Kiosk4 work also contains a candidate exact-MAC observation attempt retained only in private evidence. That passive attempt produced no usable frame and therefore does not, by itself, prove Kiosk4 identity.

BASELINE_LOCKED requires:

- one stable dashboard/source identity for the experimental reader, preferring source serial / CC identifier plus Kiosk4 alias;
- current on-device or authoritative management-plane identity evidence;
- current reader IPv4 when the network probe is used;
- expected MAC from authoritative reader/tracker evidence;
- canonical Probe-HHCCReader.cmd <IPv4> <EXPECTED_MAC> result proving the probed target matches the expected reader;
- current firmware value;
- application/build value when exposed;
- current network values needed to prove return-to-baseline without changing them;
- site/location context when the reader belongs to an H&H site profile;
- timestamped baseline receipt.

Any identity conflict means DEVICE_MISMATCH or IDENTITY_CONFLICT and no mutation.

## Outdated classification

The default planning target remains 2.0.15.260522 unless stronger accepted evidence supersedes the firmware policy.

Do not classify a reader as outdated from numeric ordering alone. Existing client inventory shows that numerically older versions can coexist with client-accepted rows.

For the selected reader, OUTDATED_CLASSIFIED requires:

- observed starting firmware;
- current tracker/client Active Outdated classification when the reader exists in that source;
- governed target firmware;
- explicit eligibility reason for this pilot.

A mismatch between source classification and observed live firmware is a reconciliation event, not permission to guess.

## Restore-first mutation contract

Before the target update is initiated, restoration must be proved possible.

RESTORE_PATH_PROVED requires:

- exact starting firmware/version recorded;
- exact starting package/release mapping on the authoritative management surface, or another authoritative supported restoration mechanism;
- evidence that the original package can be selected/assigned to this same reader;
- supported rollback/reassignment verb and constraints;
- reboot/reconnect/check-in behavior for both update and restore;
- timeout/failed-job exception path;
- post-restore acceptance criteria;
- a machine-readable restore plan bound to the baseline identity and starting firmware.

If the original firmware/package cannot be selected or the restoration contract is unknown, stop before the first firmware mutation. Do not use the forward update to discover whether rollback exists.

## Single-reader round-trip experiment

Dependencies: BASELINE_LOCKED, OUTDATED_CLASSIFIED, P5 PROVEN_PATH, RESTORE_PATH_PROVED, and explicit one-reader mutation authorization.

Execution:

1. Freeze a pre-mutation baseline receipt and restore plan.
2. Revalidate exact target identity immediately before mutation.
3. Apply the governed target firmware to only that reader.
4. Observe job state, reconnect/check-in, authoritative resulting firmware, and post-update acceptance.
5. Record TARGET_UPDATE_PROVED.
6. Revalidate exact target identity again.
7. Apply the captured starting firmware/package using the proved restoration mechanism.
8. Observe reconnect/check-in and authoritative restored firmware.
9. Rerun the relevant baseline checks and compare starting versus restored state.
10. Record ORIGINAL_STATE_RESTORED only when required state matches the frozen baseline.
11. Record SINGLE_READER_ROUNDTRIP_PROVED only when both forward and restore legs are proven.

The restore leg is part of definition of done, not optional cleanup.

## Existing SysAdminSuite reversible-batch pattern

Future CC-reader batch tooling must reuse the repository's established reversible batch conventions rather than invent a second orchestration model.

Reference pattern: mapping/Start-NorthwellPrinterBatch.ps1 and Map-NorthwellPrinters-Batch.cmd.

Adapt these concepts to firmware semantics:

- Import-Csv input;
- shape validation before network or mutation;
- materialized exact batch plan;
- WhatIf/dry-run;
- explicit APPLY confirmation for the exact plan;
- per-target execution results;
- UndoPlan.json-style restoration plan containing only observed/reversible transitions;
- Summary.json;
- durable per-run evidence path.

Do not call printer code directly. Reuse the contracts and UX pattern.

## Spreadsheet / CSV batch adapter

Batch execution is downstream of the proven single-reader round trip.

Users must be able to start from either:

- the existing CC Reader Technician Dashboard, including an exported sheet/range; or
- a CSV/XLSX containing the required batch columns.

The adapter normalizes these inputs into one canonical batch-plan schema. It must not create a second tracker.

The schema must be derived from existing dashboard identities and single-reader proof. Candidate fields:

- stable tracker/device identity;
- hostname / source name when present;
- serial / CC identifier;
- expected MAC when available;
- site code / facility;
- progress batch ID;
- campaign ticket;
- observed current firmware;
- Active Outdated classification;
- intended target firmware, defaulted from Settings and overridable only through governed policy;
- action: PLAN, UPDATE, and later RESTORE;
- baseline/identity proof reference;
- restore-plan reference.

Before any batch mutation, every row passes the same identity, policy, target-package, and restore-path gates proven by the single-reader experiment.

A failed row becomes an exception. It must never cause identity or target values to shift onto another row.

## Tracker round trip

Canonical flow:

existing dashboard or CSV export
-> normalize and validate
-> exact per-row identity binding
-> dry-run batch plan
-> explicit apply gate
-> per-device update / restore execution
-> machine-readable per-device receipts
-> batch summary
-> reconcile results into existing dashboard rows
-> human-readable HTML receipt

At minimum, tracker reconciliation must preserve unrelated operator data and be able to populate or refresh:

- Work Status;
- Final Firmware / Result;
- Firmware Updated? evidence;
- Firmware Completion Date;
- Firmware Updated By;
- Progress Batch ID;
- exception / needs-review state;
- receipt/evidence reference.

Writeback must be row-preserving and read back after mutation before synchronization is claimed.

## HTML receipt successor

HTML is a successor artifact, not a prerequisite for the first firmware mutation.

When implemented, reuse existing SysAdminSuite HTML design and rendering conventions, including tools/ConvertTo-SuiteHtml.ps1 and the newer local dashboard renderers.

The receipt must make these states obvious:

- run ID and mode: SINGLE_READER, BATCH_PLAN, BATCH_APPLY, RESTORE;
- requested target count;
- identity-locked count;
- updated count;
- restored count;
- skipped/blocked/failed count;
- target firmware;
- per-device starting firmware -> target result -> restore result;
- identity proof state;
- restore proof state;
- exact exception reason;
- paths/references to machine-readable receipts;
- overall proof ceiling.

A green summary must never hide a failed restoration or unresolved identity.

## P04 factoring and launch order

### R0 — Current floor + tracker binding

Runtime: local agent plus Drive read access.

Tasks:
- refresh SysAdminSuite current main and current overlapping PRs;
- inspect the existing dashboard schema and map its current fields to firmware-tool inputs/outputs;
- reconcile Kiosk4 prior receipts and reject READERUNK identity leakage;
- preserve the dashboard as the operational authority.

Completion gate: tracker wiring and Kiosk4 evidence map are explicit.

R0 evidence map (2026-10-02): docs/HH_CC_READER_KIOSK4_ROUNDTRIP_EVIDENCE_MAP.md
Offline admission seams (identity/baseline/restore/preview/compare/batch): harness/api/hh_cc_reader_firmware_roundtrip.py

### R1 — Kiosk4 baseline lock

Runtime: technician/local runtime on the actual experiment network.

Tasks:
- classify the active network environment before interpreting identity evidence; a hospital guest/shared LAN is a shared non-domain environment and must not inherit consumer-lab active discovery behavior;
- classify the reader's inventory identity tranche as SERIAL_AND_MAC, SERIAL_ONLY, MAC_ONLY, IDENTITY_INSUFFICIENT, or IDENTITY_INVALID;
- recover current Kiosk4 IPv4, MAC, serial/CC identifier, tracker row, firmware, and exposed app/build values;
- for SERIAL_AND_MAC, run only the canonical one-target MAC-gated Probe-HHCCReader path;
- for SERIAL_ONLY, recover MAC from approved physical or authorized management evidence before baseline lock; do not substitute subnet discovery;
- for MAC_ONLY, recover serial from the tracker, physical label/UI, or authorized management evidence before baseline lock;
- for IDENTITY_INSUFFICIENT or IDENTITY_INVALID, stop for reconciliation/correction before target probing;
- correlate network result to the same dashboard/source identity;
- preserve probe identity_assurance separately from reachability so MAC_UNRESOLVED on a shared/guest LAN cannot be mistaken for proof of the wrong reader;
- freeze timestamped baseline receipt.

Completion gate: BASELINE_LOCKED. No identity tranche by itself authorizes mutation or broad discovery.

### R2 — Management path + restoration proof

Runtime: authenticated management-plane session plus local evaluator.

Tasks:
- complete remaining P5 live observation;
- prove target package/method;
- prove starting firmware package/method can restore the same reader;
- capture update/reboot/exception/post-update semantics;
- generate restore plan before mutation.

Completion gate: P5 PROVEN_PATH plus RESTORE_PATH_PROVED.

### R3 — Single-reader forward update

Runtime: authorized mutation runtime.

Tasks:
- refresh target identity immediately before mutation;
- update only Kiosk4 to 2.0.15.260522;
- verify reconnect/check-in, authoritative firmware, and acceptance.

Completion gate: TARGET_UPDATE_PROVED.

### R4 — Single-reader restoration

Runtime: authorized mutation runtime.

Tasks:
- refresh target identity again;
- restore the frozen starting firmware/package;
- verify firmware and relevant starting-state invariants;
- preserve forward and restoration receipts.

Completion gate: ORIGINAL_STATE_RESTORED plus SINGLE_READER_ROUNDTRIP_PROVED.

### R5 — Dashboard/CSV adapter

Runtime: local implementation.

Tasks:
- define canonical batch-input schema from existing dashboard fields;
- support CSV and XLSX/dashboard export normalization;
- classify every row into SERIAL_AND_MAC, SERIAL_ONLY, MAC_ONLY, IDENTITY_INSUFFICIENT, or IDENTITY_INVALID before execution admission;
- expose tranche counts and identity-recovery rows so site work can stage the strong dual-identifier population separately from recovery-heavy tranches;
- generate dry-run BatchPlan;
- bind every executable row to baseline/identity and restore references;
- keep SERIAL_ONLY, MAC_ONLY, IDENTITY_INSUFFICIENT, and IDENTITY_INVALID rows non-executable until their explicit recovery gate is satisfied;
- add synthetic fixtures including duplicate identity, mismatched MAC, serial-only, MAC-only, missing identity, stale firmware, unsupported restoration, and mixed valid/invalid rows.

Dependency: R4.

Completion gate: synthetic and dashboard-export fixtures validate without mutating devices.

### R6 — Reversible batch executor

Runtime: local implementation plus later authorized management runtime.

Tasks:
- implement firmware batch execution using the established SysAdminSuite plan/apply/undo/summary convention;
- isolate failures per row;
- preserve exact pre-state and restoration plan per device;
- require an explicit exact-plan APPLY gate;
- do not allow fleet execution from an unvalidated raw spreadsheet.

Dependency: R5.

Completion gate: local tests plus controlled multi-row canary.

### R7 — HTML receipts + tracker reconciliation

Runtime: local implementation plus Drive writeback.

Tasks:
- render single-reader and batch receipts in SysAdminSuite visual language;
- reconcile per-device outcomes into the existing dashboard rows;
- preserve operator-entered unrelated fields;
- read back the tracker after write;
- expose batch summary without hiding exceptions/restoration failures.

Dependency: R5 and R6 for full batch result rendering. Receipt renderer may be prototyped earlier against synthetic R3/R4 receipts, but does not block the live one-reader round trip.

Completion gate: receipt validation plus tracker writeback/readback proof.

## Collision and scope rules

- R1-R4 are the critical path.
- R5-R7 are required successor work and must not delay R1-R4.
- Do not create a new operational tracker.
- Do not copy private live identifiers into tracked source.
- Do not mutate any reader whose identity is not BASELINE_LOCKED.
- Do not perform the first forward update until RESTORE_PATH_PROVED.
- Do not call a forward-update-only result a successful pilot.
- Do not enable batch apply until the single-reader round trip has been proved.
- Preserve the current P5 evaluator and firmware-policy owners; repair confirmed P5 defects rather than routing around them.

## Proof ceiling

Repository planning, fixtures, validators, dry runs, and receipt rendering can prove contracts and local behavior. They cannot prove Kiosk4 identity, live package assignment, firmware mutation, restoration, or tracker writeback until those actions are observed in the appropriate runtime.

## Recovered Kiosk4 tracker/source baseline candidate

The existing CC Reader Technician Dashboard and its underlying source inventory identify an experimental Kiosk4 record. Live serial, MAC, IPv4, and firmware values for that record remain in private/operator evidence (`PRIVATE_EVIDENCE:kiosk4-tracker-candidate`) and must not be copied into tracked source.

Tracked facts that may be stated without live identifiers:

- source name / alias: Kiosk4;
- model: PAX A80;
- client/tracker Active Outdated classification: Yes (historical snapshot);
- source state: deployed (historical snapshot);
- governed planning target: `selection.default_target` from `harness/api/hh-cc-reader-firmware-policy.json`.

These values are the expected identity/baseline *class* for the live lock. They do not prove current network reachability, current IPv4, or current live firmware. Bind private serial/MAC/firmware at runtime before BASELINE_LOCKED.

