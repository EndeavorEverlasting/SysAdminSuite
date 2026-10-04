# H&H Version-Domain Labeled Capture Program Plan

Status: ACCEPTED EXECUTION PLAN
Date: 2026-10-04
Canonical owner: this file + `docs/HH_CC_READER_FIRMWARE_OBSERVATION_PROGRAM.md`
Floor: `main` containing PR #481 UI ingest (`6f61c61f` or later)

## User outcomes

1. Stop treating every visible version string as “firmware.”
2. Require labeled PAXSTORE App & Firmware context before domain bind.
3. Keep campaign target `2.0.15.260522` as `VERSION_DOMAIN_UNRESOLVED` until labeled bind.
4. Preserve marketplace-mediated sourcing path; forbid unlabeled public/leaked images.

## Domain vocabulary

- `pax_pts_device_firmware` — PCI/PTS style `25.xx` / `26.xx`
- `paydroid_os_build` — `PX7A_A80_PayDroid_...` / Installed Firmware PayDroid names
- `experian_control_center_payment_package` — candidate domain for `2.0.15.xxxxxx` when labeled under apps/Control Center/PaymentSafe
- `payment_application` — other installed/push app versions
- `VERSION_DOMAIN_UNRESOLVED` — unlabeled or similarity-only values

## Owned scope (this sprint)

- `hh_cc_reader_version_domain.py` classify/evaluate seams
- `Classify-HHCCReaderVersionDomain.cmd`
- UI ingest integration of `labeled_observations` + campaign domain state
- focused contract tests + observation program update

## Forbidden scope

- firmware/app push
- ZIP hunting / leaked image ingestion
- PFCC/AirViewer/ADB/network scan detours
- P13 registry-generator backlog
- fleet rollout design

## Phase map

1. Prototype labeled classify + UI ingest wiring (this sprint) → integrate to `main`
2. Operator labeled TM capture for Kiosk4 → Gate A baseline + domain evidence
3. ESI/API parity only after baseline
4. Controlled deploy only when baseline + domain-bound package mapping + authority + restore + parity

## Proof ceiling

Fixtures prove classification and package-mapping gates. Live domain for `.260522` remains unobserved until labeled PAXSTORE evidence exists.
