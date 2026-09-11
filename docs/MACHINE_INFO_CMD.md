# Machine Info CMD

The technician front door is `Get-MachineInfo.cmd`. The installed equivalent is `sas machineinfo`. PowerShell snippets, the GUI, and dashboard tutorials are downstream conveniences; they do not replace the CMD/runtime contract.

## Technician use

From a current SysAdminSuite folder, double-click `Get-MachineInfo.cmd` and enter one computer name. For multiple explicit hosts, use `Get-MachineInfo.cmd HOST01 HOST02`. For a prepared one-host-per-line list, use `Get-MachineInfo.cmd file C:\Path\hosts.txt` or `sas machineinfo file C:\Path\hosts.txt`.

The command is launch-folder and Windows-username independent. The installer prefers a machine-wide `%ProgramData%\SysAdminSuite\bin\sas.cmd` when that location is writable. If machine-wide installation is unavailable, it may install a current-user `%LOCALAPPDATA%\SysAdminSuite\bin\sas.cmd` shim only when the canonical machine-local `C:\SASAL` runtime is already present. A current repository or sealed runtime resolves the sibling network-aware dispatcher. Do not make a named-user Desktop, OneDrive, or checkout path part of the technician handoff.

Remote inventory requires an approved protected Northwell path: hardwire, `NSLIJHS-WAB`, or authenticated `DomainAuthenticated` VPN. The standard SAS network canary runs before target access and may use only the repository's already-proven saved-WLAN transition/restore behavior. The machine-info lane performs read-only ICMP/WMI inventory and does not mutate the target.

## Network identity semantics

`MachineInfo.csv` keeps `IPAddress` and `MACAddress` as **legacy aggregate columns** for downstream compatibility. They are not primary/secondary fields, they do not identify Ethernet versus Wi-Fi by position, and their semicolon positions are not an interface-pairing contract. `IPAddress` contains the first IPv4 observed on each IP-enabled WMI adapter; `MACAddress` contains the available MAC values from those adapters. Do not infer interface role or mapping identity from aggregate order.

`NetworkAdapters` is the canonical provenance-bearing field. Each ` || `-separated record is one IP-enabled adapter and records:

```text
Index=<WMI adapter index>|Description=<adapter description>|IPv4=<all IPv4 values>|MAC=<adapter MAC>|Gateway=<default gateway values>|DHCP=<true|false>
```

Use `NetworkAdapters` when the question is "which IP belongs to which interface?" The HTML report intentionally shows this provenance-bearing field instead of the ambiguous legacy IP/MAC aggregates.

This distinction also prevents MachineInfo evidence from leaking into the wrong use case. The canonical Northwell printer mapper does **not** use a MachineInfo IP address as mapping identity: target PCs are hostnames/FQDNs and printers are shared queue identities. Printer IP mapping remains forbidden. Network addresses may be diagnostic evidence, but they do not replace the hostname/queue contract.

## Evidence

Each run creates `%ProgramData%\SysAdminSuite\jobs\MachineInfo\<timestamp>-<unique-suffix>\` with `targets.txt`, `MachineInfo.csv`, optional `MachineInfo.html`, and `Summary.json`. The unique suffix prevents concurrent runs from sharing an evidence directory. Success requires the CSV host set to match the normalized requested target set exactly. `Summary.json` records counts, paths, `target_mutation_performed=false`, and the proof ceiling.

The underlying collector remains `GetInfo\Get-MachineInfo.ps1`; direct invocation is an implementation/debug surface, not the primary technician guidance. A directly invoked installed runner resolves its collector only from the active runtime/controller, canonical `C:\SASAL`, or the installer-managed machine controller cache; it never treats the caller's working directory as authority.

## Proof ceiling

Repository and CI proof can establish launcher routing, parser validity, output/evidence contracts, read-only intent, exact-set validation logic, and deterministic adapter provenance in the output schema. A future physical run is still required to prove the protected path, WMI permissions, target reachability, returned adapter identities, and technician acceptance on the actual site.
