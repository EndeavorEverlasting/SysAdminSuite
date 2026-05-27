# SysAdminSuite Command Catalog

This catalog defines approved Bash-on-Windows probes for field workflows.

Use these commands directly or wrap them in scripts. Do not substitute PowerShell or Linux commands unless the workflow explicitly allows it.

## Runtime

Expected shell:

```text
Bash on Windows, usually Git Bash or MSYS2 Bash
```

Expected command pattern:

```bash
cmd.exe /c <windows-command>
```

or direct Windows executable invocation:

```bash
hostname.exe
ping.exe -n 4 <host-or-ip>
nslookup.exe <hostname-or-ip>
```

## Identity

### Hostname

```bash
hostname.exe
```

### Current User

```bash
cmd.exe /c whoami
```

## Network Survey

### Full IP Configuration

```bash
cmd.exe /c ipconfig /all
```

### MAC Address Survey

```bash
cmd.exe /c getmac /v /fo list
```

### ARP Table

```bash
cmd.exe /c arp -a
```

### Routing Table

```bash
cmd.exe /c route print
```

### DNS Lookup

```bash
nslookup.exe <hostname-or-domain>
```

### Ping Test

```bash
ping.exe -n 4 <host-or-ip>
```

## Interface Details

### Network Interface Summary

```bash
cmd.exe /c netsh interface show interface
```

### IP Address Details

```bash
cmd.exe /c netsh interface ip show config
```

### Wireless Profiles

```bash
cmd.exe /c netsh wlan show profiles
```

## Printer Recon

### Installed Printers

```bash
cmd.exe /c wmic printer get name,drivername,portname
```

Note: `wmic` may be unavailable on newer Windows builds. Keep this as a transitional probe, not the foundation of the kingdom.

## Log Capture

### Capture Survey Output

```bash
mkdir -p logs
bash scripts/survey_device.sh | tee "logs/device_survey_$(date +%Y%m%d_%H%M%S).txt"
```

### Simple Capture Fallback

```bash
mkdir -p logs
bash scripts/survey_device.sh | tee logs/device_survey.txt
```

## Forbidden For Bash-First Field Work

### PowerShell Defaults

```powershell
Get-NetAdapter
Get-CimInstance
Get-WmiObject
Test-NetConnection
Resolve-DnsName
```

### Linux Defaults

```bash
ip addr
ifconfig
nmcli dev show
systemctl status
journalctl
```

## Hostname Availability

Read-only naming sequence analysis for conventions such as `WNH270OPR###`:

```bash
bash survey/sas-survey-hostname-availability.sh \
  --convention WNH270OPR \
  --suffix-mode numeric \
  --width 3 \
  --used-names survey/fixtures/hostname_availability_sample.txt
```

See `docs/HOSTNAME_AVAILABILITY.md` for AD export, tracker union, and DNS check options.

## Auto-logon Workstation Assessment

Remote batch assessment (HTML dashboard primary):

```bash
bash survey/sas-assess-autologon.sh \
  --manifest ./survey/output/wbs_targets.csv \
  --preflight \
  --ad-live \
  --output survey/output/autologon_assessment.csv \
  --dashboard survey/output/autologon_dashboard.html \
  --open
```

See `docs/AUTOLOGON_ASSESSMENT.md`.

## Registry Install Diff (read-only pipeline)

Field entry via Bash wrapper:

```bash
bash scripts/sas_registry_install_diff.sh --help
```

Target readiness (used by auto-logon `--preflight`):

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/Test-TargetReadiness.ps1 -TargetsCsv Config/target_batch.example.csv
```

See `docs/REGISTRY_INSTALL_DIFF_PIPELINE.md`.

## Rule For New Commands

If a needed command is not listed here, add it to this catalog and wrap it in a script before sending it to a technician.
