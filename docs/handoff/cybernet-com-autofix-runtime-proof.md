# Cybernet COM AutoFix runtime proof

## Sprint status

Runtime proof is **not complete**.

A local Windows workstation inspection was performed on 2026-07-10. The selected evidence directory was:

```text
C:\Temp\CybernetCOM\autofix_20260710_230348
```

The read-only inspection reported all required release artifacts as missing and zero bytes:

```text
COMNameArbiter-before.reg        False  0
device-parameters-before-01.reg False  0
device-parameters-before-02.reg False  0
device-parameters-before-03.reg False  0
device-parameters-before-04.reg False  0
autofix-summary.json            False  0
```

The inspector then stopped with:

```text
This run did not produce autofix-summary.json. Review autofix-transcript.txt for the failure point.
```

This is a valid fail-closed negative-path result for the evidence inspector. It confirms that a normal workstation, work box, or admin box cannot satisfy the hardware/state gate. It is not proof of eligible Cybernet behavior and must not be used to merge PR #156.

## Proof classification

| Proof level | Status | Evidence |
|---|---|---|
| Contract proof | Complete | AutoFix safety, launcher, mapping, backup, parser-helper, and inspector contracts are tracked. |
| Harness proof | Complete for readiness helpers | Parser and evidence-inspection helpers are integrated into Pester/static contracts. |
| Static test proof | Complete | Targeted Python contracts and GitHub Survey doctrine/Pester checks pass. |
| Build proof | Not applicable | No compiled build surface is introduced by this hotfix. |
| Launcher/browser proof | Incomplete | No successful target launcher completion was captured. The existence of a workstation `autofix_*` directory is not sufficient. |
| Command ACK proof | Partial | The workstation evidence-inspection command executed and returned a deterministic fail-closed result. |
| Behavior observed proof | Partial | Missing artifacts were reported accurately; stale path state was not reused; the inspector stopped before claiming success. |
| Live runtime proof | Not reached | No approved non-finalized Cybernet with the known COM3-COM6 condition was tested. |

## Required target gate

The next operator must confirm all of the following:

1. Exactly one approved Cybernet is selected.
2. The target is not finalized and is not app-bound.
3. The operator is physically/local to the target, not executing remotely from an admin box.
4. The current failed map is exactly `COM3,COM4,COM5,COM6`.
5. Exactly four active `Communications Port` devices are present.
6. FINTEK or approved MultiPortSerial hardware is detected without `-Force`.
7. No SmartLynx/final app install is in progress.
8. No USB/COM driver replacement is part of this sprint.
9. Runtime evidence remains under `C:\Temp\CybernetCOM\autofix_*` and outside git.

If any gate fails, stop. Do not use `-Force` unless separately lead-approved and recorded without raw machine identity.

## Cybernet test plan

Run these steps from the SysAdminSuite repository root on the selected Cybernet.

### 1. Repository preflight

```powershell
git status --short
git branch --show-current
git log --oneline --decorate -5
Test-Path .\scripts\Invoke-CybernetComPortAutoFix.ps1
Test-Path .\Run-CybernetComPortAutoFix-DryRun.cmd
```

Required state:

- branch is `feat/cybernet-com-port-autofix`
- both path checks return `True`
- worktree has no unrelated changes

### 2. Parser proof

```powershell
.\scripts\Test-CybernetComPortAutoFixParser.ps1
```

Required output:

```text
PARSE OK
```

### 3. Dry run only

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

Do not pass arguments. Do not run apply. Do not use `-Force`.

Required observations:

- target eligibility succeeds
- before map is `COM3,COM4,COM5,COM6`
- planned map is `COM1,COM2,COM3,COM4`
- final dry-run status is unambiguous
- no reboot or COM mutation occurs

### 4. Inspect evidence

```powershell
.\scripts\Inspect-CybernetComPortAutoFixEvidence.ps1
```

Required output includes:

```text
REGISTRY BACKUPS VALIDATED
```

Required files in the latest run directory:

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

All five `.reg` files and `autofix-summary.json` must be nonempty. `autofix-summary.json` must report:

```text
registry_backups.validated: true
```

### 5. Record dry-run proof

Update this tracked document with anonymized facts only:

```text
Target state: one approved non-finalized Cybernet, local operator present
Before map: COM3, COM4, COM5, COM6
Dry-run result: eligible, backups validated, planned COM3->COM1 / COM4->COM2 / COM5->COM3 / COM6->COM4
Evidence folder: C:\Temp\CybernetCOM\autofix_<timestamp> (not committed)
Force used: no
Raw evidence committed: no
```

Do not include hostname, asset tag, serial number, registry contents, screenshots, logs, or full raw JSON.

### 6. Controlled apply lane

Apply is a separate approved runtime-proof action. Only after the dry-run proof is reviewed and approved:

```cmd
Run-CybernetComPortAutoFix.cmd
```

After reboot:

```cmd
reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM
pnputil /enum-devices /class Ports
```

Required final map:

```text
COM1, COM2, COM3, COM4
```

## Current anonymized proof fields

| Field | Current value |
|---|---|
| Target state | Workstation negative path only; no Cybernet tested |
| Finalized/app-bound status | Not verified |
| Before map | Not captured on an eligible target |
| Dry-run result | Release-grade dry run not run |
| Workstation inspection | Failed closed; all required artifacts missing |
| Apply result | Not run |
| Reboot confirmation | Not run |
| After map | Not captured |
| Force used | No |
| Raw evidence committed | No |
