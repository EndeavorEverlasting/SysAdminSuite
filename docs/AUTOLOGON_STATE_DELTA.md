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

The implementation is:

- PowerShell collector: `scripts/Invoke-SasAutoLogonStateDelta.ps1`
- Bash-on-Windows entrypoint: `survey/sas-autologon-state-delta.sh`

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
delta, CSV, JSON, screenshot, or handoff artifacts.

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
log, transcript, report, manifest, or evidence file on the target workstation.

## Target contract

Use an explicit hostname or an approved local CSV. Batch CSVs may use any one of these columns:

```text
ComputerName
HostName
Hostname
Target
```

Live target material belongs under ignored local roots such as `targets/local/`; it must not be
committed. The collector caps a run at 25 targets by default. Use smaller pilot batches first.

## Pilot workflow

### 1. Prepare the approved pilot manifest

Example local file:

```text
targets/local/autologon-pilot.csv
```

```csv
ComputerName
WORKSTATION001
WORKSTATION002
```

### 2. Capture the baseline

Bash-on-Windows:

```bash
bash survey/sas-autologon-state-delta.sh \
  --mode before \
  --manifest targets/local/autologon-pilot.csv \
  --technician-label "Auto-logon pilot A"
```

Windows PowerShell:

```powershell
.\scripts\Invoke-SasAutoLogonStateDelta.ps1 `
  -Mode Before `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -TechnicianLabel 'Auto-logon pilot A'
```

Record the generated run ID from console output and `operator_handoff.txt`.

### 3. Run the approved auto-logon deployment

Use the existing authorized technician or deployment path. Do not broaden the target list, rerun
failed targets blindly, or place credentials into command history or logs.

The evidence lane is read-only. The deployment lane remains separately authorized target mutation.

### 4. Capture and compare the final state

Bash-on-Windows:

```bash
bash survey/sas-autologon-state-delta.sh \
  --mode after \
  --run-id autologon-delta-YYYYMMDD-HHMMSS-xxxxxxxx \
  --manifest targets/local/autologon-pilot.csv \
  --technician-label "Auto-logon pilot A"
```

Windows PowerShell:

```powershell
.\scripts\Invoke-SasAutoLogonStateDelta.ps1 `
  -Mode After `
  -RunId autologon-delta-YYYYMMDD-HHMMSS-xxxxxxxx `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -TechnicianLabel 'Auto-logon pilot A'
```

After mode may reuse targets stored in the baseline when the same approved manifest is unavailable,
but passing the same manifest makes the operator intent clearest.

## Decisions

Each workstation receives one primary decision:

| Decision | Meaning |
|---|---|
| `CONFIRMED_STATE_TRANSITION` | Before was not ready; after shows enabled auto-logon with the expected hostname-based user. |
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

To inspect a workstation without a baseline:

```bash
bash survey/sas-autologon-state-delta.sh \
  --mode assess \
  --computer WORKSTATION001
```

This reports current posture only. It cannot establish when the state changed.

## Offline fixture proof

Fixture mode performs no network activity and no target mutation:

```bash
bash survey/sas-autologon-state-delta.sh \
  --mode before \
  --computer SAMPLE001 \
  --fixture-mode
```

Then rerun with `--mode after` and the emitted run ID. The synthetic after state should produce
`CONFIRMED_STATE_TRANSITION`. Fixture success is contract proof only; it is not live workstation
proof.

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
