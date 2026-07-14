# Auto Didact install workflow

## Purpose

`Run-InstallAutoDidact.cmd` is the technician-facing command capsule for installing Auto Didact through the existing SysAdminSuite guarded software-install wrapper.

The workflow enforces this order:

```text
BEFORE snapshot
-> WhatIf install plan
-> approved Auto Didact install
-> AFTER snapshot
-> local delta review
```

The before snapshot must complete before the install action can run. If any target snapshot fails, the launcher stops before target mutation.

## Technician command

From the SysAdminSuite repo root on the admin workstation, double-click or run:

```cmd
Run-InstallAutoDidact.cmd
```

The menu provides:

```text
[1] Capture BEFORE snapshot
[2] Plan Auto Didact install (WhatIf)
[3] Install Auto Didact after confirmed BEFORE snapshot
[4] Capture AFTER snapshot and compare
[5] Open latest evidence folder
```

## Required inputs

The Before step prompts for:

- an approved target CSV under `targets/local/` or `survey/input/`;
- the Auto Didact installer path relative to the approved software root;
- optional installer arguments when running the PowerShell entrypoint directly.

The approved software root is still read from `harness/api/sas-harness-api.json`. The current approved root is:

```text
\\nt2kwb972sms01\
```

Do not put the full UNC path in `InstallerRelativePath`. Supply only the path relative to the approved root.

## Snapshot protocol

The snapshot captures read-only workstation state from each explicit target:

- OS identity and boot time;
- logged-on user name;
- installed software from the 64-bit and 32-bit uninstall registry trees;
- collection status and errors.

Snapshot evidence is written only on the admin workstation under:

```text
survey/output/autodidact_install/<run_id>/
```

Expected files include:

```text
before/<target>.json
before/snapshot-manifest.json
software_install/<software-install-run-id>/software_install_summary.json
software_install/<software-install-run-id>/operator_handoff.txt
after/<target>.json
after/snapshot-manifest.json
autodidact-install-delta.json
operator-state.json
```

## Install behavior

The install action delegates to the canonical wrapper:

```text
scripts/Invoke-SasSoftwareInstall.ps1
```

The Auto Didact launcher does not duplicate remote install mechanics. It calls the wrapper with:

- `PackageName = Auto Didact`;
- the saved target CSV;
- the saved installer relative path;
- the saved installer arguments;
- the saved install mode;
- `-AllowTargetMutation`;
- `-Confirm:$false`.

The Plan action uses the same saved request with `-WhatIf` and does not contact the share or targets through the install wrapper.

## Guardrails

- Explicit target CSV only; maximum 25 targets.
- BEFORE snapshot must be complete before install.
- Snapshot evidence stays on the admin box under gitignored output roots.
- No SysAdminSuite snapshot files, reports, transcripts, scripts, or evidence are written to targets.
- No credentials, password values, tokens, secrets, log suppression, event clearing, or hidden persistence.
- The snapshot compares software inventory only. It does not prove application launch, user acceptance, or business behavior.
- Installer-owned files, logs, services, shortcuts, registry keys, or caches are outside the SysAdminSuite cleanup boundary.

## Direct PowerShell examples

Fixture contract proof:

```powershell
.\scripts\Start-SasAutoDidactInstall.ps1 `
  -Action Before `
  -TargetsCsv .\targets\local\approved-autodidact-targets.csv `
  -InstallerRelativePath 'Packages\AutoDidact\AutoDidactSetup.exe' `
  -FixtureMode `
  -NonInteractive
```

Dry-run install plan after a successful Before snapshot:

```powershell
.\scripts\Start-SasAutoDidactInstall.ps1 -Action Plan -NonInteractive
```

Approved install after a successful Before snapshot:

```powershell
.\scripts\Start-SasAutoDidactInstall.ps1 -Action Install -NonInteractive
```

After snapshot and delta:

```powershell
.\scripts\Start-SasAutoDidactInstall.ps1 -Action After -NonInteractive
```

## Production readiness boundary

This launcher is production-ready as a guarded command surface. It does not prove that the Auto Didact installer itself is silent, validly signed, reachable on the approved share, or acceptable for every target model. Prove those with package intake, a one- or two-target pilot, and direct operator observation before expansion.
