# Cybernet COM AutoFix runtime proof

## Sprint status

Runtime proof is **not complete**.

PR #165 contains the current clean release lane. PR #156 is development history and must not be used as the merge or runtime-proof base.

A prior normal-workstation inspection returned a valid fail-closed result because no eligible Cybernet evidence existed. That proved only that the inspector rejected missing artifacts. It did not prove COM mapping, mutation, reboot, or persistence.

## Proof classification

| Proof level | Status | Meaning |
|---|---|---|
| Contract proof | Complete in focused CI | Tracked safety, mapping, launch, backup, and no-remote-execution contracts pass. |
| Parser proof | Complete in focused CI | The tracked AutoFix script parses through PowerShell's parser API. |
| Readiness-helper proof | Complete in focused CI | Missing roots and legitimate already-correct summaries are handled deterministically. |
| Technician launcher proof | Static/smoke only | Launch and help surfaces exist; no target repair is inferred. |
| Dry-run proof | Not reached | No approved eligible Cybernet dry run has been recorded. |
| Live apply/reboot proof | Not reached | No approved target mutation has been performed through this lane. |
| Persistence proof | Not reached | COM1-COM4 has not yet been confirmed after reboot. |

## Required target gate

The operator must confirm all of the following before any target run:

1. Exactly one approved Cybernet is selected.
2. The target is not finalized and is not app-bound.
3. The operator is physically/local to the target, not remotely mutating it from an admin box.
4. Exactly four active `Communications Port` devices are present.
5. The current failed map is exactly `COM3,COM4,COM5,COM6`.
6. FINTEK or approved MultiPortSerial hardware is detected without `-Force`.
7. No SmartLynx/final app installation is in progress.
8. No USB/COM driver replacement is part of the proof.
9. Runtime evidence stays under `C:\Temp\CybernetCOM\autofix_*` and outside Git.

If any gate fails, stop. `-Force` is not part of the technician launcher and may be used only through direct script invocation after separate lead approval.

## Controlled test plan

Run from the SysAdminSuite repository root on the selected Cybernet.

### 1. Repository preflight

PowerShell:

```powershell
git status --short
git branch --show-current
git log --oneline --decorate -5
Test-Path .\scripts\Invoke-CybernetComPortAutoFix.ps1
Test-Path .\scripts\Start-CybernetComPortAutoFix.ps1
Test-Path .\Run-CybernetComPortAutoFix-DryRun.cmd
```

Bash on Windows:

```bash
git status --short
git branch --show-current
git log --oneline --decorate -5
test -f scripts/Invoke-CybernetComPortAutoFix.ps1
test -f scripts/Start-CybernetComPortAutoFix.ps1
test -f Run-CybernetComPortAutoFix-DryRun.cmd
```

Required state:

- branch is `feat/cybernet-com-port-release` or the merged `main` containing PR #165;
- all tracked path checks succeed;
- the worktree has no unrelated changes.

### 2. Parser proof

PowerShell:

```powershell
.\scripts\Test-CybernetComPortAutoFixParser.ps1
```

Bash on Windows:

```bash
powershell.exe -NoProfile -File ./scripts/Test-CybernetComPortAutoFixParser.ps1
```

Required output:

```text
PARSE OK
```

### 3. Dry run only

Command Prompt:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

PowerShell:

```powershell
& .\Run-CybernetComPortAutoFix-DryRun.cmd
```

Bash on Windows:

```bash
cmd.exe /d /c Run-CybernetComPortAutoFix-DryRun.cmd
```

Do not pass arguments. The dry-run lane must not reboot or write `PortName` values.

Required observations:

- target eligibility succeeds;
- before map is `COM3,COM4,COM5,COM6`;
- planned map is `COM1,COM2,COM3,COM4`;
- final status is `DRY RUN COMPLETE`;
- no reboot or COM mutation occurs.

An already-correct target is a legitimate no-op: the summary status is `already-correct`, the inspector reports `ALREADY CORRECT`, and no registry backups are expected because no mutation was planned.

### 4. Inspect evidence

PowerShell:

```powershell
.\scripts\Inspect-CybernetComPortAutoFixEvidence.ps1
```

Bash on Windows:

```bash
powershell.exe -NoProfile -File ./scripts/Inspect-CybernetComPortAutoFixEvidence.ps1
```

For an eligible COM3-COM6 dry run, required output includes:

```text
REGISTRY BACKUPS VALIDATED
```

Required nonempty files:

```text
COMNameArbiter-before.reg
device-parameters-before-01.reg
device-parameters-before-02.reg
device-parameters-before-03.reg
device-parameters-before-04.reg
autofix-summary.json
port-mapping-plan.json
autofix-transcript.txt
```

The summary must report `registry_backups.validated: true`.

### 5. Record dry-run proof

Record anonymized facts only:

```text
Target state: one approved non-finalized Cybernet, local operator present
Before map: COM3, COM4, COM5, COM6
Dry-run result: eligible; backups validated
Planned map: COM3->COM1 / COM4->COM2 / COM5->COM3 / COM6->COM4
Evidence folder: C:\Temp\CybernetCOM\autofix_<timestamp> (not committed)
Force used: no
Raw evidence committed: no
```

Never include hostname, asset tag, serial number, PnP device ID, registry contents, screenshots, transcripts, or full raw JSON.

### 6. Controlled apply and reboot

Only after the dry-run proof is reviewed and approved.

Command Prompt:

```cmd
Run-CybernetComPortAutoFix.cmd
```

PowerShell:

```powershell
& .\Run-CybernetComPortAutoFix.cmd
```

Bash on Windows:

```bash
cmd.exe /d /c Run-CybernetComPortAutoFix.cmd
```

The launcher accepts no arguments, runs the tracked elevation helper synchronously, applies the guarded mapping, writes evidence, and requests reboot.

After reboot, inspect with either shell.

Command Prompt:

```cmd
reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM
pnputil /enum-devices /class Ports
```

Bash on Windows:

```bash
cmd.exe /d /c 'reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM'
cmd.exe /d /c 'pnputil /enum-devices /class Ports'
```

Required final map:

```text
COM1, COM2, COM3, COM4
```

Do not continue final app binding until the map persists after reboot.

## Current anonymized proof fields

| Field | Current value |
|---|---|
| Target state | No approved eligible Cybernet proof recorded |
| Finalized/app-bound status | Not verified |
| Before map | Not captured on an eligible target |
| Dry-run result | Not run on an eligible target |
| Registry backup result | Not proven on an eligible target |
| Apply result | Not run |
| Reboot confirmation | Not run |
| After map | Not captured |
| Force used | No |
| Raw evidence committed | No |
