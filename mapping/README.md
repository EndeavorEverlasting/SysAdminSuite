# Northwell Printer Management

Start with [`../START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md`](../START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md).

## One technician hub

Double-click:

```text
Manage-NorthwellPrinters.cmd
```

From any current SysAdminSuite checkout, that menu exposes quick map, quick unmap, undo latest observed change, local defaults, batch editing/execution, and latest evidence. Launchers resolve the repository relative to themselves; no operator-specific `C:\Users\...` path or named technician PC is required.

Live Northwell printer work accepts the shared guard's approved protected paths: WAB Wi-Fi, `DomainAuthenticated` hardwire/LAN, authenticated VPN/non-Wi-Fi, or an explicitly configured protected route.

## Reversible quick state

Map:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

Unmap:

```text
Unmap-NorthwellPrinter-SystemWide.cmd
```

Undo the latest observed transitions:

```text
Undo-LatestNorthwellPrinterChange.cmd
```

The canonical state engine is:

```powershell
.\mapping\Invoke-NorthwellPrinterState.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01' -DesiredState Present
.\mapping\Invoke-NorthwellPrinterState.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01' -DesiredState Absent
```

Compatibility wrappers remain:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1   -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01'
.\mapping\Invoke-NorthwellPrinterUnmapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01'
```

`Present` uses SYSTEM + `PrintUIEntry /ga`; `Absent` uses SYSTEM + the paired `PrintUIEntry /gd`. Both prove the requested HKLM per-computer state. Neither prints a test page, uses direct-IP fallback, deletes printer ports, or falls back to per-user `Add-Printer -ConnectionName`.

Every live state run captures before/after machine-wide state and writes `UndoPlan.json` containing only queues that actually changed. Already-present maps and already-absent unmaps are no-ops and do not create destructive inverse entries.

## Local defaults

Double-click `Edit-NorthwellPrinter-Defaults.cmd` to create/open the gitignored:

```text
Config\northwell-printer-defaults.local.json
```

Tracked defaults remain synthetic only. There is never a default target computer.

## Mixed batch management

Edit:

```text
Edit-NorthwellPrinter-Batch.cmd
```

Run:

```text
Map-NorthwellPrinters-Batch.cmd
```

CSV columns:

```text
Action,ComputerName,PrintServer,QueueName
```

`Action` is `Map` or `Unmap`; an older local CSV without `Action` defaults to `Map`. Semicolons inside a cell express multiple computers or queues. The complete mixed plan is displayed and requires exact `APPLY` confirmation before live mutation. Batch child inverse transitions are aggregated into a parent `UndoPlan.json`.

## Stale server removal

Mapping requires the print server to resolve before mutation. Unmapping a known full `\\server\queue` deliberately does not require the old server to resolve: a stale machine-wide registration must remain removable after a server is retired or unavailable.

## Implementation surfaces

- `../Manage-NorthwellPrinters.cmd` — technician hub.
- `../Map-NorthwellPrinter-SystemWide.cmd` — quick map.
- `../Unmap-NorthwellPrinter-SystemWide.cmd` — quick unmap.
- `../Undo-LatestNorthwellPrinterChange.cmd` — inverse of latest observed transitions.
- `../Edit-NorthwellPrinter-Defaults.cmd` — local default editor.
- `../Edit-NorthwellPrinter-Batch.cmd` — local batch editor.
- `../Map-NorthwellPrinters-Batch.cmd` — mixed batch runner.
- `Start-NorthwellPrinterMapping.ps1` — interactive map/unmap wrapper.
- `Start-NorthwellPrinterBatch.ps1` — batch planner/orchestrator.
- `Undo-NorthwellPrinterChange.ps1` — state-derived undo orchestration.
- `Invoke-NorthwellPrinterState.ps1` — canonical reversible engine.
- `Invoke-NorthwellPrinterMapping.ps1` — Present compatibility wrapper.
- `Invoke-NorthwellPrinterUnmapping.ps1` — Absent wrapper.
- `Modules/NorthwellPrinterMapping.Core.psm1` — validation, queue resolution, batch parsing, desired-state proof.
- `../scripts/SasNorthwellNetworkAuthority.psm1` — printer-facing route classification over the shared Northwell network guard.

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester\NorthwellPrinterMapping.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester\NorthwellPrinterReversibility.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester\NorthwellPrinterNetworkGuard.Tests.ps1
```

A live client proof additionally requires an authorized Northwell controller route, approved target hostname(s), and approved shared queue(s).
