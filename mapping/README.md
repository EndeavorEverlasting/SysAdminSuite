# Printer Mapping

## Northwell field use: system-wide only

For Northwell shared/multi-user Windows PCs, start with [`../START-HERE-NORTHWELL-PRINTER-MAPPING.md`](../START-HERE-NORTHWELL-PRINTER-MAPPING.md).

Northwell technician-facing CMD entrypoints at the repository root:

```text
Map-NorthwellPrinter-SystemWide.cmd
Edit-NorthwellPrinter-Defaults.cmd
Edit-NorthwellPrinter-Batch.cmd
Map-NorthwellPrinters-Batch.cmd
```

### Quick mapping

Double-click `Map-NorthwellPrinter-SystemWide.cmd` for ad-hoc work. It requests elevation, asks for one or more target PC hostnames, then collects one or more print-server/queue sets.

Accepted printer forms are `\\server\queue`, `//server/queue`, or server + queue prompts. Direct printer IP addresses are rejected.

Quick mapping supports one or many computers and one or many printers. Add another print-server/queue set when prompted to span multiple print servers.

### Operator-local default printer

Double-click `Edit-NorthwellPrinter-Defaults.cmd` to create/open:

```text
Config\northwell-printer-defaults.local.json
```

That file is gitignored because it may contain live infrastructure. The repository ships only the synthetic template:

```text
mapping\Examples\NorthwellPrinterDefaults.example.json
```

Once the local file contains an approved `PrintServer` and `QueueName`, quick mapping displays them in brackets. Pressing Enter explicitly accepts the local values. There is never a default target computer.

### Batch mapping

Double-click `Edit-NorthwellPrinter-Batch.cmd` to create/open the local gitignored:

```text
mapping\NorthwellPrinterBatch.csv
```

It is copied from the tracked synthetic template:

```text
mapping\Examples\NorthwellPrinterBatch.example.csv
```

Columns:

```text
ComputerName,PrintServer,QueueName
```

Use semicolons inside a cell for multiple computers or queues. One row means: **map every queue in that row to every computer in that row**.

Synthetic example:

```text
PC001;PC002,PRINTSERVER01,QUEUE01;QUEUE02
```

After saving the CSV, double-click `Map-NorthwellPrinters-Batch.cmd`. The wrapper performs local shape validation, requires Northwell network authority before AD/DNS-backed resolution, prints the complete resolved plan, and requires the technician to type `MAP` before live mutation.

Each row delegates to `Invoke-NorthwellPrinterMapping.ps1`; batch mode is orchestration, not a second mapping implementation.

## Canonical engine

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01'
```

The engine already accepts arrays:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 `
  -ComputerName PC001,PC002 `
  -Printer '\\PRINTSERVER01\QUEUE01','\\PRINTSERVER01\QUEUE02'
```

Queue-only input can be resolved from Active Directory, or paired with `-PrintServer`.

**Northwell invariant:** mapping is per-computer/system-wide for all users. The runner stages a SYSTEM task, uses `PrintUIEntry /ga`, and requires HKLM machine-wide connection proof. It does not print test pages.

Do not substitute `Utilities\Map-Printer.ps1` or `Add-Printer -ConnectionName`; those are per-user paths.

## Implementation surfaces

- `../Map-NorthwellPrinter-SystemWide.cmd` — quick mapping launcher.
- `../Edit-NorthwellPrinter-Defaults.cmd` — local approved default editor; no mapping.
- `../Edit-NorthwellPrinter-Batch.cmd` — local batch editor; no mapping.
- `../Map-NorthwellPrinters-Batch.cmd` — batch mapping launcher.
- `Start-NorthwellPrinterMapping.ps1` — interactive wrapper.
- `Start-NorthwellPrinterBatch.ps1` — batch planner/orchestrator.
- `Examples/NorthwellPrinterDefaults.example.json` — synthetic local-default template.
- `Examples/NorthwellPrinterBatch.example.csv` — synthetic batch template.
- `Invoke-NorthwellPrinterMapping.ps1` — canonical validated mapping/proof engine.
- `Modules/NorthwellPrinterMapping.Core.psm1` — validation, queue resolution, and local batch parsing.

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester\NorthwellPrinterMapping.Tests.ps1
```

A live client proof additionally requires an authorized Northwell Windows controller, approved target hostname(s), and approved shared queue(s).
