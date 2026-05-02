# Bash Transport Layer

This folder contains Bash-first replacements for the old PowerShell workstation and printer access patterns.

PowerShell remains in the repo as legacy/reference tooling. For Northwell-targeted SysAdminSuite workflows, new work belongs here or in another Bash-oriented path.

## Legacy Patterns Mined

| Legacy PowerShell behavior | Old mechanism | Bash migration posture |
|---|---|---|
| Network preflight | `Test-Connection` | `sas-network-preflight.sh` using DNS, ping, TCP checks |
| Workstation identity | `Win32_BIOS`, `Win32_NetworkAdapterConfiguration`, `WmiMonitorID` | SSH/remote command where approved, future WMI/RPC bridge where allowed |
| Remote worker staging | `\\HOST\C$\ProgramData\SysAdminSuite\...` | SMB client mount/copy where approved; no mutation by default |
| Remote execution | `schtasks /Create /S HOST /RU SYSTEM` | Explicit remote-exec adapter only, disabled unless requested |
| Printer mapping | `PrintUIEntry /ga`, machine-wide registry connections | Preserve as legacy; Bash starts with recon/validation before mapping |
| Printer queue inventory | `Get-Printer`, `Win32_Printer` | SMB/RPC/CUPS/SNMP paths depending on environment |
| Printer identity | SNMP, HTTP scrape, port 9100/ZPL, ARP | `sas-printer-probe.sh` using SNMP/HTTP/9100/ARP |
| Central logs | per-host log collection | CSV evidence outputs and run directories |

## Safety Rules

1. Default to read-only.
2. Never mutate remote machines unless a tool has an explicit `--apply`, `--execute`, or similarly loud flag.
3. Keep survey/recon separate from remediation.
4. Write CSV outputs that can feed other tools.
5. Preserve source data and raw evidence.
6. Treat admin-share, SSH, WMI, RPC, SNMP community strings, and printer raw-port commands as environment-specific privileges.

## Current Bash Tools

| Tool | Purpose | Mutation risk |
|---|---|---|
| `sas-network-preflight.sh` | DNS, ping, TCP port checks for hosts/printers | None |
| `sas-printer-probe.sh` | Printer MAC/serial probing via SNMP, HTTP, 9100, ARP | Low/read-only; 9100 sends status request |
| `survey/sas-collect-cybernet-evidence.sh` | Deployment duplicate Cybernet evidence collection | Read-only; SSH disabled by default |

## Risks Addressed

| Risk | Mitigation |
|---|---|
| Accidentally extending PowerShell | Bash transport docs and tool locations make Bash the current path |
| Unsafe remote mutation | Recon tools are read-only by default |
| Revisit without evidence | Tools emit status/evidence CSVs first |
| Network ambiguity | Preflight separates DNS, ping, and TCP reachability |
| Printer identity uncertainty | Printer probe records source method for MAC/serial evidence |
| Data leakage | Live outputs are ignored by `.gitignore`; commit sanitized examples only |

## Known Limitations

| Limitation | Impact | Handling |
|---|---|---|
| Bash cannot natively perform Windows WMI/DCOM without extra tools | Workstation serial/MAC collection may need approved remote bridge | Use SSH when approved; add WMI/RPC adapter later |
| ICMP may be blocked | Ping failure does not prove device is offline | Use TCP checks and DNS result too |
| SNMP may be disabled or community strings unknown | Printer serial/MAC may be unavailable | Try HTTP, 9100, and ARP fallbacks |
| ARP only helps on local L2 or after traffic | MAC may be missing across routed networks | Treat ARP as fallback, not proof of absence |
| Port 9100 probes are printer-specific | Non-Zebra or locked printers may ignore commands | Record source and notes clearly |
| SSH collection is not universal | Many Windows/Cybernet devices will not support SSH | SSH requires explicit opt-in; future approved collector needed |

## Next Transport Upgrades

1. Add WMI/RPC adapter if approved tooling exists from the Bash host.
2. Add SMB admin-share recon that only lists/stages when explicitly enabled.
3. Add printer queue inventory against print servers.
4. Add JSON outputs alongside CSV for downstream automation.
5. Add dry-run/apply split for any future remediation command.

The rule is simple: scout first, shoot never, fix only with orders.
