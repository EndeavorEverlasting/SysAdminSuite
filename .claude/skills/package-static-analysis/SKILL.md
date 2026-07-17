# Package Static Analysis Skill

Use this skill when the task is to inspect an EXE, MSI, MST, MSP, ZIP, application bundle, installer wrapper, script, shortcut, or configuration package and determine what it appears to contain or change **without executing it**.

## Capability dependencies

- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [End-to-End Testing](../../capabilities/end-to-end-testing.md)
- [Package Static Inspection](../../capabilities/package-static-inspection.md)
- [Package Semantic Enrichment](../../capabilities/package-semantic-enrichment.md)
- [Package Offline Trust Verification](../../capabilities/package-offline-trust-verification.md)
- [Package VM Qualification Validation](../../capabilities/package-vm-qualification-validation.md)

## Canonical references

- Static operation: [`harness/api/package-static-analysis-skill.json`](../../../harness/api/package-static-analysis-skill.json)
- Semantic operation: [`harness/api/package-semantic-analysis-skill.json`](../../../harness/api/package-semantic-analysis-skill.json)
- Trust operation: [`harness/api/package-trust-verification-skill.json`](../../../harness/api/package-trust-verification-skill.json)
- VM qualification operation: [`harness/api/package-vm-qualification-skill.json`](../../../harness/api/package-vm-qualification-skill.json)
- Package workflow: [`harness/workflows/package-analysis.yaml`](../../../harness/workflows/package-analysis.yaml)
- Static result schema: [`schemas/harness/package-static-analysis-result.schema.json`](../../../schemas/harness/package-static-analysis-result.schema.json)
- Semantic result schema: [`schemas/harness/package-semantic-analysis-result.schema.json`](../../../schemas/harness/package-semantic-analysis-result.schema.json)
- Trust policy schema: [`schemas/harness/package-trust-policy.schema.json`](../../../schemas/harness/package-trust-policy.schema.json)
- Trust result schema: [`schemas/harness/package-trust-verification-result.schema.json`](../../../schemas/harness/package-trust-verification-result.schema.json)
- VM qualification profile schema: [`schemas/harness/package-vm-qualification-profile.schema.json`](../../../schemas/harness/package-vm-qualification-profile.schema.json)
- Static guide: [`docs/PACKAGE_STATIC_ANALYSIS.md`](../../../docs/PACKAGE_STATIC_ANALYSIS.md)
- Semantic guide: [`docs/PACKAGE_SEMANTIC_ANALYSIS.md`](../../../docs/PACKAGE_SEMANTIC_ANALYSIS.md)
- Trust guide: [`docs/PACKAGE_TRUST_VERIFICATION.md`](../../../docs/PACKAGE_TRUST_VERIFICATION.md)
- VM qualification guide: [`docs/PACKAGE_VM_QUALIFICATION_PROFILES.md`](../../../docs/PACKAGE_VM_QUALIFICATION_PROFILES.md)
- Static analyzer: [`tools/package-analysis/analyze_package.py`](../../../tools/package-analysis/analyze_package.py)
- Semantic sidecar: [`tools/package-analysis/enrich_package_semantics.py`](../../../tools/package-analysis/enrich_package_semantics.py)
- Trust interop: [`tools/package-analysis/SasPackageTrustInterop.cs`](../../../tools/package-analysis/SasPackageTrustInterop.cs)
- VM qualification validator: [`tools/package-analysis/validate_vm_qualification_profile.py`](../../../tools/package-analysis/validate_vm_qualification_profile.py)
- Windows semantic entrypoint: [`scripts/Invoke-SasPackageSemanticAnalysis.ps1`](../../../scripts/Invoke-SasPackageSemanticAnalysis.ps1)
- Bash semantic entrypoint: [`scripts/invoke-sas-package-semantic-analysis.sh`](../../../scripts/invoke-sas-package-semantic-analysis.sh)
- Windows trust entrypoint: [`scripts/Invoke-SasPackageTrust.ps1`](../../../scripts/Invoke-SasPackageTrust.ps1)

