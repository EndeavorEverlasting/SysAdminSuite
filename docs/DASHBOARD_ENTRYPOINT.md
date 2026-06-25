# Dashboard Entry Point

Plain-language guide for field users and help desk staff.

## Default front door

| What | Where |
|------|-------|
| Double-click this | `START-HERE-SysAdminSuite-Dashboard.bat` (repo root) |
| Read this first | [`START-HERE-SysAdminSuite.md`](../START-HERE-SysAdminSuite.md) |
| Browser URL | `http://127.0.0.1:5000/dashboard/` |
| Cybernet tutorial URL | `http://127.0.0.1:5000/dashboard/?tutorial=cybernet` |

The START-HERE launcher:

1. Starts the PS-independent dashboard host (`.NET 8` tray + local web server).
2. Waits a few seconds for the host to bind port `5000`.
3. Opens the browser to the Cybernet tutorial entry point.
4. Leaves the host running in the system tray.

CLI survey tools are **not** the default front door.

## What the user should see

1. A console window with a friendly title: **SysAdminSuite Dashboard**.
2. A tray icon near the clock.
3. A browser tab on the local dashboard.
4. A **Start Cybernet Survey** button or wizard rail for guided work.

If the tray icon is present, the dashboard is running even after the console window closes.

## Host lookup order

`Launch-SysAdminSuiteDashboard.Host.bat` (called by the START-HERE launcher) searches for the host executable in this order:

1. `app/bin/SysAdminSuite.DashboardHost.exe` (portable zip layout)
2. `dist/SysAdminSuiteDashboard/SysAdminSuite Dashboard.exe` (friendly local publish)
3. `tools/publish/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.exe`
4. `src/SysAdminSuite.DashboardHost/bin/Release/net8.0-windows/...`
5. `src/SysAdminSuite.DashboardHost/bin/Debug/net8.0-windows/...`

## Building the friendly executable locally

The repo does **not** commit dashboard host binaries. Build them on the workstation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\publish-dashboard-entrypoint.ps1
```

Output (gitignored):

- `dist/SysAdminSuiteDashboard/SysAdminSuite Dashboard.exe`
- `dist/SysAdminSuiteDashboard/SysAdminSuite.DashboardHost.exe`
- `tools/publish/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.exe` (compatibility copy)

Requires **.NET 8 runtime** on the target machine (framework-dependent publish).

## Advanced launchers (preserved)

| Launcher | Audience | Notes |
|----------|----------|-------|
| `START-HERE-SysAdminSuite-Dashboard.bat` | Field users | Friendly title, browser open, fallback help |
| `Launch-SysAdminSuiteDashboard.Host.bat` | IT / developers | Direct host spawn, no extra messaging |
| `Launch-SysAdminSuiteDashboard.bat` | Permissive sites | PowerShell + Python legacy path |
| `Launch-SysAdminSuite-Runtime.bat` | Portable zip | Menu: GUI, PS dashboard, .NET host |
| `Start-CybernetSurveyTutorial.cmd` | Legacy | Opens `file://` dashboard; prefer START-HERE host path |

## Troubleshooting

### Browser did not open

Paste manually:

```text
http://127.0.0.1:5000/dashboard/?tutorial=cybernet
```

### Host executable not found

Run the publish script once, then retry START-HERE.

### Port 5000 already in use

Stop the other dashboard instance from the tray icon (**Stop Dashboard**), or ask IT to free the port.

### Dashboard folder not found

Run START-HERE from the cloned repo root. The host expects a `dashboard/` folder beside the executable or in a parent directory.

### When to escalate to CLI

Use [`START-HERE-CYBERNET-NEURON-SURVEY.md`](../START-HERE-CYBERNET-NEURON-SURVEY.md) when the lead approves subnet discovery orchestration beyond the dashboard wizard.

## Related docs

- [`docs/GUI_HOST_MIGRATION.md`](GUI_HOST_MIGRATION.md) — launcher matrix and host flags
- [`docs/WAB_TEST_READINESS.md`](WAB_TEST_READINESS.md) — local smoke classification
- [`dashboard/README.md`](../dashboard/README.md) — dashboard panels and samples
