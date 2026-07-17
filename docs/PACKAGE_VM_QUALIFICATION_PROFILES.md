# Package VM Qualification Profiles

## Purpose

This contract sits between package analysis and any authorized disposable-VM run. It describes the package-specific evidence, guest isolation, execution authorization, application acceptance, and rollback requirements that must exist **before** a VM or package is started.

The profile validator is read-only. It does not start a VM, copy a package, execute an installer, contact a certificate endpoint, reboot a guest, launch an application, or perform rollback.

## Canonical surfaces

- Profile schema: `schemas/harness/package-vm-qualification-profile.schema.json`
- Operation contract: `harness/api/package-vm-qualification-skill.json`
- Workflow: `harness/workflows/package-analysis.yaml`
- Validator: `tools/package-analysis/validate_vm_qualification_profile.py`
- Sanitized blocked sample: `Tests/Fixtures/package-vm-qualification/package-vm-qualification.blocked.sample.json`
- Contracts: `Tests/survey/test_package_vm_qualification_profile_contracts.py`

## Validation command

```powershell
python .\tools\package-analysis\validate_vm_qualification_profile.py `
  --profile .\Tests\Fixtures\package-vm-qualification\package-vm-qualification.blocked.sample.json
```

A valid profile may return `status=blocked`. That means the profile honestly represents missing gates; it does not authorize execution.

## Version 2 evidence-state contract

Version 2 stops treating the blocker array as operator-authored truth. The validator derives blockers from the declared evidence state and requires the profile's `decision.blockers` array to match exactly.

The profile now records:

- whether managed code was detected and the strong-name verification status;
- whether MSI content was detected and the full-decode status;
- whether SAPIEN packaging was detected and the exact-payload recovery status;
- online revocation status;
- canonical ignored references for completed strong-name, deep-analysis, and revocation evidence.

A blocker cannot be removed manually while its evidence remains missing, partial, invalid, unsupported, indeterminate, or failed. Conversely, completed evidence cannot be claimed without its canonical result reference.

`not_applicable` is permitted only when the corresponding package shape was not detected. This prevents a managed assembly, MSI, or SAPIEN wrapper from bypassing its required gate by changing only a status string.

## Derived blockers

The validator derives, at minimum:

- `static_analysis_incomplete` when static analysis is incomplete;
- `semantic_analysis_incomplete` when semantic enrichment is incomplete;
- `offline_trust_incomplete` when trust observation or policy evaluation is incomplete;
- `trust_policy_missing` or `trust_policy_not_approved` from policy state;
- `online_revocation_unproven` unless revocation status is `verified`;
- `strong_name_unproven` when managed code is present and strong-name status is not `verified`;
- `msi_decode_incomplete` when MSI content is present and decode status is not `complete`;
- `exact_sapien_payload_unrecovered` when SAPIEN is detected and payload status is not `recovered`;
- installer-argument, VM-provider, authorization, acceptance, and rollback blockers from their owning sections.

A profile cannot be `ready_for_authorized_vm_run` with any derived blocker. A `blocked` profile must contain at least one derived blocker.

## Allscripts posture

The tracked sample uses the `allscripts` package family but contains no real installer identity, signer, endpoint, hostname, argument, or organizational approval.

Allscripts VM entry remains blocked until an approved package-family trust policy exists. The harness must never infer approval from a valid embedded signature, vendor name, or familiar package filename.

The tracked sample intentionally declares managed code, MSI content, and SAPIEN packaging as present with their evidence states unproven. It therefore demonstrates that strong-name, MSI decode, and exact SAPIEN recovery blockers are derived rather than copied from prose.

## Required pre-VM evidence

- offline trust verification must be complete;
- online revocation freshness must be proven before pilot use;
- strong-name cryptographic validity is required when managed code is present;
- complete MSI table, transform, and custom-action decoding is required for MSI packages;
- exact embedded SAPIEN payload recovery is required when SAPIEN packaging is detected;
- installer arguments must come from vendor documentation, a package authority, or an operator-approved manifest;
- application acceptance criteria must be approved;
- rollback or guest destruction must be defined and verifiable.

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

This profile does not replace `docs/VM_DRY_RUN_READINESS.md`. Repository-wide VM readiness proves the harness can safely enter the VM lane. This contract defines what one specific package must prove before that entry.

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

The qualification profile itself must keep `vm_started=false` and `package_executed=false`. Completed runtime proof belongs in a separate result contract.

## AutoLogon and physical Cybernet boundary

AutoLogon is prohibited in the VM qualification lane. It requires a separate physical-Cybernet workflow after package installation, reboot handling, application acceptance, console recovery, authorization, and observed session behavior are complete.

Physical Cybernet acceptance is not implied by a successful VM profile or VM run.

## Proof ceiling

A green validator proves only that the package-specific qualification profile is closed, internally consistent, fail-closed, and truthful about evidence completion, references, authorization, acceptance, isolation, and rollback requirements.

It does not prove online revocation, strong-name validity, exact SAPIEN recovery, MSI behavior, installer success, reboot behavior, application behavior, rollback, Allscripts approval, Cybernet compatibility, AutoLogon, or operator acceptance.
