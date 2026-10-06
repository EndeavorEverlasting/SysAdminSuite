# Plan — Kiosk4 Admin Box ADB Control Plane (P04 + P82)

Date: 2026-10-06
Status: `ACTIVE_EXECUTION_FLOOR`
Supersedes P97 successor critical-path that sent the next sprint into proprietary-console bind.
Canonical research retained: `docs/research/hh-cc-kiosk4-p97-android-remote-capability-frontier-20261006.md`
Canonical technician workflow: `docs/HH_CC_READER_ADB_ADMIN_BOX_WORKFLOW.md`

## Architecture

```text
                     ADMIN BOX
                        |
          +-------------+-------------+
          |             |             |
         ADB       observation     SysAdminSuite
          |          tooling          |
          +-------------+-------------+
                        |
                     Kiosk4
                   PAX A80 / Android
```

The Admin Box + SysAdminSuite workflows are the control plane.
ADB is a transport beneath that plane.

Experian / Payment Fusion / PAXSTORE / MAXSTORE / AirViewer are **optional/parallel
estate capabilities**, evidence sources, or alternate transports. They are **not**
prerequisites for this program. Do not redirect execution back into
“get proprietary console access.”

## Evidence categories (do not collapse)

- `DEVICE_CAPABILITY` — Android/build/packages/policy on the reader
- `CONTROL_TRANSPORT_CAPABILITY` — USB/ADB/network-ADB/remote-view session
- `REPOSITORY_CAPABILITY` — host Platform-Tools, CMDs, fixtures, registries
- `POLICY_SAFETY_CONTROL` — mutation refusal, no-scan, revert-required

Repository validation is repository proof, not a Kiosk4 experiment.

## Owned now

Technician CMDs, typed classifier, fixtures, host Platform-Tools cache, USB/ADB
probe, read-only inventory, firmware adapter into existing classifier/baseline
seams, exact-target network ADB transaction with revert, view-only remote display.

## Forbidden (global)

Firmware push; app install/uninstall; payment-parameter mutation; wipe; bootloader
unlock; fastboot flash; daemon elevation; remount; verified-boot disable; arbitrary
settings put; subnet scanning; credential attack; TLS interception; PAN/PHI persistence.
Do **not** enable Developer Options / USB debugging if they are off. Using an
already-present ADB daemon (including `unauthorized`) is authorized observation.

## Next executable action

```text
Owner: technician / Admin Box
Dependency: none on proprietary consoles
Action: Evaluate-HHCCReaderAdbControlPlane.cmd
Expected artifact: ignored receipt under survey/output/hh-cc-reader/
Completion gate: highest typed live state, or exact attended retry (RSA Allow USB debugging)
```
