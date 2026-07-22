# Cybernet client configuration troubleshooting

## Audience and purpose

Use this guide after `Run-CybernetClientConfiguration.cmd` or `Invoke-CybernetClientConfiguration.ps1` exits nonzero, reports `ACTION_REQUIRED`, or produces evidence that does not match the approved request.

This guide is for authorized technicians and administrators. It does not authorize a target, software source, restart, COM mutation, or workaround transport.

## First response: stop and preserve evidence

Do not rerun Apply immediately. Do not switch to PsExec, WinRM, an interactive installer, a guessed registry setting, a vendor utility, or another transport merely because one stage failed.

Enter the repository and locate the newest run:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

$Run = Get-ChildItem -LiteralPath '.\survey\output\cybernet_hardware' -Directory -Filter 'client-configuration-*' |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

$SummaryPath = Join-Path $Run.FullName 'cybernet_client_configuration_summary.json'
$Summary = Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json

$Summary | Select-Object run_id, mode, status, target_count, failed_stage_count
$Summary.stages | Format-Table name, kind, status, exit_code, console_log -AutoSize
$FailedStages = @($Summary.stages | Where-Object { $_.status -eq 'FAIL' -or $_.exit_code -ne 0 })
$FailedStages | Format-List *
```

Then read:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

Get-Content -LiteralPath (Join-Path $Run.FullName 'operator_handoff.txt')
$FailedStages | ForEach-Object {
    if (Test-Path -LiteralPath $_.console_log -PathType Leaf) {
        "`n===== $($_.name) ====="
        Get-Content -LiteralPath $_.console_log
    }
}
```

Keep live logs and target-identifying evidence in the approved local evidence/ticket process. Do not add them to Git.

## Failure location map

| Failure location | What it means | Safe next action |
|---|---|---|
| Launcher exits `2` | The mode, hostname, or argument count is invalid. | Run `.\Run-CybernetClientConfiguration.cmd Help`; provide exactly one mode and one explicit hostname. |
| PowerShell throws before a run summary exists | A required dependency, target input, output root, profile, or package catalog failed validation. | Correct the controller/repository problem and run Plan again. No target mutation should be assumed. |
| `hardware-plan` fails | The nested hardware Plan could not be produced. | Read `hardware-plan.console.log` and the nested hardware summary. Do not proceed to Apply. |
| `hardware-apply` fails | A no-sleep, power-button, display-button, COM, authorization, or target-access gate failed. | Software is not started. Correct the specific hardware gate, then return to Plan. |
| `approved-software-plan` fails | Git Bash, package-set metadata, software source validation, or dry-run generation failed. | Fix the controller/package evidence. Plan contacts neither target nor software share, so do not treat this as a target installation result. |
| `approved-software-install` fails | The software controller, target admin share, scheduled task, installer result, result retrieval, or cleanup failed. | Review `approved-software.console.log` and the newest `bash/apps/output/` evidence. Account for task/staging cleanup before retrying. |
| `hardware-post-software-validation` fails | Software ran, but the final hardware state no longer passed. | Do not classify the device complete. Review the failed hardware evidence and correct only the documented stage. |
| Status is successful but application behavior fails | Automation passed, but technician acceptance did not. | Record the specific application/shortcut failure. Do not change the automated status into a behavior claim. |
| Restart is required | An installer result requires a restart, or COM/AutoLogon proof requires one. | Use only the separately authorized restart process, then directly observe application and AutoLogon behavior. |

## Controller and request errors

### `Apply requires -AllowTargetMutation`

Cause: the direct PowerShell entrypoint was called in Apply mode without its explicit mutation gate.

Safe correction:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
    -Mode Plan `
    -ComputerName '<AUTHORIZED-CYBERNET>'
```

After reviewing the Plan:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
    -Mode Apply `
    -ComputerName '<AUTHORIZED-CYBERNET>' `
    -AllowTargetMutation
```

Do not add confirmation bypasses to the operator command.

### `No explicit Cybernet targets were supplied`

Provide `-ComputerName` or `-TargetsCsv`. Do not use discovery output, a subnet, or a wildcard.

### Invalid target name or target count exceeded

Target names may contain letters, numbers, `.`, `_`, and `-`, must start with a letter or number, and are deduplicated case-insensitively. Split runs that exceed the configured `-MaxTargets`; the profile hard maximum is 25.

### CSV is outside approved target intake roots

Move or normalize the CSV under:

- `targets/local/`
- `logs/targets/`
- `survey/input/` after staging/normalization

Accepted headers are `ComputerName`, `HostName`, `Hostname`, or `Target`.

### Output root refused

Custom output must remain under an approved generated-output root:

- `survey/output/`
- `logs/nmap/`
- `survey/artifacts/`

Do not redirect live evidence into a source-code or documentation folder.

### Preference profile or package-set mismatch

The workflow intentionally stops when:

- the profile schema is unsupported;
- the hardware preference values are malformed;
- package-set ID resolution is missing or ambiguous;
- the profile and catalog package order differ;
- the package count differs;
- AutoLogon is not last.

Do not edit the catalog during a field run. Use a separately reviewed repository change.

### Git Bash is missing

The workflow searches standard Git for Windows paths and then `bash.exe` on `PATH`. Supply an approved explicit path only when necessary:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
    -Mode Plan `
    -ComputerName '<AUTHORIZED-CYBERNET>' `
    -BashPath '<APPROVED-GIT-BASH-PATH>'
