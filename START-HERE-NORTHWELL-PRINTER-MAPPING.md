# Northwell Printer Mapping — Start Here

This is the **canonical field path** for mapping shared printers to Northwell Windows PCs.

## Non-negotiable client contract

- **System-wide / per-computer only.** These PCs have multiple users. A printer mapped only for the technician's current profile is not acceptable.
- **Shared queue names only.** Use `\\server\queue`, `//server/queue`, or a queue name such as `QUEUE01`.
- **Never map a Northwell printer by printer IP address.** The field entrypoint rejects IP-based printer inputs.
- **Target PCs are hostnames/FQDNs, not IP addresses.** Short Northwell hostnames are normalized to the `nslijhs.net` DNS suffix.
- The remote mapping action runs as **SYSTEM** and uses `rundll32 printui.dll,PrintUIEntry /ga`, the Windows per-computer printer-connection path.
- A run is not reported successful merely because a command launched. Each target must return evidence that every requested queue exists under the machine-wide HKLM printer-connection registry location.
- Mapping never prints a test page. Print output is not used as a substitute for correcting an incorrect queue registration.

## Technician path: double-click one file

On an authorized Northwell Windows admin box, open the current SysAdminSuite folder and double-click:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

The launcher requests Administrator rights if needed, then asks for only:

1. **Target PC hostname(s)** — one or more hostnames, comma-separated.
2. **Printer queue(s)** — `\\server\queue`, `//server/queue`, or queue name only; comma-separated when mapping more than one.

The launcher stays open after success or failure. It also prints the exact run evidence directory and opens the run `Summary.json`, so a closed terminal is not required to recover the mapping record.

Example answers:

```text
Target PC hostname(s), comma-separated: PC001,PC002,PC003
Printer queue(s), comma-separated: \\PRINTSERVER\QUEUE01
```

or, when only the queue name is known:

```text
Target PC hostname(s), comma-separated: PC001
Printer queue(s), comma-separated: QUEUE01
```

For queue-only input, the suite resolves the published queue through Active Directory. It **does not guess a print server**. If the queue is unpublished or ambiguous, the run stops before changing a target and asks for the full `\\server\queue` path.

## Same-queue direct-IP collision repair

The canonical SYSTEM worker checks for one narrow stale-registration pattern before it runs `/ga`:

- the local printer object's **Name** exactly matches either the requested `\\server\queue` or queue leaf, or its **ShareName** exactly matches the queue leaf;
- the object is local rather than a remote printer connection; and
- its `PortName` is a direct-IP style port such as `IP_10.20.30.40`, `TCP_10.20.30.40`, or a raw IPv4 address.

When **exactly one** object matches, the worker removes that stale **printer object only**, records `REPAIRED_STALE_DIRECT_IP_QUEUE_COLLISION`, preserves the TCP/IP port, and then performs the normal SYSTEM `/ga` shared-queue registration.

If more than one object matches, the run fails closed with `AMBIGUOUS_LOCAL_IP_QUEUE_COLLISION`; it does not guess which object to remove.

This repair does **not**:

- map a printer by IP;
- delete or modify the TCP/IP port;
- use `Add-Printer -ConnectionName`;
- print a test page.

## PowerShell path for agents and advanced operators

The CMD launcher delegates to `mapping\Start-NorthwellPrinterMapping.ps1`, which delegates to the canonical engine:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER\QUEUE01'
```

Multiple PCs:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001,PC002,PC003 -Printer '\\PRINTSERVER\QUEUE01'
```

Multiple queues:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '\\PRINTSERVER\QUEUE01','\\PRINTSERVER\QUEUE02'
```

Forward-slash UNC notation is accepted and normalized:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer '//PRINTSERVER/QUEUE01'
```

Queue name only:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer 'QUEUE01'
```

If the operator knows the print server but was given only the queue name:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer 'QUEUE01' -PrintServer 'PRINTSERVER'
```

## Safe preview

