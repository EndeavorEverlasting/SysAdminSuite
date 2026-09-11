# Machine Info CMD

The technician front door is `Get-MachineInfo.cmd`. The installed equivalent is `sas machineinfo`. PowerShell snippets, the GUI, and dashboard tutorials are downstream conveniences; they do not replace the CMD/runtime contract.

## Technician use

From a current SysAdminSuite folder, double-click `Get-MachineInfo.cmd` and enter one computer name. For multiple explicit hosts, use `Get-MachineInfo.cmd HOST01 HOST02`. For a prepared one-host-per-line list, use `Get-MachineInfo.cmd file C:\Path\hosts.txt` or `sas machineinfo file C:\Path\hosts.txt`.

The command is launch-folder and Windows-username independent. An installed launcher resolves through `%ProgramData%\SysAdminSuite\bin\sas.cmd`; a current repository or sealed runtime resolves the sibling network-aware dispatcher. Do not make a named-user Desktop, OneDrive, or checkout path part of the technician handoff.

Remote inventory requires an approved protected Northwell path: hardwire, `NSLIJHS-WAB`, or authenticated `DomainAuthenticated` VPN. The standard SAS network canary runs before target access and may use only the repository's already-proven saved-WLAN transition/restore behavior. The machine-info lane performs read-only ICMP/WMI inventory and does not mutate the target.

## Evidence

Each run creates `%ProgramData%\SysAdminSuite\jobs\MachineInfo\<timestamp>\` with `targets.txt`, `MachineInfo.csv`, optional `MachineInfo.html`, and `Summary.json`. Success requires the CSV host set to match the normalized requested target set exactly. `Summary.json` records counts, paths, `target_mutation_performed=false`, and the proof ceiling.

The underlying collector remains `GetInfo\Get-MachineInfo.ps1`; direct invocation is an implementation/debug surface, not the primary technician guidance.

## Proof ceiling

Repository and CI proof can establish launcher routing, parser validity, output/evidence contracts, read-only intent, and exact-set validation logic. A future physical run is still required to prove the protected path, WMI permissions, target reachability, returned inventory, and technician acceptance on the actual site.
