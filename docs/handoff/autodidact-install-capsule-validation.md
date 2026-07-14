# Approved software catalog install validation handoff

## Sprint status

This branch now provides the technician-facing command:

```cmd
Run-InstallApprovedSoftware.cmd
```

The earlier command remains compatible:

```cmd
Run-InstallAutoDidact.cmd
```

Both launch the catalog-driven workflow:

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

Current entries:

| ID | Folder | Installer | Readiness |
| --- | --- | --- | --- |
| `epic-satellite` | `packages\Epic\Satellite` | pending | Snapshot only; plan/install blocked |
| `allscripts-touchworks-22-1` | `packages\TouchWork_22.1` | `TWInstaller.exe` | Path pinned; validated live arguments pending |
| `autologon` | `packages\AutoLogonSetup` | `NW_AutoLogon_Setup_x64.exe` | Path pinned; validated live arguments pending |

The approved share root is `\\nt2kwb972sms01\`. The launcher does not scan folders to choose an executable.

## Files preserved

- `Run-InstallApprovedSoftware.cmd`
- `Run-InstallAutoDidact.cmd`
- `configs/software-packages/approved-apps.json`
- `scripts/Start-SasAutoDidactInstall.ps1`
- `docs/AUTODIDACT_INSTALL_WORKFLOW.md`
- `Tests/survey/test_autodidact_install_capsule_contracts.py`
- `tests/survey/run_offline_survey_tests.sh`

## Checkpoints

- `667d6d0f3a52e05a347d49cec89a2a1d383b6fae` preserves the folder-first catalog before wrapper expansion.
- The current completion commit updates the catalog consumer, technician launchers, tests, and documentation.

## Connector validation

```text
GitHub compare main...feat/autodidact-install-capsule
PASS: branch is ahead of main and changed files are limited to the approved software catalog/capsule lane.
```

Fetched-content review confirmed:

- the catalog root matches `harness/api/sas-harness-api.json`;
- package folders remain relative to the approved root;
- the normal technician path selects a package ID instead of prompting for a raw installer path;
- Epic fails closed before plan/install because no installer filename is pinned;
- AllScripts and AutoLogon resolve deterministic relative file paths;
- live installation fails closed when vendor-validated installer arguments are absent;
- the selected package/path is bound to the completed Before snapshot;
- a catalog path change after Before requires a new snapshot;
- snapshot evidence remains under `survey/output/approved_software_install` on the admin workstation;
- the catalog contract remains wired into `tests/survey/run_offline_survey_tests.sh`.

## Windows validation commands

Run from the branch on a Windows validation workstation:

```cmd
git diff --check
python .\Tests\survey\test_autodidact_install_capsule_contracts.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$null = [scriptblock]::Create((Get-Content .\scripts\Start-SasAutoDidactInstall.ps1 -Raw)); 'PARSE OK'"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-SasAutoDidactInstall.ps1 -Action ListPackages
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-SasAutoDidactInstall.ps1 -Action Before -PackageId autologon -TargetsCsv .\targets\local\approved-software-targets.csv -FixtureMode -NonInteractive
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-SasAutoDidactInstall.ps1 -Action Plan -NonInteractive
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-SasAutoDidactInstall.ps1 -Action After -FixtureMode -NonInteractive
```

## Proof boundary

This branch proves a guarded catalog and command shape. It does not prove:

- the package files currently exist on the live share;
- installer hashes, signatures, publishers, or versions;
- vendor-supported silent arguments;
- remote-session access to a target;
- a live installation;
- application launch, AutoLogon behavior, or business acceptance.

## Production gate

Before technicians use live Install:

1. validate this branch on Windows;
2. capture a complete Before snapshot;
3. confirm the selected pinned filename still exists in its approved folder;
4. record vendor-validated installer arguments;
5. review the WhatIf output;
6. run no more than one or two approved pilot targets;
7. capture After and review the delta;
8. directly observe the required application/runtime behavior.
