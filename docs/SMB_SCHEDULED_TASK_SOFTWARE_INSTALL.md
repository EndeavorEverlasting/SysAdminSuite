# Windows-native SMB and Task Scheduler software install

## Operator entrypoint

For a complete one-target-to-batch tutorial, start with [`tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md`](tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md). A root-level navigation page is available at [`../START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md`](../START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md).

This page covers the canonical PowerShell transport and the preserved
`bash/apps/sas-install-apps.sh` compatibility controller.

## Purpose

Use `SmbScheduledTask` when an authorized Windows target does not accept WinRM but Kerberos-authenticated administrative shares and remote Task Scheduler are certified. The canonical path is no longer a legacy fallback: `Invoke-SasValidatedSoftwareDeployment.ps1` consumes the closed request and fresh P02 decision. Run it from an approved Windows admin workstation or approved Windows admin VM.

The controller uses the current Windows admin token. It does not require `smbclient`, collect credentials, enable WinRM, change firewall policy, or weaken endpoint controls. The repository does not provision or authorize the controller VM. This fallback does not provide the canonical WinRM lane; WinRM remains an optional separately certified adapter, not a universal requirement.

## Canonical selection and execution

The canonical front door accepts `-Transport Auto`, `WinRM`, or
`SmbScheduledTask`. `Auto` never probes while mutating: it consumes one fresh,
schema-valid P02 result for its one-target pilot and fails closed on stale,
contradictory, unauthorized, or non-executable decisions. Explicit
`SmbScheduledTask` also requires one matching P02 result per target. Once selected,
the controller never changes transport during that run.

Create the fresh read-only P02 result immediately before the pilot. Remote Task
Scheduler queries can take longer than the five-second diagnostic default on an
otherwise healthy authorized path, so the production preflight uses a bounded
15-second observation timeout:

```powershell
$Target = Read-Host 'Authorized target FQDN'
$Preflight = .\scripts\Test-SasSoftwareDeploymentTransport.ps1 `
  -ComputerName $Target `
  -AllowNetworkActivity `
  -TimeoutSeconds 15 `
  -PassThru
$Preflight.result.decision | Format-List
```

Continue only when the classification is `kerberos_smb_task_ready`, the selected
transport is `kerberos_smb_task`, and the saved operator-local result remains
within the canonical entrypoint's freshness window. Keep the hostname, local
path, and raw observation evidence out of Git.

For the first pilot:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasValidatedSoftwareDeployment.ps1 `
  -RequestPath .\survey\input\software-install\approved-request.json `
  -Transport SmbScheduledTask `
  -TransportPreflightPath .\survey\output\runs\software-deployment-transport\<run>\artifacts\software_deployment_transport_result.json `
  -AllowTargetMutation
```

The canonical staging boundary is
`C:\ProgramData\SysAdminSuite\SoftwareInstall\<run-id>`. The adapter verifies
the source hash immediately before copy, verifies installer and worker hashes
through the target share, verifies the installer hash again from target-local
SYSTEM context, executes once, validates the package, retrieves a closed JSON
result, deletes the task, removes only the run root, and verifies both are absent.
Cleanup failure is deployment failure. Exit code `3010` is recorded as reboot
required; no reboot is initiated.

From Git Bash, `--request` is a bounded wrapper over that same front door and does
not use `--allow-legacy`:

```bash
bash bash/apps/sas-install-apps.sh \
  --request survey/input/software-install/approved-request.json \
  --transport SmbScheduledTask \
  --transport-preflight survey/output/runs/software-deployment-transport/<run>/artifacts/software_deployment_transport_result.json \
  --dry-run
