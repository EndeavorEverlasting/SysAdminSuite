# Approved software application and AutoLogon acceptance

## Purpose

`Run-InstallApprovedSoftware.cmd` now includes:

```text
[6] Extract application launch and AutoLogon behavior
```

This action runs only after the selected package has a complete AFTER snapshot. It collects bounded,
read-only machine evidence and stores it under the active approved-software run on the admin workstation.

The canonical extraction script is:

```text
scripts/Invoke-SasApprovedSoftwareAcceptance.ps1
```

## Required order

```text
BEFORE snapshot
-> WhatIf plan
-> approved pilot install
-> AFTER snapshot
-> technician launches or observes the approved application/session
-> Extract application launch and AutoLogon behavior
-> review acceptance-summary.json
```

The extraction action fails closed when the workflow state is not `after_complete`.

## Application launch evidence

Application observation is driven by explicit process base names from either:

- `configs/software-packages/approved-apps.json`; or
- the bounded `-ProcessName` operator parameter while a package rule is being finalized.

The extractor records:

- process name and ID;
- Windows session ID;
- executable path when Windows permits access;
- start time;
- responding state;
- main-window title and optional title-pattern match.

It never collects an application command line. It does not call `Start-Process`, `Stop-Process`,
`SendKeys`, or a remote process-creation API. The technician or approved application launcher performs
the launch; this lane extracts the resulting state.

Application results include:

- `not_configured`
- `not_running`
- `running_not_responding`
- `running_window_not_matched`
- `launch_observed`

A running application process does not by itself prove that a clinical or business workflow succeeded.

## AutoLogon evidence

The AutoLogon catalog profile uses the Windows Winlogon contract and hostname-based expected account.
It extracts:

- `AutoAdminLogon`;
- `DefaultUserName` and `DefaultDomainName`;
- whether the `DefaultPassword` value name exists;
- current logged-on Windows session identity;
- current boot time and whether it changed from the Before snapshot.

The extractor checks the DefaultPassword value name but never reads the value data.

Configuration results include:

- `not_enabled`
- `configured_user_mismatch`
- `configured_password_missing`
- `autologon_ready`

Behavior results include:

- `session_match_after_reboot_observed`
- `session_match_observed_without_reboot_delta`
- `configured_ready_current_session_mismatch`

The `configured_password_missing` check occurs before `autologon_ready`, fixing the unsafe classifier
shape identified in the older stacked AutoLogon state-delta lane.

A current session match after a reboot is strong machine evidence, but it does not by itself prove automatic sign-in. The technician separately records whether automatic sign-in was directly observed.

## Technician attestation and proof levels

The extraction action can record two bounded attestations:

- application ready surface directly observed;
- automatic sign-in directly observed after reboot.

The proof levels are:

- `FIXTURE_ONLY`
- `PARTIAL_REVIEW`
- `MACHINE_EVIDENCE_READY_FOR_TECHNICIAN_REVIEW`
- `TECHNICIAN_ATTESTED_MACHINE_EVIDENCE`

`TECHNICIAN_ATTESTED_MACHINE_EVIDENCE` means machine extraction and the required technician
observations agree. It does not prove the technician's identity and it does not replace client
business acceptance.

## Evidence layout

```text
survey/output/approved_software_install/<run_id>/acceptance/
  <target>.json
  acceptance-summary.json
```

`operator-state.json` is updated with:

```text
acceptance_summary_path
acceptance_proof_level
workflow_status = acceptance_extracted
```

## Direct examples

Fixture extraction after the fixture Before, Plan, and After chain:

```powershell
.\scripts\Start-SasApprovedSoftwareOperator.ps1 `
  -Action Acceptance `
  -ProcessName FixtureApp `
  -FixtureMode `
  -NonInteractive
```

Live application observation after a completed After snapshot:

```powershell
.\scripts\Start-SasApprovedSoftwareOperator.ps1 `
  -Action Acceptance `
  -ProcessName '<approved-process-base-name>' `
  -WindowTitlePattern '<approved-ready-title-pattern>' `
  -ApplicationObserved `
  -NonInteractive
```

AutoLogon acceptance after reboot and direct observation:

```powershell
.\scripts\Start-SasApprovedSoftwareOperator.ps1 `
  -Action Acceptance `
  -AutoLogonObservedAfterReboot `
  -NonInteractive
```

## Pilot requirement

Use one or two approved pilot workstations before expansion. Review:

1. complete Before snapshot;
2. install summary and cleanup state;
3. complete After snapshot;
4. application process and ready-surface evidence when applicable;
5. AutoLogon configuration, password-value presence, reboot delta, and session match when applicable;
6. technician observations;
7. `acceptance-summary.json` proof level and boundaries.
