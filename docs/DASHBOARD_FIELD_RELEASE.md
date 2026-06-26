# Dashboard Field Release Package

**Agent canonical reference** for how field users get the dashboard when source
checkout dependency bootstrap is not appropriate or is blocked.

## Two delivery paths

| Path | Who | What you get | .NET SDK on target? | Launcher behavior |
|------|-----|--------------|---------------------|-------------------|
| **Source clone** | Developers, IT building from git | Full repository | Can be installed by bootstrap if missing | Downloads official Microsoft .NET dependencies if needed, then prepares `app/bin/` |
| **Field release package** | Technicians, lay users on locked-down PCs | Pre-built ZIP with host under `app/bin/` | **Not required** | Double-click starts included host; runtime bootstrap may still run if framework-dependent runtimes are missing |

Field users on locked-down PCs where Microsoft downloads or administrator
installer approval are blocked should receive the **field release package**, not
a raw git clone.

Updates are also package-based for this path. The launcher may prompt when a
trusted manifest says a newer field package is available; it uses a
checksum-verified package before applying anything. See [`APPROVED_UPDATE_FLOW.md`](APPROVED_UPDATE_FLOW.md).

## Build the field release (trusted machine with .NET 8 SDK)

From repo root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\build\New-DashboardFieldRelease.ps1 -Version 0.1.0
```

Outputs (gitignored under `dist/`):

- `SysAdminSuite-Dashboard-Field-v0.1.0.zip`
- `SysAdminSuite-Dashboard-Field-v0.1.0.manifest.json` (SHA256 + UTC timestamp)

Package layout at zip root:

```text
START-HERE-SysAdminSuite-Dashboard.bat   ← double-click this
Launch-SysAdminSuiteDashboard.Host.bat
dashboard/
app/bin/SysAdminSuite.DashboardHost.exe  ← pre-built host + deps
START-HERE-SysAdminSuite.md
FIELD-RELEASE-README.txt
```

## Distribute to field users

1. Copy the zip (and manifest) to an approved channel (internal share, GitHub Release asset, Software Center).
2. Field user extracts the zip to a folder of their choice.
3. Field user double-clicks `START-HERE-SysAdminSuite-Dashboard.bat`.
4. Browser opens `http://127.0.0.1:5000/dashboard/?tutorial=setup`.

No git, no dotnet SDK, no manual publish command.

## CI artifact (optional)

Workflow [`.github/workflows/dashboard-field-release.yml`](../.github/workflows/dashboard-field-release.yml) builds the same zip on `workflow_dispatch` or when dashboard release paths change on `main`. Download the artifact from the Actions run — it is **not** committed to git.

## Launcher scenario messages

The root `.bat` tells the user which path applies:

| Situation | User sees |
|-----------|-----------|
| Packaged release (`app/bin/` host present) | “Packaged field release detected — no build step required” |
| Source clone, dependencies missing | “Source checkout — may be prepared on first run” then Microsoft .NET bootstrap and auto-build |
| Source clone, bootstrap blocked | Field-safe error: ask for field release package or IT prep |

## Requirements on target workstation

- Windows 10 or later
- .NET 8 ASP.NET Core and Windows Desktop runtimes for framework-dependent packages
- No internet required after dependencies are installed or the package is extracted

## Related docs

- [`DASHBOARD_ENTRYPOINT.md`](DASHBOARD_ENTRYPOINT.md) — launcher matrix and troubleshooting
- [`DASHBOARD_DEPENDENCY_BOOTSTRAP.md`](DASHBOARD_DEPENDENCY_BOOTSTRAP.md) — source checkout dependency bootstrap
- [`START-HERE-SysAdminSuite.md`](../START-HERE-SysAdminSuite.md) — lay-user guide (applies inside both clone and field package)
- [`DEPLOYMENT_ARTIFACTS.md`](DEPLOYMENT_ARTIFACTS.md) — full portable runtime zip (broader than dashboard-only)
- [`releases/PUBLISH.md`](releases/PUBLISH.md) — publishing checksums and channels

## Agent guardrails

- Do not commit `dist/` zip binaries to git.
- Do not tell field users to `git clone` when they need the field release package.
- Do not tell field users to run `publish-dashboard-entrypoint.ps1` by hand.
- Keep `START-HERE-SysAdminSuite-Dashboard.bat` canonical; `.cmd` files remain compatibility aliases only.
