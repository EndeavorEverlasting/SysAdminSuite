# Windows backup-image preflight

`Test-SasBackupImagePreflight.ps1` is a **read-only gate** used before creating a Windows system image on an external disk. It exists to prevent an operator or agent from treating a drive letter alone as target identity and to stop backup work when Windows lacks safe operating headroom.

## Safety contract

For any later disk-destructive operation, the required order is:

1. **Verify** the exact target identity and current state.
2. **Stop** on any mismatch or ambiguity.
3. **Act** only after the verification passes and the operator has authorized that specific mutation.
4. **Verify** the resulting state before continuing.

This preflight implements only step 1. It contains no format, repair, partition, resize, encryption-change, hibernation-change, or deletion action.

## What the preflight proves

The script checks that:

- source and target resolve to different physical disks;
- the target label matches the operator-provided expected label;
- the target filesystem is NTFS;
- source and target disk/volume health are healthy;
- the target remains present with the same identity across repeated samples;
- the Windows source has at least the configured free-space floor;
- target free space exceeds source used space by the configured raw-capacity headroom.

It also reports BitLocker status when the cmdlet is available and reports the sizes of common system files (`hiberfil.sys`, `pagefile.sys`, `swapfile.sys`) without changing them. BitLocker recovery keys and key protectors are never collected.

## Run it

From the repository root in Windows PowerShell 5.1+ or PowerShell 7+:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-SasBackupImagePreflight.ps1 `
  -SourceDrive C `
  -TargetDrive D `
  -ExpectedTargetLabel 'BackupTarget'
```

Use the label that is actually expected for the intended external backup disk. Do not copy a sample label blindly.

Optional local evidence can be written to the operator's temporary directory:

```powershell
$out = Join-Path $env:TEMP ('sas-backup-image-preflight-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-SasBackupImagePreflight.ps1 `
  -SourceDrive C `
  -TargetDrive D `
  -ExpectedTargetLabel 'BackupTarget' `
  -OutputJson $out
```

The parent directory must already exist; the script will not create directories automatically. Runtime evidence remains local and must not be committed.

## Exit codes

- `0` — `READY`: all configured preflight gates passed.
- `2` — `BLOCKED`: one or more safety gates failed.
- other nonzero — the preflight itself could not complete, for example because a drive disappeared during inspection.

`READY` means only that the **preflight** passed. It is not proof that an image was created, that the image is restorable, or that cleanup is safe.

## Required continuation after READY

The backup workflow remains dependency ordered:

1. Create the system image with the approved imaging tool.
2. Create or confirm bootable recovery media.
3. Run the imaging tool's image-integrity verification.
4. Mount/open the image and restore representative files to a temporary location.
5. Only after those proofs pass, begin a separately authorized cleanup of the source drive.

If the preflight reports low source free space, do **not** jump directly to broad deletion. Inspect reversible or expendable sources of space first, then use the verify -> act -> verify contract for any change.

## Validation

Focused repository validation:

```powershell
Invoke-Pester -Path .\Tests\Pester\BackupImagePreflight.Tests.ps1 -CI
git diff --check
```
