# Cybernet COM Port AutoFix

## Purpose

This local-only AutoFix is for Cybernets where Windows sees the FINTEK serial hardware but active serial ports are numbered incorrectly, commonly as `COM3` through `COM6` instead of `COM1` through `COM4`.

Use it only before final clinical app/device COM binding.

## Fast path for technicians

From the SysAdminSuite repo root on the affected Cybernet, run:

```cmd
Run-CybernetComPortAutoFix.cmd
```

The launcher requests Administrator permission if needed, then runs:

```powershell
scripts\Invoke-CybernetComPortAutoFix.ps1 -Apply -Restart
```

## What it does

1. Creates an evidence folder under `C:\Temp\CybernetCOM`.
2. Captures hostname, `SERIALCOMM`, Ports class, MultiPortSerial class, and PnP state.
3. Confirms the local pattern is safe: four active `Communications Port` devices and the known `COM3-COM6` failed map.
4. Confirms a FINTEK or multi-port serial device is present.
5. Exports `HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter`.
6. Clears the COM Name Arbiter `ComDB` reservation bitmap.
7. Reassigns the active local ports in sorted order:
   - `COM3` to `COM1`
   - `COM4` to `COM2`
   - `COM5` to `COM3`
   - `COM6` to `COM4`
8. Captures after-state evidence.
9. Restarts the Cybernet.

## Evidence output

Each run creates a timestamped folder like:

```text
C:\Temp\CybernetCOM\autofix_YYYYMMDD_HHMMSS
```

Expected artifacts include:

```text
hostname.txt
started-at.txt
serialcomm-before.txt
ports-before.txt
multiport-before.txt
pnp-before.json
COMNameArbiter-before.reg
port-mapping-plan.json
reg-export-output.txt
reg-reset-output.txt
serialcomm-after.txt
ports-after.txt
autofix-summary.json
autofix-transcript.txt
```

Do not commit these runtime evidence files to the repo.

## Dry run

To capture evidence and preview the mapping without applying the change:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

## Safety boundaries

- Local Cybernet only.
- No remote execution.
- No admin-box target mutation.
- No SmartLynx or final app install.
- No USB/COM driver replacement.
- The default launcher stops unless the known failed pattern is present.

## Escalation

Stop and escalate if:

- FINTEK or MultiPortSerial hardware is not detected.
- The active port set is not exactly four `Communications Port` devices.
- The failed map is not `COM3-COM6`.
- The device already completed final app/device COM binding.
- The script cannot export the COM Name Arbiter key.
