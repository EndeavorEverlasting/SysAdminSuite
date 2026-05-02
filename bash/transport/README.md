# Bash Transport Layer

This folder contains Bash-first replacements for the old PowerShell workstation and printer access patterns.

PowerShell remains in the repo as legacy/reference tooling. For Northwell-targeted SysAdminSuite workflows, new work belongs here or in another Bash-oriented path.

## Legacy Patterns Mined

| Legacy PowerShell behavior | Old mechanism | Bash migration posture |
|---|---|---|
| Network preflight | `Test-Connection` | `sas-network-preflight.sh` using DNS, ping, TCP checks |
| Workstation identity | `Win32_BIOS`, `Win32_NetworkAdapterConfiguration`, `WmiMonitorID` | `sas-workstation-identity.sh` with ordered read-only transports; optional WMI adapter where approved |
| Remote worker staging | `\\HOST\C$\ProgramData\SysAdminSuite\...` | `sas-smb-readonly-recon.sh` for read-only admin-share evidence checks; no staging yet |
| Remote execution | `schtasks /Create /S HOST /RU SYSTEM` | Future explicit remote-exec adapter only, disabled unless requested |
| Printer mapping | `PrintUIEntry /ga`, machine-wide registry connections | Preserve as legacy; Bash starts with recon/validation before mapping |
| Printer queue inventory | `Get-Printer`, `Win32_Printer` | Future SMB/RPC/CUPS/SNMP paths depending on environment |
| Printer identity | SNMP, HTTP scrape, port 9100/ZPL, ARP | `sas-printer-probe.sh` using SNMP/HTTP/9100/ARP |
| Central logs | per-host log collection | CSV evidence outputs and run directories |

## Safety Rules

1. Default to read-only.
2. Never mutate remote machines unless a tool has an explicit `--apply`, `--execute`, or similarly loud flag.
3. Keep survey/recon separate from remediation.
4. Write CSV outputs that can feed other tools.
5. Preserve source data and raw evidence.
6. Treat admin-share, SSH, WMI, RPC, SNMP community strings, and printer raw-port commands as environment-specific privileges.
7. Do not pass credentials on the command line when environment variables are available.

## Current Bash Tools

| Tool | Purpose | Mutation risk |
|---|---|---|
| `sas-network-preflight.sh` | DNS, ping, TCP port checks for hosts/printers | None |
| `sas-printer-probe.sh` | Printer MAC/serial probing via SNMP, HTTP, 9100, ARP | Low/read-only; 9100 sends status request |
| `sas-workstation-identity.sh` | Workstation/Cybernet identity collection via DNS, ping, ARP, optional SSH, optional WMI | Read-only; SSH/WMI disabled by default |
| `sas-wmi-identity.sh` | Optional WMI identity adapter for Windows hosts using approved `wmic` client | Read-only WMI queries only |
| `sas-smb-readonly-recon.sh` | Optional SMB admin-share reachability/list recon for approved evidence paths | Read-only; no writes/staging/tasks |
| `survey/sas-collect-cybernet-evidence.sh` | Deployment duplicate Cybernet evidence collection using workstation identity adapter | Read-only; adapter-driven |

## Workstation Identity Flow

```bash
./bash/transport/sas-workstation-identity.sh \
  --target WMH300OPR134 \
  --output data/outputs/workstation_identity.csv
```

Optional SSH path, only when approved:

```bash
./bash/transport/sas-workstation-identity.sh \
  --target WMH300OPR134 \
  --allow-ssh \
  --ssh-user approved_user \
  --ssh-key ~/.ssh/approved_key \
  --output data/outputs/workstation_identity.csv
```

Optional WMI path, only when approved:

```bash
export SAS_WMI_USER='approved_user'
export SAS_WMI_PASS='prompt-or-secret-store-value'
export SAS_WMI_DOMAIN='NSLIJHS'

./bash/transport/sas-workstation-identity.sh \
  --target WMH300OPR134 \
  --allow-wmi \
  --output data/outputs/workstation_identity.csv
```

Direct WMI adapter use:

```bash
./bash/transport/sas-wmi-identity.sh \
  --target WMH300OPR134 \
  --output data/outputs/wmi_identity.csv
```

Optional SMB admin-share read-only recon, only when approved:

```bash
export SAS_SMB_USER='approved_user'
export SAS_SMB_PASS='prompt-or-secret-store-value'
export SAS_SMB_DOMAIN='NSLIJHS'

./bash/transport/sas-smb-readonly-recon.sh \
  --target WMH300OPR134 \
  --allow-list \
  --approved-paths 'ProgramData/SysAdminSuite,ProgramData/SysAdminSuite/Mapping/logs' \
  --output data/outputs/smb_readonly_recon.csv
```

