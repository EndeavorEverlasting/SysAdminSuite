# Cybernet client configuration operator tutorial

## Audience and outcome

This tutorial is for an authorized field technician, deployment technician, Windows administrator, or project lead preparing Cybernet clinical workstations.

Use the composed workflow when the assignment includes the client's hardware preferences and the approved software set together. The workflow is complete only when automated evidence and technician-observed behavior are both recorded.

The current preference profile requires:

- standby and hibernate idle timeouts set to **Never** for AC and DC;
- the Windows physical power button set to **Do nothing**;
- supported integrated-display Privacy/Menu and display power-button events disabled through MCCS 2.2 DDC/CI VCP `0xCA = 0x0303`;
- COM ports verified as `COM1, COM2, COM3, COM4`;
- the approved six-package clinical workstation set installed in reviewed order;
- hardware validated again after software installation;
- every required shortcut/application checked by a technician;
- any separately authorized reboot and AutoLogon behavior observed afterward.

The machine-readable source of truth is `Config/cybernet-client-preferences.json`. The one-command implementation is `Hardware/Cybernet/Invoke-CybernetClientConfiguration.ps1`.

## Choose the correct operating surface

| Surface | Use it for | Do not use it for |
|---|---|---|
| **Windows admin workstation or approved admin VM** | Run `Run-CybernetClientConfiguration.cmd` or the PowerShell entrypoint, review evidence, and record the result. | Do not place passwords in commands or improvise a different transport. |
| **Git Bash on the Windows controller** | The composed PowerShell workflow invokes `bash/apps/sas-install-apps.sh` internally for the approved package set. | The technician does not need to reconstruct the internal package-set command for the combined workflow. |
| **Browser dashboard** | Use the browser-first tutorial for the generic software-only workflow. | The browser tutorial does not apply Cybernet no-sleep, power-button, display-button, or COM policy. |
| **Cybernet target machine** | Perform application/shortcut acceptance, the separately gated local COM AutoFix when eligible, and any separately authorized restart observation. | Do not run the combined remote controller from the target unless that machine is explicitly approved as the controller. |
| **Linux or macOS** | Read documentation and static artifacts only. | The current composed controller is a Windows workflow and is not documented as a native Linux or macOS execution path. |

## Approved software set

The profile uses package-set ID `cybernet-clinical-workstation` from `configs/software-packages/windows-native-package-sets.json`:

1. Allscripts EEHR Shortcut UAI 2.2
2. Epic Downtime Guide Shortcut 1.0
3. Nuance Dragon Medical One 2025
4. Hyland FOS Epic Integration 23.1.33.1000
5. Epic BCA Web Shortcut 1.0
6. NW AutoLogon Setup x64

**AutoLogon must remain last.** The workflow does not reboot the workstation. An installer result such as MSI exit code `3010` records a restart requirement; it does not authorize the restart or prove automatic sign-in.

## What each mode really does

### Plan — safe default

`Plan` is request-only:

1. validates the tracked preference profile and exact package-set order;
2. creates the nested hardware Plan;
3. runs the approved package-set controller with `--dry-run`;
4. writes the summary, stage logs, handoff, and technician acceptance checklist;
5. contacts neither the target nor the software share;
6. performs no target mutation.

Successful status: `PLAN_READY`.

### Apply — authorized mutation

`Apply` requires `-AllowTargetMutation` and one high-impact confirmation. It performs this order:

1. applies and validates no-sleep, physical power-button, display-button, and COM readiness through `Invoke-CybernetBatchConfiguration.ps1`;
2. stops before software when the hardware or COM gate fails;
3. installs the approved package set through the Windows controller, target `C$` administrative share, and a one-time SYSTEM scheduled task;
4. retrieves result evidence and verifies task/staging cleanup;
5. validates hardware again after software;
6. emits the technician acceptance checklist.

Successful status: `APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED`.

That status means the composed automated stages passed. It does **not** mean application behavior, reboot behavior, or AutoLogon was accepted.

### Validate — read-only hardware proof

`Validate` rechecks:

- every parsed Windows power scheme has standby and hibernate AC/DC indexes at zero;
- the physical power-button action is Do nothing;
- the selected integrated display reports VCP `0xCA = 0x0303`;
- COM ports are `COM1, COM2, COM3, COM4`.

Successful status: `HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED`.

Validate does not reinstall software and does not infer software behavior from installer exit codes.

## Controller prerequisites

Use an approved Windows admin workstation or admin VM with:

