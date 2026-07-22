# Cybernet Hardware Batch Configuration

This directory is the canonical technician/deployment surface for Cybernet-specific hardware policy and post-install validation.

## One-command workflow

Plan one target without contacting it:

```powershell
.\Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1 `
  -Mode Plan `
  -ComputerName '<AUTHORIZED-CYBERNET>'
```

Apply one authorized pilot with confirmation enabled:

```powershell
.\Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1 `
  -Mode Apply `
  -ComputerName '<AUTHORIZED-CYBERNET>' `
  -AllowTargetMutation
```

Validate without changing the target:

```powershell
.\Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1 `
  -Mode Validate `
  -ComputerName '<AUTHORIZED-CYBERNET>'
```

A root `Run-CybernetBatchConfiguration.cmd` launcher provides the same one-target Plan, Apply, and Validate flow. Use the PowerShell entrypoint with an approved local target CSV only after the one-target pilot is accepted.

## Applied configuration

| Surface | Canonical implementation | Batch behavior |
|---|---|---|
| Standby and hibernate idle timeouts | `Hardware/Cybernet/Set-NoSleep.ps1` | Sets AC/DC timeout indexes to zero on every parsed power scheme and verifies them. |
| Physical Windows power button | `scripts/Invoke-SasCybernetPowerHardening.ps1` via `Set-PowerButtonDoNothing.ps1` | Sets the physical power-button action to Do nothing for AC/DC and verifies every parsed scheme. |
| Privacy/Menu and display power buttons | `scripts/Invoke-SasCybernetDisplayButtonControl.ps1` via `Disable-PrivacyButton.ps1` | Uses MCCS 2.2 VCP `0xCA`; only eligible displays are set to `0x0303`, read back, and given a restore manifest. |
| COM ports | `COM-Port-Check.ps1` and the existing local COM AutoFix | Read-only batch classification. It never performs remote registry/PnP changes or a remote reboot. |
| Final verification | `PostInstall-Validation.ps1` | Read-only checks for no-sleep, power-button Do nothing, VCP `0xCA = 0x0303`, and COM1-COM4. |

## Privacy button authority

The repository has already established a host-controllable path for supported Cybernet integrated displays: MCCS 2.2 VCP code `0xCA` through the Windows Monitor Configuration API. `0x0303` disables OSD/Menu button events and the display power button. This module therefore does **not** guess at a registry value, Cybernet service, configuration file, BIOS setting, Device Manager property, or vendor executable.

`Enable-PrivacyButton.ps1` requires the exact restore manifest from a prior successful disable run. It never assumes a universal factory value.

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

For the exact repairable condition, run `Run-CybernetComPortAutoFix-DryRun.cmd` locally on the Cybernet, review the evidence, then use the separately gated apply launcher.

## Safety and proof ceiling

- Maximum 25 explicit targets; one authorized target is the required first pilot.
- Plan and fixture modes perform no target contact or mutation.
- Apply requires `-AllowTargetMutation` and high-impact confirmation.
- Outputs remain under ignored `survey/output/cybernet_hardware` roots.
- No credentials, live target lists, raw evidence, or machine-local paths belong in Git.
- Fixture and CI passes prove contracts and composition only. They do not prove a real display supports VCP `0xCA`, a real Cybernet was configured, a reboot succeeded, or an operator accepted a batch.
