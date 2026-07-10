# Cybernet COM AutoFix runtime proof

## Sprint status

Runtime proof was not executed in this pass.

This sprint requires physical/local access to exactly one approved, non-finalized Cybernet that currently shows the known `COM3-COM6` failure pattern. The available execution environment only has connector-side GitHub access. It has no local target Cybernet, no Windows registry/device state, no `C:\Temp\CybernetCOM` evidence folder, and no safe way to run the local launchers without violating the no-remote-execution boundary.

## Proof level

- Contract/static proof exists on PR #156 through the committed AutoFix contracts and docs.
- Runtime proof is **not complete**.
- Operator acceptance is **not complete**.

Do not treat this document as field success proof.

## Required target gate before running

The next operator must confirm all of the following before apply mode:

1. Exactly one target Cybernet is selected.
2. The target is not finalized and is not already app-bound.
3. The operator is physically/local to the target, not remote-executing from an admin box.
4. No SmartLynx/final app install is in progress.
5. No USB/COM driver replacement is planned in this sprint.
6. Dry run shows FINTEK or MultiPortSerial hardware present.
7. Dry run shows exactly four active `Communications Port` devices.
8. Dry run shows the known failed map `COM3,COM4,COM5,COM6`.
9. Dry run writes `autofix-summary.json`, `port-mapping-plan.json`, `COMNameArbiter-before.reg`, and `device-parameters-before-*.reg` under a timestamped `C:\Temp\CybernetCOM\autofix_*` folder.
10. Registry backups are present, nonempty, and recorded as validated in `autofix-summary.json`.

If any gate fails, do not run apply mode. Do not use `-Force` unless lead-approved and recorded in a tracked summary without raw evidence.

## Commands to run on the target

From the SysAdminSuite repo root on the affected Cybernet:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

Review, but do not commit:

```text
C:\Temp\CybernetCOM\autofix_*\autofix-summary.json
C:\Temp\CybernetCOM\autofix_*\port-mapping-plan.json
C:\Temp\CybernetCOM\autofix_*\COMNameArbiter-before.reg
C:\Temp\CybernetCOM\autofix_*\device-parameters-before-*.reg
```

If eligible and approved:

```cmd
Run-CybernetComPortAutoFix.cmd
```

After reboot:

```cmd
reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM
pnputil /enum-devices /class Ports
```

## Anonymized proof fields to fill after real execution

| Field | Current value |
|---|---|
| Target state | Not verified in this pass |
| Finalized/app-bound status | Not verified in this pass |
| Before map | Not captured in this pass |
| Dry-run result | Not run in this pass |
| Apply result | Not run in this pass |
| Reboot confirmation | Not run in this pass |
| After map | Not captured in this pass |
| Evidence folder path | Not created in this pass |
| Force used | No |
| Raw evidence committed | No |

## Required success wording after proof

Only after successful local execution, update this file with anonymized values like:

```text
Target state: one non-finalized Cybernet, local operator present
Before map: COM3, COM4, COM5, COM6
Dry-run result: eligible, backups validated, planned COM3->COM1 / COM4->COM2 / COM5->COM3 / COM6->COM4
Apply result: applied, restart requested
After map: COM1, COM2, COM3, COM4 after reboot
Evidence folder path: C:\Temp\CybernetCOM\autofix_<timestamp> (not committed)
Raw evidence committed: no
```

Do not include hostname, asset tag, serial number, registry export contents, logs, screenshots, or full raw JSON in the tracked proof summary.
