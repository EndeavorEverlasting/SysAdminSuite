# Cybernet power and display-button hardening

## Operational truth

SysAdminSuite has two different control planes for Cybernet buttons. They are intentionally separate because they use different Windows and display-controller interfaces.

## Windows physical power-button policy

`QRTasks/Set-PowerComfortDefaults.ps1` uses the canonical Windows physical power-button action GUID:

```text
7648efa3-dd9c-4e3e-b566-50f929386280
```

For every parsed Windows power scheme it sets the AC and DC action index to `0`, which is **Do nothing** for the physical Windows power button.

`scripts/Invoke-SasCybernetPowerHardening.ps1` is the bounded network lane for that Windows policy. It changes only the Windows physical power-button action, verifies AC and DC values, writes local evidence, and does not stage a payload on the target.

This Windows setting does not control a panel display's on-screen-display menu or display-controller button firmware.

## MCCS 2.2 display-controller button control

`scripts/Invoke-SasCybernetDisplayButtonControl.ps1` implements a separate, standards-based DDC/CI lane through the Windows Monitor Configuration API and `scripts/SasDdcciMonitorControl.cs`.

The relevant Monitor Control Command Set feature is:

```text
VCP 0xCA - OSD/Button Control
```

For MCCS 2.2, the current value is interpreted as two control bytes:

| Byte | `0x01` | `0x02` | `0x03` |
|---|---|---|---|
| SL: OSD/menu-button control | OSD disabled, button events enabled | OSD enabled, button events enabled | OSD disabled, button events disabled |
| SH: display power-button control | power button disabled, events enabled | power button enabled, events enabled | power button disabled, events disabled |

The requested lock value is therefore:

```text
0x0303
```

That value asks a conforming MCCS 2.2 display controller to disable the OSD/menu-button events and disable the display power-button events.

Protocol references used to derive this implementation:

- Microsoft Windows Monitor Configuration API, including physical-monitor enumeration, capabilities, VCP reads, and VCP writes.
- `rockowitz/ddcutil` feature metadata for MCCS VCP `0xCA`, which identifies MCCS 2.2 SH and SL button-control values: `src/vcp/vcp_feature_codes.c` at commit `e16561ffc4d87e29b03257dd5cfedaea7009c586`.

The numeric protocol values are not treated as proof that a particular Cybernet model implements them. A real target must prove support before mutation.

## Fail-closed eligibility

Apply is refused unless the selected physical monitor proves all of the following:

1. Windows exposes it through the physical Monitor Configuration API.
2. VCP `0xDF` confirms MCCS 2.2 or later.
3. VCP `0xCA` is readable.
4. The current SL OSD/menu-button control byte is one of `0x01`, `0x02`, or `0x03`.
5. The current SH display power-button control byte is one of `0x01`, `0x02`, or `0x03`.
6. Exactly one eligible monitor exists, or the operator provides an explicit `-MonitorIndex` from a prior probe.

Important classifications include:

```text
VCP_CA_V22_BUTTON_LOCK_READY
MCCS_PRE_2_2_OSD_ONLY
MCCS_VERSION_UNREADABLE
VCP_CA_UNREADABLE
HOST_BUTTON_CONTROL_UNSUPPORTED
```

MCCS versions before 2.2 may expose VCP `0xCA` as an OSD-only control. SysAdminSuite does not use that older behavior to claim physical button disablement.

## Mutation and rollback contract

Apply follows this sequence on each authorized target:

1. Enumerate physical monitors.
2. Read capabilities, MCCS version, and the original VCP `0xCA` value.
3. Refuse an ambiguous or unsupported monitor.
4. Ask for `ShouldProcess` confirmation.
5. Write `0x0303`.
6. Read VCP `0xCA` again.
7. Report success only when readback equals `0x0303`.
8. If verification fails, immediately attempt to restore the original value and verify that rollback.
9. Persist every successful target's original value in a generated restore manifest.

The helper always destroys Windows physical-monitor handles after probe or mutation.

A generated restore manifest uses:

```text
sas-cybernet-display-button-restore/v1
```

It records the exact target, monitor index, physical-monitor description, original VCP `0xCA` value, and applied value. Do not edit it manually.

## Target input

Keep live target CSV files under an ignored approved intake root such as:

```text
targets/local/cybernet-display-buttons.csv
```

Accepted columns are `ComputerName`, `HostName`, `Hostname`, or `Target`.

Do not commit live target names.

## Request-only validation