```

The older `--targets` plus `--list`/`--package` controller below is temporary
compatibility mode. Its proven PR #229 behavior is preserved behind
`--allow-legacy` until canonical parity tests support retirement.

## Implemented flow

1. Resolve one enabled package from `configs/software-packages/approved-apps.json` or one ordered Windows-native package set from `configs/software-packages/windows-native-package-sets.json`.
2. Require the catalog root to match an approved software source in `harness/api/sas-harness-api.json`.
3. Generate a package-specific PowerShell worker.
4. Parse the worker locally with Windows PowerShell before target contact when `powershell.exe` is available.
5. Verify `\\TARGET\C$` through the current Windows token.
6. Create a unique run root beneath `C:\ProgramData\SysAdminSuite\AppInstall`.
7. Stage the exact pinned MSI/EXE or the exact files required by each approved CMD bundle, plus transient worker files.
8. Create and run a uniquely named one-time scheduled task as SYSTEM.
9. Wait for the worker result.
10. Copy the result CSV to `bash/apps/output/`.
11. Delete the unique task and remove only the unique run root.
12. Classify the host as `HOST_OK` or `HOST_FAILED`.

## Preconditions

- The package and every target are explicitly authorized.
- The controller is on an approved network accepted by the SysAdminSuite network guard.
- The current Windows account can read the approved software share and write to `\\TARGET\C$`.
- Remote Task Scheduler RPC is permitted and the Schedule service is running.
- Git Bash, Python 3, `powershell.exe`, and `schtasks.exe` are available.
- A single package has an enabled, pinned MSI or EXE entry in `configs/software-packages/approved-apps.json`, or the package set and every required bundle file are pinned in `configs/software-packages/windows-native-package-sets.json`.
- Silent arguments are stored in that catalog when required.
- The target list contains 1–25 explicit authorized hostnames; start with one pilot.

The historical `--allow-legacy` switch is retained as the compatibility-controller gate. It does not classify this transport as deprecated, and it does not grant permission, credentials, package approval, a transport decision, or broader target scope. New cross-transport front doors must consume a schema-valid decision instead of relying on this flag.

## Command help

```bash
bash bash/apps/sas-install-apps.sh --help
```

The command requires exactly one of `--package`, `--package-set`, or `--list`. Approved-package and package-set installation require the Windows-native transport for live execution.

## Clinical workstation package set

The approved package-set ID `cybernet-clinical-workstation` installs these packages sequentially on each target:

1. Allscripts EEHR Shortcut UAI 2.2;
2. Epic Downtime Guide Shortcut 1.0;
3. Nuance Dragon Medical One 2025;
4. Hyland FOS Epic Integration 23.1.33.1000;
5. Epic BCA Web Shortcut 1.0;
6. NW AutoLogon Setup x64.

Dragon and Hyland are approved folder bundles. Each package is staged in its own run-scoped subdirectory so its `Install.cmd`, MST, CAB, XML, shortcut, MSI, and EXE dependencies remain together. AutoLogon runs last and is elevated through the same one-time SYSTEM task. The controller never restarts a workstation.

Dry run one explicit pilot target:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package-set cybernet-clinical-workstation \
  --allow-legacy \
  --dry-run
```

After reviewing the 18-file staging plan, remove only `--dry-run` for the authorized live run:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package-set cybernet-clinical-workstation \
  --allow-legacy
```

If a completed package-set result shows that only AutoLogon failed, rerun only the final approved step instead of reinstalling the preceding applications:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets HOST1,HOST2 \
  --package-set cybernet-autologon-only \
  --allow-legacy
```

The AutoLogon recovery set runs only `NW_AutoLogon_Setup_x64.exe` as SYSTEM. Its argument list is intentionally empty; the worker omits PowerShell's `-ArgumentList` parameter for this case.

For machines that already received the first four clinical applications but still need both BCA and the corrected AutoLogon step, use the bounded recovery set:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets HOST1,HOST2 \
  --package-set cybernet-bca-autologon-recovery \
  --allow-legacy
```

The recovery set installs BCA first and AutoLogon last. The returned full-set CSV contains one result row for each of the six packages. A failed row makes the target `HOST_FAILED`; later packages are still represented by the worker result when execution reaches them. Installer completion remains separate from technician application acceptance.

## BCA dry run

Render the one-target plan without contacting a target or package share:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy \
  --dry-run
```

