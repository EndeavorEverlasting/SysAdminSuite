# Windows 11 clean install: first-boot NVMe discovery gate

**Owner:** SysAdminSuite `recovery/windows`  
**Evidence class:** operator-observed screenshots / historical workstation-recovery notes; **not** a remotely executed live probe.  
**Updated:** 2026-10-09

## Why this exists

A successfully booted Windows 11 installation can show the system SSD in File Explorer while a second, newly installed NVMe SSD remains absent there. **File Explorer enumerates mounted volumes, not all physical disks.** A brand-new unallocated SSD can be present and healthy without a volume or drive letter.

This checklist prevents premature hardware-failure claims or writes to the wrong disk. It complements the read-only collector described in [README.md](README.md), rather than creating a competing storage-inspection engine.

## Sanitized recovery case — 2026-10-09

| Observation | Evidence | What it proves / does not prove |
| --- | --- | --- |
| Installation USB appears in UEFI boot selector | Operator photo of UEFI USB entry | Firmware enumerated and booted Windows installation media. |
| Windows Setup displayed **Disk 0: 3.7 TB unallocated**, **Disk 1: 1.8 TB unallocated**, **Disk 2: 28.9 GB ESD-USB** | Operator photo at disk-selection stage | Both internal SSD capacity classes were enumerated **during installation**; does not prove their current Windows runtime state or stable disk-number mapping. |
| Operator selected Disk 1 for a Windows 11 Home clean install | Operator setup photos / report | Installation target was the 1.8 TB class; manufacturer/model binding should be rechecked when needed. |
| Windows reached desktop; File Explorer showed **C: 1.81 TB** and installation USB, not a second internal volume | Operator desktop photo | OS boots from a 2 TB-class internal disk and the secondary is **not mounted in Explorer**. Does **not** prove that the 4 TB-class SSD disappeared, failed, or needs reseating. |
| Local-account setup appeared in Windows Settings | Operator photo | Account is local; activation, profile directory, and administrator membership remain separate checks. |
| An older source SSD was set aside to preserve recovery options | Operator report and prior recovery coordination record | No new write to the old source was authorized; backup-image/mapfile verification is still outstanding. |

### Current classification

`SECONDARY_VOLUME_NOT_VISIBLE_IN_EXPLORER` — **Windows Disk Management / Get-Disk not yet observed**. Most direct hypothesis: the previously unallocated 4 TB-class disk has no partition, filesystem, or drive letter. Treat this as a hypothesis until runtime disk enumeration proves it.

## Read-only first pass — before any initialization or formatting

1. **Open Disk Management** (`diskmgmt.msc`) and locate the physical disk with the expected capacity. Capture whether it is `Unknown / Not Initialized`, `Online / Unallocated`, `Offline`, or absent. If Windows offers a disk-initialization dialog, **cancel it until identity is confirmed**.
2. If the UI is unclear, run **read-only** PowerShell from the newly installed Windows environment:

   ```powershell
   Get-Disk | Select-Object Number, FriendlyName, @{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,1)}}, PartitionStyle, OperationalStatus, IsOffline
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

## Acceptance criteria for the next operator session

1. A current Windows runtime inventory shows the two internal NVMe devices by **model/capacity**, with both current partition states.
2. System SSD and old recovery source are protected by explicit device-identity gates.
3. Any partition or filesystem creation is confined to the *verified* secondary device, after approval.
4. Only then verify the new secondary volume in Disk Management, File Explorer, and read-only OS inventory.
5. Follow separately with Windows activation, chipset/GPU drivers, update status, SSD health/temperature/firmware, and recovery-evidence validation. These checks are **pending**, not completed.

### Proof boundary

This tracked note documents observed setup/desktop facts and a read-only decision procedure. It is **not** evidence that the new OS has been remotely inspected, secondary storage initialized, recovery media verified on another boot, original SSD forensics completed, activation confirmed, or deployment/tooling rebuilt.


## Observed outcome (2026-10-09)

The operator identified the 4 TB-class secondary model through read-only PowerShell before initializing it. A later Disk Management screenshot shows the secondary disk Basic/Online with one healthy NTFS volume, while File Explorer independently shows its E: mount and approximately 3.72 TB of free capacity. The earlier condition `SECONDARY_VOLUME_NOT_VISIBLE_IN_EXPLORER` is resolved for this case. SMART health, sustained I/O, future-boot persistence, activation, and developer tooling remain unverified. The checklist above remains the reusable first-boot method, but its pending language is historical to this completed case.
