# Package Disposable-VM Execution Skill

Use this skill only after package analysis and qualification have produced a validated `ready_for_authorized_vm_run` profile and the operator explicitly requests a disposable-VM installation test.

## Capability dependencies

- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [End-to-End Testing](../../capabilities/end-to-end-testing.md)
- [Package Disposable-VM Execution](../../capabilities/package-vm-execution.md)

## Canonical references

- Operation: [`harness/api/package-vm-execution-skill.json`](../../../harness/api/package-vm-execution-skill.json)
- Routing: [`harness/api/package-vm-execution-routing.json`](../../../harness/api/package-vm-execution-routing.json)
- Workflow: [`harness/workflows/package-vm-execution.yaml`](../../../harness/workflows/package-vm-execution.yaml)
- Qualification profile schema: [`schemas/harness/package-vm-qualification-profile.schema.json`](../../../schemas/harness/package-vm-qualification-profile.schema.json)
- Runtime result schema: [`schemas/harness/package-vm-execution-result.schema.json`](../../../schemas/harness/package-vm-execution-result.schema.json)
- Windows entrypoint: [`scripts/Invoke-SasPackageDisposableVmRun.ps1`](../../../scripts/Invoke-SasPackageDisposableVmRun.ps1)
- Guide: [`docs/PACKAGE_VM_EXECUTION.md`](../../../docs/PACKAGE_VM_EXECUTION.md)

## Workflow

1. Re-run the qualification validator and require `ready_for_authorized_vm_run` with zero blockers.
2. Re-verify the local package SHA-256 against the profile.
3. Require Hyper-V, a powered-off guest, an exact clean checkpoint, and disconnected VM adapters.
4. Require a runtime-only guest `PSCredential`, approved acceptance script, `-AllowVmMutation`, and operator confirmation.
5. Restore the checkpoint before starting the guest.
6. Enter the guest only through Hyper-V PowerShell Direct.
7. Stage and execute one EXE or MSI only inside the guest.
8. Reboot when required, run acceptance, and capture guest deltas.
9. Remove guest staging, stop the guest, and restore the checkpoint on success or failure.
10. Re-verify the host package hash and emit only gitignored local evidence.
11. Advance a passing result only to a separately authorized physical-workstation pilot.

## Forbidden conditions

- Never execute package code on the admin box.
- Never connect or reconfigure a VM network adapter.
- Never use shared folders, shared clipboard, AutoLogon, or stored credentials.
- Never mutate a physical workstation from this lane.
- Never claim production deployment validation from a VM result.
- Never continue when checkpoint teardown or host postflight fails.

## Proof ceiling

This skill can prove installation and approved application acceptance in one observed disposable Hyper-V guest. It cannot prove physical hardware, enterprise policy, clinical workflow, production networking, or workstation deployment acceptance.
