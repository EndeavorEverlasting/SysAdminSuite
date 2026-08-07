# Northwell Printer Mapping — Start Here

This is the **canonical field path** for mapping shared printers to Northwell Windows PCs.

## Non-negotiable client contract

- **System-wide / per-computer only.** These PCs have multiple users. A printer mapped only for the technician's current profile is not acceptable.
- **Shared queue names only.** Use `\\server\queue`, `//server/queue`, or a queue name such as `QUEUE01`.
- **Never map a Northwell printer by printer IP address.** The field entrypoint rejects IP-based printer inputs.
- **Target PCs are hostnames/FQDNs, not IP addresses.** Short Northwell hostnames are normalized to the `nslijhs.net` DNS suffix.
- The remote mapping action runs as **SYSTEM** and uses `rundll32 printui.dll,PrintUIEntry /ga`, the Windows per-computer printer-connection path.
- A run is not reported successful merely because a command launched. Each target must return evidence that every requested queue exists under the machine-wide HKLM printer-connection registry location.

## The one script technicians should use

From an **elevated PowerShell window** at the SysAdminSuite repo root, on the authorized Northwell network:

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

For queue-only input, the suite resolves the published queue through Active Directory. It **does not guess a print server**. If the queue is unpublished or ambiguous, the run stops before changing a target and asks for the full `\\server\queue` path.

If the technician knows the print server but was given only the queue name:

```powershell
.\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName PC001 -Printer 'QUEUE01' -PrintServer 'PRINTSERVER'
```

## Safe preview

Use `-WhatIf` to resolve hostnames and queues, validate print-server DNS, and write the local resolved plan without staging anything remotely:

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
7. Adds each queue using **PrintUIEntry `/ga`** (per-computer / all-users registration).
8. Verifies each requested `\\server\queue` from `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections`.
9. Copies `Status.json` and `Agent.log` back to the controller before cleanup.
10. Fails the overall run if even one target lacks SYSTEM identity or machine-wide registry proof.

Windows applies a `/ga` per-computer connection for users when they log on. If a user was already signed in during the mapping, have that user **sign out and back in** before treating the UI-visible printer list as final.

## Evidence and troubleshooting

Every run writes a local evidence directory under:

```text
mapping\Logs\NorthwellPrinterMap-YYYYMMDD-HHMMSS\
```

Key artifacts:

- `ResolvedPlan.json` — exact normalized PCs and shared queues before remote work.
- `Controller.log` — timestamped controller trace.
- `<target>\Status.json` — SYSTEM identity, requested queues, HKLM machine-wide queues, missing queues, success/failure.
- `<target>\Agent.log` — endpoint-side PrintUI and verification trace.
- `Summary.json` — authoritative all-target result.

Do **not** diagnose a failed run from a vanished terminal alone. Use these artifacts. The runner throws only after preserving the collected evidence.

Common failures are intentionally explicit:

- `Admin share unavailable` → verify Northwell network posture, DNS, credentials/admin rights, and endpoint firewall.
- `Remote Task Scheduler query failed` → RPC/Task Scheduler access is blocked or the operator lacks authority.
- `Queue ... was not uniquely published in Active Directory` → use the exact `\\server\queue`, or provide `-PrintServer` with the queue name.
- `Print server ... did not resolve in DNS` → correct the print-server hostname before mapping.
- `Missing machine-wide queue(s)` → the `/ga` registration did not produce HKLM machine-wide proof; treat that target as failed.

## What NOT to use for this client requirement

`Utilities\Map-Printer.ps1` wraps `Add-Printer -ConnectionName` and is **per-user**. It is not the Northwell multi-user deployment path.

Archived scripts under `mapping\Archive\` are historical evidence, not the technician entrypoint.

Workers under `mapping\Workers\` remain implementation/reference surfaces. Techs should start with `mapping\Invoke-NorthwellPrinterMapping.ps1` so input validation, queue resolution, SYSTEM execution, cleanup, and evidence checks stay consistent.

## Agent / ChatGPT routing rule

When a technician asks how to map a printer on a Northwell PC, answer with this workflow first. Ask only for the missing concrete inputs:

- target PC hostname(s), and
- printer queue(s): either `\\server\queue` or queue name.

Do not recommend direct-IP printer installation or a per-user `Add-Printer -ConnectionName` command for this use case.
