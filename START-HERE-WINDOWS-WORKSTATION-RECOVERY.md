# Start here: Windows workstation backup, repair, and upgrade proof

Use `recovery/windows/README.md` for the guarded Windows workflow.

Fast entry point from an Administrator PowerShell:

```powershell
.\Inspect-WindowsWorkstationRecovery.cmd -OutputPath .\runs\windows-recovery\quick.json
```

Use the evidence collector before cleanup or hardware changes; pass a backup target explicitly when validating `WindowsImageBackup`. If the source disk is failing or must be made read-only, stop using the Windows lane and follow `recovery/systemrescue/README.md` instead.

## Preserved failing disk -> WinRE

When SystemRescue preservation is complete and the original disk is moving into Windows Recovery Environment diagnosis, use `recovery/windows/WINRE_QRFY_TRANSITION.md` and its machine-readable `recovery/windows/winre-qrfy-catalog.json`.

The QRFY transition uses short `cmd.exe` probes with **no explicit write commands**, detects the shell before choosing commands, accepts terminal photos as field evidence, and keeps machine-specific output out of Git. This is not a media write-blocking guarantee: Linux `blockdev --setro` does not survive reboot, so source-volume/filesystem probes are gated until hardware/controller or another independently proven Windows-side write-protection mechanism exists.

Do not jump from a WinRE `RAW`/`Unknown` display to CHKDSK. Bind the intended source volume to its **current-session DiskPart disk number**, then prove that exact backing disk is still present. Disk numbers must be re-resolved every boot, and an unrelated recovery USB or other disk row never satisfies source presence. If the binding cannot be resolved, fail closed as `source_disk_identity_unresolved`; if the resolved source disk is absent, classify `backing_device_unavailable` and use the metadata-only connected-device probe before any source-volume access, repair, reset, formatting, or reinstall.

An already-observed unlocked BitLocker state plus `A device which does not exist was specified.` is supporting evidence, not a symptom the workflow should reproduce on an unprotected source.
