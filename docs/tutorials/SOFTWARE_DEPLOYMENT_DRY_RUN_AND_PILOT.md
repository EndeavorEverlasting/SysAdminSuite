# Tutorial: Deploy Software Safely with SysAdminSuite

Use this tutorial when you need to prove the software-deployment workflow before using it in the real environment, then deploy one approved package to one authorized pilot workstation.

## Start here

For most users, begin at the repository root and double-click:

```text
START-HERE-SysAdminSuite-Dashboard.bat
```

Use the commands in this tutorial only when you are ready to run the software-deployment workflow. Do not improvise installer paths, arguments, targets, or package sources.

## What this tutorial covers

```text
safe executable dry run
-> review generated executable and dummy-file delta
-> prepare one approved package and one authorized target
-> create a WhatIf plan
-> execute one confirmation-enabled pilot
-> review logs, exit codes, cleanup, and installed behavior
-> decide whether to stop, adjust, or expand
```

The dry run is fixture proof. It does not contact the software share or a workstation. The pilot is a separate live mutation step and requires explicit authorization.

---

# Phase 1: Run the safe executable dry run

## 1. Open PowerShell at the repository root

In File Explorer, open the `SysAdminSuite` folder. Click the address bar, type `powershell`, and press Enter.

Confirm you are at the repository root:

```powershell
git status --short
```

Do not continue from inside `scripts`, `docs`, or another subfolder.

## 2. Run the software-install E2E journey

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasSoftwareInstallE2E.ps1 `
  -OutputRoot .\survey\output\software-install-e2e
```

This command:

1. compiles `Tests/fixtures/software-install/DummyInstaller.cs` into a temporary Windows executable;
2. records the executable SHA-256 and build manifest;
3. sends the generated executable through the real SysAdminSuite software-install wrapper;
4. installs a harmless dummy file into an isolated fixture target;
5. captures before and after snapshots;
6. computes an exact added, changed, and removed delta;
7. records operator, installer, cleanup, and final-result logs.

It does not contact a real package share or workstation.

## 3. Confirm the terminal result

Required result:

```text
Status: PASS
Proof class: fixture-software-install-executable-e2e
Delta: 3 added / 0 changed / 0 removed
Live target proof: false
```

Stop if the status is `FAIL`, the executable was not generated, the delta differs, or cleanup reports a remnant.

## 4. Review the dry-run evidence

Open:

```text
survey\output\software-install-e2e
```

Required generated executable evidence:

```text
generated-installer\sysadminsuite-dummy-installer.exe
generated-installer\sysadminsuite-dummy-installer.exe.build.json
```

Required installed fixture state:

```text
fixture-target\InstalledPackages\SysAdminSuiteFixturePackage\dummy-installed.txt
fixture-target\InstalledPackages\SysAdminSuiteFixturePackage\manifest.json
fixture-target\InstallerLogs\sysadminsuite-fixture-package.jsonl
```

Required orchestration evidence:

```text
software_install_before.json
software_install_after.json
software_install_delta.json
software_install_e2e_events.jsonl
software_install_e2e_result.json
software_install_e2e_matrix.txt
operator\software-install-*\software_install_events.jsonl
operator\software-install-*\software_install_summary.json
operator\software-install-*\operator_handoff.txt
```

## 5. Verify the dry-run result JSON

Open `software_install_e2e_result.json` and confirm:

```text
status = PASS
real_operator_wrapper_executed = true
real_installer_executable_executed = true
executable.committed_binary = false
package.observed_version = 1.0.0
delta.added_count = 3
delta.changed_count = 0
delta.removed_count = 0
operator.completed_count = 1
operator.failed_count = 0
operator.cleanup_failure_count = 0
operator.repo_artifact_remaining_count = 0
live_target_e2e = false
```

The executable and evidence stay under ignored output paths. Do not add them to git.

---

# Phase 2: Prepare one real pilot deployment

Do not begin this phase until the fixture dry run passes.

## 6. Collect the approved deployment facts

Write down all of the following before running a command:

| Required fact | Example shape |
|---|---|
| Authorized workstation | `WNH269OPR009` |
| Package display name | `ExampleVendorTool` |
| Approved relative installer path | `packages\Vendor\Package\setup.exe` |
| Vendor-supported silent arguments | `'/quiet', '/norestart'` |
| Installation mode | `UncDirect` preferred |
| Change/request/ticket approval | Your approved reference |
| Expected installed version or detection method | Vendor or packaging evidence |
| Reboot requirement | Yes or no |
| Post-install behavior to observe | Version, service, shortcut, launch, or other approved check |

The approved source root is controlled by `harness/api/sas-harness-api.json`. Do not use a different server root or an absolute installer path.

Use `UncDirect` first when the target can read the approved share. Use `CopyThenInstall` only when direct execution is not practical and temporary target staging has been approved.

## 7. Confirm the package independently

Before contacting a target, verify on the admin workstation:

- the installer exists at the approved relative path;
- its SHA-256 is recorded;
- its Authenticode signature and publisher are reviewed when applicable;
- the package version is recorded;
- the silent arguments come from vendor documentation, packaging evidence, or an approved test record;
- the selected target is authorized and inside the maintenance window.

Do not guess silent arguments. Do not test unknown arguments on a production workstation.

---

# Phase 3: Create the WhatIf plan

## 8. Run a request-only plan

Replace every placeholder before running:

