# Maintenance Status Harness

`maintenance_status.sh` is a Bash prototype harness for workstation maintenance workflows.

It displays a rotating status screen while a device is under IT control. The current modules are placeholders by design. Replace each placeholder module with real checks as SysAdminSuite matures.

## Current Purpose

- Keep a workstation visibly marked as under maintenance.
- Show active module rotation and progress movement.
- Prevent accidental shutdown, unplugging, restart, or user interference.
- Provide a clean shell prototype that can later be wired into real checks.
- Support restricted Cybernet/autologon workflows where local browsing is blocked.

## Files

```text
Tools/MaintenanceStatus/
├── maintenance_status.sh
├── Run-MaintenanceStatus.cmd
├── Register-MaintenanceStatus-Task.cmd
└── README.md
```

## Recommended Field Model

The Bash script is the display engine. The technician should usually run the CMD launcher.

```text
CMD / QR / Task Scheduler
        ↓
Run-MaintenanceStatus.cmd
        ↓
Bash available?
    yes ↓
maintenance_status.sh
```

This avoids requiring the operator to `cd` into local folders or browse through blocked local directories.

## Run From a File Share

Use a full UNC path to the launcher:

```bat
cmd /k "\\YOUR-SERVER\YOUR-SHARE\SysAdminSuite\Tools\MaintenanceStatus\Run-MaintenanceStatus.cmd"
```

Expected share layout:

```text
\\YOUR-SERVER\YOUR-SHARE\SysAdminSuite\Tools\MaintenanceStatus\
    maintenance_status.sh
    Run-MaintenanceStatus.cmd
    Register-MaintenanceStatus-Task.cmd
```

## Run Locally When Allowed

From this folder:

```bash
chmod +x maintenance_status.sh
./maintenance_status.sh
```

Optional faster/slower display cadence:

```bash
TICK_DELAY_SECONDS=2 ./maintenance_status.sh
```

## Register at Logon With Task Scheduler

From the file share:

```bat
"\\YOUR-SERVER\YOUR-SHARE\SysAdminSuite\Tools\MaintenanceStatus\Register-MaintenanceStatus-Task.cmd"
```

Or pass the launcher path explicitly:

```bat
"\\YOUR-SERVER\YOUR-SHARE\SysAdminSuite\Tools\MaintenanceStatus\Register-MaintenanceStatus-Task.cmd" "\\YOUR-SERVER\YOUR-SHARE\SysAdminSuite\Tools\MaintenanceStatus\Run-MaintenanceStatus.cmd"
```

Test the task:

```bat
schtasks /Run /TN "SysAdminSuite Maintenance Status"
```

Remove the task:

```bat
schtasks /Delete /TN "SysAdminSuite Maintenance Status" /F
```

## Startup Folder Option

Task Scheduler is preferred. If Task Scheduler is blocked, this can be tested where `%APPDATA%` is writable:

```bat
copy "\\YOUR-SERVER\YOUR-SHARE\SysAdminSuite\Tools\MaintenanceStatus\Run-MaintenanceStatus.cmd" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Run-MaintenanceStatus.cmd"
```

## CMD-only QR Fallback

Use this when Bash is unavailable and the payload must fit into a QR-driven CMD launch:

```bat
cmd /k "title IT Maintenance Status & mode con: cols=88 lines=28 & setlocal EnableDelayedExpansion & set n=0 & for /L %A in (1,0,2) do @(for %M in ("Pre-requisite verification" "Cybernet readiness" "SIS validation" "SmartLynx review" "Network validation" "Security policy alignment" "Autologon posture" "Peripheral checks" "Final QA pending") do @(for %P in (7 14 23 31 42 56 68 77 86 94 99) do @(cls & echo ============================================================ & echo              IT MAINTENANCE STATUS HARNESS & echo ============================================================ & echo. & echo Workstation : %COMPUTERNAME% & echo Current Time: %DATE% %TIME% & echo. & echo Status      : Device is under IT maintenance / review. & echo Instruction : Do not power off, unplug, restart, or use. & echo. & echo Current Module: %~M & echo Progress      : %P%% & echo. & echo Placeholder modules active until real checks are wired in. & echo ============================================================ & timeout /t 3 /nobreak >nul)))"
```

It is intentionally crude. Use it only when file-share or Bash launch is blocked.

## Placeholder Modules

- Pre-requisite verification
- Cybernet workstation readiness
- SIS application validation
- SmartLynx configuration review
- Epic / TDR access posture
- Network connectivity validation
- Security policy alignment
- Autologon access posture review
- Peripheral communication checks
- COM port / serial pathway review
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
- Future compiled executable fallback for endpoints where Bash and PowerShell are blocked

## Design Rule

This is a status harness first. Make the screen honest, useful, and replaceable. When a module becomes real, wire it in cleanly instead of hiding logic in the display layer.
