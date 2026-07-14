# Cybernet COM Port Quick Help

## Double-click entrypoint

From the SysAdminSuite repo root:

```cmd
Run-CybernetComPortHelp.cmd
```

This opens a read-only tutorial menu. It prints or copies commands; it does not execute the repair.

Direct topics are also available:

```cmd
Run-CybernetComPortHelp.cmd status
Run-CybernetComPortHelp.cmd overview
Run-CybernetComPortHelp.cmd dry-run
Run-CybernetComPortHelp.cmd inspect
Run-CybernetComPortHelp.cmd qr
Run-CybernetComPortHelp.cmd apply
Run-CybernetComPortHelp.cmd diagnostics
Run-CybernetComPortHelp.cmd setup-loop
```

Add `-Copy` after a topic to copy its command block to the Windows clipboard:

```cmd
Run-CybernetComPortHelp.cmd diagnostics -Copy
```

## Decision guide

| Situation | Use |
|---|---|
| Need to know whether the local checkout has the COM tools and whether the readiness doc says HOLD | `Run-CybernetComPortHelp.cmd status` |
| Approved, non-finalized Cybernet shows COM3-COM6 | Parser check, dry-run, then evidence inspector |
| Need scannable snippets while standing at a target | `Run-CybernetComPortQrPack.cmd` |
| Need read-only COM state | `Run-CybernetComPortHelp.cmd diagnostics` |
| Windows is stuck in the setup restart/error loop | `Run-CybernetComPortHelp.cmd setup-loop` |
| Ready for controlled apply after approval and successful evidence inspection | `Run-CybernetComPortAutoFix.cmd` |

## Required COM AutoFix sequence

```powershell
.\scripts\Test-CybernetComPortAutoFixParser.ps1
```

Required result:

```text
PARSE OK
```

Then:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

Then:

```powershell
.\scripts\Inspect-CybernetComPortAutoFixEvidence.ps1
```

Required result includes:

```text
REGISTRY BACKUPS VALIDATED
```

Apply remains a separate approved action:

```cmd
Run-CybernetComPortAutoFix.cmd
```

Do not use apply on a finalized/app-bound Cybernet. Do not continue final app binding until COM1-COM4 sticks after reboot.

## Quick read-only snippets

```cmd
reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM
pnputil /enum-devices /class Ports
pnputil /enum-devices /class MultiPortSerial
cmd /c "set devmgr_show_nonpresent_devices=1&&start devmgmt.msc"
explorer C:\Temp\CybernetCOM
```

## Separate setup-loop use case

The Windows setup completion flag is not the COM repair.

Open the Field Hotfixes GUI:

```cmd
Run-FieldHotfixesGui.cmd
```

At the Windows setup unexpected-restart/error screen, press `Shift+F10` and use the **Cybernet Windows Setup Completion Flag** QR. Its CMD payload is:

```cmd
reg add HKLM\SYSTEM\Setup\Status\ChildCompletion /v setup.exe /t REG_DWORD /d 3 /f && shutdown /r /t 0
```

Use only before final app binding and only when the target is actually stuck in the Windows setup error loop.

## Safety

- The help/tutorial launcher does not execute commands.
- COM AutoFix is local-only on the affected Cybernet.
- No remote execution or admin-box target mutation.
- No SmartLynx/final app installation.
- No USB/COM driver replacement.
- Runtime evidence under `C:\Temp\CybernetCOM` must not be committed.
