# Windows 11 clean install: first-boot NVMe discovery gate

**Owner:** SysAdminSuite `recovery/windows`  
**Evidence class:** operator-observed screenshots / historical workstation-recovery notes; **not** a remotely executed live probe.  
**Updated:** 2026-11-13 (reconciliation of 2026-10-09 evidence)

## Why this exists

A successfully booted Windows 11 installation can show the system SSD in File Explorer while a second, newly installed NVMe SSD remains absent there. **File Explorer enumerates mounted volumes, not all physical disks.** A brand-new unallocated SSD can be present and healthy without a volume or drive letter.

This checklist prevents premature hardware-failure claims or writes to the wrong disk. It complements the read-only collector described in [README.md](README.md), rather than creating a competing storage-inspection engine.

## Installation USB: historical failure and verified recovery

The first Windows 11 Media Creation Tool attempt failed with `0x80070032 - 0xA001B`. The USB was intermittently absent from the tool's eligible-device list, and Windows also reported an unsuccessful format. Windows recognizing a USB device in the safe-removal menu proves some enumeration, **not** durable media writes. A volume disappearing after the operator deliberately selects **Eject** is expected and does not by itself indicate a malfunction; physically unplug and reconnect the device for another test.

**Later observed outcome:** after an administrator-run attempt and FAT32 preparation, the Media Creation Tool reported **"Your USB flash drive is ready"**, installation files were visible as `ESD-USB`, the target machine booted the UEFI USB entry, and Windows 11 Home successfully installed. Neither administrator elevation nor FAT32 preformatting was isolated as the root-cause fix; do not diagnose the first failure as permissions, hardware failure, or partition damage without a discriminating observation.

**Reusable recovery rule:** before repeating destructive formatting, compare the USB's physical disk identity, capacity and operational/read-only state using the existing read-only Windows recovery collector, and reconnect after Eject. If media is consistently writable but the Microsoft tool fails, an official Windows ISO and a verified ISO-to-USB utility are alternatives. If physical media is intermittently absent or reports no media, inspect port/device stability or substitute a known-good USB. Never select an internal SSD or protected recovery-source disk as the USB preparation target. This is historical context; no fresh USB remediation is currently required for the completed case.

## Sanitized recovery case — 2026-10-09

| Observation | Evidence | What it proves / does not prove |
| --- | --- | --- |
| Installation USB appears in UEFI boot selector | Operator photo of UEFI USB entry | Firmware enumerated and booted Windows installation media. |
| Windows Setup displayed **Disk 0: 3.7 TB unallocated**, **Disk 1: 1.8 TB unallocated**, **Disk 2: 28.9 GB ESD-USB** | Operator photo at disk-selection stage | Both internal SSD capacity classes were enumerated **during installation**; does not prove their current Windows runtime state or stable disk-number mapping. |
| Operator selected Disk 1 for a Windows 11 Home clean install | Operator setup photos / report | Installation target was the 1.8 TB class; manufacturer/model binding should be rechecked when needed. |
| Windows reached desktop; File Explorer showed **C: 1.81 TB** and installation USB, not a second internal volume | Operator desktop photo | OS boots from a 2 TB-class internal disk and the secondary is **not mounted in Explorer**. Does **not** prove that the 4 TB-class SSD disappeared, failed, or needs reseating. |
| Local-account setup appeared in Windows Settings | Operator photo | Account is local; activation, profile directory, and administrator membership remain separate checks. |
| An older source SSD was set aside to preserve recovery options | Operator report and prior recovery coordination record | No new write to the old source was authorized; backup-image/mapfile verification is still outstanding. |

### Initial classification (historical; subsequently resolved)

`SECONDARY_VOLUME_NOT_VISIBLE_IN_EXPLORER` was the **initial** Windows Setup / Explorer checkpoint, before current-runtime Disk Management and Get-Disk evidence was captured. At that stage an unallocated 4 TB-class disk was a hypothesis, not a failure diagnosis. The later observed NTFS mount below supersedes this temporary state for the 2026-10-09 case.

