# Bluetooth Targeted Device Eviction — Field Guide

This document outlines the usage, technical design, privacy rules, and restoration procedures for the targeted Bluetooth device eviction tool.

## Key Concepts

The eviction workflow enables a field technician to completely backup and remove all PnP nodes, registry state, and cached device identifiers for a *single target device* without affecting other paired devices or removing general Bluetooth OEM driver packages.

### Targeted Removal vs. Full Stack Reset

1. **Targeted Removal (`-RemoveTarget`)**:
   - Focuses strictly on one resolved device (by Friendly Name, MAC, or Instance ID).
   - Groups related nodes dynamically across multiple device classes (Bluetooth, AudioEndpoint, Media, SoftwareComponent).
   - Removes nodes in strict **leaf-to-parent** order.
   - Cleans up only the BTHPORT cache key for that device's remote MAC.
   - **Never** deletes global OEM driver packages from the driver store.
2. **Full Stack Reset (`-FullStackReset`)**:
   - Flushes general Bluetooth configurations.
   - Evicts all audio-class Bluetooth client devices.
   - Deletes matching Bluetooth OEM driver packages from the driver store using `pnputil /delete-driver`.

---

## Technical Workflow

### 1. List Candidates (Read-Only)
Run the following command to display all paired client devices, their statuses, masked MACs, and primary PnP IDs:
```powershell
.\Utilities\Invoke-BluetoothDriverFlush.ps1 -ListCandidates
```

### 2. Private Target Selection
To select a device, use one of the target selectors:
- `-TargetDeviceName "<FriendlyName>"`
- `-TargetMac "<MAC>"`
- `-TargetInstanceId "<PnpInstanceId>"`

#### Matching Behavior
- **Exact matching**: Friendly name matches are literal and case-insensitive by default.
- **Explicit contains/wildcard/regex**: Can be selected via `-MatchMode Contains|Wildcard|Regex`.
- **Ambiguous targets**: If a selector matches more than one physical device, the tool fails closed, prints a numbered list of candidates, and aborts with `TARGET_AMBIGUOUS`.
- **Zero matches**: If no device matches, the tool aborts with `TARGET_NOT_FOUND`.

### 3. Backup and Validation
Before any changes occur, a local backup folder is created at:
`$env:APPDATA\BT_Flush_Backups\<timestamp>\`

#### Restricted Permissions
To protect sensitive pairing-key link keys (if exported), the backup folder's inheritance is disabled, and ACLs are restricted strictly to:
- `SYSTEM`
- `Administrators`
- the executing `User`

#### Backup Manifest
The backup contains:
- `run-context.json` — operator, hostname, timestamp, OS, and mode details.
- `target-identity-before.json` — full details of the resolved target.
- `target-pnp-nodes-before.json` — list of related PnP nodes.
- `all-bluetooth-devices-before.json` — all paired Bluetooth devices.
- `audio-endpoints-before.json` — all audio endpoints.
- `bluetooth-services-before.json` — state of Bluetooth services before mutation.
- `bluetooth-radio-before.json` — status of the host Bluetooth adapter before mutation.
- `driver-packages-before.json` — list of driver packages in the store.
- `registry-backup-manifest.json` — manifest listing all exported registry files.
- `removal-plan.json` — ordered removal plan of PnP nodes and registry keys.
- `restore-plan.txt` — plain text guide for restoring state.
- `transcript.txt` — log transcript of the execution.
- Targeted registry exports:
  - `bthport_device_<MAC>.reg` — remote MAC device cache.
  - `enum_node_<index>.reg` — PnP node enum registry subkeys.

All backup files are verified to exist, be nonempty, and (if JSON) parse successfully. If validation fails, the run aborts before any service stops or PnP mutations occur.

### 4. Eviction Phase
1. Stops minimum services: `RFCOMM`, `bthserv`, `BthAudioHF`, `btwavext`, `BthLEEnum`.
2. Removes target PnP nodes in leaf-to-parent order:
   - `AudioEndpoint` nodes first
   - `Media` / child nodes second
   - `Bluetooth` service nodes third
   - Primary `Bluetooth` nodes last
3. Captures `pnputil.exe` output and checks exit codes.
4. Rescans PnP devices via `pnputil /scan-devices`.
5. Removes the target registry key under `HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<MAC>`.
6. Restarts all stopped services (including after failures).

---

## Privacy and Anonymization Rules

To protect private metadata:
- **Do not commit** the timestamped backup folders to Git.
- **Do not include** real friendly names, MAC addresses, instance IDs, or hostnames in tracked tests, documentation, or commit messages.
- Console displays mask MAC addresses by default (e.g. `00:11:22:xx:xx:xx`). Full MAC values exist only within the local, ACL-protected backup folder.

---

## Restore Plan

If manual restoration is required, locate the backup folder and run:
```powershell
# Restore target device registry parameters:
reg import "<backup-folder>\bthport_device_<MAC>.reg"

# Restore general Bluetooth parameters:
reg import "<backup-folder>\bthport.reg"
```
Re-plug the Bluetooth radio or restart the machine to reload registry keys.

---

## Failure Classifications

Every run returns a machine-readable summary object with a `.result` code:
- `BACKUP_FAILED` — Backup file creation or integrity validation failed.
- `TARGET_NOT_FOUND` — Selector did not match any candidate.
- `TARGET_AMBIGUOUS` — Selector matched multiple candidates.
- `ADMIN_REQUIRED` — Script run in mutation mode without Administrator elevation.
- `TARGET_REMOVAL_FAILED` — A PnP node failed uninstallation via `pnputil`.
- `REGISTRY_CLEANUP_FAILED` — Registry keys could not be removed.
- `SERVICE_RESTORE_FAILED` — Services could not be restarted.
- `TARGET_EVICTION_COMPLETE` — Eviction was fully successful.
- `REPAIR_CONFIRMED` — Post-eviction pairing verified.
