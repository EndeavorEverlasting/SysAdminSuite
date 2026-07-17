# Disposable-VM Package Execution

## Purpose

Use a disposable Windows VM to perform the first real installation test without risking the admin box. The admin box remains the controller and evidence store. Installer code is copied into and executed only inside the guest.

This lane begins only after the package qualification profile passes as `ready_for_authorized_vm_run`. It is separate from static analysis and separate from physical-workstation deployment.

## Supported initial runtime

- Hyper-V on a Windows admin box
- Windows guest powered off before the run
- Exact clean checkpoint
- All VM network adapters disconnected
- Hyper-V PowerShell Direct with a runtime-supplied `PSCredential`
- One EXE or MSI per run
- One package-specific acceptance script
- Checkpoint restore before and after every run

Windows Sandbox, VMware, VirtualBox, connected guests, MSIX, and script installers are not authorized by this initial implementation.

## Safety boundary

The runner refuses execution unless:

1. The qualification validator passes.
2. The profile status is `ready_for_authorized_vm_run` with zero blockers.
3. The profile explicitly authorizes execution and names an authorization reference.
4. The package SHA-256 matches the qualified source hash.
5. The profile selects Hyper-V, disconnected networking, clean-checkpoint rollback, no AutoLogon, no shared clipboard, and no shared folders.
6. The VM is powered off, the checkpoint exists, and no adapter is connected to a virtual switch.
7. `-AllowVmMutation` is supplied and the operator confirms the high-impact action.

Credentials are accepted only as a `PSCredential` at runtime and are never written to artifacts. The runner does not clear Windows or endpoint logs.

## Acceptance script contract

The operator-local acceptance script runs inside the guest after installation and any required reboot. It must return one object:

```powershell
[pscustomobject]@{
    passed = $true
    checks = @(
        [pscustomobject]@{ id = 'application_launch'; status = 'passed'; detail = 'Process opened and exited cleanly.' }
        [pscustomobject]@{ id = 'service_state'; status = 'passed'; detail = 'Required service is running.' }
    )
}
```

The script should verify only approved package behavior. It must not contain credentials, production hostnames, AutoLogon changes, or physical-device claims.

## Example fixture-only validation

Fixture mode validates the profile, package hash, result contract, and entrypoint without starting a VM or executing package code:

```powershell
.\scripts\Invoke-SasPackageDisposableVmRun.ps1 `
  -QualificationProfilePath .\Tests\Fixtures\package-vm-execution\ready-profile.fixture.json `
  -InstallerPath .\Tests\Fixtures\package-vm-execution\fixture-installer.payload `
  -VmName SAS-FIXTURE-VM `
  -CheckpointName clean `
  -AcceptanceScriptPath .\Tests\Fixtures\package-vm-execution\acceptance.fixture.ps1 `
  -FixtureMode
```

## Example authorized VM run

```powershell
$credential = Get-Credential -Message 'Disposable VM local administrator'

.\scripts\Invoke-SasPackageDisposableVmRun.ps1 `
  -QualificationProfilePath .\survey\output\package-analysis\run\package-vm-profile.json `
  -InstallerPath 'D:\approved-local-packages\Vendor\setup.exe' `
  -VmName 'SAS-Package-Test-01' `
  -CheckpointName 'clean-baseline' `
  -AcceptanceScriptPath '.\survey\local\Vendor-acceptance.ps1' `
  -Credential $credential `
  -AllowVmMutation
```

## Result posture

A passing VM result means **qualified in a disposable VM and eligible for a controlled physical pilot**. It does not close physical-workstation acceptance. A separate pilot must validate hardware, drivers, COM/serial devices, endpoint controls, GPO, production networking, clinical workflow, and site-specific behavior.

All runtime artifacts remain under a gitignored local output root:

```text
survey/output/package-vm-execution/<run_id>/
  package_vm_execution_events.jsonl
  package_vm_execution_result.json
  operator_handoff.txt
```