## Read-only first pass — before any initialization or formatting

1. **Open Disk Management** (`diskmgmt.msc`) and locate the physical disk with the expected capacity. Capture whether it is `Unknown / Not Initialized`, `Online / Unallocated`, `Offline`, or absent. If Windows offers a disk-initialization dialog, **cancel it until identity is confirmed**.
2. If the UI is unclear, run **read-only** PowerShell from the newly installed Windows environment:

   ```powershell
   Get-Disk | Select-Object Number, FriendlyName, @{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,1)}}, PartitionStyle, OperationalStatus, IsOffline, IsReadOnly
   Get-Partition | Select-Object DiskNumber, PartitionNumber, DriveLetter, @{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,1)}}, Type
   ```

3. Correlate **model + reported capacity + partition style + current OS state**. A disk number is session-local and must never be used alone as disk identity; a drive letter is not physical identity.
4. Classify the outcome:
   - **Present, online, entirely unallocated:** expected to be absent from Explorer. Eligible for a *separately authorized* GPT/new-simple-volume/NTFS plan after exact target binding.
   - **Present but uninitialized:** identify the physical device before authorizing GPT initialization; no assumption that all uninitialized disks are disposable.
   - **Offline / read-only / unexpected partition layout:** stop and investigate the reason; do not automatically toggle online or clear partitions.
   - **Not present in Windows:** check firmware NVMe enumeration, device seating/power isolation, M.2 slot sharing, and drivers *after* preserving evidence. Historical Setup visibility narrows but does not eliminate a new detection fault.

## Mutation gates

- **Never touch the original recovery-source SSD** or its external image/mapfiles during this first-boot workflow. Recovery claims remain historical until independently reverified.
- Do **not** use `diskpart clean`, `Clear-Disk`, `Format-Volume`, or delete an existing partition to make a disk appear.
- Do **not** assume `Disk 0` is the secondary drive after reboot. Rebind by model/capacity on every session.
- A proposed GPT initialization and partition format must explicitly identify the intended secondary drive, confirm it contains no needed data, and receive separate operator approval.
- Preserve read-only inspection output privately under ignored runtime evidence (such as `runs/windows-recovery/`); do not commit serial numbers, hostnames, user paths, or screenshots containing identifiers.

## Reusable acceptance criteria for a still-unresolved secondary SSD

1. A current Windows runtime inventory shows the two internal NVMe devices by **model/capacity**, with both current partition states.
2. System SSD and old recovery source are protected by explicit device-identity gates.
3. Any partition or filesystem creation is confined to the *verified* secondary device, after approval.
4. Only then verify the new secondary volume in Disk Management, File Explorer, and read-only OS inventory.
5. Follow separately with Windows activation, chipset/GPU drivers, update status, SSD health/temperature/firmware, and recovery-evidence validation. These checks are **pending**, not completed.

### Proof boundary

This note contains dated operator-observed milestones, including successful secondary-volume commissioning, plus a read-only decision procedure for future cases. It is **not** evidence that this host was remotely inspected, the USB was independently re-tested on a later date, original-source forensics completed, activation confirmed, SSD long-term health certified, or developer tooling completely rebuilt.


## Observed outcome (2026-10-09)

The operator identified the 4 TB-class secondary model through read-only PowerShell before initializing it. A later Disk Management screenshot shows the secondary disk Basic/Online with one healthy NTFS volume, while File Explorer independently shows its E: mount and approximately 3.72 TB of free capacity. The earlier condition `SECONDARY_VOLUME_NOT_VISIBLE_IN_EXPLORER` is resolved for this case. SMART health, sustained I/O, future-boot persistence, activation, and developer tooling remain unverified. The checklist above remains the reusable first-boot method, but its pending language is historical to this completed case.
