# Package Disposable-VM Execution Capability

## Contract

Execute one qualified package only inside a disposable Hyper-V guest after the package profile is validated as `ready_for_authorized_vm_run`. The admin box controls the VM and retains ignored evidence, but package code never executes on the admin box.

## Preconditions

- Static, semantic, trust, revocation, strong-name, MSI, and SAPIEN gates required by the package shape are complete.
- `validate_vm_qualification_profile.py` passes with zero derived blockers.
- The package SHA-256 still matches the profile.
- The selected Hyper-V VM is powered off and has the exact clean checkpoint.
- Every VM network adapter is disconnected.
- The operator supplies a guest credential at runtime, an approved acceptance script, and `-AllowVmMutation`.

## Runtime boundary

- Restore the clean checkpoint before the run.
- Use Hyper-V PowerShell Direct; do not open a network session.
- Stage one installer and one acceptance script in a run-specific guest directory.
- Execute supported EXE or MSI arguments only inside the guest.
- Capture baseline, installation, reboot, acceptance, delta, cleanup, rollback, and host-postflight evidence.
- Remove guest staging, stop the guest, and restore the checkpoint on success or failure.

## Forbidden

Do not execute the package on the admin box, connect the guest to a switch, use shared folders or clipboard, perform AutoLogon, mutate a physical workstation, persist credentials, or claim production deployment validation.

## Authority

- `harness/api/package-vm-execution-skill.json`
- `harness/workflows/package-vm-execution.yaml`
- `scripts/Invoke-SasPackageDisposableVmRun.ps1`
- `schemas/harness/package-vm-execution-result.schema.json`
- `docs/PACKAGE_VM_EXECUTION.md`

## Proof ceiling

A passing result proves bounded installation and approved application acceptance in the observed disposable VM. Hardware, enterprise policy, device integration, clinical workflow, and physical-workstation acceptance remain separate pilot gates.