- Windows PowerShell 5.1 or PowerShell 7;
- a current authorized Windows administrative token;
- the current SysAdminSuite checkout;
- Git for Windows / Git Bash, either in a standard installation path or supplied with `-BashPath`;
- approved access to each explicit target;
- access to each target's `C$` administrative share;
- remote Task Scheduler RPC and the target Schedule service available;
- read access to the approved software source;
- an authorized target, package scope, ticket/change, operator, and maintenance window.

Never place a password in the command. Do not use wildcard hostnames, subnets, discovery output, or more than 25 explicit targets.

## Controller preflight

Start every command block by entering the repository:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'
```

Review launcher and PowerShell help:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Help
Get-Help .\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 -Full
```

Verify the tracked entrypoints exist without contacting a target:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

@(
    '.\Run-CybernetClientConfiguration.cmd'
    '.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1'
    '.\Config\cybernet-client-preferences.json'
    '.\configs\software-packages\windows-native-package-sets.json'
    '.\bash\apps\sas-install-apps.sh'
) | ForEach-Object {
    [pscustomobject]@{
        Path = $_
        Present = Test-Path -LiteralPath $_ -PathType Leaf
    }
}
```

Every `Present` value must be `True`. Missing dependencies are a repository/controller problem; do not work around them on the target.

## One-target pilot

The root `.cmd` launcher accepts exactly one mode and one explicit hostname. It is the preferred technician entrypoint for a pilot.

### 1. Plan one authorized target

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Plan <AUTHORIZED-CYBERNET>
```

Expected process exit code: `0`.

The newest run is created under:

```text
survey\output\cybernet_hardware\client-configuration-<timestamp>-<id>
```

Inspect the newest summary and stage table:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

$Run = Get-ChildItem -LiteralPath '.\survey\output\cybernet_hardware' -Directory -Filter 'client-configuration-*' |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

$SummaryPath = Join-Path $Run.FullName 'cybernet_client_configuration_summary.json'
$Summary = Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json

$Summary | Select-Object run_id, mode, status, target_count, package_set_id, failed_stage_count
$Summary.stages | Format-Table name, kind, mode, status, exit_code, dry_run -AutoSize
Get-Content -LiteralPath (Join-Path $Run.FullName 'operator_handoff.txt')
```

Required Plan evidence:

- `status` is `PLAN_READY`;
- `failed_stage_count` is `0`;
- the hardware stage passed in Plan mode;
- the approved-software stage passed with `dry_run = True`;
- the target and package set are correct;
- no reboot or remote COM mutation is planned;
- the technician acceptance file exists.

### 2. Apply one authorized pilot

Run Apply only after the Plan matches the approved request:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Apply <AUTHORIZED-CYBERNET>
```

Read the high-impact confirmation carefully. Confirm only when the hostname, profile, package set, and maintenance window match the approved request.

Expected successful status:

```text
APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED
```

Expected successful stage order:

1. `hardware-apply`
2. `approved-software-install`
3. `hardware-post-software-validation`

If the process exits nonzero or the status is `ACTION_REQUIRED`, stop and use [Cybernet client configuration troubleshooting](CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md). Do not rerun Apply blindly.

### 3. Complete technician software acceptance

Open the generated file in the same run folder:

```text
technician_software_acceptance.txt
```

At the Cybernet, or through the normal approved support session:

1. confirm each expected shortcut/application exists;
2. open Allscripts EEHR and confirm the expected launch path;
3. open Epic Downtime Guide and confirm the intended guide destination;
4. open Dragon Medical One and confirm its expected ready/login surface;
5. open Hyland FOS Epic Integration and confirm the expected integration surface;
6. open the Epic BCA shortcut and confirm the approved destination;
7. record AutoLogon as installed only;
8. do not claim automatic sign-in until after a separately authorized reboot and direct observation;
9. confirm no unapproved reboot was performed;
10. record acceptance in the ticket/change without copying private evidence into Git.

### 4. Run read-only validation

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Validate <AUTHORIZED-CYBERNET>
```

Expected successful status:

```text
HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED
```

This status deliberately preserves application acceptance as separate human proof.

## Approved CSV batches after pilot acceptance

Use the PowerShell entrypoint, not the one-target `.cmd` launcher.

Place the CSV under one of the approved local input roots:

- `targets/local/`
- `logs/targets/`
- `survey/input/` only after normalization/staging

Use one of these header names: `ComputerName`, `HostName`, `Hostname`, or `Target`.

Recommended shape:

```csv
ComputerName
CYBERNET-01
CYBERNET-02
CYBERNET-03
```

Plan the batch:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
    -Mode Plan `
    -TargetsCsv '.\targets\local\cybernet-approved-batch.csv'
```

Apply only after reviewing the complete batch Plan:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
    -Mode Apply `
    -TargetsCsv '.\targets\local\cybernet-approved-batch.csv' `
    -AllowTargetMutation
```

