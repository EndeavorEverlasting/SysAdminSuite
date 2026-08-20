# Northwell Printer Mapping — Start Here

This is the **canonical Northwell field path** for shared-printer mapping. Northwell printer behavior is organization-specific; do not reuse these commands for Health & Hospitals or another organization unless that use case is separately registered and proven.

## Non-negotiable Northwell contract

- **System-wide / per-computer only.** These PCs may have multiple users.
- **Shared queue names only.** Use `\\server\queue`, `//server/queue`, or a queue name.
- **Never map by printer IP address.**
- **Target PCs are hostnames/FQDNs, not IP addresses.**
- Endpoint mapping runs as **SYSTEM** with `rundll32 printui.dll,PrintUIEntry /ga`.
- Success requires SYSTEM identity plus the requested queue under the machine-wide HKLM printer-connection registry location.
- The canonical mapper **does not print test pages**.
- A real requested document printed after mapping is separate runtime acceptance evidence.

## Start from any PowerShell directory

Do **not** assume the current shell is already inside a SysAdminSuite checkout. `git rev-parse --show-toplevel` is not a field bootstrap.

The standalone bootstrap is:

```text
Bootstrap-SysAdminSuitePrinter.ps1
```

Its clickable in-repository wrapper is:

```text
Bootstrap-SysAdminSuitePrinter.cmd
```

The bootstrap treats the caller's current directory as irrelevant. It first reuses an eligible local runtime from the explicit/canonical SysAdminSuite authorities (`SAS_RUNTIME_ROOT`, `C:\SASAL`, or `SAS_REPO_ROOT`). When a required fix commit is supplied, the local runtime must contain that commit by Git ancestry.

If no eligible local runtime exists, the bootstrap uses a dedicated `%LOCALAPPDATA%\SysAdminSuite\printer-bootstrap` Git cache, fetches `origin/main` without force, verifies that the required fix is an ancestor of the fetched mainline, and creates a persistent detached runtime keyed by the fetched commit. It does **not** reset, clean, or check out an arbitrary technician repository. The dedicated runtime remains after execution so normal `mapping\Logs` evidence is not destroyed.

This ancestry rule deliberately allows `main` to advance after a validated printer fix. Do not require `origin/main` to equal an old exact SHA when the required fix is still contained in the newer mainline.

## Technician CMDs

### Quick mapping

Double-click:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

The launcher asks for target PC hostname(s), then one or more print-server/queue sets. It supports one computer or many computers and one printer or many printers. Add another server/queue set when prompted.

Accepted forms:

```text
\\PRINTSERVER01\QUEUE01
//PRINTSERVER01/QUEUE01
PRINTSERVER01 + QUEUE01 via the prompts
```

No live endpoint is committed as a repository default.

### Optional local default

Double-click:

```text
Edit-NorthwellPrinter-Defaults.cmd
```

It creates/opens the gitignored file:

```text
Config\northwell-printer-defaults.local.json
```

The repository ships only a synthetic template at `mapping\Examples\NorthwellPrinterDefaults.example.json`. Put one approved Northwell `PrintServer` and `QueueName` in the local file. Quick mapping then shows those values in brackets; pressing Enter explicitly accepts them. **The target computer is never defaulted.**

This gives technicians a convenient site/team default without putting live infrastructure into Git.

### Edit a batch

Double-click:

```text
Edit-NorthwellPrinter-Batch.cmd
```

It creates/opens the local gitignored:

```text
mapping\NorthwellPrinterBatch.csv
```

Tracked synthetic template:

```text
mapping\Examples\NorthwellPrinterBatch.example.csv
```

CSV columns:

```text
ComputerName,PrintServer,QueueName
```

Use semicolons inside a cell for multiple values. One row means:

> map every queue in this row to every computer in this row.

Synthetic example:

```text
PC001;PC002,PRINTSERVER01,QUEUE01;QUEUE02
```

Every `REPLACE-WITH-*` placeholder is blocked from execution.

