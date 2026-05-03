# SysAdminSuite AI Runtime Contract

This document prevents AI agents and contributors from mixing incompatible command environments.

SysAdminSuite supports several implementation paths, but field guidance must name the runtime explicitly before giving commands.

## Runtime categories

| Runtime | Meaning | Acceptable use |
|---|---|---|
| Bash on Windows | Git Bash, MSYS2 Bash, or equivalent shell on Windows endpoints | New lightweight technician probes and wrappers |
| PowerShell | Windows PowerShell 5.1 or PowerShell 7+ | Existing `.ps1` / `.psm1` tools, tests, GUI launchers, and maintained optional tooling |
| .NET / C# | Compiled managed code | Preferred path for robust GUI and automation where scripts are blocked |
| Native Windows | C/C++ or direct Windows executables | Restricted endpoints, printer mapping, and low-dependency workflows |
| Linux Bash | Bash on a Linux host | Only when explicitly requested |
| WSL | Windows Subsystem for Linux | Only when explicitly requested |

## Default for technician field guidance

When the user asks for Bash guidance for Windows endpoints, assume:

- Bash is running on Windows.
- Windows-native executables are available.
- Linux networking tools are not available.
- PowerShell may be blocked, outdated, or intentionally avoided.

## Bash-on-Windows command rule

Bash scripts may call Windows-native executables.

Approved examples:

```bash
cmd.exe /c ipconfig /all
cmd.exe /c getmac /v /fo list
cmd.exe /c arp -a
cmd.exe /c route print
cmd.exe /c netsh interface show interface
cmd.exe /c netsh interface ip show config
hostname.exe
ping.exe -n 4 <host-or-ip>
nslookup.exe <hostname-or-domain>
```

## PowerShell restriction

PowerShell is not banned from the repository. It is already part of the repo and remains valid for existing modules, tests, GUI launchers, migration references, and environments where it is explicitly allowed.

However, AI agents must not default to PowerShell for new technician-facing field commands unless the request, file, or workflow explicitly calls for it.

Avoid defaulting to:

```powershell
Get-NetAdapter
Get-CimInstance
Get-WmiObject
Test-NetConnection
Resolve-DnsName
New-NetIPAddress
Set-NetIPInterface
```

## Linux command restriction

When the target is a Windows endpoint, do not provide Linux-only commands.

Forbidden examples:

```bash
ip addr
ifconfig
nmcli dev show
systemctl status
journalctl
lsusb
lspci
udevadm
rfkill
iwconfig
```

## Command generation policy

AI agents must choose commands from documented sources first:

1. `docs/COMMAND_CATALOG.md`
2. Existing scripts in the repository
3. Existing runbooks and examples

If no approved command exists, the correct response is to add a documented wrapper or propose a new catalog entry. Do not improvise unsupported field commands in front of technicians.

## Language precision

PowerShell has cmdlets.

Bash has commands, functions, shell scripts, and wrappers.

For Bash workflows, use terms like:

- Bash command
- Bash wrapper
- SysAdminSuite probe
- technician survey command

Do not call Bash commands cmdlets.

## Acceptance standard

A field command is acceptable only if a technician can copy it, run it on a Windows endpoint in the named runtime, and get predictable output without shell translation games.