Agents and advanced operators can use `-WhatIf` to resolve hostnames and queues, validate print-server DNS, and write the local resolved plan without staging anything remotely:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer 'QUEUE01' -WhatIf
```

## What the tool proves

For each target the runner:

1. Validates the target is a hostname/FQDN and the printer is a shared queue, not an IP/IPP/HTTP target.
2. Resolves queue-only input through AD, or uses the explicit `-PrintServer`.
3. Resolves each print-server hostname in DNS before any endpoint mutation.
4. Verifies the target administrative share (`C$`) and remote Task Scheduler are reachable.
5. Stages a run-scoped agent under `C:\ProgramData\SysAdminSuite\Mapping\NorthwellPrinterMap\...`.
6. Runs that agent as **SYSTEM** through Task Scheduler.
7. Repairs one exact same-queue local direct-IP printer-object collision when present, while preserving its TCP/IP port; ambiguity fails closed.
8. Adds each queue using **PrintUIEntry `/ga`** (per-computer / all-users registration).
9. Polls and verifies each requested `\\server\queue` from `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections`.
10. Copies `Status.json` and `Agent.log` back to the controller before cleanup.
11. Fails the overall run if even one target lacks SYSTEM identity or machine-wide registry proof.

Windows applies a `/ga` per-computer connection for users when they log on. If a user was already signed in during the mapping, have that user **sign out and back in** before treating the UI-visible printer list as final.

## Evidence and troubleshooting

Every run writes a local evidence directory under:

```text
mapping\Logs\NorthwellPrinterMap-YYYYMMDD-HHMMSS-...
```

The engine also refreshes:

```text
mapping\Logs\LATEST-PATH.txt
```

That pointer contains the exact latest mapping evidence directory used by the launcher.

Key artifacts:

- `ResolvedPlan.json` — exact normalized PCs and shared queues before remote work, including the bounded collision-repair policy.
- `Controller.log` — timestamped controller trace.
- `<target>\Status.json` — SYSTEM identity, requested queues, collision repairs, HKLM machine-wide queues, missing queues, success/failure, and negative proof that no port/test page was used.
- `<target>\Agent.log` — endpoint-side collision-repair, PrintUI, and verification trace.
- `Summary.json` — authoritative all-target result and exact `SessionRoot`.

Do **not** diagnose a failed run from a vanished terminal alone. Use these artifacts. The runner throws only after preserving the collected evidence, and the CMD launcher prints the exact directory, opens `Summary.json`, and pauses before closing.

Common failures are intentionally explicit:

- `Admin share unavailable` → verify Northwell network posture, DNS, credentials/admin rights, and endpoint firewall.
- `Remote Task Scheduler query failed` → RPC/Task Scheduler access is blocked or the operator lacks authority.
- `Queue ... was not uniquely published in Active Directory` → use the exact `\\server\queue`, or provide `-PrintServer` with the queue name.
- `Print server ... did not resolve in DNS` → correct the print-server hostname before mapping.
- `AMBIGUOUS_LOCAL_IP_QUEUE_COLLISION` → multiple local direct-IP objects match the requested queue leaf; inspect `<target>\Agent.log` and remove ambiguity deliberately rather than guessing.
- `Missing machine-wide queue(s)` → the `/ga` registration did not produce HKLM machine-wide proof; treat that target as failed.

## What NOT to use for this client requirement

`Utilities\Map-Printer.ps1` wraps `Add-Printer -ConnectionName` and is **per-user**. It is not the Northwell multi-user deployment path.

Archived scripts under `mapping\Archive\` are historical evidence, not the technician entrypoint.

Workers under `mapping\Workers\` remain implementation/reference surfaces. Techs should start with `Map-NorthwellPrinter-SystemWide.cmd` so elevation, prompts, input validation, queue resolution, SYSTEM execution, bounded collision repair, cleanup, evidence checks, and terminal persistence stay consistent.

## Agent / ChatGPT routing rule

When a technician asks how to map a printer on a Northwell PC, answer with the **CMD launcher first**. Ask only for the missing concrete inputs:

- target PC hostname(s), and
- printer queue(s): either `\\server\queue` or queue name.

Do not recommend direct-IP printer installation, a per-user `Add-Printer -ConnectionName` command, or repeated test pages for this use case.
