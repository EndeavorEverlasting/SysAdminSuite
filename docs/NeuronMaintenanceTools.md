# Neuron Maintenance Console Tooling

## Purpose

This document captures the built-in Neuron maintenance tools observed from field photos and turns them into a SysAdminSuite roadmap. The immediate goal is not to clone the vendor console pixel-for-pixel. The goal is colder and better: reproduce the useful checks remotely, safely, and repeatably so a tech does not need to log into the hidden maintenance interface just to determine survey status, device identity, software posture, or network readiness.

## Field observation notes

The screen is physically rotated 90 or 270 degrees depending on viewing angle. Treat photos from these devices as orientation-variable evidence. Do not rely on OCR as the authority when building production logic. Use the visible button labels and command output as the first catalog, then validate each item with hands-on runs.

Observed command output included:

- Echo server check
- Ping VPN check against a 10.8.0.x VPN endpoint
- ICMP response timing around 14-15 ms in the photo
- Output panel showing basic command result text, packet counts, and round-trip stats

## Observed left-side tool buttons

### Page 1: echo, ping, and IP basics

| Observed button | Likely purpose | SysAdminSuite target behavior | Risk level |
|---|---|---|---|
| Echo Server | Test application/server echo path | Resolve target, test TCP/HTTP/ICMP depending on known protocol, log response | Read-only |
| Echo Follower Servers | Test redundant/follower echo endpoints | Iterate configured follower endpoints and compare reachability | Read-only |
| Ping VPN | Ping VPN gateway or tunnel endpoint | ICMP ping configured VPN target, store latency/loss | Read-only |
| Ping Server | Ping primary application/server host | ICMP ping primary endpoint, include DNS resolution | Read-only |
| Ping Follower Servers | Ping secondary/follower endpoints | Iterate follower host list with latency/loss table | Read-only |
| Ip Config | Show standard IP configuration | Capture `ipconfig` summary and adapter basics | Read-only |
| Ip Config All | Show full IP configuration | Capture `ipconfig /all`, DNS, DHCP, gateway, MACs | Read-only |
| All Tasks Services | Likely service status subset for task-related services | Collect all vendor-relevant service statuses into one table | Read-only |
| All Tasks | Likely runs broad task/status checks | Run the non-destructive snapshot profile | Read-only by default |

### Page 2: services, firewall, netstat, wireless inventory

| Observed button | Likely purpose | SysAdminSuite target behavior | Risk level |
|---|---|---|---|
| MSMQ service | Check Microsoft Message Queuing service | Query service existence/start mode/status; optional start only when explicitly requested | Read-only default |
| OpenVPN service | Check VPN service | Query OpenVPN services and tunnel adapter state | Read-only default |
| DCIS service | Check device/vendor integration service | Query matching service by exact configured name or fuzzy service display name | Read-only default |
| All Services | Show all Windows services | Export service name/display/start/status table | Read-only |
| Firewall | Show firewall profile state | Capture domain/private/public profile state and rules summary | Read-only |
| NetStat | Show network sessions/listeners | Capture `netstat -ano`; optional process resolution | Read-only |
| Wireless Profiles | Show saved WLAN profiles | Capture `netsh wlan show profiles` | Read-only |
| Wireless Interfaces | Show WLAN adapter/interface status | Capture `netsh wlan show interfaces` | Read-only |
| Wireless Networks | Show visible WLAN networks | Capture `netsh wlan show networks mode=bssid` | Read-only |

### Page 3: traces, discovery, and DHCP repair

| Observed button | Likely purpose | SysAdminSuite target behavior | Risk level |
|---|---|---|---|
| Wireless Traces | Start/stop or collect WLAN tracing | Provide trace collection wrapper with explicit start/stop and output path | Controlled write |
| Scan Network Devices | Discover devices on subnet | ARP table plus optional ping sweep of local subnet | Read-only with network traffic |
| Release/Renew | DHCP release and renew | Require explicit `-AllowNetworkReset`; never run during passive recon | Disruptive |

## Functional groups for SysAdminSuite

### 1. Identity and software posture

Use case: determine which Neuron is in front of you and whether it matches expected configuration without logging into the vendor maintenance server.

Minimum data to capture:

- Hostname
- BIOS serial
- MAC addresses
- IP address and default gateway
- VPN adapter presence and IP
- Installed software list
- Neuron software reference/version, such as the observed `11.8.0.328`
- Services related to MSMQ, OpenVPN, DCIS, SmartLynx, SIS, Epic, Imprivata, or other configured site baselines

Planned module names:

- `Get-NeuronIdentity`
- `Get-NeuronSoftwarePosture`
- `Compare-NeuronSoftwareBaseline`
- `Export-NeuronSurveyPacket`

### 2. Network and VPN readiness

Use case: prove whether the Neuron can reach what it needs before escalating to TSE, network, or application teams.

Minimum checks:

- DNS resolution
- Primary server ping
- Follower server pings
- VPN endpoint ping
- VPN service state
- VPN adapter state
- Current routes
- TCP port checks once the real service ports are known
- Latency/loss summary

Planned module names:

- `Test-NeuronNetworkPath`
- `Test-NeuronVpnPath`
- `Get-NeuronRouteSnapshot`

### 3. Service readiness

Use case: determine whether required local services exist, are running, and are configured correctly.

Minimum checks:

- MSMQ
- OpenVPN
- DCIS or vendor integration service
- SmartLynx/SIS/Epic related services when present
- Start mode
- Current state
- Service account
- Last start failure where available

Planned module names:

- `Get-NeuronServiceState`
- `Compare-NeuronServiceBaseline`

### 4. Wireless diagnostics

Use case: inventory wireless profile and interface status without clicking through the local maintenance UI.

Minimum checks:

- Saved wireless profiles
- Active wireless interface state
- Visible SSIDs/BSSIDs
- Signal quality
- Authentication/cipher details where available
- Optional trace capture

Planned module names:

- `Get-NeuronWirelessSnapshot`
- `Start-NeuronWirelessTrace`
- `Stop-NeuronWirelessTrace`

### 5. Controlled repair actions

Use case: keep dangerous actions behind explicit switches.

Rules:

- Release/renew requires `-AllowNetworkReset`.
- Service start/restart requires `-AllowServiceChange`.
- Firewall rule modification is out of scope for the first pass.
- Default mode is survey/recon only.

Stern judge note: if it can knock a device offline, it is not a diagnostic. It is a repair action wearing a fake mustache.

## First implementation checkpoint

The first committed tool is `QRTasks/Get-NeuronMaintenanceSnapshot.ps1`.

It provides a safe field snapshot for:

- Host identity
- IP configuration
- VPN/server ping checks
- selected service status
- firewall profiles
- netstat listeners/sessions
- wireless profiles/interfaces/networks
- optional network scan
- optional DHCP release/renew only when explicitly allowed

## Next build targets

1. Add a JSON baseline file per site/device class.
2. Add software comparison against expected Neuron app/version lists.
3. Add CSV/HTML report output matching the existing SysAdminSuite style.
4. Add GUI tab integration under Machine Info or a new Neuron tab.
5. Add remote execution profile using SMB plus scheduled task, matching the existing no-WinRM posture.
6. Add tests that verify dangerous actions are locked behind explicit switches.
