# Virtual Machine Dry-Run Readiness

## Purpose

Use this lane before any supplied Epic, Hyland, Imprivata, shortcut, or other real application package is allowed to run in a virtual machine.

The readiness validator is intentionally offline. It proves that the repository has a bounded VM test contract and that its existing fixture journeys remain safe to use as the pre-VM dry run. It does **not** start a VM, create a checkpoint, run a real installer, launch an application, contact a target, or change the host.

This lane consumes the canonical `sas-harness-proof/v1` result contract. The schema-backed one-command harness floor must land before this VM-readiness layer is merged to `main`.

## One command

From the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasVmDryRunHarnessProof.ps1 `
  -OutputRoot .\survey\output\vm-dry-run-harness
```

The command composes:

1. `scripts/validate-sysadmin-harness.ps1`;
2. `scripts/Test-SasVmDryRunReadiness.ps1`;
3. `harness/e2e/vm-dry-run-readiness.json`;
4. the three existing network-free software-install journey contracts in `harness/e2e/e2e-profiles.json`.

The combined output remains under the ignored `survey/output/` evidence root.

## What the offline proof checks

The matrix must confirm:

- required harness, software-install, profile, and schema files exist;
- the VM profile is closed and fail-safe;
- the fixture installation, validated finalization, and result-presentation journeys are required, network-free, and target-mutation-free;
- `-WhatIf` remains request-only and does not probe the share or target;
- actual VM entry requires a selected provider, a clean checkpoint or ephemeral guest, a host negative gate, approved package identity, supported installer arguments, a guest evidence root, a rollback or destruction plan, and explicit AutoLogon exclusion;
- runtime evidence must include host preflight and postflight, guest baseline and delta, package identity, dry-run plan, install result, application acceptance, and rollback or destruction result;
- an installed VM provider is detected only through command presence and is optional for offline readiness.

## VM provider detection

The validator may report command presence for:

- Hyper-V VMConnect;
- Windows Sandbox;
- VirtualBox;
- VMware `vmrun`.

This is not a provider health check and never starts the provider. No detected provider results in:

```text
[SKIP] optional VM provider smoke - vm_provider_not_available
```

That skip does not invalidate the repository's offline readiness contract. It blocks only the later real VM execution lane until an approved provider is available.

## Existing dry-run proof

`Invoke-SasSoftwareInstallE2E.ps1` already builds a real dummy Windows executable from tracked source and runs it through the production software-install wrapper against an isolated fixture target. It proves transport adaptation, executable launch, logging, package-state deltas, cleanup, and result presentation without WinRM, SMB, or a live workstation.

The one-command VM-readiness validator checks that this executable journey remains present, required, network-free, and target-mutation-free. It deliberately does not launch the dummy installer itself. The repository's separate default fixture-safe E2E workflow executes that generated installer and supplies the stronger executable dry-run proof.

Together they establish:

```text
one-command readiness matrix
-> default fixture-safe executable E2E
-> disposable-VM package testing
-> physical Cybernet proof where hardware or AutoLogon is required
```

The fixture E2E is the safe synthetic dry run. It is not proof that a real vendor package works in a VM.

## Entry gate for actual VM testing

Before a real package can run, record all of the following outside Git:

1. approved VM provider and guest type;
2. clean checkpoint or explicitly ephemeral guest;
3. proof that the package process cannot execute on the host;
4. package SHA-256 and signature posture;
5. vendor- or packaging-supported installer arguments;
6. one package selected for the clean snapshot;
7. guest evidence directory;
8. rollback or destruction procedure;
9. package-specific application acceptance criteria;
10. explicit statement that AutoLogon is excluded.

Run one package per clean snapshot. Preserve evidence, shut down the application, then revert the checkpoint or destroy the guest. Prove the package is absent from the host afterward.

## AutoLogon boundary

AutoLogon is not part of VM package dry-run readiness and must remain disabled in this lane. Its real proof requires an approved physical Cybernet, console recovery, application acceptance, completion of package reboots, explicit authorization, reboot, and observed session behavior.

## Artifacts

The combined command emits:

```text
survey/output/vm-dry-run-harness/harness_validation_matrix.txt
survey/output/vm-dry-run-harness/harness_validation_result.json
survey/output/vm-dry-run-harness/base-harness/<run>/reports/harness_validation_matrix.txt
survey/output/vm-dry-run-harness/base-harness/<run>/reports/harness_validation_result.json
survey/output/vm-dry-run-harness/vm-readiness/vm_dry_run_readiness_matrix.txt
survey/output/vm-dry-run-harness/vm-readiness/vm_dry_run_readiness_result.json
```

The top-level JSON uses `sas-harness-proof/v1` and must keep runtime, network, launcher, target-mutation, and data-mutation claims false.

## Proof ceiling

A green matrix proves synthetic-offline harness integrity and VM dry-run readiness only. It does not prove:

- that a VM was started;
- that a real package executed;
- application launch or behavior;
- VM rollback;
- Cybernet compatibility;
- AutoLogon behavior;
- operator acceptance.
