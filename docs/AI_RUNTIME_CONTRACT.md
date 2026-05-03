# SysAdminSuite Bash-on-Windows Runtime Contract

This contract exists to stop field guidance from drifting into the wrong shell.

SysAdminSuite may contain PowerShell, C#, native Windows tooling, and Bash. For Northwell-targeted field workflows, the active operational path is Bash running on Windows.

## Target Runtime

Supported Bash environments:

- Git Bash on Windows
- MSYS2 Bash on Windows
- Comparable Bash environments that can invoke Windows executables

Not assumed unless explicitly documented:

- Linux
- WSL
- macOS
- PowerShell

## Default Rule

For Northwell-targeted field workflows, do not generate PowerShell commands by default.

PowerShell is allowed only when:

- the user explicitly asks for PowerShell
- the existing workflow is specifically PowerShell-based
- a documented fallback requires it
- the task is in a lab, unrestricted Windows environment, or migration-reference context

## Bash-on-Windows Rule

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
nslookup.exe <hostname-or-ip>
```

## Forbidden PowerShell Defaults

Do not recommend these for Bash-first field workflows unless explicitly requested:

```powershell
Get-NetAdapter
Get-CimInstance
Get-WmiObject
Test-NetConnection
Resolve-DnsName
New-NetIPAddress
Set-NetIPInterface
```

## Forbidden Linux Assumptions

Do not recommend Linux-only commands for Windows Bash workflows:

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

## Command Generation Policy

Agents should recommend commands only from:

- `AGENTS.md`
- `docs/COMMAND_CATALOG.md`
- `survey/`
- `scripts/`
- `bash/`
- `bin/`
- existing README examples that match the requested runtime

If no approved command exists, add or propose a wrapper script. Do not invent a one-off command in front of a technician.

## Field Output Policy

Field commands should be:

- short
- repeatable
- copy/paste-safe
- log-friendly
- readable by technicians without shell archaeology

Good:

```bash
bash scripts/survey_device.sh
```

Risky:

```text
Run whatever network discovery command works on your shell.
```

## Documentation Rule

Whenever a workflow is Bash-based, documents must explicitly say **Bash on Windows** if Windows-native executables are expected.

The word `Bash` by itself is not enough. It invites Linux assumptions. That is how field work dies in public.
