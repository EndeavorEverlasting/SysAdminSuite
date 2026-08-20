# Northwell Printer Management — Advanced Operations

Use this page for **Northwell** shared-printer administration beyond routine mapping: unmap, undo, defaults, batches, and evidence.

For an ordinary technician who only needs to map a printer, use the simpler path instead:

```text
Map-NorthwellPrinter.cmd
```

Tutorial: `docs/tutorials/NORTHWELL_PRINTER_MAPPING_FOR_TECHS.md`.

## Advanced management menu

From a current SysAdminSuite checkout/runtime, double-click:

```text
Manage-NorthwellPrinters.cmd
```

The menu exposes:

1. map printer(s) system-wide;
2. unmap printer(s) system-wide;
3. undo the latest observed printer-state change;
4. edit an operator-local default printer;
5. edit the local batch CSV;
6. run a mixed map/unmap batch;
7. open the latest printer evidence directory for that runtime.

This management menu is intentionally broader than the one-click technician mapper. Routine tech distribution should favor `Map-NorthwellPrinter.cmd`, which routes through the installed `sas printer`/current-origin bootstrap path and does not require the technician to know a checkout location.

## Network authority

Live Northwell printer work requires an approved protected route, including:

- NSLIJHS-WAB;
- a live Windows `DomainAuthenticated` non-Wi-Fi hardwire/LAN path;
- an authenticated VPN represented by a live `DomainAuthenticated` non-Wi-Fi interface; or
- another explicitly configured protected route accepted by the shared Northwell network authority.

Guest/Internet-only posture remains fail-closed for target printer operations.

## Map

Preferred routine technician path:

```text
Map-NorthwellPrinter.cmd
```

Terminal equivalent:

```text
sas printer
```

Current-runtime/internal launcher:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

Advanced PowerShell:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01'
```

Mapping drives the requested machine-wide queue state to **Present**. The endpoint action runs as SYSTEM using the registered Northwell machine-wide PrintUI path. A queue already present is a safe no-op.

## Unmap

Clickable:

```text
Unmap-NorthwellPrinter-SystemWide.cmd
```

Advanced:

```powershell
.\mapping\Invoke-NorthwellPrinterUnmapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01'
```

Unmapping drives the requested machine-wide queue state to **Absent** with the paired SYSTEM operation. It removes the requested per-computer shared-queue registration; it does **not** delete arbitrary printer ports and does not switch to per-user `Remove-Printer` behavior.

When a full `\\server\queue` is supplied for unmapping, a retired print server does not need to resolve merely to remove its stale machine-wide registration.

## Undo

Every live desired-state run records observed before/after state and writes `UndoPlan.json` only for queues whose requested state actually changed.

To reverse the latest observed transitions:

```text
Undo-LatestNorthwellPrinterChange.cmd
```

The inverse plan is shown before mutation and requires typing `UNDO`. A successful undo creates its own inverse evidence.

## Defaults

Edit the local approved server/queue default with:

```text
Edit-NorthwellPrinter-Defaults.cmd
```

The file is local/gitignored. The target computer is never defaulted.

## Batch map and unmap

Edit:

```text
Edit-NorthwellPrinter-Batch.cmd
```

Run:

```text
Map-NorthwellPrinters-Batch.cmd
```

Tracked columns are:

```text
Action,ComputerName,PrintServer,QueueName
```

`Action` is `Map` or `Unmap`. Use semicolons inside a cell for multiple computers or queues. One row applies its action to every listed queue on every listed computer.

Before live mutation the complete resolved plan is displayed and requires explicit confirmation. Child undo plans are aggregated into the batch undo evidence.

## Evidence and failure handling

A normal printer state run can produce:

```text
ResolvedPlan.json
Controller.log
Summary.json
UndoPlan.json
<target>\Status.json
<target>\Agent.log
ActiveUserMaterialization.json
```

Do not infer success merely because a CMD launched. Do not repeatedly remap after an ambiguous failure. Use the run evidence to determine whether the requested state changed and whether another action is safe.

## Hard client boundaries

- Northwell only; Health & Hospitals remains a separate `discovery_required` use case.
- Shared queue identity only.
- Target hostnames/FQDNs, not target IPs.
- No printer-IP mapping fallback.
- System-wide/per-computer mapping for the Northwell shared-PC requirement.
- SYSTEM endpoint identity.
- No per-user connection fallback.
- No test page emitted by map, unmap, batch, or undo.
- A real requested document printed after canonical mapping outranks lower-level diagnostic telemetry for that observed case.

## Proof checkpoint

On August 20, 2026, the current-main quick mapping path was field-observed on an approved `DomainAuthenticated` wired connection producing both SYSTEM-wide HKLM registration proof and immediate active-user materialization proof.

That validates the Northwell mapping/materialization path; physical document output remains separate runtime acceptance evidence.
