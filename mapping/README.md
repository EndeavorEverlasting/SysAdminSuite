# Printer Mapping

## Northwell field use: system-wide only

For Northwell shared/multi-user Windows PCs, start with [`../START-HERE-NORTHWELL-PRINTER-MAPPING.md`](../START-HERE-NORTHWELL-PRINTER-MAPPING.md).

Northwell now has three technician-facing CMD entrypoints at the repository root:

```text
Map-NorthwellPrinter-SystemWide.cmd
Edit-NorthwellPrinter-Batch.cmd
Map-NorthwellPrinters-Batch.cmd
```

### Quick mapping

Double-click `Map-NorthwellPrinter-SystemWide.cmd` for one-off work. It requests elevation when needed, asks for one or more target PC hostnames, then collects one or more **print server + queue set** pairs.

The quick launcher offers this known field-proven Northwell example:

```text
\\SYKPNHPHPS01V\LS001-EMS01
```

Pressing Enter at both printer prompts explicitly accepts that example. The target PC is never defaulted; the technician must still supply the intended hostname(s).

A quick run can map:

- one PC to one printer;
- many PCs to one printer;
- one PC to many printers;
- many PCs to many printers.

For a second print server, answer `y` when the quick launcher asks whether another server/queue set should be added.

### Batch mapping

Double-click `Edit-NorthwellPrinter-Batch.cmd` to create/open the local batch file:

```text
mapping\NorthwellPrinterBatch.csv
```

That local CSV is ignored by Git. It is created from the tracked safe template:

```text
mapping\Examples\NorthwellPrinterBatch.example.csv
```

Columns are:

```text
ComputerName,PrintServer,QueueName
```

Use semicolons **inside a cell** to list more than one computer or queue. One row means: map every queue in that row to every computer in that row.

Examples:

```text
ComputerName,PrintServer,QueueName
PC001;PC002,SYKPNHPHPS01V,LS001-EMS01
PC003;PC004,PRINTSERVER02,QUEUE01;QUEUE02
```

After saving the CSV, double-click:

```text
Map-NorthwellPrinters-Batch.cmd
```

The batch wrapper validates each row, resolves every queue through the same canonical Northwell queue rules, and delegates each row to `Invoke-NorthwellPrinterMapping.ps1`. It does not implement a second mapping mechanism.

Queue input in the quick or advanced paths may be `\\server\queue`, `//server/queue`, or queue name only. Direct printer IP addresses are rejected.

For agents or advanced operators, the underlying PowerShell engine is:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER\QUEUE01'
```

The engine already accepts arrays of computers and printers:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 `
  -ComputerName PC001,PC002 `
  -Printer '\\PRINTSERVER\QUEUE01','\\PRINTSERVER\QUEUE02'
```

The engine also accepts queue name only:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer 'QUEUE01'
```

Queue-only input is resolved from Active Directory, or can be paired with `-PrintServer`.

**Client invariant:** mapping must be per-computer/system-wide for all users. The canonical runner stages a SYSTEM task and uses `PrintUIEntry /ga`, then requires HKLM machine-wide connection proof before reporting success.

Do not substitute `Utilities\Map-Printer.ps1` or `Add-Printer -ConnectionName`; those are per-user paths and do not satisfy the Northwell multi-user requirement.

## Implementation surfaces

- `../Map-NorthwellPrinter-SystemWide.cmd` — canonical one-click quick technician front door; self-elevates and preserves terminal result.
- `../Edit-NorthwellPrinter-Batch.cmd` — creates/opens the local gitignored batch CSV.
- `../Map-NorthwellPrinters-Batch.cmd` — self-elevating batch launcher.
- `Start-NorthwellPrinterMapping.ps1` — interactive quick wrapper with repeated server/queue-set collection.
- `Start-NorthwellPrinterBatch.ps1` — batch planner/orchestrator; one CSV row becomes one canonical engine call.
- `Examples/NorthwellPrinterBatch.example.csv` — tracked starter batch template.
- `Invoke-NorthwellPrinterMapping.ps1` — canonical validated mapping/proof engine.
- `Modules/NorthwellPrinterMapping.Core.psm1` — hostname/queue normalization, queue-only AD resolution, direct-IP rejection, and batch-row planning.
- `Workers/` — maintained machine-wide worker implementations and reference logic.
- `Controllers/` — existing orchestration/recon controllers.
- `native/` — compiled/native printer-mapping path for restricted environments.
- `Archive/` — historical scripts; not a field entrypoint.

## Validation

Targeted contract tests:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester\NorthwellPrinterMapping.Tests.ps1
```

Broader mapping tests:

```powershell
Invoke-Pester -Path .\Tests\Pester\Mapping.Tests.ps1,.\Tests\Pester\NorthwellPrinterMapping.Tests.ps1
```

A live client proof additionally requires an authorized Northwell Windows controller, reachable target PC hostname(s), and real shared printer queue(s).
