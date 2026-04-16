# Native mapping contract (parity with PowerShell)

This document defines behavioral and artifact contracts for the native tools in this folder. They mirror [`../Workers/Map-MachineWide.ps1`](../Workers/Map-MachineWide.ps1) and [`../Controllers/Map-Run-Controller.ps1`](../Controllers/Map-Run-Controller.ps1) unless noted below.

## SysAdminSuite.Mapping.Worker.exe (endpoint)

### Purpose

Runs **locally** on a workstation or server to inventory and/or change **machine-wide** printer connections (`PrintUIEntry /ga` and `/gd`), emitting logs and CSV/HTML under `OutputRoot`.

### CLI parameters

| Switch | PowerShell equivalent | Notes |
|--------|----------------------|--------|
| `-ListOnly` | `-ListOnly` | Snapshot only; no changes. |
| `-PlanOnly` | `-PlanOnly` | No changes; results show planned add/remove. |
| `-Preflight` | `-Preflight` | Checks Spooler service and logs admin warning if not elevated. |
| `-PruneNotInList` | `-PruneNotInList` | After adds, remove UNC connections not in `-Queues` (requires non-empty desired set). |
| `-RestartSpoolerIfNeeded` | `-RestartSpoolerIfNeeded` | Restarts Spooler after changes. |
| `-OutputRoot` | `-OutputRoot` | Default `C:\ProgramData\SysAdminSuite\Mapping`. |
| `-Queues` | `-Queues` | Comma-separated UNC paths. May be repeated. |
| `-QueuesFile` | *(extension)* | UTF-8 file; one UNC per line (`#` comments OK). Merged with `-Queues`. |
| `-RemoveQueues` | `-RemoveQueues` | Comma-separated removes. |
| `-RemoveQueuesFile` | *(extension)* | Same as `-QueuesFile` for removals. |
| `-DefaultQueue` | `-DefaultQueue` | Registers a one-shot **at-logon** scheduled task for `BUILTIN\Users` using `rundll32 printui.dll,PrintUIEntry` (`/in` then `/y`) — **no PowerShell** in the task. |
| `-StopSignalPath` | `-StopSignalPath` | Default `%OutputRoot%\Stop.json`. |
| `-StatusPath` | `-StatusPath` | Default `%OutputRoot%\status.json`. |
| `-EnableUndoRedo` | `-EnableUndoRedo` | **Not supported** in the native worker (PowerShell undo stack). If passed, a warning is printed and execution continues. |

`--help` / `-?` prints usage.

### Artifacts (when I/O enabled)

I/O runs when any of: `ListOnly`, `PlanOnly`, non-empty queues/removals, or `DefaultQueue` is set (same rule as the script’s `$doIO`).

Layout under `OutputRoot`:

```
logs\<yyyyMMdd-HHmmss>\
  Run.log
  Preflight.csv
  Results.csv
  Results.html
```

- **Preflight.csv** columns: `SnapshotTime`, `ComputerName`, `Type`, `Target`, `PresentNow`, `InDesired`, `Notes`
- **Results.csv** columns: `Timestamp`, `ComputerName`, `Type`, `Target`, `Driver`, `Port`, `Status`
- **Results.html**: dark-theme table + optional Run.log excerpt (fallback path when `ConvertTo-SuiteHtml.ps1` is unavailable).
- **Run.log**: UTF-8; line-oriented log (PowerShell used `Start-Transcript`; native uses direct file append).

### Status and stop JSON

Compatible with [`Utilities/Invoke-RunControl.ps1`](../../Utilities/Invoke-RunControl.ps1):

**Stop.json** (input): `RequestedAt`, optional `RequestedBy`, `Reason`.

**status.json** (output): `GeneratedAt`, `State`, `Stage`, `Message`, `Data` (object with paths, flags, queue lists).

### Internals

- **UNC list**: `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections` → `\\server\share` lowercased.
- **Local printers**: `EnumPrinters` (local).
- **Add/remove**: `rundll32 printui.dll,PrintUIEntry /ga|/gd /n "<unc>"`
- **gpupdate**: `gpupdate.exe /target:computer /force` after mutations (when not stopped).

---

## SysAdminSuite.Mapping.Controller.exe (orchestrator)

### Purpose

Stages the **native worker EXE** over the admin share, creates a **one-shot** scheduled task (`/SC ONCE`) as **SYSTEM**, runs it, polls `%RemoteBase%\logs` for a new timestamped folder, copies artifacts to `%SessionRoot%\<ComputerName>\`, then deletes the task and cleans launcher crumbs.

### CLI parameters

| Switch | PS equivalent | Default |
|--------|----------------|---------|
| `-Computer` / `-Computers` | `-Computers` | Repeat per host. |
| `-ComputerFile` | `-ComputerFile` | One hostname per line; `#` comments. |
| `-LocalWorkerPath` | `-LocalScriptPath` (worker exe) | `SysAdminSuite.Mapping.Worker.exe` next to the controller exe. |
| `-SessionRoot` | `-SessionRoot` | `.\SysAdminSuite-Session-yyyyMMdd-HHmmss` |
| `-RemoteBase` | `-RemoteBase` | `C:\ProgramData\SysAdminSuite\Mapping` |
| `-TaskName` | `-TaskName` | `SysAdminSuite_PrinterMap` |
| `-MaxWaitSeconds` | `-MaxWaitSeconds` | `45` |
| `-WorkerArgs` | `-WorkerArgumentLine` | Extra arguments for the worker (quoted string). |
| `-StopSignalPath` | `-StopSignalPath` | Local controller `Stop.json`. |
| `-StatusPath` | `-StatusPath` | Local `Controller.Status.json`. |

### Remote layout

On `\\<Computer>\C$\ProgramData\SysAdminSuite\Mapping\`:

- `SysAdminSuite.Mapping.Worker.exe` (copy of local worker)
- `Stop.json` / `status.json` cleared before each run (worker writes status)

**No** `Start-Worker.ps1`, **no** `powershell.exe` in `/TR`.

Scheduled task command line (short form):

`"C:\ProgramData\SysAdminSuite\Mapping\SysAdminSuite.Mapping.Worker.exe" <WorkerArgs>`

If `WorkerArgs` would exceed ~200 characters, prefer `-QueuesFile` on the worker and stage a small args file via an extra copy step (future extension). The initial native controller passes `WorkerArgs` as provided.

### Differences from PowerShell controller

- **Undo/redo** (`EnableUndoRedo`, `Invoke-UndoRedo.ps1`) is **not** implemented; task create/delete is best-effort without a reversible session log.
- **Run-control / Invoke-RunControl.ps1** is **not** copied; the worker implements stop/status in-process.

### Session output

- `controller-log.txt` under `SessionRoot`
- Per-host folder: `SessionRoot\<ComputerName>\` with copied log bundle + `Worker.Status.json` if present.

---

## Build and signing

See [README.md](README.md). Release binaries should be **Authenticode-signed** for enterprise allowlists.
