# Cybernet software deployment tutorial

## Audience and supported workflow

This tutorial is for authorized technicians and Windows administrators installing one approved software package on one or more Cybernet workstations.

The implemented operator path is:

```text
approved Windows admin workstation or admin VM
  -> Git Bash controller
  -> target C$ administrative share
  -> unique run-scoped staging folder
  -> one-time scheduled task running as SYSTEM
  -> installer result copied back to the controller
  -> scheduled task and run-scoped staging removed
  -> technician application acceptance
```

The intentionally supported SMB/Task Scheduler compatibility-controller entrypoint is `bash/apps/sas-install-apps.sh`. It is not the cross-transport selector or the validated PowerShell front door. A single package must be enabled in `configs/software-packages/approved-apps.json`; an ordered Windows-native package set must be enabled in `configs/software-packages/windows-native-package-sets.json`.

A Windows admin VM can be the controller when it has the same approved network access, Windows administrative token, Git Bash, repository checkout, package-share access, `powershell.exe`, and `schtasks.exe`. SysAdminSuite does not create, configure, snapshot, or approve that VM.

## What has been proven

PR #229 records one authorized production pilot for package ID `bca` on one Windows target. The evidence states that the pinned MSI was staged, the generated worker passed Windows PowerShell syntax preflight, a one-time SYSTEM task ran, the result CSV returned to the controller, task and staging cleanup were verified, the host finished as `HOST_OK`, and a technician confirmed the installed shortcut/application worked.

That proof applies to one authorized pilot. It does not automatically authorize another target, another package, a site-wide rollout, an uninstall, a reboot, or a maximum-size batch.

PR #212 is developer-workstation orchestration fixture proof. PR #222 is the Resume Matcher lifecycle. Neither is the authority for this Cybernet Task Scheduler deployment.

## Roles and boundaries

| Location | Operator action | What happens there |
| --- | --- | --- |
| Windows admin workstation or VM | Run Git Bash commands and review local evidence | Package selection, target loop, staging control, Task Scheduler control, result collection, and cleanup verification |
| Approved software share | Read-only source | Supplies only the exact catalog-pinned MSI or EXE |
| Target Cybernet workstation | No manual command required during the automated run | Receives the run-scoped payload; Task Scheduler launches the installer as SYSTEM |
| Technician at target or remote support session | Perform application acceptance | Confirms the shortcut or application opens and satisfies the ticket |

This lane does not enable WinRM, alter firewall policy, collect credentials, embed passwords, reboot a target, or kill unrelated processes.

## Prerequisites

Before opening Git Bash, confirm all of the following:

- The change, ticket, package, target list, maintenance window, and operator are authorized.
- Start with exactly one pilot target, even when the request ultimately covers many workstations.
- The controller is a Windows system on an approved network accepted by the SysAdminSuite network guard.
- Your current Windows account can read the approved package share.
- Your current Windows account can open `\\TARGET\C$` for every target.
- Remote Task Scheduler RPC is permitted and the target Schedule service is running.
- Git Bash, Python 3, Windows PowerShell, and `schtasks.exe` are available on the controller.
- The package is enabled and has one exact MSI or EXE filename and reviewed silent arguments in `configs/software-packages/approved-apps.json`.
- The target list contains 1–25 explicit hostnames. Do not use wildcards, subnets, discovery output, or more than 25 targets.
- Local output under `bash/apps/output/` is protected as operator evidence and will not be committed.

Do not pass `--smb-user`, `--smb-pass`, or `--smb-domain` for the Windows-native path. It intentionally uses the current approved Windows administrative token.

## 1. Open the repository in Git Bash

From Git Bash, change to the repository root. Confirm the script and catalog exist:

```bash
pwd
test -f bash/apps/sas-install-apps.sh
test -f configs/software-packages/approved-apps.json
```

Show the current command help before a live change:

```bash
bash bash/apps/sas-install-apps.sh --help
```

The help must show `--targets`, `--package`, `--package-set`, `--dry-run`, `--allow-legacy`, `--wait-timeout`, and the maximum of 25 targets.

## 2. Review the approved package

For the proven BCA package, the catalog ID is `bca`. The current entry pins:

- display name: Epic BCA Web Shortcut 1.0;
- installer: `EPIC_BCA_Web-Shortcut_1.0.msi`;
- installer type: MSI;
- arguments: `/qn /norestart`;
- install status: enabled.

