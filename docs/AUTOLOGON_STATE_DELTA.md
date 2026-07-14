# Auto-logon workstation state delta

## Purpose

This workflow answers a practical field question:

```text
What was true on this workstation before auto-logon work, what is true afterward,
and is there enough evidence to say that the workstation changed into the expected state?
```

It does **not** install auto-logon by itself. It wraps read-only evidence around the existing,
approved technician or deployment lane:

```text
approved target list
  -> capture Before state
  -> technician or deployment lane performs approved auto-logon work
  -> capture After state
  -> compare the two snapshots
  -> review one decision per workstation
```

## Technician entry point

Technicians should not compose PowerShell commands, remember a run ID, or re-enter the target list.

Double-click this repository launcher:

```text
Run-AutoLogonStateDelta.cmd
```

The menu provides four actions:

```text
[1] Capture BEFORE state
[2] Capture AFTER state and compare automatically
[3] Assess current state only
[4] Open latest evidence folder
```

For the normal pilot:

1. Double-click `Run-AutoLogonStateDelta.cmd` and choose option 1.
2. Select the approved target CSV in the Windows file picker. When
   `targets/local/autologon-pilot.csv` already exists, accept the saved default.
3. Enter an assignment label or press Enter to accept the generated dated label.
4. Let the approved AutoLogon installation work occur.
5. Double-click the same launcher and choose option 2.
6. Review the evidence folder that opens automatically.

The launcher remembers:

- the generated run ID;
- the approved baseline target set;
- the assignment label;
- whether the run is waiting for its After capture;
- the latest evidence folder.

The local workflow state is stored at:

```text
survey/output/autologon_state_delta/operator-state.json
```

It contains workflow metadata only. It does not contain credentials or password values.

### Fail-closed behavior

- A new baseline is blocked while the saved baseline is still waiting for its After capture.
- After mode automatically reuses the targets stored in the baseline.
- When state is missing but exactly one incomplete baseline exists, that baseline is recovered.
- When more than one incomplete baseline exists, the interactive menu asks which one to finish.
- Noninteractive automation fails and requires an explicit `-RunId` when the choice is ambiguous.

## Implementation surfaces

- Double-click launcher: `Run-AutoLogonStateDelta.cmd`
- Stateful technician orchestrator: `scripts/Start-SasAutoLogonStateDelta.ps1`
- Canonical collector and comparer: `scripts/Invoke-SasAutoLogonStateDelta.ps1`
- Bash-on-Windows direct wrapper: `survey/sas-autologon-state-delta.sh`

The launcher delegates to the canonical collector rather than duplicating snapshot or comparison
logic.

## What it captures

Each snapshot records bounded workstation evidence:

| Evidence group | Examples |
|---|---|
| Host identity | computer name, domain, manufacturer, model, BIOS serial |
| Windows state | OS version/build, last boot time, logged-on user |
| Auto-logon posture | `SetAutoLogon`, `AutoAdminLogon`, `DefaultUserName`, `DefaultDomainName`, `ForceAutoLogon`, `AutoLogonCount` |
| Credential-presence signal | whether the `DefaultPassword` **value name** exists |
| Installed applications | 64-bit and 32-bit uninstall-registry inventory |
| Related runtime surfaces | selected services and scheduled tasks matching auto-logon, Imprivata, Citrix, VMware/Horizon, or Epic terms |
| Reboot posture | component servicing, Windows Update, and pending-file-rename indicators |

The collector does not use the `Win32_Product` class because that query can be disruptive. It reads
installed software from the normal uninstall registry keys.

## Credential boundary

The workflow never reads or exports the data stored in Winlogon's `DefaultPassword` value. It only
uses the registry key's value-name list to record this boolean:

```text
default_password_present: true|false
default_password_value_collected: false
```

Do not add password data, secret values, deployment credentials, or account passwords to snapshot,
delta, CSV, JSON, screenshot, state, or handoff artifacts.

## Evidence location

All SysAdminSuite evidence stays on the admin workstation under:

```text
survey/output/autologon_state_delta/<run_id>/
```

Typical run contents:

```text
before/<target>.json
after/<target>.json
current/<target>.json
delta/<target>.json
run_manifest_before.json
run_manifest_after.json
autologon_state_delta_summary.csv
autologon_state_delta_summary.json
operator_handoff.txt
```

The remote collector returns objects through the PowerShell session. It does not place a script,
log, transcript, report, manifest, state file, or evidence file on the target workstation.

## Target contract

Use an explicit hostname or an approved local CSV. Batch CSVs may use any one of these columns:

```text
ComputerName
HostName
Hostname
Target
```

Live target material belongs under ignored local roots such as `targets/local/`; it must not be
committed. The collector caps a run at 25 targets by default. Use a two-workstation pilot first.

