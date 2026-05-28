# Validation - Pester (2026-05-27)

Validation branch: `docs/post-convergence-validation-2026-05-27`  
Commit under test: `9ec89e44fb2fe24458dbdb799ac64d8b4f796bdf`  
Command:

```powershell
.\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester
```

## Result summary

- Pester version: `5.7.1`
- Total tests: `398`
- Passed: `352`
- Failed: `46`
- Exit code: `1`
- Full log: `_out/validation/pester.log`

## Known gaps

- Missing fixture/config artifacts referenced by tests:
  - `Tests/Fixtures/DeploymentTracker/deployments.csv`
  - `Mapping/Config/host-mappings.csv`
  - `Mapping/Config/wcc_printers.csv`
  - `Config/Neuron/baselines/default.neuron.json`
  - `GetInfo/Config/NeuronTargets.example.csv`
  - `GetInfo/Config/NeuronSoftwareReferences/11.8.0.328.json`
  - `GetInfo/Config/NeuronObservedPackages.example.csv`
  - `docs/NeuronMaintenanceTools.md`
  - `docs/NEURON_SOFTWARE_REFERENCE.md`
- Script parse failure in `scripts/powershell/Invoke-TrackedInstall.ps1` (`$_ .software_id` tokenization errors).
- Multiple registry-related tests fail due `$scriptPath` not initialized in test scripts.
- Repo health checks report many `.ps1` files missing UTF-8 BOM.

## Risks

- Registry install-diff and tracked installer lanes are not reliably testable in current state.
- Neuron maintenance/software reference contracts are partially orphaned (tests expect files absent on `main`).
- Repo-health and parse failures can mask regressions in operational scripts.

## Targets

1. Fix parser error in `scripts/powershell/Invoke-TrackedInstall.ps1` and re-run `TrackedInstall.Tests.ps1`.
2. Restore/realign expected Neuron baseline and reference artifacts, or update tests to current intended paths.
3. Fix `$scriptPath` setup in registry-oriented Pester tests (`Registry*`, `TargetReadiness`).
4. Run BOM normalization workflow and enforce BOM checks in PR gating where policy requires it.