Technicians choose an existing approved package ID. Adding or changing a catalog entry is an administrator/reviewer task and must not be improvised during deployment.

## 3. Run the mandatory one-target dry run

Use a synthetic hostname first to learn the output without contacting a target or the package share:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy \
  --dry-run
```

A successful dry run ends with `DRY_RUN_OK` and displays:

- `transport=dry-run`;
- the approved package ID and exact pinned installer;
- a unique `C:\ProgramData\SysAdminSuite\AppInstall\app-install-*` run root;
- a unique one-time task name;
- Task Scheduler `/Create` and `/Run` commands;
- result-copy, task-removal, and run-root-removal intentions.

`--allow-legacy` is the retained compatibility-controller gate. It does not mean SMB/Task Scheduler is deprecated, and it does not supply a schema-valid transport decision, authorization, credentials, target scope, or acceptance.

Stop when the dry run shows the wrong package, filename, target, staging parent, or task identity.

## 4. Run one authorized pilot

Replace the placeholder with the exact authorized Cybernet hostname. Remove only `--dry-run`:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy
```

The controller performs this sequence for the target:

1. Passes the network and compatibility-controller gates.
2. Resolves the package only through the approved catalog and approved source root.
3. Generates a PowerShell worker and parses it locally with Windows PowerShell before target contact.
4. Verifies access to `\\TARGET\C$`.
5. Creates one unique run root beneath `C:\ProgramData\SysAdminSuite\AppInstall`.
6. Copies the worker, launcher, and exact pinned installer into that run root.
7. Creates and starts one uniquely named scheduled task as SYSTEM.
8. Waits up to 1,800 seconds by default for the worker result.
9. Copies the result CSV and controller log into `bash/apps/output/`.
10. Deletes the task and removes only that run's staging root.
11. Reports `HOST_OK` or `HOST_FAILED`.

Do not close the controller terminal while the command is running unless directed by an incident procedure. The worker has best-effort self-cleanup, but the controller performs the authoritative result retrieval and cleanup verification.

## 5. Review pilot evidence

A successful controller run should include these messages:

```text
transport=windows-native
Worker syntax preflight passed with Windows PowerShell.
Staged pinned package: EPIC_BCA_Web-Shortcut_1.0.msi
Task triggered; waiting up to ...
Result copied locally:
Cleanup complete: task and run-scoped staging removed or already absent.
HOST_OK
```

Review the local files:

```text
bash/apps/output/sas-install-<target>-package-bca-<timestamp>.log
bash/apps/output/sas-install-<target>-package-bca-<timestamp>.results.csv
```

The CSV must record `Installed` or `ExitOK_NotDetected` for the package. MSI exit code `3010` is a successful installation that requires a later authorized restart; this lane does not restart the workstation.

A zero installer exit code does not prove that the application works. Complete technician acceptance:

- confirm the expected shortcut or application exists;
- open it through the normal user workflow;
- confirm the intended approved destination or application behavior;
- record the ticket/change acceptance without copying private evidence into Git.

Proceed only when controller evidence, cleanup, and technician acceptance all pass.

## 6. Expand to multiple workstations

After the one-target pilot is accepted, use a comma-separated list of explicit authorized hostnames:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-01,CYBERNET-02,CYBERNET-03 \
  --package bca \
  --allow-legacy \
  --dry-run
```

Review the batch dry run, then remove only `--dry-run`:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-01,CYBERNET-02,CYBERNET-03 \
  --package bca \
  --allow-legacy
```

Operational rules for batches:

- Maximum: 25 explicit targets per command.
- Start with a small approved batch; 25 is a guardrail, not a recommended first rollout size.
- The script processes and classifies each target separately.
- Keep every target's log and result CSV until the change is closed.
- A failure on one workstation is not proof that another workstation failed or succeeded.
- Do not rerun a failed target blindly. Read its exact failure and inspect residual task/staging state first.

## 7. Install the approved six-package clinical set

The package-set ID `cybernet-clinical-workstation` installs Allscripts EEHR Shortcut, Epic Downtime Guide, Dragon Medical One 2025, Hyland FOS Epic Integration, Epic BCA Web Shortcut, and AutoLogon in that order. Dragon and Hyland keep their approved folder dependencies together; BCA uses its pinned MSI with `/qn /norestart`; AutoLogon runs last as SYSTEM. The command does not reboot the workstation.