## Workflow

1. Confirm the package is operator-local and is not tracked in Git.
2. Require an explicit local input path and ignored local output directory.
3. Create or reuse the dedicated Python virtual environment.
4. Run the canonical static inventory first. Optional `pefile` and `olefile` enrichment may be installed only from an approved offline wheelhouse.
5. Require the semantic sidecar to consume that static result and re-verify every source hash.
6. Reject changed, missing, symlinked, reparse-point, or root-escaping sources.
7. Inspect bounded PE/CLR metadata, SAPIEN and PowerShell-host markers, MSI/OLE table signals, archives, scripts, and configurations.
8. Emit generic packaging signals, behavior inferences, and endpoint fingerprints, never raw secrets, credentials, private endpoints, stream names, or complete command lines.
9. On Windows, run trust observation against the same static result before creating a deployment policy.
10. Review the generated starter policy. Never auto-approve an observed signer or unsigned wrapper.
11. Require valid signed code to match an exact approved signer subject or thumbprint.
12. Require unsigned internal code to be pinned by exact SHA-256 and an explicit approval reference.
13. Keep certificate-table presence, offline Authenticode policy, online revocation, strong-name validation, and runtime behavior as separate evidence levels.
14. Convert findings into package-specific preflight, logging, acceptance, reboot, rollback, VM, and physical-device requirements.
15. Create a package-specific disposable-VM qualification profile and validate it with `validate_vm_qualification_profile.py`.
16. Keep the profile blocked until required trust policy, online revocation, strong-name, SAPIEN/MSI decoding, supported arguments, authorization, application acceptance, and rollback gates are satisfied.
17. Move into a separate disposable-VM execution lane only after static intake, semantic intake, trust policy, and the qualification profile are complete and explicitly authorized.

## Required output distinctions

Report separately:

- observed file identity and re-verified hashes;
- certificate-table or strong-name presence versus verified trust;
- cache-only Authenticode integrity/local trust versus online revocation freshness;
- observed signer identity versus explicitly approved signer policy;
- CLR metadata and managed packaging versus strong-name cryptographic validity and observed managed runtime behavior;
- MSI table markers versus decoded tables and executed custom actions;
- SAPIEN/PowerShell-host markers versus the exact embedded script and runtime path;
- inferred mutation classes;
- generated harness requirements;
- package-specific VM qualification blockers;
- unknown or unreadable surfaces;
- current proof ceiling;
- VM/runtime checks still required.

## Forbidden conditions

- Never execute an EXE, MSI, script, shortcut, embedded payload, or custom action from this skill.
- Never start a VM from the qualification-profile validator.
- Never follow `.lnk`, `.url`, symlink, junction, or other reparse-point targets.
- Never extract archive or packaged-script payloads by default.
- Never contact discovered URLs, UNC paths, domains, hosts, CRL, OCSP, or certificate endpoints.
- Never install optional dependencies from the public internet during a package-analysis run.
- Never emit raw strings that may contain credentials, activation data, private endpoints, hostnames, stream names, or client configuration.
- Never auto-approve an observed signer.
- Never treat an invalid signature as an unsigned-package exception.
- Never represent offline trust as current online revocation proof.
- Never represent strong-name presence, installer completion, application behavior, rollback, or device compatibility as proven.
- Never infer Allscripts or another package-family trust approval from a filename, signer label, or embedded signature alone.

## Proof ceiling

This skill can prove bounded static inspection, source-hash continuity, semantic inference, harness-requirement generation, a cache-only Windows Authenticode policy result, and fail-closed VM qualification-profile validation. Online revocation, strong-name cryptographic validity, real installation, service behavior, browser policy, driver behavior, reboot handling, application launch, clinical workflow, rollback, physical Cybernet acceptance, AutoLogon, and operator acceptance require separate authorized validation lanes.
