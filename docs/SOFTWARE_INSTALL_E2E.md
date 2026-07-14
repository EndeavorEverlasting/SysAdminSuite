# Software Installation End-to-End Proof

## Purpose

The default SysAdminSuite E2E gate must execute a software installation, not merely parse the installer wrapper or produce a WhatIf plan.

The fixture journey runs:

```text
scripts/Invoke-SasEndToEndValidation.ps1
  -> scripts/Invoke-SasSoftwareInstallE2E.ps1
      -> scripts/Invoke-SasSoftwareInstall.ps1
          -> real remote-install script block
              -> real fixture installer child process
                  -> installed package manifest and installer-owned log
```

The journey uses a process-local transport adapter so the production operator wrapper traverses its real session and installation branches without requiring WinRM, an SMB connection, or a live workstation. The approved UNC path is mapped only to the tracked fixture installer for this isolated process.

## What is proven

The E2E journey proves all of the following together:

- the real software-install operator wrapper runs with its explicit mutation gate;
- the real installer execution block launches a child installer process;
- the installer creates observable package state;
- the operator emits `software_install_events.jsonl` and `software_install_summary.json`;
- before and after snapshots are captured;
- an added, changed, and removed delta is computed;
- installer-owned logging is preserved;
- required operator events are present;
- no SysAdminSuite-owned staging remains;
- the final result is machine-readable and fails closed.

## Artifacts

The journey output contains:

```text
software_install_before.json
software_install_after.json
software_install_delta.json
software_install_e2e_events.jsonl
software_install_e2e_result.json
software_install_e2e_matrix.txt
fixture-target/InstalledPackages/SysAdminSuiteFixturePackage/manifest.json
fixture-target/InstallerLogs/sysadminsuite-fixture-package.log
operator/software-install-*/software_install_events.jsonl
operator/software-install-*/software_install_summary.json
operator/software-install-*/operator_handoff.txt
```

All artifacts remain under the ignored `survey/output` evidence root or a CI artifact.

## Run

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasSoftwareInstallE2E.ps1 `
  -OutputRoot .\survey\output\software-install-e2e
```

The default profile also runs this journey through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 `
  -Profile default `
  -OutputRoot .\survey\output\e2e-validation
```

## Proof ceiling

This is real fixture software-install E2E. It is not live WinRM, SMB-share, workstation, deployment, or operator-acceptance proof. The journey performs no external network activity, does not contact a target, does not collect credentials, and does not weaken the separately authorized live mutation gate.
