# Approved software catalog install validation handoff

## Sprint status

Technician entrypoint:

```cmd
Run-InstallApprovedSoftware.cmd
```

Compatibility entrypoint:

```cmd
Run-InstallAutoDidact.cmd
```

Both launch the catalog-driven operator workflow:

```text
select package
-> BEFORE snapshot
-> WhatIf plan
-> approved install
-> AFTER snapshot
-> local delta review
```

## Catalog

Tracked authority:

```text
configs/software-packages/approved-apps.json
```

| ID | Folder | Installer | Readiness |
| --- | --- | --- | --- |
| `epic-satellite` | `packages\Epic\Satellite` | pending | Snapshot only; plan/install blocked |
| `allscripts-touchworks-22-1` | `packages\TouchWork_22.1` | `TWInstaller.exe` | Path pinned; validated live arguments pending |
| `autologon` | `packages\AutoLogonSetup` | `NW_AutoLogon_Setup_x64.exe` | Path pinned; validated live arguments pending |

The approved share root is `\\nt2kwb972sms01\`. The operator does not scan package folders to select an executable.

## Files preserved

- `Run-InstallApprovedSoftware.cmd`
- `Run-InstallAutoDidact.cmd`
- `configs/software-packages/approved-apps.json`
- `scripts/Start-SasApprovedSoftwareOperator.ps1`
- `scripts/Start-SasApprovedSoftwareInstall.ps1`
- `scripts/Start-SasAutoDidactInstall.ps1`
- `docs/AUTODIDACT_INSTALL_WORKFLOW.md`
- `Tests/survey/test_autodidact_install_capsule_contracts.py`
- `.github/workflows/approved-software-catalog-contracts.yml`
- `tests/survey/run_offline_survey_tests.sh`

## Preservation checkpoint

```text
667d6d0f3a52e05a347d49cec89a2a1d383b6fae feat(software): add approved package catalog
```

This checkpoint preserved the folder-first catalog before expanding into technician wrappers, validation, and documentation.

## Failures found and repaired

The dedicated Windows fixture exposed two integration defects:

1. The first snapshot manifest wrapped a generic PowerShell list during JSON materialization. The individual snapshot succeeded, but the manifest was not written. The repaired engine uses bounded PowerShell arrays for snapshot and delta collections.
2. The existing install engine completed its WhatIf run and wrote a valid `software_install_summary.json` plus `operator_handoff.txt`, but the final in-memory summary object did not materialize cleanly through the composed PowerShell pipeline. The technician operator now validates the durable summary artifact, confirms target counts and WhatIf completion, records the handoff in workflow state, and preserves live failure reporting.

Neither repair contacts the live software share or a target during fixture validation.

## Validation completed

Dedicated GitHub Actions run:

```text
Approved software catalog contracts #15
run id: 29314828855
head: 44991f8ba18e815bd2591de23afe982f5482a7cf
```

Ubuntu static job: **PASS**

- full checkout with credentials not persisted;
- `git diff --check`;
- `python3 Tests/survey/test_autodidact_install_capsule_contracts.py`.

Windows fixture job: **PASS**

- Python catalog contracts;
- parser validation for operator, engine, and compatibility wrappers;
- catalog listing;
- synthetic target manifest preparation;
- complete fixture BEFORE snapshot and manifest;
- complete WhatIf install plan;
- complete fixture AFTER snapshot;
- delta and operator-state verification;
- synthetic artifact upload.

Synthetic proof artifact:

```text
approved-software-catalog-synthetic-proof
artifact id: 8303505390
sha256: 80fbefd0a9ad8cad468cc1e6df81d60b6c14a93f49efc1fcf2dbdac6f573444a
```

## Proof boundary

This validation proves:

- package catalog structure and fail-closed readiness rules;
- technician CMD routing;
- PowerShell parser correctness;
- fixture BEFORE snapshot preservation;
- request-only WhatIf planning through the existing install engine;
- fixture AFTER snapshot and local delta generation;
- durable artifact recovery and operator-state continuity.

It does not prove:

- package files currently exist on the live share;
- installer hashes, signatures, publishers, or versions;
- vendor-supported silent arguments;
- remote-session access to a workstation;
- a live installation;
- application launch, AutoLogon behavior, or business acceptance.

## Production gate

Before technicians use the live Install action:

1. use an approved pilot target CSV;
2. capture and review a complete Before snapshot;
3. confirm the selected pinned filename still exists in its approved folder;
4. validate package hash, signature, publisher, version, and installer arguments;
5. review the WhatIf output;
6. run no more than one or two approved pilot targets;
7. capture After and review the delta;
8. directly observe the required application/runtime behavior.
