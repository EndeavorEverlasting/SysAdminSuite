# Start here: Windows workstation backup, repair, and upgrade proof

Use `recovery/windows/README.md` for the guarded Windows workflow.

Fast entry point from an Administrator PowerShell:

```powershell
.\Inspect-WindowsWorkstationRecovery.cmd -OutputPath .\runs\windows-recovery\quick.json
```

Use the evidence collector before cleanup or hardware changes; pass a backup target explicitly when validating `WindowsImageBackup`. If the source disk is failing or must be made read-only, stop using the Windows lane and follow `recovery/systemrescue/README.md` instead.

## Preserved failing disk -> WinRE

When SystemRescue preservation is complete and the original disk is moving into Windows Recovery Environment diagnosis, use `recovery/windows/WINRE_QRFY_TRANSITION.md` and its machine-readable `recovery/windows/winre-qrfy-catalog.json`.

The QRFY transition is read-only by default. It detects the shell before choosing commands, keeps each generated WinRE `cmd.exe` payload within the catalog's practical character budget, accepts terminal photos as field evidence, and keeps machine-specific output out of Git.

Do not jump from a WinRE `RAW`/`Unknown` display to CHKDSK. In particular, an unlocked BitLocker volume that returns `A device which does not exist was specified.` while DiskPart has no physical-disk row is classified as `backing_device_unavailable`; prove current device presence before any write-capable repair, reset, formatting, or reinstall.
