# Progress reporting contract

Long-running SysAdminSuite operator actions must report determinate progress when a total is known and must always name their lifecycle state. The required states are `running`, `waiting`, `complete`, `failed`, and `skipped`. Animation may supplement these states, but cannot replace them.

Bash scripts source `survey/lib/sas-progress.sh`. Human progress goes to stderr so CSV, JSON, and other stdout output stays machine-readable. Accept `--no-progress` and call `sas_progress_disable`, or honor `SAS_PROGRESS=0` for noninteractive callers.

PowerShell scripts import `scripts/SasProgress.psm1`. Create a context with `New-SasProgressContext`, pass `-NoProgress` when requested, and publish transitions with `Write-SasProgressState`. The helper uses the information/progress streams and does not emit success-stream objects. Callers remain responsible for mapping caught errors to `failed` before returning a nonzero exit code.

## Covered entrypoints

| Surface | Entrypoints | Coverage |
|---|---|---|
| Bash transport | `sas-network-preflight.sh`, `sas-printer-probe.sh`, `sas-smb-readonly-recon.sh`, `sas-wmi-identity.sh`, `sas-workstation-identity.sh` | Determinate per-target bars, completion/failure, stderr routing, `--no-progress` |
| Dashboard bootstrap | `Launch-SysAdminSuiteDashboard.Host.bat`, `scripts/ensure-dashboard-host.sh` | Child/bootstrap running, complete, failed, fallback skipped, determinate bootstrap stages |
| Dashboard relay | `dashboard/relay.py`, `dashboard/js/relay-client.js`, `dashboard/js/run-control.js` | Running/progress/completion/failure plus explicit waiting and skipped lifecycle states; unexpected relay failures reach the browser |
| Harness validator | `Run-HarnessValidation.cmd` | PowerShell child process reports running, complete, or failed with its exit code |
| PowerShell convention | `scripts/SasProgress.psm1` | Shared required-state, determinate-count, status-channel, and suppression behavior |

## Inventoried but not converted in this bounded PR

| Surface | Reason |
|---|---|
| `survey/sas-network-preflight.ps1` | Already has determinate `Write-Progress`; PR #144 owns the same file, so suppression and shared-helper adoption are deferred to avoid collision. |
| `scripts/validate-sysadmin-harness.ps1` | PR #154 owns the validator implementation. Its non-overlapping `.cmd` child-process wrapper is covered here. |
| Naabu, packet-probe, reconciliation, and deployment-audit pipelines | They have different totals and evidence semantics. Converting them safely needs per-workflow design and fixture coverage; no runtime behavior is changed here. |
| App install, staging, mapping workers, QR tasks, and GUI launchers | These are mutation-capable or interactive Windows lanes. They need dedicated PowerShell/Bash adoption without changing authorization, teardown, or target behavior. |
| Archived mapping scripts | Retained historical/reference tooling; inventory only, with no deprecation or deletion. |

## Contract checks

`Tests/bash/test_progress_reporting_contracts.sh` locks the shared states, status channels, suppression switches, covered entrypoints, dashboard child failure propagation, and launcher/validator lifecycle markers. `Tests/Pester/SasProgress.Tests.ps1` verifies PowerShell state and suppression behavior. New long-running entrypoints in the covered operational families must adopt a helper and be added to the covered table and contract test; otherwise they must be listed as uncovered with a concrete reason.