### Run the batch

After saving the CSV, double-click:

```text
Map-NorthwellPrinters-Batch.cmd
```

The batch path deliberately has two gates before mutation:

1. **local-only shape validation** of columns, semicolon lists, and placeholders;
2. **Northwell network-authority validation** before any AD/DNS-backed queue resolution.

The wrapper then writes and displays the complete resolved plan. For live execution the technician must type:

```text
MAP
```

Anything else cancels with no printer mapping. Advanced automation may supply `-ConfirmBatch` explicitly.

Batch mode delegates every row to the same `mapping\Invoke-NorthwellPrinterMapping.ps1` engine used by quick mapping. It does not create a second mapping mechanism.

## PowerShell paths

Quick wrapper:

```powershell
.\mapping\Start-NorthwellPrinterMapping.ps1
```

Batch wrapper:

```powershell
.\mapping\Start-NorthwellPrinterBatch.ps1
```

Canonical engine:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER01\QUEUE01'
```

Multiple PCs and queues:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 `
  -ComputerName PC001,PC002,PC003 `
  -Printer '\\PRINTSERVER01\QUEUE01','\\PRINTSERVER01\QUEUE02'
```

Queue-only input can be resolved through AD, or paired with `-PrintServer`.

## What the canonical engine proves

For each target the engine:

1. validates hostname and shared-queue input;
2. rejects direct-IP/URL printer targets;
3. resolves queue-only input through AD or an explicit print server;
4. resolves print-server DNS before endpoint mutation;
5. verifies `C$` and remote Task Scheduler access;
6. stages a run-scoped worker;
7. runs the worker as **SYSTEM**;
8. adds each queue with **PrintUIEntry `/ga`**;
9. verifies requested queues under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections`;
10. copies endpoint evidence back before cleanup;
11. fails the engine run if any target lacks SYSTEM identity or machine-wide registration proof.

## Evidence precedence: do not repair a working mapping

Proof order:

1. **Real requested document printed after mapping** → runtime acceptance.
2. **SYSTEM + HKLM queue proof** → machine-wide registration proof.
3. **PortName / WorkOffline / CIM / RPC / SMB / remote `Get-Printer` telemetry** → diagnostic context.

If a real requested document actually printed after the canonical mapping workflow, do not demand another test page or rebuild a working printer only to make lower-ranked telemetry look cleaner.

Machine-readable authority:

```text
harness\api\northwell-printer-mapping-evidence-policy.json
```

## Evidence locations

Quick runs:

```text
mapping\Logs\NorthwellPrinterMap-...
```

Batch runs:

```text
mapping\Logs\NorthwellPrinterBatch-...
```

Latest pointer:

```text
mapping\Logs\LATEST-PATH.txt
```

Quick artifacts include `ResolvedPlan.json`, `Controller.log`, per-target `Status.json` / `Agent.log`, and `Summary.json`.

Batch artifacts add parent `BatchPlan.json`, parent `Summary.json`, and `Group-NNN` child engine evidence.

## Do not use these as substitutes

`Utilities\Map-Printer.ps1` uses the per-user `Add-Printer -ConnectionName` path and does not satisfy the Northwell multi-user requirement.

Archived scripts under `mapping\Archive\` are historical/reference surfaces, not technician entrypoints.

## Agent routing rule

When Northwell is the selected proven printer use case:

- if the operator may start outside a checkout, use `Bootstrap-SysAdminSuitePrinter.ps1` rather than assuming the current directory is a repository;
- use `Map-NorthwellPrinter-SystemWide.cmd` for ad-hoc mapping;
- use `Edit-NorthwellPrinter-Defaults.cmd` only to maintain a local approved default pair;
- use `Edit-NorthwellPrinter-Batch.cmd` + `Map-NorthwellPrinters-Batch.cmd` for repeated/tabular assignments;
- never invent a direct-IP or per-user fallback;
- never transfer these Northwell commands to Health & Hospitals without a separately proven H&H use case.
