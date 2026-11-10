# Bluetooth mouse discovery recovery

## Portable CLI and constrained hosts

`SasBluetooth.cmd` is the unified front door. It uses Windows device/service APIs, not computer vision. Commands run locally in the explicitly selected workstation context; they do not discover remote hosts or change network posture.

| Command | Behavior | Rights and context |
| --- | --- | --- |
| `SasBluetooth.cmd capabilities` | Report runtime, language mode, prepared helper, services and elevation | Read-only; use this first on a new host |
| `SasBluetooth.cmd list` | List paired Bluetooth mappings, stable DeviceId, connected/disconnected/unknown state | Intended user; four-second observation; powered-off paired devices are retained |
| `SasBluetooth.cmd pair -ExactName "ProtoArc EM11 NL"` | Ensure selected services if stopped, then pair exact target; optional `-DeviceId` disambiguates | Intended interactive user; existing/delegated service rights or explicit administrator repair if denied |
| `SasBluetooth.cmd ensure-service` | Idempotently start bthserv and one selected per-user instance; never stop/restart a running service | Existing or delegated rights; `-ServiceName` required if ambiguous |
| `SasBluetooth.cmd restart -InstanceId "EXACT_INSPECTED_RADIO_ID"` | Targeted adapter restart | Administrator; briefly interrupts Bluetooth devices |
| `SasBluetooth.cmd reenumerate -InstanceId "EXACT_INSPECTED_RADIO_ID"` | Export driver, remove radio node, rescan | Administrator; separate escalation |
| `SasBluetooth.cmd prepare -Destination "NEW_BUNDLE_DIRECTORY"` | Build and hash a portable runtime folder | Preparation host with Windows SDK; committed clean source required |

Prepare on an approved development/IT host, then copy the entire folder to the authorized workstation through its existing approved deployment channel. The target does not need Git, Python, the Windows SDK, a named user's checkout, or computer vision. Launch-folder independence comes from sibling runtime paths. The SHA-256 manifest records the source commit and verifies deployment drift; it is integrity evidence, not a digital signature or publisher identity. Only deploy from a trusted source through the host's approved channel.

The supported target floor is Windows 10/11 x64, Windows PowerShell 5.1 and permitted .NET Framework/WinRT execution. Capabilities are reported rather than promising every locked-down host can execute arbitrary code. AppLocker, WDAC, Constrained Language, organizational policy and Windows consent remain authoritative. A Session 0 service/WinRM process cannot stand in for the intended interactive user's pairing session. Service repair tries existing rights; access denial returns REQUIRES_ELEVATION without changing UAC, service ACLs, startup templates, or machine execution policy. CMD launchers use a process-local script execution preference; enforced organizational policy still wins.

