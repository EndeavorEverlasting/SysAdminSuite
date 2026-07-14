# Auto Didact install capsule validation handoff

## Sprint status

This sprint added a production-facing command surface for technicians:

```cmd
Run-InstallAutoDidact.cmd
```

The command opens a menu that enforces:

```text
BEFORE snapshot -> WhatIf plan -> approved install -> AFTER snapshot -> local delta review
```

## Files preserved

- `Run-InstallAutoDidact.cmd`
- `scripts/Start-SasAutoDidactInstall.ps1`
- `docs/AUTODIDACT_INSTALL_WORKFLOW.md`
- `Tests/survey/test_autodidact_install_capsule_contracts.py`
- `tests/survey/run_offline_survey_tests.sh`

## Validation performed in connector environment

```text
GitHub compare main...feat/autodidact-install-capsule
PASS: branch is 7 commits ahead, 0 behind, with changes limited to the Auto Didact install capsule surfaces, validation handoff, and test runner wiring.
```

Static fetched-content review confirmed:

- the CMD uses the repo-relative PowerShell wrapper;
- the wrapper imports existing target-intake policy and delegates install to `Invoke-SasSoftwareInstall.ps1`;
- before snapshot must be complete before install;
- snapshots write only local admin-box evidence under `survey/output/autodidact_install`;
- snapshot collection uses uninstall registry inventory rather than `Win32_Product`;
- the docs state the proof boundary and pilot requirements;
- the static contract is wired into `tests/survey/run_offline_survey_tests.sh`.

## Skipped checks

The connector sandbox has no local checkout and cannot run Windows PowerShell. Run these on a Windows validation workstation:

```cmd
git diff --check
python .\Tests\survey\test_autodidact_install_capsule_contracts.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$null = [scriptblock]::Create((Get-Content .\scripts\Start-SasAutoDidactInstall.ps1 -Raw)); 'PARSE OK'"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-SasAutoDidactInstall.ps1 -Action Before -TargetsCsv .\targets\local\approved-autodidact-targets.csv -InstallerRelativePath "<relative path under approved root>" -FixtureMode -NonInteractive
```

## Proof boundary

This branch proves a guarded command surface and static contract shape. It does not prove:

- the real Auto Didact installer path;
- the installer signature or publisher;
- real package-share reachability;
- target remote-session access;
- a live install;
- application launch or business behavior after install.

## Production gate before field use

Before technicians use the install action on live targets, confirm:

1. the target CSV is approved and limited to a pilot batch;
2. the Auto Didact installer path is relative to `\\nt2kwb972sms01\`;
3. silent arguments are vendor-supported;
4. the Before snapshot completes for every target;
5. the WhatIf plan writes local evidence;
6. a one- or two-target pilot is reviewed before expansion.