`-WhatIf` validates target intake and writes a local plan. It does not open a remote session or mutate a workstation.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-SasCybernetDisplayButtonControl.ps1 `
  -TargetsCsv .\targets\local\cybernet-display-buttons.csv `
  -Operation Apply `
  -WhatIf
```

Expected evidence root:

```text
survey/output/cybernet_display_button_control/<workflow-id>/
```

## Offline fixture proof

Apply fixture:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-SasCybernetDisplayButtonControl.ps1 `
  -ComputerName CYBERNET-FIXTURE-01 `
  -Operation Apply `
  -FixtureMode
```

Restore fixture:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-SasCybernetDisplayButtonControl.ps1 `
  -ComputerName CYBERNET-FIXTURE-01 `
  -Operation Restore `
  -FixtureMode
```

Fixture proof validates output, classification, desired value, and restore-manifest contracts. It performs no network activity and proves no real monitor behavior.

## First authorized capability probe

Probe exactly one representative Cybernet before applying the lock:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-SasCybernetDisplayButtonControl.ps1 `
  -ComputerName AUTHORIZED-CYBERNET `
  -Operation Probe
```

Probe is read-only but does contact the target through one remote PowerShell session. Review `cybernet_display_button_details.json` and confirm exactly one monitor reports:

```text
VCP_CA_V22_BUTTON_LOCK_READY
```

A remote session may fail to expose the physical display on some Windows or graphics-driver configurations. That is a failed capability probe, not permission to bypass the gate.

## First authorized apply pilot

Use the same approved Cybernet and keep confirmation enabled:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-SasCybernetDisplayButtonControl.ps1 `
  -ComputerName AUTHORIZED-CYBERNET `
  -Operation Apply `
  -AllowTargetMutation
```

If the probe found multiple eligible monitors, add the exact index:

```powershell
-MonitorIndex 0
```

The operator must verify all of the following before expanding scope:

- the result is `APPLIED_VERIFIED` or `ALREADY_LOCKED_VERIFIED`;
- final VCP `0xCA` is `0x0303`;
- the local OSD/menu buttons no longer invoke the OSD or display action;
- the display power button no longer turns off the panel;
- normal Windows display output remains available;
- the generated restore manifest is readable from the admin workstation.

## Restore the pilot

Use the restore manifest generated by the Apply run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-SasCybernetDisplayButtonControl.ps1 `
  -ComputerName AUTHORIZED-CYBERNET `
  -Operation Restore `
  -RestoreManifest .\survey\output\cybernet_display_button_control\<apply-workflow-id>\cybernet_display_button_restore_manifest.json `
  -AllowTargetMutation
```

Restore reads and writes the exact original VCP `0xCA` value for that target and monitor index. Success requires readback of the original value.

## Bounded fleet run

Do not run this fleet-wide until one Cybernet has capability, apply, physical-behavior, and restore proof.

After that gate is satisfied:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-SasCybernetDisplayButtonControl.ps1 `
  -TargetsCsv .\targets\local\cybernet-display-buttons.csv `
  -Operation Apply `
  -AllowTargetMutation `
  -MaxTargets 25
```

The workflow uses one remote PowerShell session per target. It does not pre-ping, scan the subnet, install a service, create a scheduled task, change registry values, or stage a payload.

Keep the Apply restore manifest until the fleet result and physical acceptance are complete.

## Evidence

Each display-button run writes:

```text
cybernet_display_button_events.jsonl
cybernet_display_button_results.csv
cybernet_display_button_details.json
cybernet_display_button_summary.json
operator_handoff.txt
```

Apply additionally writes:

```text
cybernet_display_button_restore_manifest.json
```

Runtime evidence belongs under ignored `survey/output/` roots and must not be committed.

## Existing physical-button event probe

`QRTasks/Test-DisplayMenuButtonEvent.ps1` remains a separate, read-only local event probe:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\QRTasks\Invoke-TechTask.ps1 `
  -Task DisplayMenuButtonProbe
```

It returns one of:

```text
OBSERVED_WINDOWS_EVENT
NO_WINDOWS_EVENT_OBSERVED
```

This event probe is useful when DDC/CI is unavailable or when a model appears to expose a Windows input signal. It does not write VCP features and does not disable a button.

## Proof ceiling

The repository now contains a real gated implementation for MCCS 2.2 VCP `0xCA`, including apply, verification, rollback, restore manifest, fixtures, and CI.

That implementation does not prove that the deployed Cybernet model supports DDC/CI or conforms to MCCS 2.2. Only an authorized hardware probe and physical-button observation can establish that proof.
