# SystemRescue to WinRE QRFY transition

Use this boundary when a failing Windows disk has already been preserved from SystemRescue and the operator is ready to diagnose the original disk from Windows Recovery Environment (WinRE).

The machine-readable companion is `recovery/windows/winre-qrfy-catalog.json`.

## Scope

This contract preserves the useful recovery method without carrying private field evidence into source control. It owns:

- shell detection before command selection;
- QRFY-sized WinRE probes with no explicit write commands;
- the preservation-to-diagnosis handoff;
- source-specific binding between the intended source volume and its current-session DiskPart disk locator;
- classification of retained volume objects whose intended backing disk disappears even when unrelated recovery-media disks remain present;
- the source-volume-access and write gate before CHKDSK, Startup Repair, Reset, formatting, partition mutation, or reinstall.

It does **not** own personal machine profiles, serial-number ledgers, BitLocker recovery keys, product keys, usernames, private cloud-storage links, raw terminal photos, or recovered-file paths. Keep those in an operator-controlled private evidence store. Runtime output must remain ignored/untracked.

## QRFY transport contract

QRFY is the field transport mechanism used when the recovery environment has no convenient clipboard or remote shell. The agent supplies a balanced command payload, the operator renders it as a QR code, scans it into the recovery console, and returns the terminal result as text or a photograph.

Use the repository catalog instead of improvising command bodies:

`recovery/windows/winre-qrfy-catalog.json`

Rules:

1. Detect the current shell before selecting commands. `root@sysrescue` means Bash/SystemRescue; `X:\Windows\System32>` means WinRE `cmd.exe`.
2. Never send Windows `reg`, DiskPart, `manage-bde`, `pnputil`, or `mountvol` syntax to SystemRescue.
3. Never send Bash/Linux commands to WinRE.
4. Keep each rendered command at or below the catalog's practical 240-character QRFY limit.
5. Bundle closely related metadata checks when that reduces scans without producing a fragile oversized payload.
6. A legible terminal photo is valid field evidence. Do not force manual transcription merely because the result arrived as an image.
7. Do not commit returned terminal output or machine-specific values.

## Preservation gate before leaving SystemRescue

Before Windows diagnosis begins, prove all of these facts:

1. the destination disk identity is current and distinct from the failing source;
2. the whole-device image and map/checkpoint artifacts exist on that destination;
3. any read-only image filesystem, BitLocker mapper, and loop device are cleanly detached;
4. the failing source has been returned to the intended protected read-only state before SystemRescue shutdown;
5. the recovery destination is unmounted and physically disconnected before Windows repair.

If `protect-source` or an equivalent operator-approved preservation step previously ran `blockdev --setro`, then a later Linux `RO=1` observation is expected host-side protection. It is **not by itself proof** that the SSD controller permanently forced the device read-only. Controller health and kernel evidence are separate diagnostic inputs.

### Preservation limit across reboot

The Linux block-layer `setro` flag is host state and does **not** survive the reboot into WinRE. The QRFY WinRE catalog contains no explicit write command, but that is not the same thing as a media write blocker. Windows can mount or otherwise touch a volume while servicing a seemingly read-only query.

Therefore:

- metadata-only WinRE probes may establish shell and physical-device presence;
- do **not** traverse the source filesystem or run source-volume probes other than the metadata-only `volume_disk_binding_probe` merely to diagnose disappearance;
- if strict source preservation must continue in WinRE, establish hardware/controller write protection or another independently proven Windows-side read-only mechanism first;
- when no such WinRE protection exists and strict preservation remains mandatory, return to the SystemRescue/image lane rather than lowering the preservation guarantee.

## Entering WinRE

Prefer built-in Automatic Repair or known-good Windows recovery media. On systems where firmware exposes a boot menu, use the board/vendor-specific boot-menu key only to select recovery media; do not describe that key as a universal WinRE hotkey.

Once WinRE Command Prompt is open, start with metadata-only probes. Do not claim the source remains read-only merely because the previous SystemRescue session ended at `RO=1`.

Disk numbers are session locators, not durable identity. Re-resolve the intended source-volume-to-disk relationship on every WinRE boot. A recovery USB or other attached disk must never stand in for the intended source merely because some disk row remains visible.

## Non-mutating-intent WinRE sequence

The catalog intentionally starts with primitive metadata probes rather than CHKDSK or source-volume traversal.

### 1. Confirm shell

Catalog command: `shell_identity`.

### 2. Inventory physical disks and retained volumes

Catalog command: `volume_inventory`.

Do not treat a drive letter as a disk identity. Record current physical-disk rows and retained volume rows independently.

