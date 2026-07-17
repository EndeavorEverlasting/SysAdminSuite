# Package Static Analysis Skill

Use this skill when the task is to inspect an EXE, MSI, MST, MSP, ZIP, application bundle, installer wrapper, script, shortcut, or configuration package and determine what it appears to contain or change **without executing it**.

## Capability dependencies

- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [End-to-End Testing](../../capabilities/end-to-end-testing.md)

## Canonical references

- Static operation: [`harness/api/package-static-analysis-skill.json`](../../../harness/api/package-static-analysis-skill.json)
- Semantic operation: [`harness/api/package-semantic-analysis-skill.json`](../../../harness/api/package-semantic-analysis-skill.json)
- VM qualification operation: [`harness/api/package-vm-qualification-skill.json`](../../../harness/api/package-vm-qualification-skill.json)
- Static result schema: [`schemas/harness/package-static-analysis-result.schema.json`](../../../schemas/harness/package-static-analysis-result.schema.json)
- Semantic result schema: [`schemas/harness/package-semantic-analysis-result.schema.json`](../../../schemas/harness/package-semantic-analysis-result.schema.json)
- VM qualification profile schema: [`schemas/harness/package-vm-qualification-profile.schema.json`](../../../schemas/harness/package-vm-qualification-profile.schema.json)
- Static guide: [`docs/PACKAGE_STATIC_ANALYSIS.md`](../../../docs/PACKAGE_STATIC_ANALYSIS.md)
- Semantic guide: [`docs/PACKAGE_SEMANTIC_ANALYSIS.md`](../../../docs/PACKAGE_SEMANTIC_ANALYSIS.md)
- VM qualification guide: [`docs/PACKAGE_VM_QUALIFICATION_PROFILES.md`](../../../docs/PACKAGE_VM_QUALIFICATION_PROFILES.md)
- Static analyzer: [`tools/package-analysis/analyze_package.py`](../../../tools/package-analysis/analyze_package.py)
- Semantic sidecar: [`tools/package-analysis/enrich_package_semantics.py`](../../../tools/package-analysis/enrich_package_semantics.py)
- VM qualification validator: [`tools/package-analysis/validate_vm_qualification_profile.py`](../../../tools/package-analysis/validate_vm_qualification_profile.py)
- Windows composed entrypoint: [`scripts/Invoke-SasPackageSemanticAnalysis.ps1`](../../../scripts/Invoke-SasPackageSemanticAnalysis.ps1)
- Bash composed entrypoint: [`scripts/invoke-sas-package-semantic-analysis.sh`](../../../scripts/invoke-sas-package-semantic-analysis.sh)

## Workflow

1. Confirm the package is operator-local and is not tracked in Git.
2. Require an explicit local input path and ignored local output directory.
3. Create or reuse the dedicated Python virtual environment.
4. Run the canonical static inventory first. Optional `pefile` and `olefile` enrichment may be installed only from an approved offline wheelhouse.
5. Require the semantic sidecar to consume that static result and re-verify every source hash.
6. Reject changed, missing, symlinked, or root-escaping sources.
7. Inspect bounded PE/CLR metadata, SAPIEN and PowerShell-host markers, MSI/OLE table signals, archives, scripts, and configurations.
8. Emit generic packaging signals, behavior inferences, and endpoint fingerprints, never raw secrets, credentials, private endpoints, stream names, or complete command lines.
9. Keep observed structure, static inference, verified trust, and runtime behavior as separate evidence levels.
10. Convert findings into package-specific preflight, logging, acceptance, reboot, rollback, VM, and physical-device requirements.
11. Create a package-specific disposable-VM qualification profile and validate it with `validate_vm_qualification_profile.py`.
12. Keep the profile blocked until required trust policy, online revocation, strong-name, SAPIEN/MSI decoding, supported arguments, authorization, application acceptance, and rollback gates are satisfied.
13. Move into a separate disposable-VM execution lane only after static intake, semantic intake, trust policy, and the qualification profile are complete and explicitly authorized.

## Required output distinctions

Report separately:

- observed file identity and re-verified hashes;
- certificate-table or strong-name presence versus verified trust;
- CLR metadata and managed packaging versus observed managed runtime behavior;
- MSI table markers versus decoded tables and executed custom actions;
- SAPIEN/PowerShell-host markers versus the exact embedded script and runtime path;
- inferred mutation classes;
- generated harness requirements;
- package-specific VM qualification blockers;
- unknown or unreadable surfaces;
- static proof ceiling;
- VM/runtime checks still required.

## Forbidden conditions

- Never execute an EXE, MSI, script, shortcut, embedded payload, or custom action from this skill.
- Never start a VM from the qualification-profile validator.
- Never follow `.lnk` or `.url` targets.
- Never extract archive or packaged-script payloads by default.
- Never contact discovered URLs, UNC paths, domains, hosts, CRL, or OCSP endpoints.
- Never install optional dependencies from the public internet during a package-analysis run.
- Never emit raw strings that may contain credentials, activation data, private endpoints, hostnames, stream names, or client configuration.
- Never represent strong-name presence, installer completion, application behavior, rollback, or device compatibility as statically proven.
- Never infer Allscripts or another package-family trust approval from a filename, signer label, or embedded signature alone.

## Proof ceiling

This skill proves bounded static inspection, source-hash continuity, semantic inference, harness-requirement generation, and fail-closed VM qualification-profile validation only. Real installation, service behavior, browser policy, driver behavior, reboot handling, application launch, online revocation, strong-name validity, rollback, physical Cybernet acceptance, AutoLogon, and operator acceptance require separate authorized runtime proof.