```

Do not substitute an unrelated Linux host for the Windows controller.

## Hardware-stage troubleshooting

### No-sleep or physical power-button failure

Review the nested hardware batch summary and the relevant stage log. The expected state is:

- standby AC/DC timeout index `0`;
- hibernate AC/DC timeout index `0`;
- physical power-button action Do nothing for every parsed power scheme.

Do not edit a single guessed scheme and assume the remaining schemes match.

### Display-button ineligible or unreadable

The Privacy/Menu setting is allowed only when the integrated display proves:

- MCCS 2.2 or later;
- readable VCP `0xCA`;
- host-controllable OSD/menu-button and display power-button bytes.

The desired value is `0x0303`.

The workflow fails closed instead of trying:

- registry guesses;
- BIOS guesses;
- Device Manager properties;
- an unknown Cybernet service or configuration file;
- an unreviewed vendor utility.

When the wrong display was selected on a multi-monitor controller, rerun **Plan** with an explicitly reviewed monitor index:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
    -Mode Plan `
    -ComputerName '<AUTHORIZED-CYBERNET>' `
    -MonitorIndex <INDEX>
```

Do not guess the index during Apply.

### COM classification

The remote workflow reads COM state but never changes it.

| Observed shape | Classification | Required action |
|---|---|---|
| `COM1,COM2,COM3,COM4` | `COM_PORTS_READY` | Continue the reviewed workflow. |
| Exact `COM3,COM4,COM5,COM6` | `COM_AUTOFIX_ELIGIBLE_LOCAL_ONLY` | Stop. Run the local dry-run launcher on the Cybernet and follow the separate reboot-gated AutoFix procedure. |
| Any other shape | `COM_PORT_REVIEW_REQUIRED` | Stop for review. Do not force a mapping. |

Local dry run on the Cybernet:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetComPortAutoFix-DryRun.cmd
```

The local Apply and restart remain separate authorized actions. Resume the composed workflow only after post-reboot COM1-COM4 proof.

## Software-stage troubleshooting

### Review the composed software log

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

Get-Content -LiteralPath (Join-Path $Run.FullName 'approved-software.console.log')
```

Then locate the newest controller outputs:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

Get-ChildItem -LiteralPath '.\bash\apps\output' -File |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 20 Name, LastWriteTimeUtc, Length
```

Review the result CSV, worker/controller log, and package-set metadata associated with the same run. Match by timestamp/run ID; do not mix evidence from different attempts.

### Admin share or Task Scheduler failure

Confirm through the approved support process that:

- the current Windows token is authorized;
- `C$` access is available;
- remote Task Scheduler RPC is available;
- the target Schedule service is available;
- the maintenance window is active.

Do not paste SMB credentials into the composed command. Do not use `--no-teardown` as a field workaround.

### Timeout

The default software wait is 1800 seconds. A reviewed longer timeout may be supplied within `10` to `7200` seconds:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
    -Mode Plan `
    -ComputerName '<AUTHORIZED-CYBERNET>' `
    -SoftwareWaitTimeout 3600
```

Changing the timeout does not correct a failed task, missing result, blocked installer, or cleanup failure. Plan again and document why the override is appropriate before Apply.

### Cleanup uncertainty

The controller is expected to retrieve results and remove the one-time scheduled task and run-scoped target staging. If evidence is missing or contradictory:

1. stop the batch;
2. record the task/run identity from the logs;
3. use the approved cleanup verification process;
4. do not rerun until transient state is accounted for;
5. do not commit raw cleanup evidence to Git.

## Technician acceptance failures

Automated success does not prove the following:

- shortcut points to the intended destination;
- application launches to the expected ready/login surface;
- clinical integration behaves correctly;
- a restart completed safely;
- AutoLogon signs in automatically.

Record the exact failed application and observed behavior. Preserve the controller result as automation evidence, but classify overall device completion as not accepted until the human gate passes.

## Display-button rollback

The combined workflow does not provide a complete-profile rollback. The display-button stage is the one current stage with an exact generated restore path.

Locate the `cybernet_display_button_restore_manifest.json` produced by the prior successful display Apply. The manifest must remain under an approved generated-output root and must contain the target entry.

Plan the restore first:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Enable-PrivacyButton.ps1 `
    -ComputerName '<AUTHORIZED-CYBERNET>' `
    -RestoreManifest '<EXACT-RESTORE-MANIFEST-PATH>' `
    -WhatIf
```

Apply only after separate approval:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Enable-PrivacyButton.ps1 `
    -ComputerName '<AUTHORIZED-CYBERNET>' `
    -RestoreManifest '<EXACT-RESTORE-MANIFEST-PATH>' `
    -AllowTargetMutation
```

The restore script refuses to invent a factory value. A failed Apply readback also triggers the display controller's immediate best-effort restore to the original value.

No equivalent complete-profile rollback command currently exists for software, no-sleep, physical power-button policy, COM ports, or AutoLogon. Use the approved stage-specific correction process.

## Safe retry sequence

After correcting the documented cause:

1. run one-target `Plan` again;
2. verify `PLAN_READY` and the exact approved request;
3. run one-target `Apply` only when authorized;
4. review all three expected Apply stages;
5. complete technician acceptance;
6. run `Validate`;
7. update the ticket/change;
8. expand only after the pilot is accepted.

A retry is a new run with new evidence. Never overwrite the meaning of an earlier failed run.

## Proof boundary

Documentation, static tests, fixture runs, and CI can prove command shape, artifact contracts, fail-closed behavior, and offline composition. They do not prove a real Cybernet was reachable, a real display supported VCP `0xCA`, software installed correctly, cleanup completed on a real target, a restart succeeded, AutoLogon worked, or a technician accepted the applications.
