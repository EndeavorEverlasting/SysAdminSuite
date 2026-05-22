# PR #6 Harvest Plan

## Decision

PR #6 must not be merged directly.

It is divergent from current `main`, but it contains useful Neuron maintenance and software-reference payloads. The correct path is to harvest useful files into a fresh branch from current `main`.

## Compare Snapshot

```text
base: main
head: feature/2026-04-30-neuron-tooling-test-readiness
status: diverged
ahead_by: 20
behind_by: 75
merge_base: 451fbc1f8232a41c556a3381624d17c19767a73a
```

## Harvest Review Table

| File | Action |
|---|---|
| `Config/Neuron/baselines/default.neuron.json` | Harvest candidate. Additive baseline file. |
| `GetInfo/Config/NeuronObservedPackages.example.csv` | Harvest candidate. Confirm example data is sanitized. |
| `GetInfo/Config/NeuronSoftwareReferences/11.8.0.328.json` | Harvest candidate. Additive reference file. |
| `GetInfo/Get-NeuronSoftwareReference.ps1` | Harvest candidate. PowerShell GetInfo lane. |
| `QRTasks/Get-NeuronMaintenanceSnapshot.ps1` | Harvest candidate. QRTasks lane. |
| `QRTasks/Invoke-TechTask.ps1` | Manual merge only. Do not overwrite the current dispatcher. |
| `QRTasks/Set-DisableScreensaver.ps1` | Harvest candidate. Review safety posture. |
| `Run-SysAdminSuite-Bash.cmd` | Review before harvest. May overlap with current launchers. |
| `Tests/Pester/NeuronMaintenanceSnapshot.Tests.ps1` | Harvest with Neuron maintenance payload. |
| `Tests/Pester/NeuronSoftwareReference.Tests.ps1` | Harvest with software reference payload. |
| `Tools/MaintenanceStatus/README.md` | Harvest candidate. |
| `Tools/MaintenanceStatus/Run-MaintenanceStatus.cmd` | Harvest candidate if still useful. |
| `Tools/MaintenanceStatus/maintenance_status.sh` | Harvest candidate. Bash-on-Windows review required. |
| `bash/neuron/neuron_maintenance_snapshot.sh` | Harvest candidate. Bash-on-Windows review required. |
| `bash/neuron/neuron_software_reference.sh` | Harvest candidate. Bash-on-Windows review required. |
| `bash/sysadminsuite.sh` | Manual review. May overlap with current Bash entrypoints. |
| `docs/BRANCH_CLEANUP_2026-04-30.md` | Historical record only. Ledger/archive candidate. |
| `docs/NEURON_SOFTWARE_REFERENCE.md` | Harvest candidate. |
| `docs/NeuronMaintenanceTools.md` | Harvest candidate. |

## Required Replacement Workflow

1. Create a fresh branch from current `main`.
2. Copy additive files from PR #6.
3. Manually merge only the QRTasks dispatcher registration from `QRTasks/Invoke-TechTask.ps1`.
4. Review Bash scripts against Bash-on-Windows requirements.
5. Review fixtures and examples for fake or sanitized data only.
6. Run Pester tests where possible.
7. Open a replacement PR named similar to `harvest: recover Neuron maintenance and software reference tooling`.
8. Comment on PR #6 pointing to the replacement PR.
9. Close PR #6 as superseded only after the replacement PR exists.

## Compatibility Rules

Use `docs/CONVERGENCE_COMPATIBILITY_CONTRACT.md` as the governing document for this harvest.

Special attention:

- Preserve PowerShell tooling unless there is tested parity.
- Preserve Bash-on-Windows field behavior.
- Preserve compiled/native long-term direction.
- Do not commit generated output or real device/site data.
- Do not overwrite dispatcher files wholesale.

## Verdict

PR #6 is a harvest source, not a merge source.