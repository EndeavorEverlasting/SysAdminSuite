# Agent Instructions for SysAdminSuite

SysAdminSuite is a Windows sysadmin toolkit with multiple supported implementation paths. The repository contains PowerShell, .NET/C#, native tooling, and emerging Bash-on-Windows workflows.

The current field problem is not that one shell exists. The problem is agents inventing the wrong shell for the job.

## Non-negotiables

1. Do not default to PowerShell for new field-facing technician guidance.
2. Do not provide Linux networking commands for Windows endpoints.
3. When Bash is requested, assume Bash running on Windows unless the user explicitly says Linux, WSL, or macOS.
4. Prefer reusable scripts and documented probes over one-off terminal improvisation.
5. Use Windows-native executables from Bash when needed.
6. Inspect existing docs and scripts before advising.
7. Do not recommend commands that conflict with `docs/AI_RUNTIME_CONTRACT.md` or `docs/COMMAND_CATALOG.md`.

## Correct Bash-on-Windows command style

Use Windows-native executables from Bash:

```bash
cmd.exe /c ipconfig /all
cmd.exe /c getmac /v /fo list
cmd.exe /c arp -a
hostname.exe
ping.exe -n 4 <host-or-ip>
nslookup.exe <hostname-or-domain>
cmd.exe /c netsh interface show interface
```

## Forbidden default command style

Do not suggest PowerShell as the first answer for technician field usage unless the user explicitly requests the PowerShell path or the existing script being edited is PowerShell.

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

## Forbidden Linux assumptions

Do not suggest Linux-only commands for Windows endpoint surveys:

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

## Product rule

Technicians should run simple commands. SysAdminSuite should hide complexity behind documented scripts, wrappers, or compiled tools.

If a needed probe does not exist, document the gap and add a wrapper instead of inventing unsupported terminal soup.
