# Northwell Printer Mapping — Start Here

This is the **canonical Northwell field path** for shared-printer mapping. Northwell printer behavior is organization-specific; do not reuse these commands for Health & Hospitals or another organization unless that use case is separately registered and proven.

## Non-negotiable Northwell contract

- **System-wide / per-computer only.** These PCs have multiple users.
- **Shared queue names only.** Use `\\server\queue`, `//server/queue`, or a queue name.
- **Never map by printer IP address.**
- **Target PCs are hostnames/FQDNs, not IP addresses.**
- Endpoint mapping runs as **SYSTEM** with `rundll32 printui.dll,PrintUIEntry /ga`.
- Success requires SYSTEM identity plus the requested queue under the machine-wide HKLM printer-connection registry location.
- The canonical mapper **does not print test pages**.
- A real requested document printed after mapping is separate, higher-value runtime acceptance evidence.

## Technician CMDs

Choose the CMD that matches the job. All are at the repository root.

### 1. Quick mapping

Double-click:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

Use this for one-off work. The launcher:

1. asks for one or more target PC hostnames;
2. asks for a print server and one or more queue names;
3. lets you add another server/queue set;
4. maps every requested queue to every requested computer;
5. preserves evidence and leaves the window open.

Known field-proven Northwell example:

```text
\\SYKPNHPHPS01V\LS001-EMS01
```

The quick launcher shows that server and queue as defaults. **Press Enter at both printer prompts only when you intentionally want that example.** There is no default target computer; the technician must always enter the intended PC hostname(s).

Examples of what the quick launcher supports:

```text
1 PC  -> 1 printer
5 PCs -> 1 printer
1 PC  -> 4 printers
5 PCs -> 4 printers
```

If the queues live on two print servers, enter the first server/queue set and answer `y` when asked to add another set.

### 2. Edit a batch

Double-click:

```text
Edit-NorthwellPrinter-Batch.cmd
```

It creates or opens this **local, gitignored** file:

```text
mapping\NorthwellPrinterBatch.csv
```

The tracked starter template is:

```text
mapping\Examples\NorthwellPrinterBatch.example.csv
```

CSV columns:

```text
ComputerName,PrintServer,QueueName
```

Use semicolons inside a cell for multiple values. One row means:

> map every queue in this row to every computer in this row.

Examples:

```text
ComputerName,PrintServer,QueueName
PC001;PC002,SYKPNHPHPS01V,LS001-EMS01
PC003;PC004,PRINTSERVER02,QUEUE01;QUEUE02
PC005,,\\PRINTSERVER03\QUEUE03;\\PRINTSERVER04\QUEUE04
```

Rules:

- `ComputerName`: one or more Northwell hostnames, separated by `;`.
- `PrintServer`: one server hostname for queue-name entries; blank is allowed when the queue cell contains full UNC paths or when queue-only AD resolution is intended.
- `QueueName`: one or more queue names or full UNC paths, separated by `;`.
- The shipped `REPLACE-WITH-PC-HOSTNAME` placeholder is blocked from execution.

### 3. Run the batch

After saving the CSV, double-click:

```text
Map-NorthwellPrinters-Batch.cmd
```

The batch launcher self-elevates, validates the CSV, checks Northwell network authority, and delegates each CSV row to the **same canonical engine** used by quick mapping. Batch mode is orchestration only; it does not implement a second printer-mapping mechanism.

Each row gets its own child evidence directory. The parent batch run writes:

```text
BatchPlan.json
Summary.json
Group-001\Summary.json
Group-002\Summary.json
...
```

`mapping\Logs\LATEST-PATH.txt` points back to the parent batch evidence directory when the batch finishes.

## Why the batch model is row-based

A row is a simple mapping group. That keeps technician intent visible:

```text
these computers -> these printers
```

It also allows different hospitals, departments, or printer servers to be expressed as separate rows without hiding the assignment inside code.

## PowerShell path for agents and advanced operators

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
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER\QUEUE01'
```

The engine natively accepts multiple PCs and multiple queues:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 `
  -ComputerName PC001,PC002,PC003 `
  -Printer '\\PRINTSERVER\QUEUE01','\\PRINTSERVER\QUEUE02'
```

