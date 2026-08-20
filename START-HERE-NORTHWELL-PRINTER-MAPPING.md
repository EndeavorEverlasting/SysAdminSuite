# Northwell Printer Mapping — Start Here

This is the canonical **Northwell Health shared-printer mapping** path. It is for multi-user Windows PCs and approved shared print queues.

> **Technician:** start with `Map-NorthwellPrinter.cmd`.
>
> **Terminal equivalent:** `sas printer`.
>
> **Detailed technician walkthrough:** `docs/tutorials/NORTHWELL_PRINTER_MAPPING_FOR_TECHS.md`.

Do not reuse this workflow for Health & Hospitals or another organization unless that organization has its own separately registered and proven printer use case.

## Fast technician path

1. Connect to an approved Northwell protected path: hardwire/LAN, NSLIJHS-WAB, or authenticated Northwell VPN.
2. Double-click `Map-NorthwellPrinter.cmd`.
3. Approve the Administrator prompt if Windows displays one.
4. Choose a recent proven PC/printer by number when offered, or enter the requested hostname/shared queue.
5. Let the mapper finish and read the final result.

Success is explicit:

```text
PASS: requested printer map is proven SYSTEM-wide in HKLM.
READY: <computer> - active user <user> has the requested printer connection now.
Done. Machine-wide registration is proven; any active user session was finalized and verified.
```

If the mapper fails, **do not remap blindly**. Preserve the displayed error and evidence path for diagnosis.

## Northwell contract

- **System-wide / per-computer mapping.** These PCs may have multiple users.
- **Target PCs use hostnames/FQDNs, not IP addresses.**
- **Printers use shared queue identity**, such as `\\server\queue`, `//server/queue`, or a uniquely resolvable queue name.
- **Never map by printer IP address.**
- Endpoint registration runs as **SYSTEM** with `PrintUIEntry /ga`.
- Mapping success requires SYSTEM identity plus requested queue proof under the machine-wide HKLM printer-connection location.
- An already logged-on user is materialized and verified after successful machine-wide registration.
- The mapper **does not print test pages**.
- A real requested document printed afterward is separate, higher-level runtime acceptance evidence.

## Why `Map-NorthwellPrinter.cmd` is the technician front door

The technician CMD does not implement printer mapping itself. It delegates to the same trusted installed `sas printer` path and current-origin bootstrap already used by technical operators.

That means a non-technical technician does not need to know:

- where SysAdminSuite is checked out;
- which Git commit is current;
- a PowerShell command;
- the bootstrap cache/runtime path; or
- the underlying fallback transport.

When installed by the universal SysAdminSuite launcher installer, `Map-NorthwellPrinter.cmd` is placed beside `sas.cmd`. A copy from a current repository/runtime can also fall back through `Bootstrap-SysAdminSuitePrinter.cmd`.

## Recent PCs and printers

The quick mapper can show **Recent proven target PCs** and **Recent proven printer inputs**. Entering a displayed number reuses that input without forcing the technician to remember or retype it.

The interaction cache is convenience only. It does not replace authoritative network, queue, SYSTEM, or HKLM proof.

## One or many

Quick mapping supports one or multiple target PCs and shared queues through its prompts.

For larger prepared assignments, use the file/batch path:

```text
Edit-NorthwellPrinter-Batch.cmd
Map-NorthwellPrinters-Batch.cmd
```

The tracked template is synthetic. Local assignment data stays outside Git.

Batch mode validates the file, establishes Northwell network authority, displays the resolved plan, requires explicit confirmation, and delegates work to the same canonical printer engine. It is orchestration, not a second implementation.

## Defaults

`Edit-NorthwellPrinter-Defaults.cmd` maintains one local approved server/queue default in:

```text
Config\northwell-printer-defaults.local.json
```

The target PC is never defaulted. The repository template contains placeholders only.

## Advanced management

For unmapping, undo, defaults, mixed map/unmap batches, and local evidence tools, use:

```text
Manage-NorthwellPrinters.cmd
```

See `START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md`.

## Technical/runtime entrypoints

The following surfaces are implementation or advanced-operator paths, not the preferred non-technical technician front door:

```text
Bootstrap-SysAdminSuitePrinter.cmd
Bootstrap-SysAdminSuitePrinter.ps1
Map-NorthwellPrinter-SystemWide.cmd
mapping\Start-NorthwellPrinterMapping.ps1
mapping\Invoke-NorthwellPrinterMapping.ps1
```

`Map-NorthwellPrinter-SystemWide.cmd` remains the canonical quick **runtime launcher** registered by the Northwell use-case harness. `Map-NorthwellPrinter.cmd` is the human-facing distribution wrapper that gets the technician safely to that current runtime.

## Current-origin bootstrap behavior

The standard bootstrap treats the caller's current directory as irrelevant. It uses a dedicated machine-local printer state/cache, fetches current `origin/main` without force, proves the configured required printer baseline is contained in that mainline, and launches a clean detached runtime for the exact current branch head.

It does not reset, clean, stash, or check out an arbitrary technician repository. Superseded bootstrap-owned runtimes may be retired only under the bootstrap's preservation rules, with printer evidence preserved first.

Explicit offline/local-only mode remains separate and does not claim current-origin freshness.

## Evidence

Quick evidence is written beneath the selected printer runtime's:

```text
mapping\Logs\NorthwellPrinterMap-...
```

and includes authoritative run artifacts such as:

```text
ResolvedPlan.json
Controller.log
Summary.json
UndoPlan.json
<target>\Status.json
<target>\Agent.log
ActiveUserMaterialization.json
```

The active runtime also maintains `mapping\Logs\LATEST-PATH.txt`. Bootstrap state maintains the current runtime identity separately so evidence can survive runtime retirement.

## Proof precedence

Use evidence in this order:

1. **Real requested document printed after mapping** → runtime acceptance for that observed case.
2. **SYSTEM + HKLM queue proof** → machine-wide registration proof.
3. **Port/CIM/RPC/SMB/remote printer telemetry** → diagnostic context.

Do not demand another test page or rebuild a working printer merely to make lower-ranked telemetry look cleaner.

Machine-readable evidence authority:

```text
harness\api\northwell-printer-mapping-evidence-policy.json
```

## Field-proven checkpoint

On **August 20, 2026**, the current-main quick workflow was observed on an approved `DomainAuthenticated` wired Northwell path successfully producing:

- requested printer SYSTEM-wide HKLM registration proof; and
- immediate active-user materialization proof.

That closes the mapping/materialization proof gap for this Northwell use case. It does **not** claim physical document output unless a real document is separately observed printing.

## Do not substitute these paths

`Utilities\Map-Printer.ps1` is a per-user connection helper and does not satisfy the Northwell multi-user contract.

Archived printer scripts under `mapping\Archive\` are historical/reference surfaces, not technician entrypoints.

Never invent a direct-IP fallback, a per-user fallback, or an organization crossover when the registered use case does not authorize it.
