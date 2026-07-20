# Approved software install workflow

## Purpose

`Run-InstallApprovedSoftware.cmd` is the canonical technician-facing command capsule for installing approved software through the existing SysAdminSuite guarded software-install wrapper.

`Run-InstallAutoDidact.cmd` remains as a compatibility launcher and routes to the same catalog-driven workflow. The technician PowerShell surface is:

```text
scripts/Start-SasApprovedSoftwareOperator.ps1
```

It composes the catalog/snapshot engine at `scripts/Start-SasApprovedSoftwareInstall.ps1` and the canonical install engine at `scripts/Invoke-SasSoftwareInstall.ps1`. `scripts/Start-SasAutoDidactInstall.ps1` remains as a compatibility forwarder.

The workflow enforces this order:

```text
select approved catalog package
-> BEFORE snapshot
-> WhatIf install plan
-> approved install
-> AFTER snapshot
-> local delta review
```

The BEFORE snapshot must complete for every selected target before the install action can run. If any target snapshot fails, the wrapper stops before target mutation.

## Technician command

From the SysAdminSuite repo root on the admin workstation, double-click or run:

```cmd
Run-InstallApprovedSoftware.cmd
```

The menu provides:

```text
[1] List approved packages and readiness
[2] Select package and capture BEFORE snapshot
[3] Plan selected package install (WhatIf)
[4] Install selected package after confirmed BEFORE snapshot
[5] Capture AFTER snapshot and compare
[6] Open latest evidence folder
```

The launcher reads package folders, filenames, default mode, and readiness from:

```text
configs/software-packages/approved-apps.json
```

Technicians do not type a raw installer path into the normal menu workflow.

## Approved server and package catalog

The approved software root remains:

```text
\\nt2kwb972sms01\
```

The tracked catalog is folder-first. Each entry records the confirmed package folder and, when known, a pinned installer filename.

| Package | Catalog ID | Confirmed folder | Pinned installer | Current readiness |
| --- | --- | --- | --- | --- |
| Epic Satellite | `epic-satellite` | `packages\Epic\Satellite` | Not yet confirmed | Before snapshot allowed; plan/install blocked |
| Epic BCA Web Shortcut 1.0 | `bca` | `packages\Epic\EPIC_BCA_Web-Shortcut_1.0` | `EPIC_BCA_Web-Shortcut_1.0.msi` | Path and unattended MSI arguments confirmed for a guarded pilot |
| AllScripts TouchWorks 22.1 | `allscripts-touchworks-22-1` | `packages\TouchWork_22.1` | `TWInstaller.exe` | Path confirmed; vendor arguments still required for live install |
| NW AutoLogon Setup x64 | `autologon` | `packages\AutoLogonSetup` | `NW_AutoLogon_Setup_x64.exe` | Path confirmed; vendor arguments still required for live install |

Resolved file paths for the pinned entries are:

```text
packages\Epic\EPIC_BCA_Web-Shortcut_1.0\EPIC_BCA_Web-Shortcut_1.0.msi
packages\TouchWork_22.1\TWInstaller.exe
packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe
```

The wrapper does not search a package folder for the newest executable. Dynamic discovery could select an unintended installer after a server-side package refresh. When a filename changes, update and validate the catalog entry before plan or install.

## Folder-first policy

The catalog preserves the operator preference to manage software by its package folder while keeping execution deterministic:

```text
confirmed folder
-> pinned approved installer filename
-> complete relative installer path
-> canonical guarded install wrapper
```

A folder entry without a pinned installer file can still be selected for a read-only BEFORE snapshot, but it cannot proceed to WhatIf planning or live installation.

## Required inputs

The Before step requires:

- an approved target CSV under `targets/local/` or `survey/input/`;
- a package selected from the tracked catalog;
- vendor-validated installer arguments before live installation when the catalog does not contain them.

The CMD menu may accept arguments separated with `|` while establishing the Before state. Leaving arguments blank is valid for snapshot work and WhatIf planning only. The live Install action fails closed when validated arguments are required but absent.

## Snapshot protocol

The snapshot captures read-only workstation state from each explicit target:

- OS identity and boot time;
- logged-on user name;
- installed software from the 64-bit and 32-bit uninstall registry trees;
- selected package ID and display name;
- collection status and errors.

Snapshot evidence is written only on the admin workstation under:

```text
survey/output/approved_software_install/<run_id>/
```

Expected files include:

