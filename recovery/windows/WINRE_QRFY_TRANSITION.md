# SystemRescue to WinRE QRFY transition

Use this boundary when a failing Windows disk has already been preserved from SystemRescue and the operator is ready to diagnose or repair the original disk from Windows Recovery Environment (WinRE).

The machine-readable companion is `recovery/windows/winre-qrfy-catalog.json`.

## Scope

This contract preserves the useful recovery method without carrying private field evidence into source control. It owns:

- shell detection before command selection;
- QRFY-sized read-only WinRE probes;
- the preservation-to-repair handoff;
- classification of retained volume objects whose backing disk disappears;
- the write gate before CHKDSK, Startup Repair, Reset, formatting, partition mutation, or reinstall.

It does **not** own personal machine profiles, serial-number ledgers, BitLocker recovery keys, product keys, usernames, private cloud-storage links, raw terminal photos, or recovered-file paths. Keep those in an operator-controlled private evidence store. Runtime output must remain ignored/untracked.

## QRFY transport contract

QRFY is the field transport mechanism used when the recovery environment has no convenient clipboard or remote shell. The agent supplies a balanced command payload, the operator renders it as a QR code, scans it into the recovery console, and returns the terminal result as text or a photograph.

Use the repository catalog instead of improvising command bodies:

`recovery/windows/winre-qrfy-catalog.json`

Rules:

1. Detect the current shell before selecting commands. `root@sysrescue` means Bash/SystemRescue; `X:\Windows\System32>` means WinRE `cmd.exe`.
2. Never send Windows `reg`, DiskPart, `manage-bde`, `pnputil`, or `fsutil` syntax to SystemRescue.
3. Never send Bash/Linux commands to WinRE.
4. Keep each rendered command at or below the catalog's practical 240-character QRFY limit.
5. Bundle closely related read-only checks when that reduces scans without producing a fragile oversized payload.
6. A legible terminal photo is valid field evidence. Do not force manual transcription merely because the result arrived as an image.
7. Do not commit returned terminal output or machine-specific values.

## Preservation gate before leaving SystemRescue

Before Windows repair begins, prove all of these facts:

1. the destination disk identity is current and distinct from the failing source;
2. the whole-device image and map/checkpoint artifacts exist on that destination;
3. any read-only image filesystem, BitLocker mapper, and loop device are cleanly detached;
4. the failing source has been returned to the intended protected read-only state;
5. the recovery destination is unmounted and physically disconnected before Windows repair.

If `protect-source` or an equivalent operator-approved preservation step previously ran `blockdev --setro`, then a later Linux `RO=1` observation is expected host-side protection. It is **not by itself proof** that the SSD controller permanently forced the device read-only. Do not clear the protection merely to satisfy curiosity; controller health and kernel evidence are separate diagnostic inputs.

The Linux block-layer flag is host state. Rebooting into WinRE starts a new storage stack; do not assume Linux `setro` persists into Windows.

## Entering WinRE

Prefer built-in Automatic Repair or known-good Windows recovery media. On systems where firmware exposes a boot menu, use the board/vendor-specific boot-menu key only to select recovery media; do not describe that key as a universal WinRE hotkey.

Once WinRE Command Prompt is open, remain read-only until physical-device presence, volume mapping, and BitLocker state are reconciled.

## Read-only WinRE sequence

The catalog intentionally starts with primitive probes rather than CHKDSK.

### 1. Confirm shell

Catalog command: `shell_identity`.

### 2. Inventory physical disks and retained volumes

Catalog command: `volume_inventory`.

Do not treat a drive letter as a disk identity. Record whether DiskPart enumerates physical-disk rows separately from the volume rows it retains.

### 3. Probe BitLocker and directory access together

Catalog command: `bitlocker_volume_probe` with the observed drive letter.

BitLocker `Lock Status: Unlocked` proves only that BitLocker is not currently blocking access. It does **not** prove that the backing physical disk or filesystem remains addressable.

### 4. Classify backing-device disappearance before filesystem repair

If all three observations are present:

- BitLocker reports `Lock Status: Unlocked`;
- `dir <drive>:\` returns `A device which does not exist was specified.`;
- DiskPart `list disk` returns zero physical-disk rows while volume objects still exist;

classify the state as:

`backing_device_unavailable`

This is a device-presence/storage-stack problem until contrary evidence is obtained. **Do not run CHKDSK**, Startup Repair, Reset this PC, formatting, DiskPart clean, or reinstall merely because the volume's filesystem column looks Unknown/RAW.

The next safe catalog command is `device_presence_probe`, which checks connected DiskDrive devices, the volume GUID mapping, and filesystem metadata without intentionally writing to the target.

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

This contract can prove that SysAdminSuite routes a preserved failing disk into a privacy-safe, read-only WinRE diagnostic sequence and refuses common write-capable repair actions when the physical backing device is unavailable.

It cannot prove a specific SSD is healthy, that a disappeared device will return after power cycling, that CHKDSK/Startup Repair would succeed, that Windows will reactivate after reinstall, or that a particular backup image is restorable. Those remain field/runtime gates.
