# Software Installation End-to-End Proof

## Purpose

The default SysAdminSuite E2E gate must execute a software installation, not merely parse the installer wrapper or produce a WhatIf plan.

The fixture journey now generates a Windows executable from tracked C# source and runs:

```text
scripts/Invoke-SasEndToEndValidation.ps1
  -> scripts/Invoke-SasSoftwareInstallE2E.ps1
      -> scripts/Build-SasSoftwareInstallFixtureExecutable.ps1
          -> generated sysadminsuite-dummy-installer.exe
      -> scripts/Invoke-SasSoftwareInstall.ps1
          -> real remote-install script block
              -> real generated executable child process
                  -> dummy-installed.txt
                  -> installed package manifest
                  -> installer-owned JSONL log
```

The journey uses a process-local transport adapter so the production operator wrapper traverses its real session and installation branches without requiring WinRM, an SMB connection, or a live workstation. The approved UNC path is mapped only to the generated fixture executable for this isolated process.

## Executable generation

Tracked source:

```text
Tests/fixtures/software-install/DummyInstaller.cs
```

Tracked builder:

```text
scripts/Build-SasSoftwareInstallFixtureExecutable.ps1
```

Generate the executable manually:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-SasSoftwareInstallFixtureExecutable.ps1 `
  -OutputPath .\survey\output\software-install-fixture\sysadminsuite-dummy-installer.exe
```

The builder uses the Windows .NET Framework `csc.exe` compiler and emits:

```text
sysadminsuite-dummy-installer.exe
sysadminsuite-dummy-installer.exe.build.json
```

The build manifest records the source SHA-256, executable SHA-256, byte count, compiler path, and build time. The binary is not committed. It remains under ignored `survey/output` paths or a CI artifact.

## Dummy installation behavior

The generated executable accepts explicit `--name=value` arguments. The E2E journey supplies:

```text
--target-root=<isolated fixture target>
--package-name=SysAdminSuite Fixture Package
--version=1.0.0
--dummy-relative-path=InstalledPackages\SysAdminSuiteFixturePackage\dummy-installed.txt
--log-path=<isolated fixture target>\InstallerLogs\sysadminsuite-fixture-package.jsonl
```

It validates that the manifest, dummy file, and log stay beneath the fixture target root. It then installs:

```text
fixture-target/InstalledPackages/SysAdminSuiteFixturePackage/dummy-installed.txt
fixture-target/InstalledPackages/SysAdminSuiteFixturePackage/manifest.json
fixture-target/InstallerLogs/sysadminsuite-fixture-package.jsonl
```

The executable returns a nonzero exit code on invalid arguments, path escape, or write failure.

## What is proven

The E2E journey proves all of the following together:

- the real software-install operator wrapper runs with its explicit mutation gate;
- a generated Windows executable is built from tracked source;
- the generated executable hash matches its build result;
- the real installer execution block launches that executable as a child process;
- the executable installs `dummy-installed.txt`;
- the package manifest reports version `1.0.0` and the executable installer identity;
- the operator emits `software_install_events.jsonl` and `software_install_summary.json`;
- the executable emits installer-owned JSONL logging;
- before and after snapshots are captured;
- an added, changed, and removed delta is computed;
- the delta contains exactly the dummy file, package manifest, and installer log;
- required operator events are present;
- no SysAdminSuite-owned staging remains;
- the final result is machine-readable and fails closed.

## Artifacts

The journey output contains:

```text
generated-installer/sysadminsuite-dummy-installer.exe
generated-installer/sysadminsuite-dummy-installer.exe.build.json
software_install_before.json
software_install_after.json
software_install_delta.json
software_install_e2e_events.jsonl
software_install_e2e_result.json
software_install_e2e_matrix.txt
fixture-target/InstalledPackages/SysAdminSuiteFixturePackage/dummy-installed.txt
fixture-target/InstalledPackages/SysAdminSuiteFixturePackage/manifest.json
fixture-target/InstallerLogs/sysadminsuite-fixture-package.jsonl
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

## Real-environment follow-up

This executable is the dry-run package for proving the transport, execution, logging, delta, cleanup, and reporting chain before entering the real environment.

The real-environment sprint must replace only the fixture transport/package assumptions that differ in practice, then rerun the same proof chain against one authorized pilot target and the approved read-only software share. Do not promote this fixture result to live WinRM, SMB-share, workstation, deployment, or operator-acceptance proof.

## Proof ceiling

This is real generated-executable software-install E2E against an isolated fixture target. It is not live WinRM, SMB-share, workstation, deployment, or operator-acceptance proof. The journey performs no external network activity, does not contact a target, does not collect credentials, and does not weaken the separately authorized live mutation gate.