### 3. Bind the intended source volume to its current-session DiskPart disk

Catalog command: `volume_disk_binding_probe` with the intended source volume's observed drive letter.

`detail volume` can expose the disk number associated with the selected volume without traversing filesystem contents. Treat that disk number only as a locator for the current WinRE session.

If the intended source volume is present but no backing-disk number can be resolved, classify:

`source_disk_identity_unresolved`

Fail closed. Do not access the source volume or run repair commands merely because the volume object exists.

### 4. Re-query that exact backing disk

Catalog command: `source_disk_presence_probe` with the disk number resolved in step 3.

Compare the resolved source disk number with the current DiskPart disk inventory. Unrelated recovery USB or other disks do not satisfy this gate.

If the intended source volume resolves to a disk number but that disk number is absent from current DiskPart inventory or cannot be selected/detailed, classify:

`backing_device_unavailable`

This is a source-specific device-presence/storage-stack problem until contrary evidence is obtained. **Do not run CHKDSK**, Startup Repair, Reset this PC, formatting, DiskPart clean, reinstall, or source-volume traversal merely because a retained volume's filesystem column looks Unknown/RAW.

Catalog command `device_presence_probe` can supplement that diagnosis by enumerating currently connected disk-class PnP devices. It is not a substitute for the source-volume-to-disk binding.

### 5. Treat already-observed filesystem symptoms as supporting evidence only

An already-observed combination of BitLocker `Lock Status: Unlocked` plus `dir <drive>:\` returning `A device which does not exist was specified.` supports `backing_device_unavailable` when source-specific presence evidence also points there.

Do **not** reproduce that symptom with a fresh directory probe unless source write protection is independently proven in the current WinRE session.

### 6. Gate volume-level probes

Catalog commands `bitlocker_status_probe`, `volume_guid_probe`, `windows_hive_probe`, and `directory_probe` are marked `requires_source_write_protection=true`.

Use them only after hardware/controller write protection or another independently proven Windows-side read-only mechanism protects the source. Their presence in the catalog is not authorization to run them on an unprotected failing disk.

## Why RAW/Unknown and generic disk counts are not enough

Recovery environments can retain partition or volume objects even when the intended backing device becomes unavailable. Recovery media can also remain as an unrelated physical disk. Therefore:

- `RAW` or `Unknown` is diagnostic evidence, not a corruption verdict;
- `Healthy` is a volume-manager status, not proof that the underlying SSD is healthy;
- an unlocked BitLocker status is not proof of current source-device presence;
- `list disk` showing one or more rows is not proof that the intended source disk is among them;
- a zero-row `list disk` result with retained source-volume objects is one obvious special case, not the generic rule;
- CHKDSK requires an addressable filesystem and should not be used to diagnose a disappearing controller/device.

## Write gate

Write-capable repair may be considered only after current evidence proves:

1. the intended source volume has a current-session binding to the intended physical disk;
2. that exact backing disk is enumerated and stable in the current session;
3. BitLocker state is understood and the volume is accessible under an authorized source-protection posture;
4. preserved recovery artifacts remain independently available;
5. the operator has explicitly entered a repair/reinstall lane with its own mutation authorization.

Until then, keep these actions blocked:

- source-volume traversal when strict preservation lacks a current write blocker;
- CHKDSK repair modes;
- Startup Repair;
- Reset this PC;
- formatting or partition-table mutation;
- `diskpart clean` / `clean all`;
- reinstall or image restore to the source.

## Privacy boundary

Repository artifacts should contain only reusable commands, classifications, reason codes, and tests. Never commit:

- actual serial numbers or hostnames;
- product keys or firmware-embedded key values;
- BitLocker recovery keys;
- usernames, email addresses, or private local paths;
- Google Drive or other private evidence-store URLs;
- raw terminal photos or recovered-file listings.

Sanitized fixtures may use obviously synthetic placeholders when executable tests require representative values.

## Proof ceiling

This contract can prove that SysAdminSuite routes a preserved failing disk into a privacy-safe, non-mutating-intent WinRE diagnostic sequence, binds retained source-volume state to the intended current-session backing disk, ignores unrelated recovery-media disks when deciding source presence, and refuses source-volume access or common write-capable repair actions when source identity/presence is unresolved.

It does **not** prove WinRE itself write-blocks the source. It cannot prove a specific SSD is healthy, that a disappeared device will return after power cycling, that CHKDSK/Startup Repair would succeed, that Windows will reactivate after reinstall, or that a particular backup image is restorable. Those remain field/runtime gates.
