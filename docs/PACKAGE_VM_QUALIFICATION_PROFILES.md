# Package VM Qualification Profiles

## Purpose

This contract sits between static or semantic package analysis and any authorized disposable-VM run. It describes the package-specific evidence, guest isolation, execution authorization, application acceptance, and rollback requirements that must exist **before** a VM or package is started.

The profile validator is read-only. It does not start a VM, copy a package, execute an installer, contact a certificate endpoint, reboot a guest, launch an application, or perform rollback.

## Canonical surfaces

- Profile schema: `schemas/harness/package-vm-qualification-profile.schema.json`
- Operation contract: `harness/api/package-vm-qualification-skill.json`
- Validator: `tools/package-analysis/validate_vm_qualification_profile.py`
- Sanitized blocked sample: `Tests/Fixtures/package-vm-qualification/package-vm-qualification.blocked.sample.json`
- Contracts: `Tests/survey/test_package_vm_qualification_profile_contracts.py`

## Validation command

```powershell
python .\tools\package-analysis\validate_vm_qualification_profile.py `
  --profile .\Tests\Fixtures\package-vm-qualification\package-vm-qualification.blocked.sample.json
```

A valid profile may still return `status=blocked`. That means the profile honestly represents missing gates; it does not authorize execution.

## Allscripts posture

The tracked sample uses the `allscripts` package family but contains no real installer identity, signer, endpoint, hostname, argument, or organizational approval.

Allscripts VM entry remains blocked until an approved package-family trust policy exists. The policy reference must be explicit and repository-relative or operator-local evidence must remain outside Git. The harness must never infer approval from a valid embedded signature, a vendor name, or a familiar package filename.

## Required pre-VM evidence

The profile makes these unresolved package-analysis gates explicit:

- offline trust verification must be complete;
- online revocation freshness must be proven before pilot use;
- strong-name cryptographic validity is required when managed code is present;
- complete MSI table, transform, and custom-action decoding is required for MSI packages;
- exact embedded SAPIEN payload recovery is required when SAPIEN packaging is detected;
- installer arguments must come from vendor documentation, a package authority, or an operator-approved manifest;
- application acceptance criteria must be approved;
- rollback or guest destruction must be defined and verifiable.

A profile cannot move to `ready_for_authorized_vm_run` while any declared blocker remains.

## Guest isolation

Every profile requires:

- a disposable guest or clean checkpoint;
- exactly one package per clean snapshot;
- package execution forbidden on the host;
- disconnected or explicitly isolated allowlist networking;
- shared clipboard disabled;
- shared folders disabled;
- AutoLogon disabled;
- checkpoint reversion or guest destruction after evidence capture.

This profile does not replace the existing repository-wide VM readiness contract. `docs/VM_DRY_RUN_READINESS.md` proves the harness is safe to enter the VM lane. This contract defines what one specific package must prove before that entry.

## Runtime evidence boundary

A future authorized VM runner must produce separate gitignored evidence for:

- host preflight;
- guest baseline;
- package identity and trust;
- execution plan;
- install result;
- reboot result;
- application acceptance;
- guest delta;
- rollback or destruction result;
- host postflight.

The qualification profile itself must keep `vm_started=false` and `package_executed=false`. Completed runtime proof belongs in a separate result contract and must never be represented by editing the profile.

## AutoLogon and physical Cybernet boundary

AutoLogon is prohibited in the VM qualification lane. It requires a separate physical-Cybernet workflow after package installation, reboot handling, application acceptance, console recovery, authorization, and observed session behavior are complete.

Physical Cybernet acceptance is not implied by a successful VM profile or VM run.

## Proof ceiling

A green validator proves only that the package-specific qualification profile is closed, internally consistent, fail-closed, and explicit about trust, decoding, authorization, acceptance, evidence, and rollback requirements.

It does not prove online revocation, strong-name validity, exact SAPIEN recovery, MSI behavior, installer success, reboot behavior, application behavior, rollback, Allscripts approval, Cybernet compatibility, AutoLogon, or operator acceptance.
