# Windows-native SMB and Task Scheduler software install

## Purpose

Use this guarded fallback when an authorized Windows target does not accept WinRM but its `C$` administrative share and remote Task Scheduler are available. Run it from Git Bash on the approved admin workstation.

The fallback uses the current Windows admin token. It does not require `smbclient`, collect credentials, enable WinRM, change firewall policy, or weaken endpoint controls.

## Preconditions

- The target is explicitly authorized for software installation.
- The admin workstation is on an approved network accepted by the SysAdminSuite network guard.
- The current Windows account can read the approved software share and write to `\\TARGET\C$`.
- Remote Task Scheduler RPC is permitted and the Schedule service is running.
- The package has an enabled, pinned MSI or EXE entry in `configs/software-packages/approved-apps.json`.
- Silent installer arguments are stored in that catalog when the package requires them.
- The explicit target list contains no more than 25 authorized hostnames; start with one pilot.

The `--allow-legacy` switch enables only this preserved deployment lane. It does not grant permission, credentials, or broader target scope.

## BCA dry run

From the repository root in Git Bash, render the complete one-target plan without contacting the target or package share:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets SYNTHETIC001 \
  --package bca \
  --allow-legacy \
  --dry-run
```

The plan must show:

- approved package ID `bca`;
- pinned file `EPIC_BCA_Web-Shortcut_1.0.msi`;
- a unique `C:\ProgramData\SysAdminSuite\AppInstall\app-install-*` run root;
- a one-time `SYSTEM` scheduled task;
- local result retrieval followed by task and run-root cleanup.

## One-target pilot

After reviewing the dry run, replace the synthetic hostname with the one authorized pilot target and omit only `--dry-run`:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets SYNTHETIC001 \
  --package bca \
  --allow-legacy
```

The controller resolves BCA from the approved catalog, copies the pinned MSI from the approved read-only share into that run's target staging folder, and creates a uniquely named one-time task. The task runs the local staged MSI as `SYSTEM` with `/qn` and `/norestart`.

The controller waits for the worker result, copies the CSV and log to `bash/apps/output/`, verifies that the result is `Installed` or `ExitOK_NotDetected`, then verifies task removal and deletes only the unique run root. Windows Installer exit code `3010` is accepted as success requiring a later restart; this lane never initiates the restart.

If installation or cleanup cannot be proven, the command exits nonzero and records `HOST_FAILED` in the local log. Use `--no-teardown` only for approved debugging because it deliberately retains the run-scoped target artifacts.

## Evidence and acceptance boundary

Review these controller-side artifacts:

```text
bash/apps/output/sas-install-<target>-package-bca-<timestamp>.log
bash/apps/output/sas-install-<target>-package-bca-<timestamp>.results.csv
```

An MSI exit code proves only installer completion. BCA is a web-shortcut package, so a technician must still confirm the shortcut exists, opens the intended approved destination, and meets the ticket's acceptance criteria. This fallback does not provide the canonical WinRM lane's Before/After software snapshots.

## Adding another approved package

Add one reviewed entry to `configs/software-packages/approved-apps.json` with:

- a unique package ID and display name;
- a relative folder under the approved software root;
- one exact MSI or EXE filename;
- its approved silent arguments;
- `install_enabled: true` only after package review.

Then run the same dry-run and pilot commands with the new package ID. Do not pass arbitrary UNC installer paths on the command line and do not store credentials in the catalog or scripts.