Windows normally creates per-user services from templates at sign-in, and BluetoothUserService is Manual by default. A changing suffix or stopped Manual service alone is not evidence of corruption. Preserve that configuration; diagnose recurrence before introducing any persistent policy change. Source: [Microsoft per-user services](https://learn.microsoft.com/en-us/windows/application-management/per-user-services-in-windows). Windows may still require its native pairing/consent ceremony; the CLI does not guess PINs or suppress required consent. Source: [Microsoft device pairing](https://learn.microsoft.com/en-us/windows/uwp/devices-sensors/pair-devices).

Current operator acceptance: ProtoArc connected and working; second mouse paired for future use and intentionally powered off. A disconnected paired spare is not a regression.

Critical recurring desktop incident: a ProtoArc EM11 NL stopped being discoverable between the previous night and the operator's report. Other laptops could discover it. A separate M343 mouse must not inherit this diagnosis.

## Responsible owners

SysAdminSuite owns OS service, Bluetooth adapter and driver recovery. BetterInstincts owns cooperative game capture/input and must preserve OS peripheral preferences. Companion fix: BetterInstincts branch `fix/capture-desktop-ownership-20261110`, `docs/PERIPHERAL_INCIDENT.md`. No responsible Cursor session has been established.

## Ordered diagnostic and repair gates

The repository front door is `Recover-BluetoothPeripheral.cmd`. It resolves its script relative to itself, defaults to read-only Inspect, and stores private before/after evidence outside Git. Preserve the current network posture; this is LocalOnly work. Follow the repository's freshness-before-launch procedure before running a repository command. Mutating actions require a separately elevated Windows session; this launcher never silently elevates.

1. Inspect exact mouse identity, present adapter, screenshot preference, `bthserv`, and the suffixed `BluetoothUserService_*`. Stopped Manual services are observations, not sufficient proof of failure. Do not change all service start types to Automatic.
2. If the per-user service is stopped, use the unified ensure-service command. StartUserService remains a compatibility action for the per-user instance only. Selection requires exactly one suffixed instance or an explicit ServiceName and refuses Disabled services. Use existing/delegated rights; elevate only when needed. Check discovery and physical behavior before escalation; never hardcode a suffix across sessions.
3. For adapter nonresponse/timeouts or failed service-only recovery, use `RestartAdapter` with the exact inspected USB Bluetooth adapter InstanceId. This may briefly disconnect Bluetooth input/audio. It does not remove pairing records, reset preferences or delete the driver package.
4. If restart fails to recover discovery, use `ReenumerateAdapter` for that exact radio. It first exports and verifies the third-party INF backup, removes only the radio node, then scans for hardware. This retains the installed package and pairing records. Re-enumeration is not a fresh driver-package installation. If the node does not return, use Device Manager to install the backed-up INF; preserve error receipts and escalate rather than loop.
5. Driver replacement is a separate reviewed escalation: verify actual motherboard/radio identity, hardware IDs, installed INF/version, signed vendor support and rollback package. Never select a Lenovo package merely because another computer is Lenovo. Do not delete the only driver package or reboot automatically.
6. Pair only the exact observed mouse through `Add-BluetoothMouse.cmd -ExactName "ProtoArc EM11 NL"` for this model (substitute only an independently observed, intended device name). It uses the Windows association-endpoint watcher across protocols, including name updates, and limits discovery to 20 seconds and pairing to 30 seconds. It accepts only ConfirmOnly pairing for the exact target; it never guesses a PIN. The helper requires the installed Windows SDK and .NET Framework; no downloads. Close competing pairing attempts first. Name matching alone is not cryptographic identity verification; same-name ambiguity requires Windows UI identification. A discovery result is not pairing success. Classic Bluetooth-only fallback is insufficient for LE-only devices.
7. Verify target-associated HID mouse node, movement, clicks and physical Print Screen. Any regression stops repair. Keep the incident open until physical acceptance.

## Observed recovery and evidence ceiling

The main Bluetooth service was running; the per-user service was stopped. A targeted adapter restart completed, both services subsequently ran, and Windows displayed ProtoArc EM11 NL. Native exact-name ConfirmOnly pairing returned Paired, a target-associated Bluetooth HID mouse node reported healthy, and the operator confirmed pointer movement and clicks work. Print Screen baseline remained intact. Functional incident recovered; recurrence cause remains open. The operator identifies the per-user service as the likely fault. Adapter restart and service transition happened together; a service-only cause was not isolated. Earlier adapter command timeouts support investigating the radio stack. A historical pairing-key removal belongs to an unidentified device and must not be labeled EM11 without identity evidence.

An earlier peripheral repair also changed the Print Screen shortcut preference. Restoring the prior state was physically confirmed. The recovery tool snapshots that preference and fails if it changes; it never sets a universal screenshot preference. No evidence establishes a shared Bluetooth/capture root cause or deliberate interference.

Do not run this as a watchdog, install a scheduled reset, force per-user service templates to Automatic, or repeatedly reset devices during game automation. Record recurrence and trigger-start/service errors first. Raw MACs, serials, logs, screenshots, device inventories and user-profile paths remain private; commit reusable code, synthetic tests and reviewed incident findings only.
