# Cybernet COM Port QR Pack

## Purpose

This package lets a technician pull QR-ready CMD snippets from SysAdminSuite while standing at a Cybernet that has FINTEK serial hardware present but COM ports numbered incorrectly.

Use the QR menu launcher:

```cmd
Run-CybernetComPortQrPack.cmd
```

Use the one-shot local AutoFix launcher when the suite is already on the affected Cybernet:

```cmd
Run-CybernetComPortAutoFix.cmd
```

The QR launcher reads `configs/hotfix-command-packs/cybernet-com-port-repair.pack.json`, builds a temporary Field Hotfix manifest for the selected step, and opens the existing Field Hotfixes GUI so the command appears as a scannable QR code.

## Fast AutoFix path

Run this from the SysAdminSuite repo root on the affected Cybernet:

```cmd
Run-CybernetComPortAutoFix.cmd
```

The AutoFix captures evidence, exports COM Name Arbiter, exports each active COM device `Device Parameters` key, resets the COM reservation bitmap, assigns the active ports in sorted order from COM3-COM6 to COM1-COM4, captures after-state evidence, and restarts.

The launcher and script now print a progress bar plus plain status lines. A technician should wait for one of these final statuses:

```text
DRY RUN COMPLETE
COMPLETE
FAILED
REBOOTING
```

If the console says `FAILED`, stop and review the evidence folder before retrying.

## Manual operator sequence

1. Make evidence folder.
2. Capture `SERIALCOMM` before.
3. Capture Ports class before.
4. Capture MultiPortSerial class before.
5. Open hidden-device Device Manager.
6. In Device Manager, choose `View > Show hidden devices`.
7. Expand `Ports (COM & LPT)` and `Multi-port serial adapters`.
8. Do not remove active `FINTEK PCIe To Serial`.
9. If ports remain COM3-COM6, manually assign:
   - COM3 to COM1
   - COM4 to COM2
   - COM5 to COM3
   - COM6 to COM4
10. If COM1/COM2 are still unavailable, export COM Name Arbiter.
11. Reset COM Name Arbiter only after export and lead/operator approval.
12. Reboot.
13. Capture `SERIALCOMM` after.
14. Capture Ports class after.
15. Open the evidence folder and review the captured text files.

## Menu

| Menu | Snippet | Purpose |
|---:|---|---|
| 1 | Make evidence folder | Creates `C:\Temp\CybernetCOM`. |
| 2 | Capture SERIALCOMM before | Captures the pre-change serial device map. |
| 3 | Capture Ports before | Captures pre-change Ports class devices. |
| 4 | Capture MultiPortSerial before | Captures pre-change FINTEK/multi-port state. |
| 5 | Show hidden Device Manager | Opens Device Manager for hidden-device inspection. |
| 6 | Export COM Name Arbiter | Exports COM Name Arbiter before reset. |
| 7 | Reset COM Name Arbiter | Clears the COM reservation bitmap. |
| 8 | Reboot Cybernet | Reboots after reset or manual assignment. |
| 9 | Capture SERIALCOMM after | Captures the post-change serial device map. |
| 10 | Capture Ports after | Captures post-change Ports class devices. |
| 11 | Open evidence folder | Opens the evidence folder. |
| 12 | Run automated COM AutoFix | Runs the local AutoFix launcher from the repo root. |

## Boundaries

- No silent remote execution.
- No target mutation from the admin box.
- No SmartLynx or final app install.
- No USB/COM driver replacement in this QR pack.
- Do not scan reset/reboot/AutoFix snippets unless the operator is physically at the target and has captured or accepted evidence first.

## Evidence folder

All capture snippets write to:

```text
C:\Temp\CybernetCOM
```

AutoFix runs write timestamped evidence folders under:

```text
C:\Temp\CybernetCOM\autofix_YYYYMMDD_HHMMSS
```

Expected files include:

```text
serialcomm-before.txt
ports-before.txt
multiport-before.txt
COMNameArbiter-before.reg
device-parameters-before-01.reg
device-parameters-before-02.reg
device-parameters-before-03.reg
device-parameters-before-04.reg
port-mapping-plan.json
serialcomm-after.txt
ports-after.txt
autofix-summary.json
autofix-transcript.txt
```
