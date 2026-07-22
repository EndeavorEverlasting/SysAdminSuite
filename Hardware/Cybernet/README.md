# Cybernet Hardware and Complete Client Configuration

This directory is the canonical technician/deployment surface for Cybernet hardware policy, the complete client configuration, post-install validation, and exact display-button restore.

## Operator start points

| Need | Start here |
|---|---|
| Hardware and approved software together | `Run-CybernetClientConfiguration.cmd Help` and `docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md` |
| A combined run failed | `docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md` |
| Hardware only | `Run-CybernetBatchConfiguration.cmd` and the hardware-only commands below |
| Exact display-button restore | `Enable-PrivacyButton.ps1` with the generated restore manifest |
| Exact COM3-COM6 repairable condition | Run the separate local COM AutoFix dry run on the Cybernet |

Always enter the repository before running examples:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'
```

## Complete client workflow

Use the composed workflow when the technician needs the client's hardware preferences and the approved software set applied together.

Read launcher help:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Help
```

Plan one authorized pilot without target or software-share contact:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Plan <AUTHORIZED-CYBERNET>
```

After reviewing `PLAN_READY`, apply one authorized pilot:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Apply <AUTHORIZED-CYBERNET>
```

Complete the generated `technician_software_acceptance.txt`, then validate hardware read-only:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Validate <AUTHORIZED-CYBERNET>
```

The direct PowerShell entrypoint is:

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

The machine-readable source of truth is `Config/cybernet-client-preferences.json`.

The composed order is:

1. hardware Apply and validation;
2. stop before software when hardware or COM readiness fails;
3. approved six-package software installation with AutoLogon last;
4. result retrieval and task/staging cleanup verification;
5. post-software hardware validation;
6. technician software acceptance.

The workflow never reboots a target or repairs COM ports remotely.

Combined evidence is written under:

```text
survey\output\cybernet_hardware\client-configuration-*
```

Primary files are `cybernet_client_configuration_summary.json`, `operator_handoff.txt`, and `technician_software_acceptance.txt`.

## Hardware-only workflow

Plan one target without contacting it:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1 `
    -Mode Plan `
    -ComputerName '<AUTHORIZED-CYBERNET>'
```

Apply one authorized pilot with confirmation enabled:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1 `
    -Mode Apply `
    -ComputerName '<AUTHORIZED-CYBERNET>' `
    -AllowTargetMutation
```

Validate without changing the target:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1 `
    -Mode Validate `
    -ComputerName '<AUTHORIZED-CYBERNET>'
```

The root `Run-CybernetBatchConfiguration.cmd` launcher provides the same one-target hardware-only Plan, Apply, and Validate flow. Use the PowerShell entrypoint with an approved local target CSV only after the one-target pilot is accepted.

## Applied configuration

| Surface | Canonical implementation | Batch behavior |
|---|---|---|
| Standby and hibernate idle timeouts | `Set-NoSleep.ps1` | Sets AC/DC timeout indexes to zero on every parsed power scheme and verifies them. |
| Physical Windows power button | `scripts/Invoke-SasCybernetPowerHardening.ps1` via `Set-PowerButtonDoNothing.ps1` | Sets the physical power-button action to Do nothing for AC/DC and verifies every parsed scheme. |
| Privacy/Menu and display power buttons | `scripts/Invoke-SasCybernetDisplayButtonControl.ps1` via `Disable-PrivacyButton.ps1` | Uses MCCS 2.2 VCP `0xCA`; only eligible displays are set to `0x0303`, read back, and given a restore manifest. |
| COM ports | `COM-Port-Check.ps1` and the existing local COM AutoFix | Read-only batch classification. It never performs remote registry/PnP changes or a remote reboot. |
| Approved software | `bash/apps/sas-install-apps.sh` and package set `cybernet-clinical-workstation` | Installs six reviewed packages through the Windows-native SMB/Task Scheduler lane, with AutoLogon last. |
| Final verification | `PostInstall-Validation.ps1` | Read-only checks for no-sleep, power-button Do nothing, VCP `0xCA = 0x0303`, and COM1-COM4. |

## Approved CSV target intake

The PowerShell entrypoints accept `-TargetsCsv` only from codified input roots:

- `targets/local/`
- `logs/targets/`
- `survey/input/` after normalization

Accepted headers: `ComputerName`, `HostName`, `Hostname`, or `Target`.

Target names are validated, deduplicated case-insensitively, and bounded by `-MaxTargets` with a hard maximum of 25.

## Privacy button authority and restore

The repository has established a host-controllable path for supported Cybernet integrated displays: MCCS 2.2 VCP code `0xCA` through the Windows Monitor Configuration API. `0x0303` disables OSD/Menu button events and the display power button.

This module does **not** guess at a registry value, Cybernet service, configuration file, BIOS setting, Device Manager property, or vendor executable.

`Enable-PrivacyButton.ps1` requires the exact `cybernet_display_button_restore_manifest.json` from a prior successful disable run. It never assumes a universal factory value.

Plan an approved restore with `-WhatIf`, then use `-AllowTargetMutation` only after separate authorization. The complete commands are documented in `docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md`.

## COM boundary

The merged COM AutoFix is intentionally local-only because it requires:

- local administrator context;
- validated COM Name Arbiter and device-key registry backups;
- exact four-device eligibility;
- controlled `PortName` changes;
- a reboot and local post-reboot evidence review.

The batch classifies:

- `COM1,COM2,COM3,COM4` as `COM_PORTS_READY`;
- exact `COM3,COM4,COM5,COM6` as `COM_AUTOFIX_ELIGIBLE_LOCAL_ONLY`;
- any other shape as `COM_PORT_REVIEW_REQUIRED`.

For the exact repairable condition, run `Run-CybernetComPortAutoFix-DryRun.cmd` locally on the Cybernet, review the evidence, then use the separately gated apply/restart process.

## Safety and proof ceiling

- Maximum 25 explicit targets; one authorized target is the required first pilot.
- Plan and fixture modes perform no target contact or mutation.
- Apply requires `-AllowTargetMutation` and high-impact confirmation.
- Outputs remain under ignored `survey/output/cybernet_hardware` roots.
- No credentials, live target lists, raw evidence, or machine-local paths belong in Git.
- Software installer results do not prove application behavior; technician acceptance remains mandatory.
- There is no one-command rollback for the complete client profile.
- Fixture and CI passes prove contracts and composition only. They do not prove a real display supports VCP `0xCA`, a real Cybernet was configured, a reboot succeeded, or an operator accepted a batch.
