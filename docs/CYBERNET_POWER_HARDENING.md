# Cybernet power and display-button hardening

## Operational truth

SysAdminSuite currently has two different button surfaces that must not be conflated.

### Proven Windows physical power-button control

`QRTasks/Set-PowerComfortDefaults.ps1` uses the canonical Windows physical power-button action GUID:

```text
7648efa3-dd9c-4e3e-b566-50f929386280
```

For every parsed power scheme it sets the AC and DC action index to `0`, which is **Do nothing** for the physical Windows power button. The local QRTask also exports power-scheme backups before applying its broader comfort preset.

`scripts/Invoke-SasCybernetPowerHardening.ps1` is the bounded network repair lane. It changes only this physical power-button action, verifies AC and DC values, writes local evidence, and does not stage a payload on the target.

### Unproven physical display/menu-button control

The physical Cybernet display/menu button is not the Windows Start-menu power button. Repository review found no proven Windows policy, registry value, HID contract, vendor API, firmware interface, or OSD control that disables it.

Do **not** use `UIBUTTON_ACTION = 0` as a substitute. That Windows setting maps the Start-menu power action to Sleep rather than disabling the Cybernet display/menu button.

The repository therefore reports:

```text
NOT_APPLIED_UNPROVEN
```

for the physical display/menu button. `QRTasks/Test-DisplayMenuButtonEvent.ps1` is a read-only local probe that records whether pressing the button produces a plausible Windows event. An observed event is evidence for a later bounded implementation. No event suggests a firmware-only or display-OSD path, but does not by itself prove that conclusion.

## Target input

Keep live target CSV files under an ignored approved intake root such as:

```text
targets/local/cybernet-power-hardening.csv
```

Accepted columns are `ComputerName`, `HostName`, `Hostname`, or `Target`.

Do not commit live target names.

## Request-only plan

`-WhatIf` validates target intake and writes a local plan. It does not open a remote session or mutate a workstation.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasCybernetPowerHardening.ps1 `
  -TargetsCsv .\targets\local\cybernet-power-hardening.csv `
  -WhatIf
```

Expected evidence root:

```text
survey/output/cybernet_power_hardening/<workflow-id>/
```

## Offline fixture proof

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasCybernetPowerHardening.ps1 `
  -ComputerName CYBERNET-FIXTURE-01 `
  -FixtureMode
```

Fixture proof does not contact a target and does not prove a real power-policy change.

## First authorized pilot

Use exactly one approved Cybernet and keep confirmation enabled.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasCybernetPowerHardening.ps1 `
  -ComputerName AUTHORIZED-CYBERNET `
  -AllowTargetMutation
```

The script prompts through `ShouldProcess` before the remote session. Verify the target name and approve only during the authorized change window.

## Bounded fleet run

After one pilot has behavior-observed proof, use an approved target CSV. The default maximum is 25 targets per run.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasCybernetPowerHardening.ps1 `
  -TargetsCsv .\targets\local\cybernet-power-hardening.csv `
  -AllowTargetMutation `
  -MaxTargets 25
```

The workflow uses one remote PowerShell session per target and does not pre-ping or scan the subnet.

## Evidence

Each run writes:

```text
cybernet_power_hardening_events.jsonl
cybernet_power_hardening_results.csv
cybernet_power_hardening_summary.json
operator_handoff.txt
```

A target is technically successful only when every parsed power scheme reports AC and DC action index `0` after application.

This proves the Windows physical power-button policy was applied and verified. It does not prove the physical display/menu button was disabled, and it does not replace an operator test of the actual Cybernet button behavior.

## Display/menu-button probe

Run on one representative Cybernet while physically present:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\QRTasks\Invoke-TechTask.ps1 `
  -Task DisplayMenuButtonProbe
```

The probe writes under `GetInfo\Output\QRTasks` and returns one of:

- `OBSERVED_WINDOWS_EVENT`
- `NO_WINDOWS_EVENT_OBSERVED`

Preserve the local report outside git. A later firmware or OSD sprint must name the exact Cybernet model, control surface, rollback path, and live proof gate before it can claim the display/menu button is disabled.
