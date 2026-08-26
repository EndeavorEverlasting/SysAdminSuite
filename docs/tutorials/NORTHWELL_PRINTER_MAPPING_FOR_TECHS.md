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

Both routes enter the trusted SysAdminSuite printer bootstrap and the same Northwell machine-wide mapping workflow.

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

## Read the result

The operator layer now uses explicit outcomes instead of making a technician infer what happened.

A newly added machine-wide mapping can report:

```text
MAPPED NOW: <computer> -> <printer>. Machine-wide HKLM registration changed and is proven.
RESULT: READY (MAPPED_NOW). Machine-wide registration and active-user readiness are proven.
```

If the requested mapping was already present, a successful no-op can report:

```text
ALREADY MAPPED: <computer> -> <printer>. No machine-wide change was needed; HKLM registration is proven.
RESULT: READY (ALREADY_MAPPED). Machine-wide registration and active-user readiness are proven.
```

If nobody is logged on and no immediate user-session materialization is required, success can end with:

```text
RESULT: READY NEXT LOGON (...). Machine-wide registration is proven; no active user session required immediate materialization.
```

What the words mean:

- **MAPPED NOW** — this run changed the machine-wide printer registration and proved the new HKLM state.
- **ALREADY MAPPED** — the correct machine-wide registration was already present, so no duplicate change was needed.
- **READY** — machine-wide registration is proven and the active-user readiness step succeeded when applicable.
- **READY NEXT LOGON** — machine-wide registration is proven; there was no active session that needed immediate materialization.
- **NOT FOUND** — the requested print server/queue could not be authoritatively resolved or was invalid; the workflow does not guess.
- **FAILED** — readiness was not proven. Treat the error and evidence as the next diagnostic input instead of repeatedly remapping.

The mapper does **not** print a test page. If the user later prints the real requested document successfully, that is higher-level runtime acceptance for that observed case.

## If it fails

Do not repeatedly run the mapper against the same failure.

Keep the error text and the evidence locations shown in the window. The operator wrapper preserves two different kinds of evidence:

1. **Authoritative run evidence** under the selected printer runtime's `mapping\Logs\NorthwellPrinterMap-...` directory, including the summary and per-target proof.
2. **A bounded local admin-box trail** under `%LOCALAPPDATA%\SysAdminSuite\Cache\Printer`, including `runs.v1.jsonl` and `latest.v1.json`.

The local trail is per-user, local to the admin box, and optional to share. It does not get copied to target PCs and it does not replace authoritative mapping proof.

When the one-click `Map-NorthwellPrinter.cmd` is the actual front door, `latest.v1.json` records `EntryPoint=TECHNICIAN_CMD`. A direct or otherwise unmarked `sas printer` run records `EntryPoint=SAS_PRINTER`. This field is local entrypoint provenance only; it does not replace the authoritative HKLM/HKCU/HKU printer proof.

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

On **August 20, 2026**, SysAdminSuite commit `4c5f1252aae24269ac1e0ab28ef9366ea08fd33f` was observed through `sas printer` on a protected `DomainAuthenticated` wired connection completing both:

- SYSTEM-wide requested queue proof in HKLM; and
- immediate active-user printer materialization.

That field observation validates the underlying Northwell mapping/materialization use case on that protected path. Later mainline work added the explicit operator outcomes and bounded local trail while preserving the same resilient mapper/finalizer chain. The one-click wrapper now stamps `EntryPoint=TECHNICIAN_CMD` into that local trail, making the next protected field run attributable to the exact wrapper; repository validation proves the composition, but the newer one-click technician wrapper still needs its own post-refresh field acceptance before claiming that exact wrapper was live-tested.

The August 20 observation does not by itself claim that a physical document was printed.

## Organization boundary

This workflow is registered for **Northwell Health**. It must not be copied to Health & Hospitals or another organization merely because Windows printer technology looks similar. Other organizations require their own discovered and proven mapping contract.
