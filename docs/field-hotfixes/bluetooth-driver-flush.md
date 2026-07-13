# Bluetooth Driver Flush and Restore

## Purpose

This local-only utility is for corporate Windows workstations where Bluetooth audio drops randomly, devices fail to connect, or the Bluetooth settings interface cannot remove or pair devices. 

The tool performs a safe, evidence-first reset of the Bluetooth stack, backing up all state before clearing corrupt PnP driver packages and radio bindings.

## Fast path for technicians

From the SysAdminSuite repo root on the affected workstation, run:

```cmd
Run-BluetoothDriverFlushHelp.cmd
```

The launcher requests Administrator permission (required to query PnP devices and stop system services) and presents an interactive menu.

## Menu Options

1. **Status / Help**: Queries the current status of Bluetooth system services (`bthserv`, `BthAudioHF`, `btwavext`, `RFCOMM`, `BthLEEnum`) and lists active Bluetooth PnP devices.
2. **WhatIf Preview**: Simulates the flush procedure to show what will be removed, reset, or restarted without making changes.
3. **Backup Only**: Performs a complete backup of the registry keys, service state, COM ports, audio endpoints, and driver store Bluetooth entries, then exits.
4. **Open Latest Backup Folder**: Opens the Windows Explorer to the latest timestamped backup folder under `%APPDATA%\BT_Flush_Backups`.
5. **Run Full Repair**: Runs the full procedure (Backup -> Validate Backup -> Remove corrupt Bluetooth PnP nodes -> Reset Radio -> Restart Services). **Requires explicit 'YES' confirmation.**
6. **Restore and Re-Pair Guidance**: Displays restoration details and re-pairing steps.

## Safety and Validation Gates

- **Evidence-First Backup**: The repair phase will NOT mutate the system unless a complete state backup is captured first.
- **Backup Verification**: The utility validates that all critical backup files (`bthport.reg`, `com_ports.reg`, `service_states.json`, etc.) exist and are non-empty before any driver packages or device nodes are deleted. If any validation check fails, the utility aborts.
- **Safe-by-Default Filters**: By default, device removal is restricted to audio profiles (speakers, headsets, earbuds). Unrelated Bluetooth devices (e.g. mouse, keyboard) are preserved unless their friendly name matches the target filter.

## Evidence Output

Each run creates a timestamped folder under:
`%APPDATA%\BT_Flush_Backups\YYYYMMDD_HHMMSS`

The directory contains:
- `bthport.reg` (BTHPORT registry hive export)
- `bt_audio.reg` (BluetoothAudio registry hive export)
- `com_ports.reg` (COM Ports registry hive export)
- `bt_enum.reg` (Bluetooth Enumeration registry hive export)
- `bt_class.reg` (Bluetooth Class registry hive export)
- `service_states.json` (Service states query)
- `com_ports_current.txt` (Active SERIALCOMM registry query)
- `audio_endpoints.json` (PnP Audio Endpoint list)
- `bt_devices.json` (PnP Bluetooth device list)
- `driver_store_bt.txt` (Bluetooth drivers in the driver store)

> [!IMPORTANT]
> Do not commit these registry backups or local log files to the repository.

## Rollback and Restoration

To restore the system state from a backup:
1. Open the latest backup folder under `%APPDATA%\BT_Flush_Backups`.
2. To restore a registry hive, run:
   ```cmd
   reg import <backup_folder>\<file_name>.reg
   ```
3. Restart the Bluetooth services or reboot the workstation.

## Escalation Criteria

Stop and escalate to system leads if:
- Backup validation fails repeatedly.
- The Bluetooth radio is disabled and cannot be enabled.
- PnP device removal fails with access denied (even when run as Administrator).
