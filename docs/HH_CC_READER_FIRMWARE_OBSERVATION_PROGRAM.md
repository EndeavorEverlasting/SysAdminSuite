# H&H CC Reader Firmware Observation Program

Status: DESIGNED + THIN PROTOTYPE (UI ingest + OpenAPI observe + version-domain classify)
Date: 2026-10-04
Floor: `main` containing P95 + PAXSTORE observe (PR #480) + TM UI ingest (PR #481) + version-domain labels
Mission owner: live Kiosk4 firmware/package deployment (not harness theater)

## User outcomes / invariants

1. Bind the already-proved Kiosk4 identity to an **authoritative** installed value with its **version domain**.
2. Reach `BASELINE_LOCKED` without inventing values from trackers, fixtures, or chronology.
3. Prefer non-mutating cloud/TMS/Android/POS observation over inbound LAN guessing.
4. Keep `2.0.15.260522` as the campaign **target**, not an assumed current value, and as `VERSION_DOMAIN_UNRESOLVED` until labeled bind.
5. Do not silently violate restore-first mutation policy; surface an explicit operator decision if restore proof is the sole remaining blocker after a ready forward path.
6. When the operator owns/administers the PAXSTORE marketplace, missing External System Integration keys are `AUTHORIZED_ACCESS_SETUP_REQUIRED`, not an external `CREDENTIAL_GATE`.
7. Never source or deploy an unlabeled public/leaked A80 image; marketplace-mediated packages only.

## Domain vocabulary

| Term | Owns |
|---|---|
| `TerminalIdentity` | serial, MAC, live IPv4, unique-target proof |
| `FirmwareObservation` | value + version domain + source surface + timestamp |
| `VersionDomain` | `pax_pts_device_firmware` / `paydroid_os_build` / `experian_control_center_payment_package` / `payment_application` / `VERSION_DOMAIN_UNRESOLVED` |
| `LabeledObservation` | section + field_heading + value (+ package name/id); label required for bind |
| `ManagementSurface` | PAXSTORE TM UI / PAXSTORE OpenAPI / PFCC-IngEstate / AirViewer / USB-ADB / POS |
| `EstateAccessDisposition` | `AUTHORIZED_ACCESS_SETUP_REQUIRED` (owned estate setup) vs `CREDENTIAL_GATE` (external owner) |
| `PackageMapping` | observed package identity for campaign target; `PROVEN` requires domain-bound campaign target |
| `UiApiParity` | serial/firmware/status/check-in compare; `PASS` or `DIVERGENCE` |
| `BaselineFreeze` | offline round-trip admission (`freeze_baseline`) |
| `SourcingPath` | Experian/Control Center → PAXSTORE marketplace → Push Firmware/App → terminal |

## Module / interface map

| Module | Responsibility | Side effects |
|---|---|---|
| `hh_cc_reader_version_domain.py` | labeled classify + campaign domain state | local only |
| `Classify-HHCCReaderVersionDomain.cmd` | operator classify entrypoint | launches Python seam |
| `hh_cc_reader_paxstore_ui_observation.py` | TM UI capture → observation receipt + parity | local ingest only |
| `Ingest-HHCCReaderPaxstoreUiObservation.cmd` | operator UI ingest entrypoint | launches Python seam |
| `hh_cc_reader_paxstore_terminal_observe.py` | serial → installedFirmware OpenAPI observe | optional HTTPS GET with env credentials |
| `Observe-HHCCReaderPaxstoreTerminal.cmd` | operator API entrypoint | launches Python seam |
| `hh_cc_reader_firmware_roundtrip.py` | identity + baseline freeze | local ignored receipt |
| `hh_cc_reader_estate_authority.py` | PROVEN_PATH classifier | offline only |

Dependency direction:

```text
CMD/CLI -> UI ingest
                 \-> version-domain evaluate (labeled_observations)
                 \-> FirmwareObservation receipt
                 \-> freeze_baseline (offline)
                 \-> optional UI/API parity (pure)
         -> OpenAPI observe adapter (deterministic repeat)
```

## Version-domain critical observation

Capture **labels**, not bare numbers:

```text
section (Installed Firmware | Installed Apps | Push Firmware | Push App)
field_heading
value
package_name / application_name
package_id
install_time
```

If Installed Firmware is PayDroid/`PX7A_A80_...` and `2.0.15.x` appears under Installed Apps / Push App, those are different domains. Campaign `2.0.15.260522` may be an Experian/Control Center/payment package mediated by PAXSTORE, not PTS/PayDroid flash firmware.

## Two-layer critical path

```text
PAXSTORE Terminal Management UI (fast truth + labels)
  -> private capture JSON with labeled_observations
  -> Ingest-HHCCReaderPaxstoreUiObservation.cmd --freeze
  -> BASELINE_LOCKED
  -> campaign_target_domain_state BOUND|VERSION_DOMAIN_UNRESOLVED

External System Integration (deterministic repeat)
  -> SAS_PAXSTORE_API_KEY / SECRET / BASE_URL
  -> Observe-HHCCReaderPaxstoreTerminal.cmd --freeze
  -> UI/API parity PASS before mutation
```

## Success call stack (Terminal Management UI)

```text
OPERATOR captures App & Firmware fields
  -> Ingest-HHCCReaderPaxstoreUiObservation.cmd --input <private.json> --freeze
  -> ingest_ui_observation
  -> map_ui_capture (identity bind + Installed Firmware extract)
  -> to_baseline_observation
  -> resolve_target_identity + freeze_baseline
  -> receipt: access_state=OBSERVED, baseline.state=BASELINE_LOCKED
```

## Success call stack (PAXSTORE OpenAPI)

```text
OPERATOR / CMD
  -> Observe-HHCCReaderPaxstoreTerminal.cmd --serial <SN> --expected-mac <MAC> --freeze
  -> observe_terminal_by_sn
  -> credentials_from_env (SAS_PAXSTORE_API_KEY/SECRET)
  -> build_signed_get (HMAC-SHA256 query signature header)
  -> GET {base}/v1/3rdsys/terminal?serialNo&includeInstalledFirmware=true
  -> map_terminal_payload (identity bind + firmwareName extract)
  -> to_baseline_observation
  -> resolve_target_identity + freeze_baseline
  -> receipt: access_state=OBSERVED, baseline.state=BASELINE_LOCKED
```

## Failure call stacks

| Failure | Classification | Return |
|---|---|---|
| Missing API key/secret, estate owned (`SAS_PAXSTORE_ESTATE_AUTHORITY=OWNED_ADMINISTERING`) | `AUTHORIZED_ACCESS_SETUP_REQUIRED` | exit 3; no network |
| Missing API key/secret, estate not marked owned | `CREDENTIAL_GATE` | exit 3; no network |
| HTTP/business error | `API_CALL_FAILED` / `TERMINAL_NOT_FOUND` | exit 2 |
| Serial/MAC mismatch (UI or API) | `IDENTITY_MISMATCH` | reject firmware |
| Identity OK, no firmware field | `FIRMWARE_FIELD_ABSENT` | keep searching surfaces |
| UI/API disagree after both observed | `DIVERGENCE` | do not pick a winner; refresh/resolve |
| Firmware observed but wrong version domain for eligibility | observation retained; eligibility remains separate | do not rewrite to `.260522` |

## Package mapping and restore (same UI session)

While App & Firmware is open, inspect Push Firmware **without submitting**:

- whether package/version for `2.0.15.260522` is selectable
- whether the current installed package remains selectable for restore

Capture on the UI ingest schema as `target_package_*` and `current_package_restorable`. Do not invent mapping from numeric similarity. If restore proof is the only remaining blocker after baseline + mapped target + mutation authority, surface that operator decision explicitly.

## Alternatives compared

| Candidate | Verdict |
|---|---|
| A. PAXSTORE TM UI ingest + OpenAPI `getTerminalBySn(+installedFirmware)` | **Selected** — complementary layers; UI unsticks fastest; API repeats |
| B. API-only wait until ESI configured | Rejected — slower unstick when operator already owns the marketplace |
| C. Repeat inbound TCP sweeps | Rejected as exhausted for common ports |
| D. Tracker/history inference | Forbidden — not authoritative |
| E. Physical Software versions / AirViewer | Retained alternate when estate API/UI unavailable |
| F. USB ADB property dump | Retained; different version domain risk |

## Proof ceiling

- Prototypes prove UI ingest, owned-estate setup disposition, OpenAPI observe, freeze, and UI/API parity with fixtures.
- Live `current_firmware_value` remains **UNOBSERVED** until Terminal Management (or authorized API) returns a serial-bound firmware field.
- Deployment readiness still requires package mapping for `2.0.15.260522`, mutation authority, and restore-path policy disposition.

## Implementation seam ready for next live gate

1. Operator: Terminal Management → serial `1240473751` → App & Firmware → private capture JSON.
2. Agent: `Ingest-HHCCReaderPaxstoreUiObservation.cmd --input <capture> --freeze` → `BASELINE_LOCKED`.
3. Operator: enable External System Integration; bind `SAS_PAXSTORE_*` locally; set `SAS_PAXSTORE_ESTATE_AUTHORITY=OWNED_ADMINISTERING`.
4. Agent: `Observe-HHCCReaderPaxstoreTerminal.cmd --serial ... --freeze`, then `Ingest-HHCCReaderPaxstoreUiObservation.cmd --input <capture> --compare-api <api-receipt.json>` for UI/API parity → continue deployment gates.
