# GUI Host Migration

Status: slice 1 landed — PS-independent dashboard host. Earlier WinForms control center
(`GUI/Start-SysAdminSuiteGui.ps1`) is preserved per
[`docs/POWERSHELL_LEGACY_POLICY.md`](POWERSHELL_LEGACY_POLICY.md) and remains the only
path for printer mapping run control, Kronos lookup, Machine Info, Compare/Deploy, and
UTF-8 BOM Sync. Slice 1 only replaces the dashboard launcher.

## Lane diagram

```
+---------------------------+    +------------------------------+    +------------------+
| Launch-SysAdminSuite-     |    | Launch-SysAdminSuiteDashboard|    | Launch-          |
| Runtime.bat               |    | .Host.bat                    |    | SysAdminSuiteDash|
| [1] PS GUI (WinForms)     |    | (no PowerShell, no Python)   |    | board.bat        |
| [2] PS dashboard launcher |--> | SysAdminSuite.DashboardHost  |    | (PS + Python)    |
| [3] .NET dashboard host   |    |  .exe  (.NET 8 tray)         |    | server.py        |
+---------------------------+    +--------------+---------------+    +--------+---------+
                                                |                             |
                                                v                             v
                                          http://127.0.0.1:5000/dashboard/  (vanilla HTML/JS)
```

## Launcher matrix

| Launcher | Requires PowerShell | Requires Python | Process model | Notes |
|----------|---------------------|-----------------|---------------|-------|
| `Launch-SysAdminSuite.bat` | yes (PS 5.1+) | no | WinForms GUI (`Start-SysAdminSuiteGui.ps1`) | Full control center (printer mapping, Kronos, Machine Info, BOM, tutorial). |
| `Launch-SysAdminSuiteDashboard.bat` | yes | yes | PS WinForms tray + `server.py` | Original Harold-splash launcher; preserved for permissive sites. |
| `Launch-SysAdminSuiteDashboard.Host.bat` | **no** | **no** | `SysAdminSuite.DashboardHost.exe` (.NET 8 tray + Kestrel) | Slice 1 deliverable. |
| `Launch-SysAdminSuite-Runtime.bat` `[3]` | no | no | Same as host `.bat` | Portable-zip entry point. |

## When to use the host

Use `Launch-SysAdminSuiteDashboard.Host.bat` (or Runtime `[3]`) when:

- `powershell.exe` is blocked, AppLocker-restricted, or governed by Constrained Language Mode.
- Python is not available on the endpoint.
- An operator only needs the dashboard surface (Log Mode + Live Mode command generation),
  not the full WinForms control center.

Use `Launch-SysAdminSuite.bat` when any of these are needed: printer mapping Run Control,
Kronos / Machine Info / Compare / Deploy vs AD probes, UTF-8 BOM Sync, or the guided tour.

## Host command-line options

```
SysAdminSuite.DashboardHost.exe [--port <int>] [--bind <ip>] [--dashboard-root <path>]
                                [--no-browser] [--no-tray]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--port` | `5000` | TCP port for Kestrel to bind. |
| `--bind` | `127.0.0.1` | Interface address. Keep `127.0.0.1` unless the dashboard must be reachable from other hosts. |
| `--dashboard-root` | auto-resolved | Override the `dashboard/` directory location (useful for tests and split installs). |
| `--no-browser` | off | Do not auto-launch the default browser. |
| `--no-tray` | off | Run as a console process without a NotifyIcon (CI / smoke). |

## Build and publish

Local dev:

```
dotnet build SysAdminSuite.sln -c Release
dotnet test SysAdminSuite.sln -c Release
```

Publish for portable packaging (framework-dependent, requires .NET 8 runtime on the target):

```
dotnet publish src/SysAdminSuite.DashboardHost -c Release -r win-x64 --self-contained false ^
  -o tools/publish/SysAdminSuite.DashboardHost
```

The publish output is what `tools/build/New-PortableArtifact.ps1` copies into
`app/bin/` in the portable zip, and what the host `.bat` looks for first.

## Behavior parity with `server.py`

`DashboardStaticServer` mirrors `server.py do_GET` (lines 562-598):

- `GET /dashboard` -> 301 redirect to `/dashboard/`.
- `GET /dashboard/` -> serves `dashboard/index.html`.
- `GET /dashboard/<path>` -> serves the file if it resolves inside `dashboard/`,
  otherwise 403 (path traversal) / 404 (missing).
- MIME table matches `server.py MIME_TYPES`; everything else falls back to
  `application/octet-stream`.
- `GET /` -> 302 redirect to `/dashboard/`. The host does **not** port the large
  embedded overview HTML from `server.py` (deferred to a later slice).

## Follow-up slices (separate branches)

1. `feature/runtime-menu-host-default` - make Runtime menu prefer host path by default.
2. `feature/gui-run-control-host` - C# Run Control panel calling native mapping EXEs.
3. `feature/gui-probe-launcher` - C# Machine Info / survey probe runner.
4. Installer / Authenticode signing - sign `SysAdminSuite.DashboardHost.exe` like
   the native mapping binaries under `mapping/native/`.

## Field smoke (operator)

From a portable zip:

```
Launch-SysAdminSuite-Runtime.bat   (choose [3])
```

Or directly:

```
Launch-SysAdminSuiteDashboard.Host.bat
```

Expected:

- Tray icon appears.
- Default browser opens `http://127.0.0.1:5000/dashboard/`.
- Right-click tray -> Open Dashboard / Copy URL / Stop Dashboard.
- Stop returns the port immediately.

Restricted-endpoint classification on success: `OK_LOCAL_SMOKE` per
[`docs/WAB_TEST_READINESS.md`](WAB_TEST_READINESS.md). Network-feature claims still
require the preflight gate per [`docs/TEST_RESULT_CLASSIFICATION.md`](TEST_RESULT_CLASSIFICATION.md).