Pilot dry run:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package-set cybernet-clinical-workstation \
  --allow-legacy \
  --dry-run
```

Pilot live run after reviewing the staging plan:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package-set cybernet-clinical-workstation \
  --allow-legacy
```

After the pilot is accepted, use a comma-separated list of the remaining authorized hostnames. The local result CSV contains five rows per target. Review each application through the normal technician workflow before closing the change.

## Troubleshooting

### `Admin share unavailable or access denied`

Confirm the hostname, network context, current Windows admin token, and access to `\\TARGET\C$`. Do not add credentials to the command or weaken endpoint policy.

### `requires Windows powershell.exe + schtasks.exe`

Run the approved-package workflow from a Windows controller with Git Bash. Package mode does not fall back to the non-Windows `smbclient` transport.

### `approved package id not found or ambiguous`

Check the package ID against `configs/software-packages/approved-apps.json`. Do not substitute an arbitrary UNC path or filename.

### `package is not enabled for installation`

Stop. The package needs catalog review and approval before deployment.

### `generated PowerShell worker failed local syntax preflight`

No target should have been contacted. Preserve the local output, record the failure, and repair or update the repository before retrying.

### Task creation, run, query, or deletion fails

Record the exact `schtasks.exe` output. Confirm Task Scheduler RPC and the Schedule service. Do not switch to an unreviewed remote-execution method.

### Result times out

The default wait is 1,800 seconds. A reviewed run can use `--wait-timeout` from 10 to 7,200 seconds. Before rerunning, inspect whether the task still exists, whether a result was written, and whether staging remains.

### `HOST_FAILED`

Review the target log and result CSV. The controller still attempts cleanup after installer failure. Treat missing cleanup proof as a separate failure requiring review.

### Exit code `3010`

Record `restart required`. Do not reboot through this lane. Use the site's separately approved restart process.

### Cleanup cannot be proven

Do not classify the deployment as complete. Inspect only the unique task and run root named in the controller log. Never delete the parent staging tree broadly.

## Cleanup, rollback, and uninstall boundary

Normal success requires both:

- the unique scheduled task is removed or already absent; and
- the unique run-scoped staging root is removed or already absent.

`--no-teardown` is for explicitly approved debugging only. It deliberately leaves transient target artifacts and must not be used as a routine production shortcut.

Transport cleanup is not software rollback. This script does not implement a general uninstall or application rollback. When the installed package must be removed, stop and use a separately reviewed vendor uninstall command, change record, and acceptance plan.

## Adding another package

Only a reviewer/administrator should add a package. The catalog entry must use the approved software root, one relative folder, one exact MSI or EXE filename, reviewed unattended arguments, and `install_enabled: true` only after qualification.

Before the new package reaches Cybernet workstations:

1. Complete static/trust/qualification evidence required by repository policy.
2. Validate the installer in an authorized disposable environment when required.
3. Run the repository contract tests.
4. Run one synthetic dry run.
5. Run one authorized physical pilot.
6. Complete application-specific technician acceptance.
7. Expand only after the pilot decision is recorded.

The current Task Scheduler controller does not provision or validate a VM; VM qualification is a separate gate.

## Operator closeout checklist

- [ ] Exact authorized package ID used.
- [ ] One-target dry run reviewed.
- [ ] One-target live pilot completed.
- [ ] Controller log and result CSV retained locally.
- [ ] `HOST_OK` recorded only after task and run-root cleanup.
- [ ] Application/shortcut accepted by a technician.
- [ ] Restart requirement recorded without an unauthorized reboot.
- [ ] Batch targets remained explicit and at or below 25.
- [ ] Failed targets reviewed individually before retry.
- [ ] No credentials, live hostnames, raw logs, or local evidence committed.

## Related references

- Technical transport reference: [`../SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md`](../SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md)
- Approved package lifecycle: [`../AUTODIDACT_INSTALL_WORKFLOW.md`](../AUTODIDACT_INSTALL_WORKFLOW.md)
- Teardown rules: [`../DEPLOYMENT_TEARDOWN_DOCTRINE.md`](../DEPLOYMENT_TEARDOWN_DOCTRINE.md)
- VM qualification boundary: [`../PACKAGE_VM_QUALIFICATION_PROFILES.md`](../PACKAGE_VM_QUALIFICATION_PROFILES.md)