The collector emits `IdentityStatus`:

| Status | Meaning |
|---|---|
| `IdentityCollected` | At least one hostname, serial, or MAC value was collected |
| `ReachableNeedsApprovedIdentityTransport` | Device responds, but current transport cannot collect full identity |
| `UnreachableOrBlocked` | DNS/ping/available transport could not confirm the target |

The WMI adapter emits `WmiStatus`:

| Status | Meaning |
|---|---|
| `WmiIdentityCollected` | WMI returned host, serial, or MAC evidence |
| `WmiClientMissing` | No approved `wmic` client exists on the Bash host |
| `WmiQueryFailed` | Firewall, permissions, DCOM/RPC, or query failure blocked collection |
| `WmiNoIdentityReturned` | WMI ran but did not return identity fields |

The SMB adapter emits `ReconStatus`:

| Status | Meaning |
|---|---|
| `EvidencePathReachable` | Approved SMB evidence path exists and is reachable/listable |
| `NeedsApprovedCredentialsOrPolicy` | SMB authentication or policy blocked access |
| `SMBUnavailable` | Host/share could not be reached |
| `EvidencePathMissing` | Host/share reachable, but approved path missing |
| `ReviewRequired` | SMB response was ambiguous |

## Risks Addressed

| Risk | Mitigation |
|---|---|
| Accidentally extending PowerShell | Bash transport docs and tool locations make Bash the current path |
| Unsafe remote mutation | Recon tools are read-only by default |
| Credential leakage | WMI/SMB support environment variables and do not write credentials to output |
| Revisit without evidence | Tools emit status/evidence CSVs first |
| Network ambiguity | Preflight separates DNS, ping, and TCP reachability |
| Printer identity uncertainty | Printer probe records source method for MAC/serial evidence |
| Cybernet identity uncertainty | Workstation identity adapter centralizes target identity collection |
| Windows identity gap | Optional WMI adapter gives a stronger approved path when available |
| Admin-share uncertainty | SMB recon verifies approved evidence paths without staging or executing anything |
| Duplicate audit drift | Deployment evidence collector calls the identity adapter instead of embedding one-off probe logic |
| Data leakage | Live outputs are ignored by `.gitignore`; commit sanitized examples only |

## Known Limitations

| Limitation | Impact | Handling |
|---|---|---|
| Bash cannot natively perform Windows WMI/DCOM without extra tools | Workstation serial/MAC collection needs an approved WMI client | Use `--allow-wmi` only where approved client/policy exists |
| WMI often fails across firewalls or restricted DCOM/RPC policy | Identity may remain unavailable even when device is online | Output `WmiStatus`; fall back to `NeedsPrivilegedSurvey` rather than false certainty |
| SMB admin shares may be disabled or blocked | Evidence path reachability may be unavailable | Output `ReconStatus`; do not assume host absence |
| SMB listing is not the same as identity proof | It proves path access, not Cybernet identity | Use as support evidence, not replacement for serial/MAC identity |
| ICMP may be blocked | Ping failure does not prove device is offline | Use TCP checks and DNS result too |
| ARP only helps on local L2 or after traffic | MAC may be missing across routed networks | Treat ARP as fallback, not proof of absence |
| SSH collection is not universal | Many Windows/Cybernet devices will not support SSH | SSH requires explicit opt-in |
| SSH output is platform-dependent | Linux, Windows OpenSSH, and appliances return different identity formats | Output includes `TransportUsed`, `IdentityStatus`, and notes |
| SNMP may be disabled or community strings unknown | Printer serial/MAC may be unavailable | Try HTTP, 9100, and ARP fallbacks |
| Port 9100 probes are printer-specific | Non-Zebra or locked printers may ignore commands | Record source and notes clearly |
| Remote staging and scheduled-task execution are not ported | No Bash mutation/remediation path yet | Keep mutation/re-exec out until explicitly approved |

## Next Transport Upgrades

1. Add printer queue inventory against print servers.
2. Add JSON outputs alongside CSV for downstream automation.
3. Add dry-run/apply split for any future remediation command.
4. Add a private/sanitized sample fixture set for repeatable tests without live identifiers.
5. Add explicit file allowlist support for SMB read checks, still read-only.

The rule is simple: scout first, shoot never, fix only with orders.