```text
before/<target>.json
before/snapshot-manifest.json
software_install/<software-install-run-id>/software_install_summary.json
software_install/<software-install-run-id>/operator_handoff.txt
after/<target>.json
after/snapshot-manifest.json
approved-software-install-delta.json
operator-state.json
```

## Install behavior

The catalog/snapshot engine delegates installation to:

```text
scripts/Invoke-SasSoftwareInstall.ps1
```

The catalog-driven launcher does not duplicate remote install mechanics. It passes:

- the selected catalog display name as `PackageName`;
- the saved target CSV;
- the catalog-derived installer relative path;
- the saved vendor-validated installer arguments;
- the catalog default install mode;
- the catalog software share root;
- `-AllowTargetMutation`;
- `-Confirm:$false`.

The Plan action uses the same saved request with `-WhatIf`. The canonical install engine performs request validation only and does not contact the share or targets in that mode.

### Durable handoff recovery

The canonical install engine writes `software_install_summary.json` and `operator_handoff.txt` before returning. If PowerShell cannot materialize the final in-memory summary object cleanly, the technician operator wrapper accepts only the durable JSON contract after validating:

- schema `sas-software-install-summary/v1`;
- target count matches the completed Before snapshot;
- the handoff path exists;
- every WhatIf target is planned and no WhatIf failure is reported;
- live failures, cleanup failures, and target remnants remain reportable failures.

The wrapper does not convert a failed install into success. Artifact recovery only preserves a completed, validated handoff from the existing install engine.

## Guardrails

- Explicit target CSV only; maximum 25 targets.
- BEFORE snapshot must be complete before plan or install.
- Package selection comes from the tracked catalog.
- Package folders remain relative to the approved share root.
- Plan/install requires a pinned installer file.
- Live installation requires vendor-validated installer arguments when the catalog marks them required.
- Snapshot evidence stays on the admin box under gitignored output roots.
- No SysAdminSuite snapshot files, reports, transcripts, scripts, or evidence are written to targets.
- No credentials, password values, tokens, secrets, log suppression, event clearing, or hidden persistence.
- The snapshot compares software inventory only. It does not prove application launch, user acceptance, or business behavior.
- Installer-owned files, logs, services, shortcuts, registry keys, or caches are outside the SysAdminSuite cleanup boundary.

Targets without WinRM can use the separately guarded Windows-native admin-share and Task Scheduler transport documented in [`SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md`](SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md). That transport uses the same approved package catalog but does not provide the canonical WinRM workflow's Before/After snapshot sequence.

## Direct PowerShell examples

List the catalog without contacting the share or targets:

```powershell
.\scripts\Start-SasApprovedSoftwareOperator.ps1 -Action ListPackages
```

Fixture Before snapshot for AutoLogon:

```powershell
.\scripts\Start-SasApprovedSoftwareOperator.ps1 `
  -Action Before `
  -PackageId autologon `
  -TargetsCsv .\targets\local\approved-software-targets.csv `
  -FixtureMode `
  -NonInteractive
```

WhatIf plan after a successful Before snapshot:

```powershell
.\scripts\Start-SasApprovedSoftwareOperator.ps1 -Action Plan -NonInteractive
```

Approved live installation requires explicit validated arguments recorded during the Before step or supplied directly:

```powershell
.\scripts\Start-SasApprovedSoftwareOperator.ps1 `
  -Action Before `
  -PackageId autologon `
  -TargetsCsv .\targets\local\approved-software-targets.csv `
  -InstallerArguments @('<vendor-validated-argument-1>', '<vendor-validated-argument-2>') `
  -NonInteractive

.\scripts\Start-SasApprovedSoftwareOperator.ps1 -Action Install -NonInteractive
```

After snapshot and delta:

```powershell
.\scripts\Start-SasApprovedSoftwareOperator.ps1 -Action After -NonInteractive
```

## Production readiness boundary

The catalog and launchers are production-ready as guarded command surfaces. They do not prove that an installer is validly signed, reachable on the approved share, silent with the supplied arguments, compatible with every workstation model, or operationally successful after installation.

Before field expansion:

1. capture and review a complete Before snapshot;
2. confirm the pinned installer filename still exists in the approved folder;
3. validate package hash, signature, publisher, version, and installer arguments;
4. run the WhatIf plan;
5. perform a one- or two-target pilot;
6. capture the After snapshot and review the local delta;
7. directly observe application or AutoLogon behavior when that behavior is part of acceptance.
