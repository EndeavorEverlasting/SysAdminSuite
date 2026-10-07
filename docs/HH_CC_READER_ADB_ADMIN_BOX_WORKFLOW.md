# H&H CC Reader — Admin Box ADB Control Plane

The Admin Box plus these SysAdminSuite commands are the control plane.
Android Debug Bridge (ADB) is only the transport underneath that plane.

Experian / Payment Fusion / PAXSTORE / MAXSTORE / AirViewer remain optional
estate capabilities. They are **not** prerequisites for this workflow.

Mutation remains unauthorized even after a ready ADB session. Do not mutate
firmware, apps, payment parameters, security controls, or the bootloader.

## Technician front doors

| Command | Purpose |
| --- | --- |
| `Evaluate-HHCCReaderAdbControlPlane.cmd` | Orchestrate host prepare + probe + inventory + exact-target network ADB + view-only display |
| `Prepare-HHCCReaderAdbHost.cmd` | Install or locate official Google Platform-Tools in the SysAdminSuite local cache |
| `Probe-HHCCReaderAdb.cmd` | Classify USB and ADB authorization |
| `Capture-HHCCReaderAdbInventory.cmd` | Read-only Android inventory and firmware-property adapter |
| `Certify-HHCCReaderAdbTcpip.cmd` | Exact-IP network ADB prove-then-revert |
| `Certify-HHCCReaderRemoteView.cmd` | View-only remote display after proven ADB |

Receipts land under ignored `survey/output/hh-cc-reader/`. Closing the terminal does not erase them.

## How to read a result

The command prints typed fields. Do not interpret raw `adb` output.

```text
STATE=ADB_DEVICE_UNAUTHORIZED
PROVED=USB ADB transport is present
SCREEN_CONFIRMATION=UNOBSERVED
NEXT_ACTION=On Kiosk4, approve the Admin Box RSA debugging key, then rerun this command
ATTENDED_RETRY_REQUIRED=true
MUTATION_AUTHORIZED=false
```

`unauthorized` is success-typed transport proof. Someone later must tap Allow on the reader.

## Host tooling

`Prepare-HHCCReaderAdbHost.cmd` prefers `%LOCALAPPDATA%\SysAdminSuite\tools\android-platform-tools\adb.exe`.
It records official source, archive SHA256 when downloaded, path precedence, timestamp, and `adb version`.
It does not silently hide another existing `adb.exe`; PATH/SDK copies are reported.

## Identity

An ADB serial is not automatically the payment-terminal serial. Bind with the private expected MAC and vendor properties. Do not copy live serials, MACs, or IPs into Git.

## Firmware

Inventory adapts `getprop` keys into `Classify-HHCCReaderVersionDomain.cmd`.
Campaign target `2.0.15.260522` is never used as observed current firmware.
If the classifier binds an Installed Firmware row, run:

```bat
Evaluate-HHCCReaderFirmwareRoundtrip.cmd baseline --input PRIVATE_BASELINE.json
```

`BASELINE_INCOMPLETE` with an exact missing field is a valid measurement.

## Network ADB

Do not scan for port 5555. After USB ready + identity bound, the workflow uses the device-derived IP only, then returns the reader to USB mode and proves the network listener is gone. `NETWORK_ADB_REVERT_FAILED` is incomplete, not success.

## Remote display

View-only. Do not tap the payment terminal through the stream. Full remote-control is a separate later classification.

## Attended retry

If the operator was asleep during an RSA or display prompt:

1. Keep the receipt.
2. On the reader, approve the Admin Box debugging key (or view prompt).
3. Rerun only `Probe-HHCCReaderAdb.cmd` (or the dependent command), not the entire discovery chain.

## Physical A80 multi-port wiring (operator-confirmed 2026-10-06)

Do not re-litigate whether cables are "really plugged in" once the operator has provided
photo evidence of the Kiosk4/PAX multi-port pigtail and the Admin Box ports. Physical
attachment and Windows/ADB enumeration are different facts.

| Port on A80 multi-cable | Meaning | Admin Box expectation |
| --- | --- | --- |
| `LAN` (red network icon) | Ethernet | May appear as Admin Box `Ethernet` link; needs correct RJ45-to-LAN path |
| `RS232` (blue) | Serial (RJ45 **shape**, not Ethernet) | Never treat as LAN. An Ethernet patch cable here does not give IP reachability |
| `USB-HOST` | Terminal is USB **host** (peripherals into the reader) | Will **not** enumerate as Android ADB client on the Admin Box |
| `POWER` | Power only | Not a data path |
| `PINPAD` | PIN pad accessory | Not an Admin Box ADB path |

