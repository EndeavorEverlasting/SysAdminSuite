# Northwell Printer Management — Start Here

Use this workflow for **Northwell** shared printers on multi-user Windows PCs. It is deliberately reversible and path-portable.

## Technician front door

Double-click from any current SysAdminSuite checkout:

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
7. open the latest printer evidence directory.

No `C:\Users\...` path, named technician workstation, or machine-local checkout location is part of the product contract. Root CMD launchers resolve their own checkout with `%~dp0`.

## Network authority

Live printer-device work is allowed when the shared Northwell guard proves **any approved protected route**, including:

- Northwell WAB Wi-Fi;
- a live Windows `DomainAuthenticated` non-Wi-Fi hardwire/LAN path;
- an authenticated VPN represented by a live `DomainAuthenticated` non-Wi-Fi interface;
- an explicitly configured protected route accepted by the shared network guard.

The workflow does not require one adapter product name, one exact IP address, or one technician's PC. Guest Wi-Fi may remain connected when an authenticated protected non-Wi-Fi route supplies Northwell authority.

`-WhatIf` planning remains available without live target mutation.

## Map

Clickable:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

Advanced:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01'
```

Mapping drives the requested machine-wide queue state to **Present**. The endpoint action runs as SYSTEM and uses `PrintUIEntry /ga`. A queue already present is a safe no-op.

## Unmap

Clickable:

```text
Unmap-NorthwellPrinter-SystemWide.cmd
```

Advanced:

```powershell
.\mapping\Invoke-NorthwellPrinterUnmapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01'
```

Unmapping drives the requested machine-wide queue state to **Absent**. The endpoint action runs as SYSTEM and uses the paired `PrintUIEntry /gd` operation. It removes the requested per-computer shared-queue registration; it does **not** delete printer ports and does not use per-user `Remove-Printer` behavior.

When a full `\\server\queue` is supplied for unmapping, the old print server does not need to resolve in DNS. This allows stale/decommissioned machine-wide connections to be removed instead of becoming permanent because their server is gone.

## Reversibility and evidence

Each live state run records the requested queues before and after the operation. The run writes:

```text
ResolvedPlan.json
Controller.log
Summary.json
UndoPlan.json
<target>\Status.json
<target>\Agent.log
```

`UndoPlan.json` contains **only queues whose requested state actually changed**. Therefore:

- mapping a queue that was already mapped creates no destructive inverse entry for that queue;
- unmapping a queue that was already absent creates no inverse entry;
- a partial failure can still preserve an inverse for an observed transition that happened before the failure;
- no inference from a command launch alone is used to populate undo work.

To reverse the latest observed transitions, double-click:

```text
Undo-LatestNorthwellPrinterChange.cmd
```

The exact inverse plan is displayed before mutation and requires typing `UNDO`. A successful undo creates another `UndoPlan.json`, so the undo itself can be reversed.

## Batch map and unmap

Edit:

```text
Edit-NorthwellPrinter-Batch.cmd
```

Run:

```text
Map-NorthwellPrinters-Batch.cmd
```

Tracked template columns:

```text
Action,ComputerName,PrintServer,QueueName
```

`Action` is `Map` or `Unmap`. Older local CSV files without an `Action` column remain compatible and default to `Map`.

Use semicolons inside a cell for multiple computers or queues. One row applies its action to every listed queue on every listed computer. A batch may mix map and unmap rows.

Before live mutation the complete resolved plan is shown and the technician must type `APPLY`. Child undo plans are aggregated into the batch `UndoPlan.json`.

## Hard client boundaries

- Northwell only. Health & Hospitals remains a separate `discovery_required` use case.
- Shared queue names only: `\\server\queue`, `//server/queue`, or queue name resolved through the approved flow.
- No printer-IP mapping fallback.
- No target-PC IP input.
- System-wide/per-computer only for the Northwell shared-PC requirement.
- SYSTEM endpoint identity.
- No per-user `Add-Printer -ConnectionName` fallback.
- No test page emitted by map, unmap, batch, or undo.
- A real requested document that successfully printed after canonical mapping remains runtime acceptance for that observed case; do not demand another test page merely because lower-level telemetry is odd.

## Proof ceiling

Repository/CI validation can prove parser behavior, desired-state contracts, inverse-plan rules, network-routing policy, and launcher portability. Live proof still requires an authorized Northwell controller route plus reachable approved target(s). A successful map/unmap run proves the requested HKLM machine-wide registration state, not application-specific printing beyond separately observed runtime output.
