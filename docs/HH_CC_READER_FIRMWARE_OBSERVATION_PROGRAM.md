# H&H CC Reader Firmware Observation Program

Status: DESIGNED + THIN PROTOTYPE  
Date: 2026-10-03  
Floor: `main` containing P95 + this observe seam  
Mission owner: live Kiosk4 firmware deployment (not harness theater)

## User outcomes / invariants

1. Bind the already-proved Kiosk4 identity to an **authoritative** installed firmware/software value.
2. Reach `BASELINE_LOCKED` without inventing values from trackers, fixtures, or chronology.
3. Prefer non-mutating cloud/TMS/Android/POS observation over inbound LAN guessing.
4. Keep `2.0.15.260522` as the campaign **target**, not an assumed current value.
5. Do not silently violate restore-first mutation policy; surface an explicit operator decision if restore proof is the sole remaining blocker after a ready forward path.

## Domain vocabulary

| Term | Owns |
|---|---|
| `TerminalIdentity` | serial, MAC, live IPv4, unique-target proof |
| `FirmwareObservation` | value + version domain + source surface + timestamp |
| `VersionDomain` | PayDroid/firmwareName vs campaign package vs Android OS vs payment app |
| `ManagementSurface` | PAXSTORE / PFCC-IngEstate / AirViewer / USB-ADB / POS / egress telemetry |
| `BaselineFreeze` | offline round-trip admission (`freeze_baseline`) |
| `CredentialGate` | missing authorized read rights (not “human-only forever”) |

## Module / interface map

| Module | Responsibility | Side effects |
|---|---|---|
| `hh_cc_reader_paxstore_terminal_observe.py` | serial → installedFirmware observe | optional HTTPS GET with env credentials |
| `Observe-HHCCReaderPaxstoreTerminal.cmd` | operator entrypoint | launches Python seam |
| `hh_cc_reader_firmware_roundtrip.py` | identity + baseline freeze | local ignored receipt |
| `hh_cc_reader_estate_authority.py` | PROVEN_PATH classifier | offline only |
| Future PFCC/AirViewer/ADB adapters | alternate observation ports | same observation contract |

Dependency direction:

```text
CMD/CLI -> observe adapter -> (transport port) -> PAXSTORE
                         \-> map observation -> freeze_baseline (offline)
```

## Success call stack (PAXSTORE)

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
| Missing API key/secret | `CREDENTIAL_GATE` | exit 3; no network |
| HTTP/business error | `API_CALL_FAILED` / `TERMINAL_NOT_FOUND` | exit 2 |
| Serial/MAC mismatch | `IDENTITY_MISMATCH` | reject firmware |
| Identity OK, no firmwareName | `FIRMWARE_FIELD_ABSENT` | keep searching surfaces |
| Firmware observed but wrong version domain for eligibility | observation retained; eligibility remains separate | do not rewrite to `.260522` |

## Alternatives compared

| Candidate | Verdict |
|---|---|
| A. PAXSTORE OpenAPI `getTerminalBySn(+installedFirmware)` | **Selected primary** — serial-bound, explicit firmware field, no inbound listener required |
| B. Repeat inbound TCP sweeps | Rejected as exhausted for common ports |
| C. Tracker/history inference | Forbidden — not authoritative |
| D. Physical Software versions / AirViewer | Retained alternate when estate API unavailable |
| E. USB ADB property dump | Retained; different version domain risk |

## Proof ceiling

- Prototype proves the **executable observation seam** and fail-closed credential/identity behavior with fixtures.
- Live `current_firmware_value` remains **UNOBSERVED** until an authorized PAXSTORE (or alternate) read returns a serial-bound firmware field.
- Deployment readiness still requires package mapping for `2.0.15.260522`, mutation authority, and restore-path policy disposition.

## Implementation seam ready for next build

Broaden only after a live observe succeeds or credentials prove the API path:

1. Register command/validator in harness registries if the seam becomes the permanent owner.
2. Add PFCC Settings-by-serial adapter behind the same observation receipt shape.
3. Keep AirViewer/ADB as alternate producers of `FirmwareObservation`, not parallel baseline engines.
