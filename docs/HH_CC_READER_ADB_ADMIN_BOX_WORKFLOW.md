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
