# SystemRescue disk-recovery harness

This lane turns the repeatable parts of a failing-Windows-drive recovery into a guarded SystemRescue workflow.

It is designed for a three-device field topology:

1. **Failing source drive** installed internally or connected through a dock.
2. **Large destination drive** connected by USB and used for the image, mapfile, evidence, and recovered files.
3. **SysAdminSuite media** connected by USB and mounted read-only or read-write only as needed to run this repository's scripts.

The SystemRescue boot USB may be a fourth device. Device names are never assumed to remain stable across boots.

## Safety boundary

The harness:

- identifies devices before any operation;
- requires the source to be unmounted and kernel-read-only;
- requires explicit source and destination paths;
- creates a new image only with `--confirm-new-image`;
- resumes only when both the image and GNU ddrescue mapfile already exist;
- attaches images, BitLocker mappers, and NTFS filesystems read-only;
- writes evidence and recovered files only to the explicit destination;
- never runs `chkdsk`, `ntfsfix`, `bootrec`, filesystem repair, BitLocker decryption-in-place, or writes an image back to the source.

A successful percentage shown by ddrescue is not the same as a verified file evacuation. Keep the source preserved until priority files have been copied and validated from the image.

## Entry point

```bash
bash recovery/systemrescue/sas-recovery.sh --help
```

The repository can live on a separate USB drive. Mount it at a short path such as `/mnt/sas`; then QR codes can point to the checked-in script instead of embedding script bodies.

## Operator loop

### 1. Inventory every boot

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh inventory
```

Record model and serial. Do not carry `/dev/sdX` assumptions across boots.

### 2. Protect the confirmed source

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh protect-source --source /dev/nvme0n1 --expect-model 'CONFIRMED MODEL' --expect-serial 'CONFIRMED SERIAL'
```

The command fails if the model or serial does not match, if any source partition is mounted, or if the read-only lock cannot be verified.

### 3. Mount the confirmed destination

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh mount-destination --partition /dev/sda2 --mount /mnt/expansion --expect-label Expansion
```

The current implementation accepts an exFAT destination and verifies the mount is read-write.

### 4A. Start a new whole-device image

Use this only when the image and mapfile do not exist:

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh start-image --source /dev/nvme0n1 --workdir /mnt/expansion/CASE_RECOVERY --image full-disk.img --map full-disk.map --confirm-new-image
```

The harness verifies source read-only state, destination free space, and artifact absence before starting GNU ddrescue.

### 4B. Resume an interrupted image

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh resume-image --source /dev/nvme0n1 --workdir /mnt/expansion/CASE_RECOVERY --image full-disk.img --map full-disk.map
```

This refuses to run without the existing image and mapfile. The fixed broad-pass policy is currently:

```text
ddrescue --no-scrape --verbose SOURCE IMAGE MAPFILE
```

Do not add direct I/O, reverse mode, retries, scraping, trimming overrides, or sector-size overrides without case evidence.

### 5. Preserve a failure or completion checkpoint

After ddrescue returns to the prompt:

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh capture-checkpoint --workdir /mnt/expansion/CASE_RECOVERY --map full-disk.map --tag pass1
```

This writes and syncs:

- full `dmesg` output;
- `ddrescuelog -t` map status;
- an artifact listing.

If the kernel disabled the source after a timeout/reset failure, do not issue another source read during that boot.

### 6. Attach and inspect the image read-only

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh attach-image --image /mnt/expansion/CASE_RECOVERY/full-disk.img --state-file /mnt/expansion/CASE_RECOVERY/loop.state
```

The loop device is written to `loop.state`. Inspect the printed partitions before choosing the BitLocker partition.

### 7. Open BitLocker read-only

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh open-bitlocker --partition /dev/loop1p3 --name sas_image_bitlk
```

If a clear-key protector is available, cryptsetup may open without prompting. If it prompts for a recovery passphrase, keep that secret off chat and out of logs.

### 8. Mount decrypted NTFS read-only

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh mount-ntfs --mapper /dev/mapper/sas_image_bitlk --mount /mnt/recovery-image
```

### 9. Audit extraction scope before copying

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh audit-user-data --source-root /mnt/recovery-image/Users --report /mnt/expansion/CASE_RECOVERY/user-audit.txt
```

The audit lists profiles, profile-root entries, and non-regular entries such as junctions, reparse points, and sockets. This makes skipped OneDrive links and similar cases visible before claiming full evacuation.

### 10. Copy user data

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh copy-user-data --source-root /mnt/recovery-image/Users --destination-root /mnt/expansion/CASE_RECOVERY/RECOVERED_USER_DATA --log /mnt/expansion/CASE_RECOVERY/user-copy.log
```

Default scope:

- all non-system profile directories under `Users`;
- normal files and directories;
- excludes `AppData`, `NTUSER.DAT*`, and standard Windows profile junctions;
- logs nonfatal rsync issues;
- syncs the destination;
- performs a final rsync dry-run comparison for the same profile scope.

Use `--include-appdata` only when application state is explicitly required and destination capacity has been considered.

This profile-copy pass does not include volume-root folders such as `ProgramData`, custom root directories, or application installations. Add those as separate evidence-backed copy lanes instead of silently broadening the default scope.

### 11. Clean up the read-only image stack

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh cleanup --mount /mnt/recovery-image --mapper-name sas_image_bitlk --loop-state-file /mnt/expansion/CASE_RECOVERY/loop.state --image /mnt/expansion/CASE_RECOVERY/full-disk.img
```

Cleanup refuses to detach a loop device unless the state file is a regular non-symlink file, names a valid read-only loop device, records the same canonical image path supplied by the operator, and matches the loop device's current backing file.

## QR-safe command catalog

The repository follows **QR = pointer, not payload**. Do not embed full shell scripts in QR codes.

After device paths and case paths are confirmed, generate exact commands:

```bash
bash recovery/systemrescue/sas-recovery.sh qr-catalog --repo-mount /mnt/sas --source /dev/nvme0n1 --expect-model 'CONFIRMED MODEL' --expect-serial 'CONFIRMED SERIAL' --destination /dev/sda2 --destination-label Expansion --workdir /mnt/expansion/CASE_RECOVERY --image full-disk.img --map full-disk.map --bitlocker-partition-number 3 --mode resume --max-chars 240
```

The catalog:

- emits numbered commands;
- reports each exact character count;
- fails if any command exceeds the selected limit;
- requires confirmed source model/serial, destination label, and BitLocker partition number;
- uses one short environment-setting QR followed by pointer commands;
- contains no base64 script payloads.

The default practical limit is 240 characters, below the 300-character truncation observed in the field workflow.

## Docking-station guidance

A USB dock or hub is appropriate when it provides stable power and enough ports for destination and SysAdminSuite media. Do not identify devices by USB-port order. Always gate on model, serial, filesystem, label, size, and current mount state.

For unstable NVMe devices, a cold power cycle may restore detection temporarily. A cold boot is not permission to restart blindly; repeat identity, read-only, destination, image, and mapfile gates first.

## Validation

Repository contract tests:

```bash
python Tests/recovery/test_systemrescue_recovery_contracts.py
```

Local shell checks:

```bash
bash -n recovery/systemrescue/sas-recovery.sh
bash recovery/systemrescue/sas-recovery.sh --help
```