Example local file:

```text
targets/local/autologon-pilot.csv
```

```csv
ComputerName
WORKSTATION001
WORKSTATION002
```

## Decisions

Each workstation receives one primary decision:

| Decision | Meaning |
|---|---|
| `CONFIRMED_STATE_TRANSITION` | Before was not ready; after shows enabled auto-logon, the expected hostname-based user, and password-value presence. |
| `ALREADY_CONFIGURED_BEFORE` | The baseline was already ready, so the later state does not prove new work. |
| `NO_MATERIAL_CHANGE` | No auto-logon registry/status change was detected. |
| `PARTIAL_CHANGE_REVIEW` | Some values changed, but the final state is not fully ready. |
| `REGRESSION_REVIEW` | The workstation was ready before but is not ready afterward. |
| `INCONCLUSIVE` | A snapshot was missing or collection failed. |

Installed-software additions and version changes are supporting evidence. Auto-logon can be a
registry configuration rather than an installed application, so absence from Installed Apps does
not by itself mean the work was not performed.

## Attribution limit

A workstation delta proves state, not human identity.

`TechnicianLabel` records the assigned batch or technician name supplied by the operator. The output
always records:

```text
technician_execution_proven: false
actor_attribution: not_proven_by_state_delta
```

To establish who executed a change, correlate this state evidence with the approved work assignment,
deployment run records, ticket history, and normal Windows or endpoint audit telemetry. This workflow
does not clear, suppress, or replace those records.

## Current-state assessment

Double-click `Run-AutoLogonStateDelta.cmd` and choose option 3. This reports current posture only; it
cannot establish when the state changed.

## Direct script API

The commands below are for automation, CI, and advanced administrators. They are not the normal
technician procedure.

A noninteractive baseline can be created with:

```powershell
.\scripts\Start-SasAutoLogonStateDelta.ps1 `
  -Action Before `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -TechnicianLabel 'Auto-logon pilot A' `
  -NonInteractive
```

The saved baseline can then be completed without repeating the run ID, target CSV, or label:

```powershell
.\scripts\Start-SasAutoLogonStateDelta.ps1 `
  -Action After `
  -NonInteractive
```

When multiple incomplete baselines intentionally exist, advanced automation must supply the selected
`-RunId` explicitly. The lower-level collector remains available for harness composition, but it is
not a field memorization contract.

## Offline fixture proof

Fixture mode performs no network activity and no target mutation. The stateful launcher itself can be
proved end to end:

```powershell
$runId = 'autologon-delta-20260713-170000-1a2b3c4d'
$outputRoot = Join-Path $PWD 'survey\output\autologon_state_delta'

.\scripts\Start-SasAutoLogonStateDelta.ps1 `
  -Action Before `
  -ComputerName SAMPLE001 `
  -RunId $runId `
  -OutputRoot $outputRoot `
  -TechnicianLabel synthetic-ci `
  -FixtureMode `
  -NonInteractive `
  -NoOpen

.\scripts\Start-SasAutoLogonStateDelta.ps1 `
  -Action After `
  -OutputRoot $outputRoot `
  -FixtureMode `
  -NonInteractive `
  -NoOpen
```

The second call discovers the saved run automatically. It should produce one
`CONFIRMED_STATE_TRANSITION`. Fixture success is contract proof only; it is not live workstation
proof.

## Repository validation

Run the focused contracts before a live pilot:

```powershell
python .\Tests\survey\test_autologon_state_delta_contracts.py

$paths = @(
  '.\scripts\Invoke-SasAutoLogonStateDelta.ps1',
  '.\scripts\Start-SasAutoLogonStateDelta.ps1'
)
foreach ($path in $paths) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $path),
    [ref]$tokens,
    [ref]$errors
  )
  if ($errors.Count -gt 0) { throw "$path has $($errors.Count) parser error(s)." }
}
```

From Git Bash or another Bash-on-Windows shell:

```bash
bash -n survey/sas-autologon-state-delta.sh
```

The dedicated GitHub Actions workflow runs the stateful launcher through a synthetic Before/After
pair and requires exactly one `CONFIRMED_STATE_TRANSITION` without network activity or target
mutation.

## Pilot acceptance gate

Before expanding beyond the first two workstations, require:

1. Both baseline snapshots collected successfully.
2. The approved auto-logon lane ran against only those two targets.
3. Both after snapshots collected successfully.
4. Expected transitions are classified correctly.
5. At least one reboot/logon observation confirms the configured account actually logs on.
6. No password data appears in local artifacts.
7. No SysAdminSuite evidence or staging remains on the targets.

The registry delta proves configuration posture. A real reboot and observed auto-logon remain the
strongest runtime proof that the workstation behaves as intended.
