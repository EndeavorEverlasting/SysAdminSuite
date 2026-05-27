# Registry Install Diff Bash Wrapper

## Purpose
`scripts/sas_registry_install_diff.sh` is a Bash-on-Windows field entrypoint for the Registry Install Diff Pipeline. It provides a technician-friendly CLI that forwards execution to the PowerShell orchestrator.

## Relationship to PowerShell orchestrator
The wrapper calls `scripts/powershell/Invoke-RegistryInstallDiff.ps1` and only performs argument translation / runtime selection. Registry snapshotting, tracked install execution, diffing, classification, and evidence export all remain in PowerShell.

## Safety posture
- Evidence-first workflow.
- No registry parsing in Bash.
- No registry writes from Bash.
- No direct installer execution from Bash.
- If PowerShell is unavailable, the wrapper fails clearly.

## Usage examples
```bash
./scripts/sas_registry_install_diff.sh --mode ReconOnly --target localhost
./scripts/sas_registry_install_diff.sh --mode SnapshotOnly --target localhost --output-root exports/registry-install-diff
./scripts/sas_registry_install_diff.sh --mode AnalyzeInstall --target localhost --software-id EXAMPLE-SOFTWARE-ID --dry-run
```

## Argument mapping
- `--mode` -> `-Mode`
- `--target` -> `-Target`
- `--targets-csv` -> `-TargetsCsv`
- `--software-id` -> `-SoftwareId`
- `--source-config-path` -> `-SourceConfigPath`
- `--registry-watchlist-path` -> `-RegistryWatchlistPath`
- `--output-root` -> `-OutputRoot`
- `--dry-run` -> `-DryRun`
- `--installer-path` -> `-InstallerPath`
- `--installer-type` -> `-InstallerType`
- `--silent-args` -> `-SilentArgs`

## PowerShell availability behavior
Wrapper runtime selection order:
1. `pwsh`
2. `powershell`

If neither is available, the wrapper exits with:
`POWERSHELL_UNAVAILABLE_IN_ENVIRONMENT`

## Known limitations
- Localhost-first behavior; remote batch install execution is not implemented in this slice.
- Dependency scripts must exist for full pipeline execution.
- ApprovedRemediation mode is intentionally unsupported.

## No registry parsing in Bash
Bash is an invocation layer only. Registry operations and evidence analysis remain in PowerShell dependency scripts and orchestrator workflow.
