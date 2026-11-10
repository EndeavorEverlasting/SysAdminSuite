# Bluetooth mouse discovery recovery

Critical recurring desktop incident: a ProtoArc EM11 NL stopped being discoverable between the previous night and the operator's report. Other laptops could discover it. A separate M343 mouse must not inherit this diagnosis.

## Responsible owners

SysAdminSuite owns OS service, Bluetooth adapter and driver recovery. BetterInstincts owns cooperative game capture/input and must preserve OS peripheral preferences. Companion fix: BetterInstincts branch `fix/capture-desktop-ownership-20261110`, `docs/PERIPHERAL_INCIDENT.md`. No responsible Cursor session has been established.

## Ordered diagnostic and repair gates

The repository front door is `Recover-BluetoothPeripheral.cmd`. It resolves its script relative to itself, defaults to read-only Inspect, and stores private before/after evidence outside Git. Preserve the current network posture; this is LocalOnly work. Follow the repository's freshness-before-launch procedure before running a repository command. Mutating actions require a separately elevated Windows session; this launcher never silently elevates.

1. Inspect exact mouse identity, present adapter, screenshot preference, `bthserv`, and the suffixed `BluetoothUserService_*`. Stopped Manual services are observations, not sufficient proof of failure. Do not change all service start types to Automatic.
2. If the per-user service is stopped, use `StartUserService`, which requires exactly one suffixed service and refuses a Disabled service. Check discovery and physical behavior before escalation. Preserve the session-specific suffix rather than hardcoding it.
3. For adapter nonresponse/timeouts or failed service-only recovery, use `RestartAdapter` with the exact inspected USB Bluetooth adapter InstanceId. This may briefly disconnect Bluetooth input/audio. It does not remove pairing records, reset preferences or delete the driver package.
4. If restart fails to recover discovery, use `ReenumerateAdapter` for that exact radio. It first exports and verifies the third-party INF backup, removes only the radio node, then scans for hardware. This retains the installed package and pairing records. Re-enumeration is not a fresh driver-package installation. If the node does not return, use Device Manager to install the backed-up INF; preserve error receipts and escalate rather than loop.
5. Driver replacement is a separate reviewed escalation: verify actual motherboard/radio identity, hardware IDs, installed INF/version, signed vendor support and rollback package. Never select a Lenovo package merely because another computer is Lenovo. Do not delete the only driver package or reboot automatically.
6. Pair only the exact observed mouse. A UI discovery result is not pairing success. Classic Bluetooth-only fallback is insufficient for LE-only devices. PIN/passkey requests require the intended Windows interaction; do not guess a PIN or accept unrelated devices.
7. Verify target-associated HID mouse node, movement, clicks and physical Print Screen. Any regression stops repair. Keep the incident open until physical acceptance.

## Observed recovery and evidence ceiling

The main Bluetooth service was running; the per-user service was stopped. A targeted adapter restart completed, both services subsequently ran, and Windows displayed ProtoArc EM11 NL. The operator identifies the per-user service as the likely fault. Adapter restart and service transition happened together; a service-only cause was not isolated. Earlier adapter command timeouts support investigating the radio stack. A historical pairing-key removal belongs to an unidentified device and must not be labeled EM11 without identity evidence.

An earlier peripheral repair also changed the Print Screen shortcut preference. Restoring the prior state was physically confirmed. The recovery tool snapshots that preference and fails if it changes; it never sets a universal screenshot preference. No evidence establishes a shared Bluetooth/capture root cause or deliberate interference.

Do not run this as a watchdog, install a scheduled reset, force per-user service templates to Automatic, or repeatedly reset devices during game automation. Record recurrence and trigger-start/service errors first. Raw MACs, serials, logs, screenshots, device inventories and user-profile paths remain private; commit reusable code, synthetic tests and reviewed incident findings only.
