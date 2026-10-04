# H&H Kiosk4 Gate A Domain-Branch Continuity Plan

Status: ACCEPTED EXECUTION PLAN (live capture pending)
Date: 2026-10-04
Canonical owner: this file + `docs/plans/hh-cc-version-domain-labeled-capture-20261004.plan.md` + `docs/HH_CC_READER_FIRMWARE_OBSERVATION_PROGRAM.md`
Floor: `main@228b49bf` (PR #482 integrated)
Private runtime artifacts: `%TEMP%\hh-cc-kiosk4-paxstore-ui-capture.json`, `%TEMP%\hh-cc-kiosk4-gate-a-b-runner.ps1`, `%TEMP%\hh-cc-kiosk4-gate-a-domain-branch-design.json`

## User outcomes

1. Capture labeled PAXSTORE App & Firmware evidence for serial `1240473751` / MAC `C840523C93BA`.
2. Freeze Gate A only when `access_state=OBSERVED`, `baseline.state=BASELINE_LOCKED`, `mutation_performed=false`.
3. Bind campaign `2.0.15.260522` only from labeled section/heading evidence.
4. Repair Gate B `includeInstalledApks` **only if** campaign domain binds to an app/package domain.

## Invariants

- No Push App / Push Firmware submit during observation.
- No numeric-similarity domain promotion.
- No Gate B observer mutation before labeled domain bind.
- Baseline immutable after `BASELINE_LOCKED`.
- No secrets in artifacts.

## Domain vocabulary

Unchanged from version-domain plan: `paydroid_os_build`, `paxstore_installed_firmware_name`, `experian_control_center_payment_package`, `payment_application`, `pax_pts_device_firmware`, `VERSION_DOMAIN_UNRESOLVED`.

## Program modules / ownership

| Module | Owns | May call |
|---|---|---|
| `hh_cc_reader_paxstore_ui_observation.py` | UI map, freeze orchestration, parity | version_domain, firmware_roundtrip |
| `hh_cc_reader_version_domain.py` | labeled classify + campaign domain state | none external |
| `hh_cc_reader_firmware_roundtrip.py` | `BASELINE_LOCKED` | identity resolve |
| `hh_cc_reader_paxstore_terminal_observe.py` | Gate B OpenAPI observe | HTTPS with ESI keys |

## Success call stack (Gate A)

```
OPERATOR labeled capture JSON
  -> Ingest-HHCCReaderPaxstoreUiObservation.cmd --freeze
  -> ingest_ui_observation
  -> evaluate_version_domains(observations_from_ui_capture)
  -> freeze_baseline
  -> receipt: OBSERVED + BASELINE_LOCKED
  -> branch on campaign_target_domain_state / campaign_target_version_domain
```

## Domain branch -> Gate B disposition

| Result | Gate B disposition |
|---|---|
| `BOUND -> experian_control_center_payment_package` | REQUIRED SUCCESSOR: `includeInstalledApks=true` + parse `installedApks[]` |
| `BOUND -> payment_application` | REQUIRED SUCCESSOR: same APK repair |
| `BOUND -> paydroid_os_build` | keep firmware observe |
| `BOUND -> paxstore_installed_firmware_name` | keep firmware observe |
| `VERSION_DOMAIN_UNRESOLVED` | do not repair Gate B yet |

## Failure stacks

- TEMPLATE_ONLY / empty labels -> runner fail-closed
- serial/MAC mismatch -> `IDENTITY_MISMATCH`, no freeze
- missing firmware/app values -> `FIRMWARE_FIELD_ABSENT`, no freeze
- unlabeled campaign value -> `VERSION_DOMAIN_UNRESOLVED` / similarity rejected

## Prototype evidence already on floor

- Fixture contracts: 13 passed (`version_domain` + `paxstore_ui_observation`) on `main@228b49bf`
- Dual-domain fixture proves campaign can bind to `experian_control_center_payment_package` while Installed Firmware remains `paydroid_os_build` and baseline freezes

## Phase map

1. **DONE (integrated):** labeled domain classifier + UI ingest (PR #482)
2. **CURRENT / BLOCKED on login:** live Kiosk4 labeled capture + Gate A freeze
3. **CONDITIONAL SUCCESSOR:** Gate B APK observer repair if app/package domain bound
4. ESI bind -> API observe -> UI/API parity
5. package/restore/authority -> controlled Kiosk4 deploy

## Current blocker

`LIVE_RUNTIME_OR_OPERATOR_BOUNDARY`: PAXSTORE Administrator Center authentication at `https://auth.paxstore.us/passport/login?client_id=admin&locale=en&market=paxus`. Cursor browser is on that login page; agent has no credentials.

## Proof ceiling

This plan + fixtures prove seams and branch criteria. They do not prove live Kiosk4 labels, live `BASELINE_LOCKED`, parity, mutation authority, or deployment.

## Next command (after labeled capture filled)

```powershell
powershell -File "$env:TEMP\hh-cc-kiosk4-gate-a-b-runner.ps1"
```

Accept only: `access_state=OBSERVED`, `baseline.state=BASELINE_LOCKED`, serial `1240473751`, MAC `C840523C93BA`, `mutation_performed=false`. Then inspect `version_domain_evaluation.campaign_target_domain_state` and `campaign_target_version_domain`.
