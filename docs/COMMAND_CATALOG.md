# SysAdminSuite Command Catalog

This catalog lists approved field-safe commands for technician guidance.

The purpose is simple: agents and humans should pick from known-good probes instead of improvising shell commands under pressure.

## Assumed runtime for this catalog

Unless otherwise stated, commands in this catalog assume:

- Windows endpoint
- Bash shell running on Windows
- Windows-native executables available from Bash
- No Linux command assumptions
- No PowerShell default

## Identity

### Hostname

```bash
hostname.exe
```

### Current user

```bash
cmd.exe /c whoami
```

## Network survey

### Full IP configuration

```bash
cmd.exe /c ipconfig /all
```

### MAC address survey

```bash
cmd.exe /c getmac /v /fo list
```

### ARP table

```bash
cmd.exe /c arp -a
```

### Routing table

```bash
cmd.exe /c route print
```

### DNS lookup

```bash
nslookup.exe <hostname-or-domain>
```

### Ping test

```bash
ping.exe -n 4 <host-or-ip>
```

## Interface details

### Network interface summary

```bash
cmd.exe /c netsh interface show interface
```

### IP address details

```bash
cmd.exe /c netsh interface ip show config
```

### Wireless profiles

```bash
cmd.exe /c netsh wlan show profiles
```

## Printer reconnaissance

### Installed printers through WMIC

```bash
cmd.exe /c wmic printer get name,drivername,portname
```

Note: `wmic` is legacy and may be unavailable on newer Windows builds. Use it only as an approved fallback until a stronger compiled or native printer inventory path exists.

## Safe output capture

### Write survey output to a timestamped log

```bash
mkdir -p logs
bash scripts/survey_device.sh | tee "logs/device_survey_$(date +%Y%m%d_%H%M%S).txt"
```

### Write survey output to a simple reusable log

```bash
mkdir -p logs
bash scripts/survey_device.sh | tee logs/device_survey.txt
```

## Forbidden Linux substitutions

Do not substitute these for Windows endpoint work:

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

## Forbidden PowerShell defaults

Do not substitute these unless a PowerShell path is explicitly requested:

```powershell
Get-NetAdapter
Get-CimInstance
Get-WmiObject
Test-NetConnection
Resolve-DnsName
```

## Catalog expansion rule

When a new probe is needed, add it here first with:

1. Runtime assumption
2. Exact command
3. Expected output purpose
4. Known limitations

Then wire it into a script or runbook.
