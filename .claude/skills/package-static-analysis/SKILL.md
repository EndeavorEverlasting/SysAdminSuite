# Package Static Analysis Skill

Use this skill when the task is to inspect an EXE, MSI, MST, MSP, ZIP, application bundle, installer wrapper, script, shortcut, or configuration package and determine what it appears to contain or change **without executing it**.

## Capability dependencies

- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [End-to-End Testing](../../capabilities/end-to-end-testing.md)

## Canonical references

- Analyzer contract: [`harness/api/package-static-analysis-skill.json`](../../../harness/api/package-static-analysis-skill.json)
- Result schema: [`schemas/harness/package-static-analysis-result.schema.json`](../../../schemas/harness/package-static-analysis-result.schema.json)
- Operator guide: [`docs/PACKAGE_STATIC_ANALYSIS.md`](../../../docs/PACKAGE_STATIC_ANALYSIS.md)
- Analyzer: [`tools/package-analysis/analyze_package.py`](../../../tools/package-analysis/analyze_package.py)
- Windows entrypoint: [`scripts/Invoke-SasPackageStaticAnalysis.ps1`](../../../scripts/Invoke-SasPackageStaticAnalysis.ps1)
- Bash entrypoint: [`scripts/invoke-sas-package-static-analysis.sh`](../../../scripts/invoke-sas-package-static-analysis.sh)

## Workflow

1. Confirm the package is operator-local and is not tracked in Git.
2. Require an explicit local input path and an ignored local output directory.
3. Create or reuse the dedicated Python virtual environment.
4. Use the standard-library analyzer first. Optional `pefile` and `olefile` enrichment may be installed only from an approved offline wheelhouse.
5. Hash every analyzed file and classify it by extension and magic header.
6. Inspect bounded PE headers, OLE/compound-file structure, ZIP member metadata, scripts, and configurations.
7. Emit indicator categories and endpoint fingerprints, never raw secrets, credentials, private endpoints, or complete command lines.
8. Separate observed package structure from inferred functionality.
9. Turn findings into package-specific preflight, logging, acceptance, reboot, rollback, VM, and physical-device requirements.
10. Move into a separate disposable-VM lane only after static intake is complete and explicitly authorized.

## Required output distinctions

Report separately:

- observed file identity and hashes;
- certificate-table presence versus verified Authenticode trust;
- imported libraries and structural indicators when optional parsers are available;
- inferred mutation classes;
- unknown or unreadable surfaces;
- static proof ceiling;
- VM/runtime checks still required.

## Forbidden conditions

- Never execute an EXE, MSI, script, shortcut, embedded payload, or custom action from this skill.
- Never follow `.lnk` or `.url` targets.
- Never extract archive payloads by default.
- Never contact discovered URLs, UNC paths, domains, or hosts.
- Never install optional analysis dependencies from the public internet during a package-analysis run.
- Never emit raw strings that may contain credentials, activation data, private endpoints, hostnames, or client configuration.
- Never represent installer completion, application behavior, rollback, or device compatibility as statically proven.

## Proof ceiling

This skill proves bounded static inspection and evidence generation only. Real installation, service behavior, browser policy, driver behavior, reboot handling, application launch, clinical workflow, rollback, and physical Cybernet acceptance require separate authorized VM or runtime proof.
