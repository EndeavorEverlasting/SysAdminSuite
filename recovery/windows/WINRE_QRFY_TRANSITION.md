# SystemRescue to WinRE QRFY transition

Use this boundary when a failing Windows disk has already been preserved from SystemRescue and the operator is ready to diagnose the original disk from Windows Recovery Environment (WinRE).

The machine-readable companion is `recovery/windows/winre-qrfy-catalog.json`.

## Scope

This contract preserves the useful recovery method without carrying private field evidence into source control. It owns:

- shell detection before command selection;
- QRFY-sized WinRE probes with no explicit write commands;
- the preservation-to-diagnosis handoff;
- classification of retained volume objects whose backing disk disappears;
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
- do **not** traverse the source filesystem or query source-volume internals merely to diagnose disappearance;
- if strict source preservation must continue in WinRE, establish hardware/controller write protection or another independently proven Windows-side read-only mechanism first;
- when no such WinRE protection exists and strict preservation remains mandatory, return to the SystemRescue/image lane rather than lowering the preservation guarantee.

## Entering WinRE

Prefer built-in Automatic Repair or known-good Windows recovery media. On systems where firmware exposes a boot menu, use the board/vendor-specific boot-menu key only to select recovery media; do not describe that key as a universal WinRE hotkey.

Once WinRE Command Prompt is open, start with metadata-only probes. Do not claim the source remains read-only merely because the previous SystemRescue session ended at `RO=1`.

## Non-mutating-intent WinRE sequence

The catalog intentionally starts with primitive metadata probes rather than CHKDSK or source-volume traversal.

### 1. Confirm shell

Catalog command: `shell_identity`.

### 2. Inventory physical disks and retained volumes

Catalog command: `volume_inventory`.

Do not treat a drive letter as a disk identity. Record whether DiskPart enumerates physical-disk rows separately from the volume rows it retains.

### 3. Confirm connected disk-class devices

Catalog command: `device_presence_probe`.

This is the next safe probe when DiskPart retains volume rows but returns no physical-disk rows. It does not intentionally traverse the source filesystem.

### 4. Classify backing-device disappearance before source-volume access

If both observations are present:

- DiskPart `list disk` returns zero physical-disk rows; and
- DiskPart `list vol` still returns one or more volume objects;

classify the state as:

`backing_device_unavailable`

This is a device-presence/storage-stack problem until contrary evidence is obtained. **Do not run CHKDSK**, Startup Repair, Reset this PC, formatting, DiskPart clean, reinstall, or source-volume traversal merely because a retained volume's filesystem column looks Unknown/RAW.

An already-observed combination of BitLocker `Lock Status: Unlocked` plus `dir <drive>:\` returning `A device which does not exist was specified.` is supporting evidence for the same classification. Do **not** reproduce that symptom with a fresh directory probe unless source write protection is independently proven in the current WinRE session.

### 5. Gate volume-level probes

Catalog commands `bitlocker_status_probe`, `volume_guid_probe`, `windows_hive_probe`, and `directory_probe` are marked `requires_source_write_protection=true`.

Use them only after hardware/controller write protection or another independently proven Windows-side read-only mechanism protects the source. Their presence in the catalog is not authorization to run them on an unprotected failing disk.

## Why the RAW/Unknown display is not enough

Recovery environments can retain partition or volume objects even when the backing device becomes unavailable. Likewise, an encrypted volume can display as Unknown until the relevant layer is available. Therefore:

- `RAW` or `Unknown` is diagnostic evidence, not a corruption verdict;
- `Healthy` is a volume-manager status, not proof that the underlying SSD is healthy;
- an unlocked BitLocker status is not proof of current device presence;
- CHKDSK requires an addressable filesystem and should not be used to diagnose a disappearing controller/device.

## Write gate

Write-capable repair may be considered only after current evidence proves:

1. the intended physical disk is enumerated and stable;
2. the intended volume maps to that disk;
3. BitLocker state is understood and the volume is accessible;
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

This contract can prove that SysAdminSuite routes a preserved failing disk into a privacy-safe, non-mutating-intent WinRE diagnostic sequence, distinguishes physical-device presence from retained volume state, and refuses source-volume access or common write-capable repair actions when the backing physical disk is unavailable.

It does **not** prove WinRE itself write-blocks the source. It cannot prove a specific SSD is healthy, that a disappeared device will return after power cycling, that CHKDSK/Startup Repair would succeed, that Windows will reactivate after reinstall, or that a particular backup image is restorable. Those remain field/runtime gates.