ADB/USB debugging to the Admin Box requires a USB **device/client** path into Windows
(typically `USB OTG` / micro-USB / Type-C client on the terminal body, or an authorized
service cable), plus an already-enabled USB debugging posture. Connecting the Admin Box
only to `USB-HOST` is expected to yield `USB_DEVICE_NOT_ENUMERATED` / empty `adb devices`
even when photos prove cables are seated.

### USB OTG / client discriminator chain

`USB-HOST` is not the OTG/client candidate. Treat these as ordered, independent facts:

```text
USB-HOST != USB-OTG/client candidate
physical attachment != enumeration
enumeration != ADB interface
ADB interface != authorization
authorization != READY
```

Classifier / agent rules:

```text
OPERATOR_PHYSICAL_ATTACHMENT_CONFIRMED  !=  WINDOWS_ANDROID_ADB_INTERFACE_ENUMERATED
WINDOWS_ANDROID_ADB_INTERFACE_ENUMERATED  !=  ADB_DEVICE_READY
ADB_DEVICE_UNAUTHORIZED  =  successful USB-client + ADB-transport discovery
USB_OTG_ADB_CAPABILITY absent  !=  REMOTE_CAPABILITY none
```

Typed probe outcomes already owned by `Probe-HHCCReaderAdb.cmd`:

| Observed condition | Typed state | Meaning |
| --- | --- | --- |
| No Android/PAX USB candidate on Admin Box | `USB_DEVICE_NOT_ENUMERATED` | No Windows Android/ADB client seen |
| Operator-confirmed micro-USB/OTG seated + still no Android/ADB/MTP | `USB_DEVICE_NOT_ENUMERATED` + `--otg-confirmed` next-action | **Deployment:** reject USB OTG ADB for this config; continue LAN/management |
| Android/PAX USB present, no ADB interface | `USB_DEVICE_ENUMERATED_NO_ADB_INTERFACE` | Physical/data path exists; ADB transport not exposed |
| Driver/interface unresolved | `USB_DRIVER_OR_INTERFACE_UNRESOLVED` | Host-side binding incomplete |
| `adb devices` shows unauthorized | `ADB_DEVICE_UNAUTHORIZED` | Transport works; attend RSA Allow, then rerun probe only |
| `adb devices` shows device | `ADB_DEVICE_READY` | Continue read-only inventory / exact-target network ADB / view-only cert |

### Live finding — Kiosk4 micro-USB/OTG (operator-corrected 2026-10-06)

Operator correction: the micro-USB/OTG cable **was already seated** while Admin Box probes returned
`USB_DEVICE_NOT_ENUMERATED` / empty `adb devices -l` (no Android, ADB, MTP, or PTP client; host tools
`ADB_HOST_READY`). Re-probe with that fact confirmed reproduced the same typed state.

```text
OPERATOR_OTG_MICROUSB_SEATED
+
USB_DEVICE_NOT_ENUMERATED
=
USB_OTG_ADB_CAPABILITY not a deployment transport in this configuration
```

PAX A80 datasheets still list `1 x micro-USB 2.0, OTG`, and vendor cable guides mention an OTG /
programming accessory path (e.g. CU100-related Type-A↔micro cable). So the receptacle is **not**
explained as a decorative hole. Open (UNKNOWN, not deployment-blocking) hypotheses for why Windows
saw nothing:

| Hypothesis | Class | Notes |
| --- | --- | --- |
| Charge / power-only cable (no data lines) | UNKNOWN | Host cannot distinguish without a known-good data cable |
| Device USB data functions gated / debugging off with no MTP either | UNKNOWN | Do **not** enable Developer Options to force ADB |
| Fleet policy / PayDroid lockdown disables client mode | UNKNOWN | Management-plane question |
| Vendor programming / accessory path needs specific PAX tool/cable | ADAPT | Datasheet OTG + programming cable refs; not Admin Box ADB |
| Wrong physical receptacle | REJECT for now | Operator identified micro-USB/OTG; do not re-litigate seat |

**ADOPT for deployment:** do not plan firmware/ops work on Admin Box ↔ Kiosk4 USB OTG ADB for this
reader configuration. **ADOPT for remote ops:** keep LAN / vendor management planes as the primary
control surfaces. Do not reopen exhausted menu / Netstat / Connectivity / HID work without new
evidence.

USB OTG and LAN planes remain independent. Screen text such as "local network is unreachable" is
network-plane evidence, not a reason to keep retrying this USB path.
