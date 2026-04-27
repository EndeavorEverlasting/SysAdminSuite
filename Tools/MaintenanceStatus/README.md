# Maintenance Status Harness

`maintenance_status.sh` is a Bash prototype harness for workstation maintenance workflows.

It displays a rotating status screen while a device is under IT control. The current modules are placeholders by design. Replace each placeholder module with real checks as SysAdminSuite matures.

## Current Purpose

- Keep a workstation visibly marked as under maintenance.
- Show active module rotation and progress movement.
- Prevent accidental shutdown, unplugging, restart, or user interference.
- Provide a clean shell prototype that can later be wired into real checks.

## Run

```bash
chmod +x maintenance_status.sh
./maintenance_status.sh
```

Optional faster/slower display cadence:

```bash
TICK_DELAY_SECONDS=2 ./maintenance_status.sh
```

## Placeholder Modules

- Pre-requisite verification
- System readiness check
- Application package review
- SIS application validation
- SmartLynx configuration review
- Device integration checks
- Network connectivity validation
- Security policy alignment
- Autologon access posture review
- Peripheral communication checks
- Final QA pending technician confirmation

## Future Wiring Targets

Replace placeholder module names with actual module functions for:

- Network connectivity checks
- Required application path validation
- Service status checks
- Device Manager / COM port checks where platform-appropriate
- Policy or configuration posture checks
- Timestamped logs
- Exit codes
- JSON or TXT output artifacts
- QRTasks integration

## Design Rule

This is a status harness first. Make the screen honest, useful, and replaceable. When a module becomes real, wire it in cleanly instead of hiding logic in the display layer.
