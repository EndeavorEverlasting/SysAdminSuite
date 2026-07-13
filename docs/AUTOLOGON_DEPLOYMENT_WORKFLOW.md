# AutoLogon deployment workflow

## Purpose

This workflow deploys the approved auto-logon package from the approved read-only software share while preserving a reviewable before/install/after evidence chain on the admin box.

Canonical package:

```text
\\nt2kwb972sms01\packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe
```

Entrypoint:

```text
scripts\Invoke-SasAutoLogonDeployment.ps1
```

The workflow composes existing SysAdminSuite contracts instead of creating another installer engine:

```text
explicit target list
  -> read-only baseline snapshot
  -> skip baseline failures
  -> skip workstations already configured
  -> install eligible targets through Invoke-SasSoftwareInstall.ps1
  -> read-only after snapshot
  -> per-workstation state delta
  -> combined local JSONL, JSON, and operator handoff
```

## Why this does not use the Startup folder

A command in a Startup folder is a persistence mechanism and leaves a target-side script until a user logs on. It also makes execution identity, timing, cleanup, and administrative evidence less predictable.

This workflow uses the existing `CopyThenInstall` mode by default:

- the admin box reads the approved share;
- the installer is copied into a run-specific `%ProgramData%\SysAdminSuite\SoftwareInstall\<run_id>` directory;
- the existing install wrapper launches the installer;
- SysAdminSuite-owned staging is removed after the installer exits;
- cleanup failures and possible remnants are reported;
- installer-owned changes and normal Windows, endpoint, and application evidence are preserved.

No Startup-folder CMD, Run key, scheduled task, service, hidden listener, or background agent is created.

## Safety gates

- Explicit target names only.
- Maximum 25 targets per invocation.
- No install when baseline collection fails.
- No reinstall when baseline already reports `autologon_ready`.
- Live execution requires `-AllowTargetMutation`.
- Live execution requires explicit vendor-validated `-InstallerArguments`.
- The source root must match the approved root in `harness/api/sas-harness-api.json`.
- `-WhatIf` performs request validation only: no share read, target read, remote session, copy, or installer execution.
- `-FixtureMode` performs offline end-to-end contract proof with synthetic state and a planned install.
- SysAdminSuite evidence remains under the gitignored admin-box output root.
- `DefaultPassword` data is never collected.
- Event logs, monitoring, endpoint tooling, and installer evidence are not suppressed or cleared.

## Target CSV

Create a local, uncommitted file such as `targets\local\autologon-pilot.csv`:

```csv
ComputerName
WORKSTATION001
WORKSTATION002
```

Start with two approved pilot workstations. Do not put credentials or passwords in the CSV.

## 1. Offline end-to-end proof

This does not contact the share or any workstation:

```powershell
.\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -ComputerName SAMPLE001 `
  -FixtureMode
```

Expected status:

```text
FIXTURE_PASS
```

Expected local artifacts:

```text
survey\output\autologon_deployment\<workflow_id>\
  autologon_deployment_events.jsonl
  autologon_deployment_summary.json
  operator_handoff.txt
  state\
  install\
```

## 2. Request-only dry run for the real pilot manifest

This validates target intake, approved source resolution, relative-path safety, output boundaries, and install planning without contacting the share or workstations:

```powershell
.\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -InstallerRelativePath 'packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe' `
  -InstallMode CopyThenInstall `
  -WhatIf
```

Expected status:

```text
PLANNED_WHATIF
```

## 3. Verify silent installer arguments

Before live execution, validate the executable's supported silent switches from the approved package owner, vendor documentation, or a controlled local test. Do not assume that `/quiet /norestart` is accepted by every EXE.

The live workflow deliberately refuses to run when `-InstallerArguments` is omitted.

## 4. Two-workstation approved pilot

Replace the example arguments with the validated switches:

```powershell
.\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -InstallerRelativePath 'packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe' `
  -InstallerArguments @('<validated-silent-switch-1>', '<validated-silent-switch-2>') `
  -InstallMode CopyThenInstall `
  -TechnicianLabel 'AutoLogon pilot' `
  -AllowTargetMutation `
  -Confirm:$false
```

The workflow will:

1. capture baseline evidence;
2. exclude failed baselines and already-configured workstations;
3. install only eligible workstations;
4. clean and report SysAdminSuite-owned staging;
5. capture after evidence;
6. emit the combined summary and per-workstation delta.

## 5. Review before expansion

Open:

```text
survey\output\autologon_deployment\<workflow_id>\operator_handoff.txt
survey\output\autologon_deployment\<workflow_id>\autologon_deployment_summary.json
```

Expansion gates:

- no baseline collection failures;
- no install failures;
- no cleanup failures;
- no SysAdminSuite-owned target remnants;
- expected `CONFIRMED_STATE_TRANSITION` or justified `ALREADY_CONFIGURED_BEFORE`;
- no `PARTIAL_CHANGE_REVIEW`, `REGRESSION_REVIEW`, or `INCONCLUSIVE`;
- at least one real reboot and observed successful auto-logon on each pilot workstation.

The registry and installed-software delta proves workstation state. It does not prove which human performed the work.

## Operational notes

- `CopyThenInstall` avoids the common remote UNC second-hop problem while retaining the server as the approved package source.
- `UncDirect` is available when target-side access to the share is already proven.
- The installer may create its own files, logs, services, tasks, registry values, caches, or reboot requirements. Those are installer-owned and outside SysAdminSuite staging cleanup.
- The workflow does not reboot targets automatically.
- A completed install exit code and a registry delta are not substitutes for an observed reboot/auto-logon runtime test.