Queue-only input is allowed:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer 'QUEUE01'
```

Explicit server + queue name:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer 'QUEUE01' -PrintServer 'PRINTSERVER'
```

## Safe preview

Advanced operators can use `-WhatIf`:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER\QUEUE01' -WhatIf
.\mapping\Start-NorthwellPrinterBatch.ps1 -WhatIf
```

`-WhatIf` is planning only and does not claim machine-wide registration or live printing.

## What the canonical engine proves

For each target the engine:

1. validates hostname and shared-queue input;
2. rejects direct-IP/URL printer targets;
3. resolves queue-only input through AD or an explicit print server;
4. resolves print-server DNS before endpoint mutation;
5. verifies `C$` and remote Task Scheduler access;
6. stages a run-scoped worker under `C:\ProgramData\SysAdminSuite\Mapping\NorthwellPrinterMap\...`;
7. runs the worker as **SYSTEM**;
8. adds each queue with **PrintUIEntry `/ga`**;
9. verifies the requested `\\server\queue` values under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections`;
10. copies `Status.json` and `Agent.log` back before cleanup;
11. fails the overall engine run if any target lacks SYSTEM identity or machine-wide registration proof.

The batch wrapper never bypasses these checks. It only calls the engine repeatedly with explicit row-level groups.

## Evidence precedence: do not repair a working mapping

Keep these proof layers separate:

1. **Real requested document printed after mapping** → runtime acceptance.
2. **SYSTEM + HKLM queue proof** → machine-wide registration proof.
3. **PortName / WorkOffline / CIM / RPC / SMB / remote `Get-Printer` telemetry** → diagnostic context.

If a real requested document actually printed after the canonical mapping workflow:

- do **not** demand another test page;
- do **not** remove/rebuild the printer only because a port looks like `IP_*`, `TCP_*`, or a raw address;
- do **not** downgrade the successful mapping solely because RPC/CIM/remote status telemetry disagrees;
- reopen diagnosis only when later observed printing actually fails or higher-ranked evidence changes.

Machine-readable authority:

```text
harness\api\northwell-printer-mapping-evidence-policy.json
```

## Evidence locations

Quick engine runs:

```text
mapping\Logs\NorthwellPrinterMap-YYYYMMDD-HHMMSS-...
```

Batch runs:

```text
mapping\Logs\NorthwellPrinterBatch-YYYYMMDD-HHMMSS-...
```

Latest pointer:

```text
mapping\Logs\LATEST-PATH.txt
```

Quick-run artifacts include:

- `ResolvedPlan.json`
- `Controller.log`
- `<target>\Status.json`
- `<target>\Agent.log`
- `Summary.json`

Batch-run artifacts include:

- `BatchPlan.json`
- `Summary.json`
- `Group-NNN\...` canonical engine evidence

Both technician mapping CMDs leave their windows open and open the relevant `Summary.json` when available.

## Common failures

- `Admin share unavailable` → verify Northwell network posture, DNS, admin rights, and endpoint firewall.
- `Remote Task Scheduler ... failed` → RPC/Task Scheduler authority is missing.
- `Queue ... was not uniquely published in Active Directory` → use exact `\\server\queue` or an explicit print server.
- `Print server ... did not resolve in DNS` → correct the server hostname.
- `Missing machine-wide queue(s)` → `/ga` did not produce required HKLM proof.
- `REPLACE-WITH-PC-HOSTNAME` → edit the local batch CSV before running it.

A local `IP_*` port or remote RPC timeout is **not** by itself a mapping failure after successful real document output has been observed.

## Do not use these as substitutes

`Utilities\Map-Printer.ps1` uses the per-user `Add-Printer -ConnectionName` path and does not satisfy the Northwell multi-user requirement.

Archived scripts under `mapping\Archive\` are historical/reference surfaces, not technician entrypoints.

## Agent routing rule

When the organization is Northwell and a technician asks to map printers:

- use `Map-NorthwellPrinter-SystemWide.cmd` for ad-hoc one/many mapping;
- use `Edit-NorthwellPrinter-Batch.cmd` + `Map-NorthwellPrinters-Batch.cmd` when assignments are naturally tabular or repeated;
- ask only for missing hostnames, print-server names, and queue names;
- never invent a direct-IP or per-user fallback;
- never transfer these Northwell commands to Health & Hospitals without a separately proven H&H use case.