Target names are validated and deduplicated case-insensitively. The hard maximum is 25, but 25 is not a recommended first batch. A successful result for one device is not proof for another.

## Optional PowerShell parameters

| Parameter | Current behavior |
|---|---|
| `-MonitorIndex` | Selects one display index when the default `-1` cannot identify the intended integrated display. Accepted range: `-1` through `64`. |
| `-OutputRoot` | Overrides the run root only when the path remains under an approved generated-output root such as `survey/output/`, `logs/nmap/`, or `survey/artifacts/`. |
| `-MaxTargets` | Lowers the run limit; accepted range is `1` through `25`. It cannot raise the profile maximum. |
| `-SoftwareWaitTimeout` | Installer-result wait per target. Accepted range: `10` through `7200` seconds; default: `1800`. |
| `-BashPath` | Supplies an explicit `bash.exe` when Git Bash is not in a standard Git for Windows path or on `PATH`. |
| `-FixtureMode` | Offline CI/contract mode. It cannot be combined with `-AllowTargetMutation` and is not live proof. |

## Output artifact reference

Each run root contains:

```text
client-configuration-<timestamp>-<id>\
  cybernet_client_configuration_summary.json
  operator_handoff.txt
  technician_software_acceptance.txt
  hardware-plan.parameters.json                 # Plan
  hardware-plan.console.log                     # Plan
  hardware-apply.parameters.json                # Apply
  hardware-apply.console.log                    # Apply
  approved-software.console.log                 # Plan or Apply
  hardware-post-software-validation.parameters.json
  hardware-post-software-validation.console.log
  hardware-...\                                 # nested hardware batch evidence
```

The software controller also writes run evidence under `bash/apps/output/`.

Important summary fields:

- `status`
- `target_count`
- `package_set_id`
- `stages`
- `failed_stage_count`
- `network_activity_performed`
- `target_mutation_attempted`
- `automatic_reboot_performed`
- `com_mutation_performed`
- `software_acceptance_required`
- `software_acceptance_path`

The composed workflow reports these statuses:

| Status | Meaning |
|---|---|
| `PLAN_READY` | Hardware Plan and software dry-run passed. No target/share contact or mutation occurred. |
| `APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED` | Apply, software controller, cleanup, and post-software hardware validation passed; human acceptance remains. |
| `HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED` | Read-only hardware validation passed; software behavior remains separate proof. |
| `ACTION_REQUIRED` | At least one stage failed. Review the failed stage and stop before retrying. |
| `FIXTURE_PASS` | Offline fixture composition passed. This is CI/contract proof only. |

Launcher exit codes:

- `0` — requested mode completed without a failed stage;
- `1` — a runtime/preflight/stage error occurred;
- `2` — launcher usage, mode, or argument error.

## COM-port handling

The combined workflow never changes COM mappings remotely.

- `COM1,COM2,COM3,COM4` — ready.
- Exact `COM3,COM4,COM5,COM6` — stop the combined workflow and run `Run-CybernetComPortAutoFix-DryRun.cmd` locally on that Cybernet.
- Any other shape — review required; do not guess or force a mapping.

The local AutoFix requires administrator context, registry backups, exact eligibility, controlled `PortName` changes, a separately authorized reboot, and post-reboot proof. Resume the combined Plan/Apply only after COM1-COM4 is verified.

## Rollback and recovery boundaries

There is no one-command rollback for the complete client profile.

- A failed display-button readback triggers the display controller's immediate best-effort restore to the original VCP value.
- A later approved display-button rollback must use `Hardware/Cybernet/Enable-PrivacyButton.ps1` with the exact generated `cybernet_display_button_restore_manifest.json`; never invent a factory value.
- The combined workflow does not remotely repair or roll back COM ports.
- The combined workflow does not uninstall software.
- The combined workflow does not reboot the target.
- Power-policy or software correction must follow the approved stage-specific procedure and ticket/change authority.

See [Cybernet client configuration troubleshooting](CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md) for failure classification, safe retry, and display restore examples.

## Completion and proof standard

A Cybernet is complete only when all of these are separately true:

- hardware Apply and readback passed;
- COM1-COM4 passed;
- approved six-package controller result and cleanup passed;
- post-software hardware validation passed;
- every required application/shortcut was accepted by a technician;
- any required reboot and AutoLogon behavior were separately observed and recorded;
- the ticket/change was updated with the result.

Fixture and CI proof validate repository contracts and composition only. They do not authorize a target, prove a real display supports VCP `0xCA`, prove a live software installation, prove reboot/AutoLogon behavior, or replace technician acceptance.
