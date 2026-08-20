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

The operator-facing result is explicit. Common successful outcomes include:

```text
MAPPED NOW: <computer> -> <printer>. Machine-wide HKLM registration changed and is proven.
RESULT: READY (MAPPED_NOW). Machine-wide registration and active-user readiness are proven.
```

or, when no duplicate change is required:

```text
ALREADY MAPPED: <computer> -> <printer>. No machine-wide change was needed; HKLM registration is proven.
RESULT: READY (ALREADY_MAPPED). Machine-wide registration and active-user readiness are proven.
```

A machine-wide success with no active logged-on user can finish as `RESULT: READY NEXT LOGON (...)`. Resolution failures are labeled `NOT FOUND`; other unproven failures are labeled `FAILED`.

If the mapper fails, **do not remap blindly**. Preserve the displayed error and evidence locations for diagnosis.

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

The technician CMD does not implement printer mapping itself. It delegates only to an installer-owned sibling `sas.cmd printer` or a sibling trusted printer bootstrap, which reaches the current runtime and canonical Northwell mapping chain.

That means a non-technical technician does not need to know:

- where SysAdminSuite is checked out;
- which Git commit is current;
- a PowerShell command;
- the bootstrap cache/runtime path; or
- the underlying fallback transport.

When installed by the universal SysAdminSuite launcher installer, `Map-NorthwellPrinter.cmd` is placed beside `sas.cmd`. A copy from a current repository/runtime can use the sibling `Bootstrap-SysAdminSuitePrinter.cmd`/`.ps1` path. The launcher intentionally does **not** execute an arbitrary `sas.cmd` discovered through the current directory or PATH.

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
mapping\Invoke-NorthwellPrinterOperatorRun.ps1
mapping\Start-NorthwellPrinterMapping.ps1
mapping\Invoke-NorthwellPrinterMapping.ps1
```

`Map-NorthwellPrinter-SystemWide.cmd` remains the trusted current-runtime quick launcher registered by the Northwell use-case harness. It now routes through `mapping\Invoke-NorthwellPrinterOperatorRun.ps1`, which preserves the resilient mapper/finalizer chain while adding clear operator outcomes and a bounded local run trail. `Map-NorthwellPrinter.cmd` is the human-facing distribution wrapper that gets the technician safely to that runtime.

## Current-origin bootstrap behavior

The standard bootstrap treats the caller's current directory as irrelevant. It uses a dedicated machine-local printer state/cache, fetches current `origin/main` without force, proves the configured required printer baseline is contained in that mainline, and launches a clean detached runtime for the exact current branch head.

It does not reset, clean, stash, or check out an arbitrary technician repository. Superseded bootstrap-owned runtimes may be retired only under the bootstrap's preservation rules, with printer evidence preserved first.

Explicit offline/local-only mode remains separate and does not claim current-origin freshness.

## Evidence

Authoritative quick-run evidence is written beneath the selected printer runtime's:

```text
mapping\Logs\NorthwellPrinterMap-...
```

and includes artifacts such as:

```text
ResolvedPlan.json
Controller.log
Summary.json
UndoPlan.json
<target>\Status.json
<target>\Agent.log
ActiveUserMaterialization.json
```

The active runtime maintains `mapping\Logs\LATEST-PATH.txt`. Bootstrap state maintains the current runtime identity separately so evidence can survive runtime retirement.

The operator layer also writes a bounded **local-user trail on the admin box** under:

```text
%LOCALAPPDATA%\SysAdminSuite\Cache\Printer\runs.v1.jsonl
%LOCALAPPDATA%\SysAdminSuite\Cache\Printer\latest.v1.json
```

That local trail records compact outcomes such as `MAPPED_NOW`, `ALREADY_MAPPED`, `NOT_FOUND`, `FAILED`, `READY`, and `READY_NEXT_LOGON`. It is best-effort convenience/history, is never copied to target PCs, and does not replace authoritative mapping proof. Sharing it remains the operator's decision.

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

On **August 20, 2026**, SysAdminSuite commit `4c5f1252aae24269ac1e0ab28ef9366ea08fd33f` was observed through `sas printer` on an approved `DomainAuthenticated` wired Northwell path successfully producing:

- requested printer SYSTEM-wide HKLM registration proof; and
- immediate active-user materialization proof.

That closes the underlying mapping/materialization proof gap for this Northwell use case on that observed path. Subsequent mainline work added the operator outcome/journal layer while preserving the same resilient mapping and active-user finalization authority. Repository validation proves that composition; the newer one-click technician wrapper still requires its own post-refresh field acceptance before claiming that exact wrapper was observed live.

The August 20 field proof does **not** claim physical document output unless a real document is separately observed printing.

## Do not substitute these paths

`Utilities\Map-Printer.ps1` is a per-user connection helper and does not satisfy the Northwell multi-user contract.

Archived printer scripts under `mapping\Archive\` are historical/reference surfaces, not technician entrypoints.

Never invent a direct-IP fallback, a per-user fallback, or an organization crossover when the registered use case does not authorize it.
