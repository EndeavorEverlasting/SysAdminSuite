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

## Dry run

When unsure, run the dry path first:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

Dry run captures evidence, exports registry backups, builds the planned COM mapping, writes a summary, and stops before changing `PortName` values or rebooting.

Every registry export must return exit code 0 and create a nonempty `.reg` file. If the COM Name Arbiter export or any per-device `Device Parameters` export fails validation, AutoFix reports `FAILED` and stops before any COM registry mutation.

## Progress and final status

The script now shows a progress bar plus plain console lines so a technician can tell whether it is still working, safely stopped, failed, or rebooting.

Expected phases:

1. Evidence setup
2. Before-state capture
3. Eligibility checks
4. Registry backup
5. Mapping plan
6. Apply changes
7. After-state capture
8. Summary
9. Restart

Expected final statuses:

```text
DRY RUN COMPLETE
COMPLETE
FAILED
REBOOTING
```

If the console says `FAILED`, stop and review the evidence folder before retrying.

## What apply mode does

1. Creates an evidence folder under `C:\Temp\CybernetCOM`.
2. Captures hostname, `SERIALCOMM`, Ports class, MultiPortSerial class, and PnP state.
3. Confirms the local pattern is safe: four active `Communications Port` devices and the known `COM3-COM6` failed map.
4. Confirms a FINTEK or multi-port serial device is present.
5. Exports `HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter`.
6. Exports each active COM device `Device Parameters` registry key before changing `PortName`.
7. Validates that all five registry exports exist and are nonempty.
8. Clears the COM Name Arbiter `ComDB` reservation bitmap.
9. Reassigns the active local ports in sorted order:
   - `COM3` to `COM1`
   - `COM4` to `COM2`
   - `COM5` to `COM3`
   - `COM6` to `COM4`
10. Captures after-state evidence.
11. Restarts the Cybernet.

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
device-parameters-before-01.reg
device-parameters-before-02.reg
device-parameters-before-03.reg
device-parameters-before-04.reg
port-mapping-plan.json
reg-export-output.txt
reg-reset-output.txt
serialcomm-after.txt
ports-after.txt
autofix-summary.json
autofix-transcript.txt
```

For eligible dry-run and apply paths, `autofix-summary.json` records `registry_backups.validated: true`, the COM Name Arbiter backup path and size, and each per-device backup path, size, and validation result.

Do not commit these runtime evidence files to the repo.

## Safety boundaries

- Local Cybernet only.
- No remote execution.
- No admin-box target mutation.
- No SmartLynx or final app install.
- No USB/COM driver replacement.
- The default launcher stops unless the known failed pattern is present.
- Do not continue final app binding until COM1-COM4 sticks after reboot.

## Escalation

Stop and escalate if:

- FINTEK or MultiPortSerial hardware is not detected.
- The active port set is not exactly four `Communications Port` devices.
- The failed map is not `COM3-COM6`.
- The device already completed final app/device COM binding.
- The script cannot export the COM Name Arbiter key.
- The script cannot export any `device-parameters-before-*.reg` file.
- Any registry backup is missing or empty.
- The script reports `FAILED` instead of `COMPLETE`, `DRY RUN COMPLETE`, or `REBOOTING`.
