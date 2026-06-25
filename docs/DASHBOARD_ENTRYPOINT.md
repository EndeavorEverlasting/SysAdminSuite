# Dashboard Entry Point

**Agent canonical reference** for how field users open the SysAdminSuite web dashboard.

## Field user answer (plain language)

> Double-click **`START-HERE-SysAdminSuite-Dashboard.bat`** at the repo root.
> Your browser opens `http://127.0.0.1:5000/dashboard/?tutorial=cybernet`.
> CLI tools are optional — use them only when the dashboard or a runbook says so.

Compatibility aliases (same behavior, not the documented primary): **`START-HERE-SysAdminSuite-Dashboard.cmd`** and **`SysAdminSuite Dashboard.cmd`**.

## Launcher matrix

| File | Audience | What it does |
|------|----------|--------------|
| `START-HERE-SysAdminSuite-Dashboard.bat` | **Field users (primary)** | Friendly console, starts host, opens browser + Cybernet tutorial |
| `START-HERE-SysAdminSuite-Dashboard.cmd` | Compatibility alias | Calls the `.bat` launcher |
| `SysAdminSuite Dashboard.cmd` | Field desktops / shortcuts | Alias of the START-HERE `.bat` |
| `Launch-SysAdminSuiteDashboard.Host.bat` | IT / developers | Spawns tray host only (no extra messaging) |
| `Launch-SysAdminSuite-Runtime.bat` `[3]` | Portable zip | Menu entry for .NET host |
| `Launch-SysAdminSuiteDashboard.bat` | Permissive sites | Legacy PS + Python path |
| `dist/SysAdminSuiteDashboard/SysAdminSuite Dashboard.exe` | **Local build only** | Not committed; see publish script below |

## EXE policy (current vs future)

| Phase | Status | User action |
|-------|--------|-------------|
| **Now (shipped)** | `.bat` double-click launcher | Double-click `START-HERE-SysAdminSuite-Dashboard.bat` |
| **Now (local build)** | `tools/publish-dashboard-entrypoint.ps1` | IT runs once per machine; output under `dist/` (gitignored) |
| **Future sprint** | Committed or portable-shipped `.exe` | See [`DASHBOARD_EXE_FUTURE_SPRINT.md`](DASHBOARD_EXE_FUTURE_SPRINT.md) |

Agents must **not** tell lay users to run `python3 -m http.server`, raw `dotnet` commands, or `Launch-SysAdminSuiteDashboard.Host.bat` unless troubleshooting.

## Host executable lookup order

`Launch-SysAdminSuiteDashboard.Host.bat` searches:

1. `app/bin/SysAdminSuite.DashboardHost.exe` (portable zip)
2. `dist/SysAdminSuiteDashboard/SysAdminSuite Dashboard.exe` (friendly local publish)
3. `tools/publish/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.exe`
4. `src/SysAdminSuite.DashboardHost/bin/Release/net8.0-windows/...`
5. `src/SysAdminSuite.DashboardHost/bin/Debug/net8.0-windows/...`

## Build local EXE (developer / IT)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\publish-dashboard-entrypoint.ps1
```

Requires .NET 8 SDK to build; .NET 8 runtime on the target to run (framework-dependent publish).

## Browser tab icon (Harold)

The dashboard uses `dashboard/assets/harold.jpg` as the favicon (`<link rel="icon">` in `dashboard/index.html`).
Harold also appears on the boot loading splash and during in-app waits (`window.SASHarold`).

## Loading experience

See [`dashboard/README.md`](../dashboard/README.md) — **Loading experience (Hide the Pain Harold)**.

## Troubleshooting

| Symptom | Action |
|---------|--------|
| Browser did not open | Paste `http://127.0.0.1:5000/dashboard/?tutorial=cybernet` |
| Host exe not found | Run `tools/publish-dashboard-entrypoint.ps1`, retry `.bat` |
| Port 5000 in use | Stop prior instance from tray icon |
| User asks "do I run code?" | Point to `START-HERE-SysAdminSuite-Dashboard.bat` double-click; read [`START-HERE-SysAdminSuite.md`](../START-HERE-SysAdminSuite.md) |

## Related docs

- [`START-HERE-SysAdminSuite.md`](../START-HERE-SysAdminSuite.md) — lay user guide
- [`docs/GUI_HOST_MIGRATION.md`](GUI_HOST_MIGRATION.md) — launcher technical matrix
- [`docs/DASHBOARD_EXE_FUTURE_SPRINT.md`](DASHBOARD_EXE_FUTURE_SPRINT.md) — planned EXE sprint
- [`START-HERE-CYBERNET-NEURON-SURVEY.md`](../START-HERE-CYBERNET-NEURON-SURVEY.md) — advanced CLI path

## Agent guardrails

- Do not delete or demote the `.bat`/`.cmd` launchers in favor of CLI-only docs.
- `START-HERE-SysAdminSuite-Dashboard.bat` is the documented primary; keep the `.cmd` files as compatibility aliases, not as equal field-user choices.
- Do not commit `dist/` or live operational evidence.
- Do not edit PowerShell survey scripts unless explicitly requested.
- Preserve `Launch-SysAdminSuiteDashboard.Host.bat` for IT paths.
