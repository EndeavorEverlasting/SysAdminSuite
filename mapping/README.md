# Printer Mapping

## Northwell field use: system-wide only

For Northwell shared/multi-user Windows PCs, start with [`../START-HERE-NORTHWELL-PRINTER-MAPPING.md`](../START-HERE-NORTHWELL-PRINTER-MAPPING.md).

**Technician front door:** double-click this file at the repository root:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

It requests elevation when needed and asks only for target PC hostname(s) plus printer queue(s). Queue input may be `\\server\queue`, `//server/queue`, or queue name only. Direct printer IP addresses are rejected.

For agents or advanced operators, the underlying PowerShell engine is:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER\QUEUE01'
```

The engine also accepts queue name only:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer 'QUEUE01'
```

Queue-only input is resolved from Active Directory, or can be paired with `-PrintServer`.

**Client invariant:** mapping must be per-computer/system-wide for all users. The canonical runner stages a SYSTEM task and uses `PrintUIEntry /ga`, then requires HKLM machine-wide connection proof before reporting success.

Do not substitute `Utilities\Map-Printer.ps1` or `Add-Printer -ConnectionName`; those are per-user paths and do not satisfy the Northwell multi-user requirement.

## Implementation surfaces

- `../Map-NorthwellPrinter-SystemWide.cmd` — canonical one-click technician front door; self-elevates and preserves terminal result.
- `Start-NorthwellPrinterMapping.ps1` — interactive two-input wrapper.
- `Invoke-NorthwellPrinterMapping.ps1` — canonical validated mapping/proof engine.
- `Modules/NorthwellPrinterMapping.Core.psm1` — hostname/queue normalization, queue-only AD resolution, direct-IP rejection.
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

A live client proof additionally requires an authorized Northwell Windows controller, a reachable target PC hostname, and a real shared printer queue.