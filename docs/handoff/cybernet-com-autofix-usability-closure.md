# Cybernet COM AutoFix usability closure

## Sprint outcome

PR #156 now includes the requested follow-up hardening for the Cybernet COM AutoFix lane:

- progress/status output to avoid ambiguous hanging prompts
- per-device `Device Parameters` registry export before `PortName` changes
- clearer technician-facing launcher text and field docs
- factored PowerShell functions for future posture, GUI, or platform changes

## Operator path

Fast apply path from the affected Cybernet repo root:

```cmd
Run-CybernetComPortAutoFix.cmd
```

Dry-run path:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

The apply launcher runs the local script with `-Apply -Restart`. The dry-run launcher captures evidence and writes a mapping plan without applying changes or restarting.

## Safety boundaries

- Local Cybernet only.
- No remote execution.
- No admin-box target mutation.
- No SmartLynx or final app install.
- No USB/COM driver replacement.
- Default apply still stops unless the known COM3-COM6 pattern is present.

## Evidence additions

AutoFix continues to write timestamped folders under:

```text
C:\Temp\CybernetCOM\autofix_YYYYMMDD_HHMMSS
```

Registry backup now includes:

```text
COMNameArbiter-before.reg
device-parameters-before-01.reg
device-parameters-before-02.reg
device-parameters-before-03.reg
device-parameters-before-04.reg
```

`autofix-summary.json` records the registry backups and planned/applied mapping.

## Validation still needed on Windows

Run locally before trusting field rollout:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
python Tests\survey\test_cybernet_com_autofix_contracts.py
```

Controlled apply proof on a non-finalized Cybernet should confirm that COM1-COM4 sticks after reboot and that no runtime evidence was committed.
