# Cybernet client configuration guide

## Purpose

Use this guide to prepare an authorized Cybernet workstation with the complete client preference profile:

- standby and hibernate idle timeouts set to **Never** for AC and DC;
- Windows physical power button set to **Do nothing**;
- supported integrated-display Privacy/Menu and display power-button events disabled through MCCS 2.2 VCP `0xCA = 0x0303`;
- COM ports verified as `COM1, COM2, COM3, COM4`;
- the approved six-package clinical workstation set installed in its reviewed order, with AutoLogon last;
- hardware validated again after software installation;
- software launch and behavior accepted by the technician.

The machine-readable source of truth is `Config/cybernet-client-preferences.json`. The one-command implementation is `Hardware/Cybernet/Invoke-CybernetClientConfiguration.ps1`.

## Approved software set

The profile uses package-set ID `cybernet-clinical-workstation` from `configs/software-packages/windows-native-package-sets.json`:

1. Allscripts EEHR Shortcut UAI 2.2
2. Epic Downtime Guide Shortcut 1.0
3. Nuance Dragon Medical One 2025
4. Hyland FOS Epic Integration 23.1.33.1000
5. Epic BCA Web Shortcut 1.0
6. NW AutoLogon Setup x64

AutoLogon must remain last. The workflow does not reboot the workstation. An installer result such as MSI exit code `3010` means a restart is required later through the separately authorized site process.

## What the combined workflow does

### Plan

`Plan` is request-only:

1. validates the tracked client-preference profile against the approved package-set catalog;
2. creates the hardware Plan through the merged Cybernet hardware batch;
3. runs the approved software package-set controller with `--dry-run`;
4. writes local plan logs and a technician acceptance checklist;
5. contacts neither the target nor the software share and performs no mutation.

### Apply

`Apply` requires `-AllowTargetMutation` and one high-impact confirmation. It performs this order:

1. applies and validates no-sleep, physical power-button, display-button, and COM readiness through `Invoke-CybernetBatchConfiguration.ps1`;
2. stops before software when the hardware/COM gate fails;
3. installs the approved six-package set through Git Bash, the target administrative share, and a one-time SYSTEM scheduled task;
4. retrieves result evidence and verifies task/staging cleanup;
5. validates the hardware state again after software installation;
6. emits a technician acceptance checklist.

### Validate

`Validate` is read-only. It rechecks:

- every parsed Windows power scheme has standby and hibernate AC/DC indexes at zero;
- the physical power-button action is Do nothing;
- the integrated display reports VCP `0xCA = 0x0303`;
- COM ports are `COM1, COM2, COM3, COM4`.

Software behavior is not inferred from installer exit codes. The technician must open and verify each approved shortcut/application.

## Controller prerequisites

Run from an approved Windows admin workstation or admin VM with:

- a current authorized Windows administrative token;
- approved network access to every target;
- access to each target's `C$` administrative share;
- remote Task Scheduler RPC and the target Schedule service available;
- Git Bash installed under the standard Git for Windows path or available as `bash.exe`;
- the current SysAdminSuite repository checkout;
- read access to the approved software share;
- an authorized target, package scope, ticket/change, operator, and maintenance window.

Never place a password in the command. Do not use wildcard hostnames, subnets, discovery output, or more than 25 explicit targets.

## One-target pilot

From PowerShell, enter the repository first:

```powershell
Set-Location -LiteralPath 'C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite'
```

### 1. Plan

```powershell
.\Run-CybernetClientConfiguration.cmd Plan <AUTHORIZED-CYBERNET>
```

Review the newest run under:

```text
survey\output\cybernet_hardware\client-configuration-*
```

The summary must say `PLAN_READY`. Review both the hardware plan and the approved-software dry-run console log. Confirm the target, six-package set, run-scoped staging, Task Scheduler identity, cleanup intent, and no-reboot posture.

### 2. Apply one authorized pilot

```powershell
.\Run-CybernetClientConfiguration.cmd Apply <AUTHORIZED-CYBERNET>
```

Accept the high-impact confirmation only after the Plan is correct. The successful composed status is:

```text
APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED
```

That status means the automated configuration and post-software hardware validation passed. It does not mean the applications or AutoLogon behavior were accepted.

### 3. Complete technician acceptance

Open the generated file:

```text
technician_software_acceptance.txt
```

At the Cybernet or through the normal approved support session:

1. confirm each expected shortcut/application exists;
2. open Allscripts EEHR and confirm the expected launch path;
3. open Epic Downtime Guide and confirm the intended guide destination;
4. open Dragon Medical One and confirm its expected ready/login surface;
5. open Hyland FOS Epic Integration and confirm the expected integration surface;
6. open the Epic BCA shortcut and confirm the approved destination;
7. record AutoLogon as installed, but do not claim automatic sign-in until after a separately authorized reboot and direct observation;
8. record acceptance in the ticket/change without copying private evidence into Git.

### 4. Run read-only validation

```powershell
.\Run-CybernetClientConfiguration.cmd Validate <AUTHORIZED-CYBERNET>
```

The successful status is:

```text
HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED
```

The status deliberately preserves software acceptance as a separate human proof.

## Expanding after pilot acceptance

Use the PowerShell entrypoint for a small explicit batch:

```powershell
.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
  -Mode Plan `
  -ComputerName 'CYBERNET-01','CYBERNET-02','CYBERNET-03'
```

After reviewing the complete Plan:

```powershell
.\Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 `
  -Mode Apply `
  -ComputerName 'CYBERNET-01','CYBERNET-02','CYBERNET-03' `
  -AllowTargetMutation
```

Use an approved CSV only from the repository's codified local target-input roots. Keep the batch small even though the hard maximum is 25. A result for one target is not proof for another.

## COM-port handling

The combined workflow never changes COM mappings remotely.

- `COM1,COM2,COM3,COM4` — ready.
- Exact `COM3,COM4,COM5,COM6` — stop the combined workflow and run `Run-CybernetComPortAutoFix-DryRun.cmd` locally on that Cybernet.
- Any other shape — review required; do not guess or force a mapping.

The local AutoFix requires administrator context, registry backups, exact eligibility, controlled `PortName` changes, a separately authorized reboot, and post-reboot proof. Resume the combined Plan/Apply only after COM1-COM4 is verified.

## Failure handling

### Hardware stage fails before software

Software is not started. Review the hardware stage log and its nested batch summary. Correct COM readiness, DDC/CI eligibility, power-policy access, or target authorization before retrying.

### Software stage fails

Review the local controller log and per-target result CSV under `bash/apps/output/`. Confirm the unique scheduled task and run-scoped staging were removed or are explicitly accounted for. Do not rerun blindly and do not switch to an unreviewed execution method.

### Display button is ineligible

The Privacy/Menu setting requires MCCS 2.2 or later and readable VCP `0xCA`. The workflow fails closed instead of trying registry, BIOS, Device Manager, a vendor service, or an unknown utility.

### Restart required

Record the restart requirement. This workflow never reboots. Use only the client's separately approved restart process, then complete AutoLogon and application observation.

## Completion standard

A Cybernet is complete only when all of these are separately true:

- hardware Apply and readback passed;
- COM1-COM4 passed;
- approved six-package controller result and cleanup passed;
- post-software hardware validation passed;
- every required application/shortcut was accepted by a technician;
- any required reboot and AutoLogon behavior were separately observed and recorded;
- the ticket/change was updated with the result.

Fixture and CI proof validate repository contracts and composition only. They do not authorize or prove a live Cybernet configuration.
