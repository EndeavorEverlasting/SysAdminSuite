# Northwell Printer Mapping — Start Here

This is the **canonical field path** for mapping shared printers to Northwell Windows PCs.

## Non-negotiable client contract

- **System-wide / per-computer only.** These PCs have multiple users. A printer mapped only for the technician's current profile is not acceptable.
- **Shared queue names only.** Use `\\server\queue`, `//server/queue`, or a queue name such as `QUEUE01`.
- **Never map a Northwell printer by printer IP address.** The field entrypoint rejects IP-based printer inputs.
- **Target PCs are hostnames/FQDNs, not IP addresses.** Short Northwell hostnames are normalized to the `nslijhs.net` DNS suffix.
- The remote mapping action runs as **SYSTEM** and uses `rundll32 printui.dll,PrintUIEntry /ga`, the Windows per-computer printer-connection path.
- A mapping run is not reported successful merely because a command launched. Each target must return SYSTEM identity plus the requested queue under the machine-wide HKLM printer-connection registry location.
- The canonical mapper does **not** print test pages. A real requested document printed after mapping is separate runtime acceptance evidence.

## Technician path: double-click one file

On an authorized Northwell Windows admin box, open the current SysAdminSuite folder and double-click:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

The launcher requests Administrator rights if needed, then asks for only:

1. **Target PC hostname(s)** — one or more hostnames, comma-separated.
2. **Printer queue(s)** — `\\server\queue`, `//server/queue`, or queue name only; comma-separated when mapping more than one.

The launcher stays open after success or failure. It prints the exact run evidence directory and opens the run `Summary.json`, so the mapping record remains recoverable after a terminal closes.

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

## Evidence precedence: do not repair a working mapping

The mapping engine and the diagnostic tools observe different proof layers. Keep them separate.

1. **Post-mapping real document print observed** — runtime acceptance. If a requested document actually prints after the canonical mapping workflow, the mapped print path is working for that observed case.
2. **SYSTEM + HKLM per-computer queue proof** — machine-wide registration proof. This is what the canonical mapper itself proves.
3. **Local queue/CIM/PortName/WorkOffline/SMB/RPC/remote `Get-Printer` telemetry** — diagnostic context. These observations may explain a problem, but they do not outrank observed successful output.

Therefore, once real requested output has been observed after mapping:

- do **not** print another test page merely to prove printing again;
- do **not** remove or rebuild the printer solely because a local `PortName` looks like `IP_*`, `TCP_*`, or a raw address;
- do **not** declare the mapping failed solely because remote `Get-Printer`, RPC, CIM, or status telemetry times out or disagrees;
- preserve contradictory telemetry as a warning unless a later observed print failure reopens diagnosis.

The machine-readable authority for this ordering is:

```text
harness\api\northwell-printer-mapping-evidence-policy.json
```

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
7. Adds each queue using **PrintUIEntry `/ga`** (per-computer / all-users registration).
8. Polls and verifies each requested `\\server\queue` from `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections`.
9. Copies `Status.json` and `Agent.log` back to the controller before cleanup.
10. Fails the overall run if even one target lacks SYSTEM identity or machine-wide registry proof.

The mapper deliberately does not infer runtime print success from registration alone. Conversely, when a later real document is actually observed printing, agents must not downgrade that runtime acceptance because a lower-level diagnostic looks odd.

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

- `ResolvedPlan.json` — exact normalized PCs and shared queues before remote work.
- `Controller.log` — timestamped controller trace.
- `<target>\Status.json` — SYSTEM identity, requested queues, HKLM machine-wide queues, missing queues, success/failure, and explicit mapping proof level.
- `<target>\Agent.log` — endpoint-side PrintUI and registration-verification trace.
- `Summary.json` — authoritative all-target result and exact `SessionRoot`.

Do **not** diagnose a failed run from a vanished terminal alone. Use these artifacts. The runner throws only after preserving the collected evidence, and the CMD launcher prints the exact directory, opens `Summary.json`, and pauses before closing.

Common failures are intentionally explicit:

- `Admin share unavailable` → verify Northwell network posture, DNS, credentials/admin rights, and endpoint firewall.
- `Remote Task Scheduler query failed` → RPC/Task Scheduler access is blocked or the operator lacks authority.
- `Queue ... was not uniquely published in Active Directory` → use the exact `\\server\queue`, or provide `-PrintServer` with the queue name.
- `Print server ... did not resolve in DNS` → correct the print-server hostname before mapping.
- `Missing machine-wide queue(s)` → the `/ga` registration did not produce HKLM machine-wide proof; treat that target as failed.

A local `IP_*` port name or a remote status/RPC timeout is **not** by itself a mapping failure classification after real successful document output has been observed.

## What NOT to use for this client requirement

`Utilities\Map-Printer.ps1` wraps `Add-Printer -ConnectionName` and is **per-user**. It is not the Northwell multi-user deployment path.

Archived scripts under `mapping\Archive\` are historical evidence, not the technician entrypoint.

Workers under `mapping\Workers\` remain implementation/reference surfaces. Techs should start with `Map-NorthwellPrinter-SystemWide.cmd` so elevation, prompts, input validation, queue resolution, SYSTEM execution, cleanup, evidence checks, and terminal persistence stay consistent.

## Agent / ChatGPT routing rule

When a technician asks how to map a printer on a Northwell PC, answer with the **CMD launcher first**. Ask only for the missing concrete inputs:

- target PC hostname(s), and
- printer queue(s): either `\\server\queue` or queue name.

Do not recommend direct-IP printer installation or a per-user `Add-Printer -ConnectionName` command. If real requested output has already printed successfully after mapping, do not demand another test page or invent a remapping problem solely from diagnostic telemetry.
