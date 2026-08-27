# Windows workstation recovery proof harness

This lane captures reusable evidence from a bootable Windows workstation before a technician cleans, repairs, images, or upgrades it. It complements `recovery/systemrescue/`: use SystemRescue when a source disk is failing or must be protected read-only; use this Windows lane when Windows is bootable enough to collect host evidence and verify a Windows system image.

## Safety boundary

The default collector is evidence-first and performs no destructive cleanup. It never formats or clears disks, changes partitions, deletes files, disables the pagefile or hibernation, deletes VSS data, creates a backup image, stops servicing processes, or repairs filesystems.

Drive letters are **not identities**. The collector resolves each mounted drive through volume -> partition -> physical disk and records disk number, model, bus, size, filesystem, label, and health. Serial numbers are redacted unless `-IncludeSerials` is explicitly requested.

Live JSON/log output belongs in ignored runtime evidence such as `runs/`; do not commit machine inventories, serials, backup catalogs, or repair logs.

## Quick evidence

From the repository root on Windows:

```powershell
.\Inspect-WindowsWorkstationRecovery.cmd
```

Or directly:

```powershell
pwsh -NoProfile -File .\recovery\windows\Get-SasWindowsRecoveryEvidence.ps1 -OutputPath .\runs\windows-recovery\quick.json
```

Quick mode records disk/volume identity, storage health where the driver exposes it, exact RAM module capacity/part number/rated and configured speed, CPU/model/BIOS, GPU names/drivers, memory pressure, WinRE status, and `DISM /CheckHealth` when elevated.

`Win32_VideoController.AdapterRAM` is intentionally omitted: Windows WMI can truncate or misreport dedicated GPU memory. Do not turn that field into an upgrade decision.

## Verify a Windows system image

Pass the target explicitly and pin the stable facts you know; do not guess which USB drive is the backup disk:

```powershell
pwsh -NoProfile -File .\recovery\windows\Get-SasWindowsRecoveryEvidence.ps1 `
  -BackupTarget D: `
  -ExpectedBackupLabel LaptopBackup `
  -ExpectedBackupBusType USB `
  -BackupVersion '01/02/2026-03:04' `
  -OutputPath .\runs\windows-recovery\backup-proof.json
```

Before querying the catalog, the collector proves that the target is on a different physical disk than the system volume and can pin expected label, bus type, and model. Identity mismatch fails closed. It then queries `wbadmin get versions`, optionally `wbadmin get items` for the exact version, and measures the physical `WindowsImageBackup` tree. The proof is stronger than a displayed `100%` progress value, but it is **not** a bare-metal restore test. Preserve the source until the recovery requirement is independently satisfied.

A useful backup gate is:

1. imaging command returned success;
2. the target maps to the expected physical disk identity and is distinct from the system disk;
3. the version is registered in the backup catalog;
4. the exact version enumerates expected critical volumes/items;
5. `WindowsImageBackup` physically exists on the confirmed target;
6. WinRE or other bootable recovery media is available;
7. destructive cleanup begins only after those facts are captured.

## Storage-pressure triage

Use deep storage measurement only when needed; recursive enumeration can take minutes on a full workstation:

```powershell
pwsh -NoProfile -File .\recovery\windows\Get-SasWindowsRecoveryEvidence.ps1 -HealthDepth None -DeepStorage -OutputPath .\runs\windows-recovery\pressure.json
```

Prioritize large, evidence-backed disposable payloads before risky system tuning. Treat reparse points/junctions carefully so `All Users`/`ProgramData`-style aliases are not silently counted as independent data. Protect active repositories and irreplaceable files before deletion. This harness intentionally does **not** provide a bulk-delete command.

## Windows integrity checks

Quick mode uses `DISM /CheckHealth`. Full verification is explicit because `CHKDSK /scan`, `DISM /ScanHealth`, and `SFC /verifyonly` may take a long time:

```powershell
pwsh -NoProfile -File .\recovery\windows\Get-SasWindowsRecoveryEvidence.ps1 -HealthDepth Full -OutputPath .\runs\windows-recovery\full-health.json
```

A static DISM percentage is not proof that servicing is hung. If the display has not moved for an unusually long time, sample servicing activity from a second elevated shell:

```powershell
pwsh -NoProfile -File .\recovery\windows\Test-SasDismActivity.ps1 -Seconds 90 -OutputPath .\runs\windows-recovery\dism-activity.json
```

The sampler observes DISM/DISMHost/TiWorker/TrustedInstaller CPU time and DISM/CBS log growth. It never kills servicing processes. No activity in one sample is still not proof of a dead process; combine prolonged stagnation with logs before using a single graceful `Ctrl+C`.

## Opt-in Windows integrity repair

See the exact sequence without mutation:

```powershell
pwsh -NoProfile -File .\recovery\windows\Repair-SasWindowsIntegrity.ps1
```

Run it only from an elevated shell when repair is intended:

```powershell
pwsh -NoProfile -File .\recovery\windows\Repair-SasWindowsIntegrity.ps1 -Apply -ReportPath .\runs\windows-recovery\integrity-repair.json
```

The sequence is intentionally ordered:

1. `DISM /Online /Cleanup-Image /RestoreHealth`
2. `SFC /scannow`
3. `DISM /Online /Cleanup-Image /ScanHealth`
4. `SFC /verifyonly`

The script stops before SFC if `RestoreHealth` fails. It also treats a final `ScanHealth` result of **component store is repairable** as unresolved even when the DISM process returned exit code 0. A clean SFC result does not silently promote a still-repairable component store to clean.

## Hardware-upgrade evidence

For RAM decisions, capture the exact module count, capacity, manufacturer, part number, rated speed, configured speed, and configured voltage. Capture model and BIOS revision too. Do not infer maximum supported memory solely from a missing/zero WMI `MaxCapacityEx`, and do not infer GPU VRAM from `AdapterRAM`.

Use current manufacturer/service documentation or a compatibility database as a separate purchasing gate; this repository collector proves only what the current machine reports.

## Proof levels

- **Observed:** local metadata or native command output was captured.
- **Identity pinned:** a backup target is distinct from the system disk and matches supplied stable expectations.
- **Catalog verified:** Windows backup catalog/artifact is visible on the confirmed target.
- **Integrity verified:** the exact health commands completed and their final text is recorded.
- **Not proven here:** successful bare-metal restore, external boot-media acceptance, firmware correctness, vendor RAM/SSD compatibility, application performance, or destructive-cleanup correctness.

## Validation

```bash
python -m pytest -q Tests/recovery/test_windows_workstation_recovery_contracts.py
```

Windows CI also parses all PowerShell files and executes the sanitized fixture path through the collector.
