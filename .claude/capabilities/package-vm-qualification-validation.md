# Package VM Qualification Validation Capability

## Contract

Validate a package-specific disposable-VM qualification profile and report missing evidence without starting a VM or executing the package.

## Operation boundary

- Bind profile fields to prior static, semantic, and trust evidence hashes.
- Remain blocked until required trust, decoding, argument, authorization, acceptance, and rollback gates are satisfied.
- Keep AutoLogon excluded from the package VM lane.
- Emit qualification validation only; runtime proof remains a later authorized lane.

## Authority

- `harness/api/package-vm-qualification-skill.json`
- `tools/package-analysis/validate_vm_qualification_profile.py`
- `schemas/harness/package-vm-qualification-profile.schema.json`
- `docs/PACKAGE_VM_QUALIFICATION_PROFILES.md`

## Forbidden

Never start a VM, install a package, enable AutoLogon, or treat a valid profile as production or clinical acceptance.

## Used by

- `.claude/skills/package-static-analysis/SKILL.md`