The plan must show:

- approved package ID `bca`;
- pinned file `EPIC_BCA_Web-Shortcut_1.0.msi`;
- a unique `C:\ProgramData\SysAdminSuite\AppInstall\app-install-*` run root;
- a one-time SYSTEM scheduled task;
- local result retrieval followed by task and run-root cleanup;
- final marker `DRY_RUN_OK`.

## One-target pilot

After reviewing the dry run, use the exact authorized hostname and omit only `--dry-run`:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy
```

The task runs the staged BCA MSI as SYSTEM with `/qn` and `/norestart`. The controller waits up to 1,800 seconds by default, copies the result CSV and log locally, validates the installer result, then verifies task removal and removes only the unique run root.

Windows Installer exit code `3010` is accepted as successful installation requiring a later authorized restart. This lane never initiates the restart.

If installation, result retrieval, task cleanup, or staging cleanup cannot be proven, the command exits nonzero and records `HOST_FAILED`.

## Multiple targets

After one accepted pilot, pass a comma-separated list of no more than 25 explicit hostnames:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-01,CYBERNET-02,CYBERNET-03 \
  --package bca \
  --allow-legacy \
  --dry-run
```

Review the batch plan before removing only `--dry-run`. Each target receives its own classification and evidence. The maximum of 25 is a hard guardrail, not a recommendation to start with 25.

For the six-package clinical set, replace `--package bca` with:

```text
--package-set cybernet-clinical-workstation
```

## Evidence and application acceptance

Review controller-side artifacts:

```text
bash/apps/output/sas-install-<target>-package-bca-<timestamp>.log
bash/apps/output/sas-install-<target>-package-bca-<timestamp>.results.csv
```

Accepted package results are `Installed` or `ExitOK_NotDetected`. Installer completion is not application acceptance. BCA is a web-shortcut package, so a technician must still confirm that the shortcut exists, opens the approved destination, and meets the ticket criteria.

This compatibility controller does not provide the validated PowerShell lane's Before/After software snapshots. Its result and cleanup evidence are transport-specific and must not be represented as the validated front door's result contract.

## Production evidence

PR #229 records one authorized Windows production pilot on July 17, 2026:

- approved package `bca`;
- Windows-native admin-share staging and remote Task Scheduler;
- local Windows PowerShell worker syntax preflight;
- pinned MSI staging;
- one-time SYSTEM task creation and execution;
- result CSV returned to the controller;
- verified task and run-root cleanup;
- `HOST_OK`, one success and zero failures;
- technician-confirmed shortcut/application behavior.

The live hostname and local result artifact were intentionally not committed. This is one-target production proof, not fleet authorization.

## Teardown and rollback boundary

Normal success includes task deletion and unique run-root removal. Worker self-teardown is a fallback if the controller is interrupted.

Use `--no-teardown` only for explicitly approved debugging. It intentionally leaves transient artifacts and therefore cannot satisfy ordinary final-success cleanup.

Transport cleanup is not an uninstall. The controller does not implement a general software rollback. Removal of installed software requires a separately reviewed vendor uninstall path and acceptance plan.

## Adding another approved package

A reviewer or administrator adds one catalog entry with:

- a unique ID and display name;
- a relative folder under the approved software root;
- one exact MSI or EXE filename;
- approved unattended arguments;
- `install_enabled: true` only after review and qualification.

Then complete the same dry-run, one-target pilot, evidence review, cleanup verification, and technician acceptance. Do not pass arbitrary UNC installers on the command line and do not store credentials in the catalog, scripts, docs, or output committed to Git.

An approved CMD bundle belongs in the Windows-native package-set catalog with one pinned entrypoint and an explicit list of every staged dependency. The runner rejects absolute paths, traversal, wildcards, missing entrypoints, unsupported extensions, duplicate package IDs, and unapproved software-share roots.
