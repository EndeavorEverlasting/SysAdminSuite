# Northwell Printer Mapping for Technicians

Use this tutorial when a **Northwell** Windows PC needs one or more approved shared printers.

For normal printer mapping, you do not need Git, PowerShell, a repository path, a printer IP address, or a test page.

## The one thing to open

Double-click:

```text
Map-NorthwellPrinter.cmd
```

Terminal users can run the exact same workflow with:

```text
sas printer
```

Both routes enter the current trusted SysAdminSuite printer bootstrap and the same proven Northwell mapping workflow.

## Before you start

1. Be on an approved Northwell protected connection: hardwire/LAN, NSLIJHS-WAB, or authenticated Northwell VPN.
2. Know the target **PC hostname** or select it from the recent proven list if it appears.
3. Know the shared printer `\\server\queue` or select it from the recent proven list if it appears.
4. Approve the Windows Administrator prompt if one appears.

Do **not** use a target PC IP address. Do **not** map a printer by printer IP.

## Map a printer

After the CMD starts:

1. At **Recent proven target PCs**, type the displayed number for a known PC, or enter the hostname requested by the prompt.
2. At **Recent proven printer inputs**, type the displayed number for a known printer, or choose the manual server/queue path.
3. Review the short mapping summary.
4. Let SysAdminSuite finish. Do not close the window while it is working.

The recent lists are there to reduce typing and recollection. A remembered item is a convenience only; SysAdminSuite still performs the normal authoritative mapping and proof steps.

## What success looks like

A successful run ends with messages equivalent to:

```text
PASS: requested printer map is proven SYSTEM-wide in HKLM.
READY: <computer> - active user <user> has the requested printer connection now.
Done. Machine-wide registration is proven; any active user session was finalized and verified.
```

`PASS` means the requested shared queue is registered machine-wide for the PC under the proven Northwell SYSTEM/HKLM contract.

`READY` means the user already signed in to that PC has the requested printer connection materialized now. If nobody is signed in, machine-wide registration can still be valid and the connection can appear at the next user logon.

The mapper does **not** print a test page. If the user later prints the real requested document successfully, that is higher-level runtime acceptance for that observed case.

## If it fails

Do not repeatedly run the mapper against the same failure.

Keep the error text and the evidence path shown in the window. Printer evidence includes a run summary and per-target proof, and the latest run can be traced through the printer evidence pointers maintained by SysAdminSuite.

Useful failure behavior is intentional: the mapper fails closed instead of guessing a printer IP, silently changing to per-user mapping, or claiming success without authoritative proof.

## Many PCs or many printers

The quick mapper supports one or many target PCs and one or many shared queues through its prompts.

For a prepared assignment file or a larger repeated rollout, use the file/batch workflow documented in `START-HERE-NORTHWELL-PRINTER-MAPPING.md`. Do not build a separate mapping script.

## Advanced printer management

For unmapping, undo, defaults, mixed map/unmap batches, and evidence management, use:

```text
Manage-NorthwellPrinters.cmd
```

See `START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md`.

## Proven field boundary

On **August 20, 2026**, the current-main Northwell quick path was observed on a protected `DomainAuthenticated` wired connection completing both:

- SYSTEM-wide requested queue proof in HKLM; and
- immediate active-user printer materialization.

That field observation validates the mapping/materialization use case on that protected path. It does not by itself claim that a physical document was printed.

## Organization boundary

This workflow is registered for **Northwell Health**. It must not be copied to Health & Hospitals or another organization merely because Windows printer technology looks similar. Other organizations require their own discovered and proven mapping contract.
