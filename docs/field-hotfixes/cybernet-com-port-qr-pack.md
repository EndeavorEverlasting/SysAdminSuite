# Cybernet COM Port QR Pack

## Purpose

This package lets a technician pull QR-ready CMD snippets from SysAdminSuite while standing at a Cybernet that has FINTEK serial hardware present but COM ports numbered incorrectly.

Use the launcher:

```cmd
Run-CybernetComPortQrPack.cmd
```

The launcher reads `configs/hotfix-command-packs/cybernet-com-port-repair.pack.json`, builds a temporary Field Hotfix manifest for the selected step, and opens the existing Field Hotfixes GUI so the command appears as a scannable QR code.

## Operator sequence

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

## Boundaries

- No silent remote execution.
- No target mutation from the admin box.
- No SmartLynx or final app install.
- No USB/COM driver replacement in this QR pack.
- Do not scan reset/reboot snippets unless the operator is physically at the target and has captured evidence first.

## Evidence folder

All capture snippets write to:

```text
C:\Temp\CybernetCOM
```

Expected files include:

```text
serialcomm-before.txt
ports-before.txt
multiport-before.txt
COMNameArbiter-before.reg
serialcomm-after.txt
ports-after.txt
```
