# Start here: Windows workstation backup, repair, and upgrade proof

Use `recovery/windows/README.md` for the guarded Windows workflow.

Fast entry point from an Administrator PowerShell:

```powershell
.\Inspect-WindowsWorkstationRecovery.cmd -OutputPath .\runs\windows-recovery\quick.json
```

Use the evidence collector before cleanup or hardware changes; pass a backup target explicitly when validating `WindowsImageBackup`. If the source disk is failing or must be made read-only, stop using the Windows lane and follow `recovery/systemrescue/README.md` instead.