```powershell
.\scripts\Invoke-SasSoftwareInstall.ps1 `
  -ComputerName '<AUTHORIZED-HOST>' `
  -PackageName '<APPROVED-PACKAGE-NAME>' `
  -InstallerRelativePath 'packages\Vendor\Package\setup.exe' `
  -InstallerArguments @('/quiet', '/norestart') `
  -InstallMode UncDirect `
  -WhatIf
```

`-WhatIf` validates the request and writes local planning evidence. It does not open a remote session, contact the package share, copy a payload, or launch an installer.

## 9. Review the plan before execution

Open the newest run folder under:

```text
survey\output\software_install\
```

Review:

```text
software_install_events.jsonl
software_install_summary.json
operator_handoff.txt
```

Confirm:

- the target is exactly the approved pilot;
- the package name is correct;
- the installer path is relative and under the approved root;
- the arguments match approved evidence;
- the mode is correct;
- no unexpected target appears;
- the plan contains no unresolved validation failure.

Stop and correct the request if any field is wrong.

---

# Phase 4: Execute one approved pilot

## 10. Run the confirmation-enabled installation

Use the same reviewed values. Add `-AllowTargetMutation`. Do not add `-Confirm:$false` during the first real pilot.

```powershell
.\scripts\Invoke-SasSoftwareInstall.ps1 `
  -ComputerName '<AUTHORIZED-HOST>' `
  -PackageName '<APPROVED-PACKAGE-NAME>' `
  -InstallerRelativePath 'packages\Vendor\Package\setup.exe' `
  -InstallerArguments @('/quiet', '/norestart') `
  -InstallMode UncDirect `
  -AllowTargetMutation
```

Read the confirmation prompt carefully. Confirm only when the target, package, arguments, source, and change window still match the approved plan.

The wrapper does not accept or store credentials. It relies on the operator's approved Windows administrative context.

## 11. Do not expand while the pilot is running

Keep the first live run to one workstation. Do not add a second target because the first command appears to be progressing normally.

A process launch or exit code alone is not full deployment proof.

---

# Phase 5: Review the deployment evidence

## 12. Review the summary

Open the newest run folder under:

```text
survey\output\software_install\
```

Required files:

```text
software_install_events.jsonl
software_install_summary.json
operator_handoff.txt
```

The pilot is not clean unless all of these are true:

```text
completed_count = 1
failed_count = 0
cleanup_failure_count = 0
repo_artifact_remaining_count = 0
installer exit code = 0 or another explicitly approved success code
```

For `CopyThenInstall`, confirm the run-specific target staging path was removed. SysAdminSuite evidence must remain on the admin workstation, not the target.

## 13. Review the event sequence

`software_install_events.jsonl` should contain the expected sequence:

```text
run_started
target_started
target_completed
run_completed
```

A failure event, missing completion event, unresolved target, nonzero unapproved exit code, cleanup failure, or remaining staging path is a stop condition.

## 14. Verify the software on the pilot workstation

Use the approved package-specific checks. Depending on the package, verify:

- installed application and expected version;
- expected service, shortcut, registry detection, or file detection;
- application launch and bounded readiness;
- reboot result when required;
- the intended business behavior;
- no unexpected application, service, task, or startup behavior;
- no SysAdminSuite-owned staging remains.

Record actual observed behavior separately from installer exit-code proof.

---

# Phase 6: Decide what happens next

## Expand only when

- the dry-run executable proof passed;
- the WhatIf plan matched the approved request;
- one pilot completed without unresolved failure;
- cleanup and remnant counts are zero;
- package-specific detection and version checks passed;
- required reboot and launch behavior were actually observed;
- logs and evidence were reviewed;
- the change owner approved expansion.

## Stop and escalate when

- the package hash, signature, version, or arguments are uncertain;
- the target cannot read the approved share;
- installation requires unexpected interaction;
- the installer exits with an unapproved code;
- cleanup fails or target staging remains;
- the installed version or behavior is wrong;
- endpoint security blocks or quarantines the package;
- a reboot produces unexpected behavior;
- the evidence is incomplete or contradictory.

Do not hide failures, clear logs, or delete operating-system audit records. Preserve the local SysAdminSuite run evidence for troubleshooting.

---

# Quick reference

## Safe dry run

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasSoftwareInstallE2E.ps1 `
  -OutputRoot .\survey\output\software-install-e2e
```

## Real request-only plan

```powershell
.\scripts\Invoke-SasSoftwareInstall.ps1 `
  -ComputerName '<AUTHORIZED-HOST>' `
  -PackageName '<APPROVED-PACKAGE-NAME>' `
  -InstallerRelativePath 'packages\Vendor\Package\setup.exe' `
  -InstallerArguments @('/quiet', '/norestart') `
  -InstallMode UncDirect `
  -WhatIf
```

## Confirmation-enabled pilot

```powershell
.\scripts\Invoke-SasSoftwareInstall.ps1 `
  -ComputerName '<AUTHORIZED-HOST>' `
  -PackageName '<APPROVED-PACKAGE-NAME>' `
  -InstallerRelativePath 'packages\Vendor\Package\setup.exe' `
  -InstallerArguments @('/quiet', '/norestart') `
  -InstallMode UncDirect `
  -AllowTargetMutation
```

## Related references

- [`docs/SOFTWARE_INSTALL_E2E.md`](../SOFTWARE_INSTALL_E2E.md) — executable fixture implementation and proof artifacts.
- [`docs/SOFTWARE_INSTALL_HARNESS.md`](../SOFTWARE_INSTALL_HARNESS.md) — canonical production installer contract and safety boundaries.
- [`docs/END_TO_END_TESTING_POSTURE.md`](../END_TO_END_TESTING_POSTURE.md) — repository proof ladder and E2E default posture.
