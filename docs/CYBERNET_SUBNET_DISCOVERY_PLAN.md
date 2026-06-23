# Cybernet Subnet Discovery Plan

Date: 2026-06-23
Status: design plan
Scope: SysAdminSuite Cybernet discovery, subnet targeting, and approved scanner handoff

## Purpose

This plan defines the missing bridge between an accurate Cybernet serial inventory and a safe, useful network survey.

The core workflow is:

```text
Serial inventory
  -> identity bridge
  -> DNS/IP/MAC evidence
  -> approved subnet candidates
  -> Naabu or Nmap survey
  -> reconciliation report
```

Serial numbers are the strongest identity anchor. They do not directly reveal subnets. The product must translate serials into hostnames, MACs, DNS records, DHCP/IPAM evidence, AD/SCCM export evidence, or other approved inventory evidence before any subnet survey is attempted.

This is field IT asset discovery, not pentest tooling.

## Existing posture alignment

This plan extends the current Cybernet evidence model instead of replacing it.

Current repo posture already treats Cybernet discovery as artifact-oriented, read-only, and scanner-first where PowerShell is blocked in the field path. That remains correct.

This plan adds a stricter pre-scan stage:

```text
Do not start by scanning guessed subnets.
Start by turning serials into candidate network scope.
```

Naabu and Nmap are survey engines. They are not inventory authorities. They confirm or challenge an evidence-backed target scope.

## Non-negotiable rules

- Do not infer an authoritative subnet from a serial number alone.
- Do not infer an authoritative subnet from DNS alone.
- Do not scan public IP ranges by default.
- Do not scan unapproved subnets by default.
- Do not run full-port scans by default.
- Do not run service/version detection by default.
- Do not mutate endpoints.
- Do not treat PowerShell, WMI, CIM, or WinRM failure as proof that a Cybernet is offline.
- Preserve raw evidence before parsing.
- Record exact commands used.
- Prefer saved scanner artifacts over repeated live probing.

## Evidence classes

Keep these separate. Mixing them creates fake certainty.

| Evidence class | Examples | Authority |
| --- | --- | --- |
| Identity evidence | serial, hostname, MAC, model, asset tag | proves what the device may be |
| Network location evidence | IP, subnet, VLAN, DHCP scope, IPAM scope, route context | proves where it may live |
| Survey evidence | open ports, host up/down, scanner output | proves what was visible from the scan point |
| Reconciliation evidence | expected vs observed matches/conflicts | proves operational status |

## Target data chain

The preferred chain is:

```text
Serial
  -> known hostname or MAC
  -> DNS A/PTR or DHCP lease or SCCM/AD export
  -> IP address
  -> approved subnet match
  -> target list for Naabu/Nmap
```

Minimum useful chain:

```text
Serial
  -> hostname
  -> DNS A record
  -> IP address
  -> approved site subnet match
```

Stronger chain:

```text
Serial
  -> hostname + MAC
  -> DHCP lease or SCCM export
  -> IP + scope
  -> approved subnet match
```

Best chain:

```text
Serial
  -> hostname + MAC + asset/inventory export
  -> DHCP/IPAM scope
  -> DNS confirmation
  -> approved subnet match
  -> scanner confirmation
```

## Sources to support the bridge

Use any available approved exports or local read-only commands.

| Priority | Source | Purpose |
| ---: | --- | --- |
| 1 | Cybernet tracker / deployment manifest | serial to hostname/MAC/site expectation |
| 2 | SCCM/MECM export | serial, hostname, MAC, last seen, IP when available |
| 3 | DHCP lease export | hostname, MAC, IP, scope/subnet |
| 4 | IPAM or site subnet export | authoritative subnet approval |
| 5 | DNS forward/reverse lookup | hostname/IP bridge |
| 6 | AD computer export | hostname, DNSHostName, OU, last logon, description |
| 7 | CMD/PowerShell local network context | DNS server, DNS suffixes, route table, ARP/NetBIOS clues |
| 8 | Naabu/Nmap | approved live survey confirmation |

## CMD and local shell bridge

CMD can fill gaps that scanners do not own.

Scanners answer:

```text
Is this IP visible from here?
Which selected ports answer?
```

Local CMD/PowerShell context answers:

```text
Which DNS servers and suffixes are active?
Which routes are visible from this machine?
Which local subnet is the operator currently on?
What does a hostname resolve to?
What does an IP reverse-resolve to?
What MACs are in local ARP cache?
Does NetBIOS expose a host name from this segment?
```

Read-only CMD commands to wrap:

```cmd
ipconfig /all
route print
nslookup <hostname>
nslookup <ip>
ping -a <ip>
arp -a
nbtstat -A <ip>
```

Read-only PowerShell equivalents where allowed:

```powershell
Get-NetIPConfiguration
Get-DnsClientServerAddress
Get-DnsClientGlobalSetting
Resolve-DnsName -Name <hostname>
Resolve-DnsName -Name <ip>
Test-Connection -ComputerName <target> -Count 1
Get-NetNeighbor
Get-NetRoute
Test-NetConnection -ComputerName <target> -Port 445
```

These commands are local evidence collectors. They do not replace Nmap/Naabu for scanner evidence and they do not prove a device is absent when blocked.

## Proposed module layout

```text
modules/
  CybernetSubnetDiscovery/
    Invoke-SASCybernetSubnetDiscovery.ps1
    Import-CybernetSerialInventory.ps1
    Resolve-CybernetDnsIdentity.ps1
    Resolve-CybernetCmdIdentity.ps1
    Resolve-CybernetAdIdentity.ps1
    Resolve-CybernetDhcpIdentity.ps1
    Resolve-CybernetSccmIdentity.ps1
    Convert-IpToSubnetCandidate.ps1
    New-CybernetSubnetDiscoveryReport.ps1

  CybernetSurvey/
    Invoke-SASCybernetSurvey.ps1
    Invoke-NaabuCybernetScan.ps1
    Invoke-NmapCybernetScan.ps1
    Compare-CybernetSurvey.ps1

config/
  cybernet-port-profile.json
  cybernet-subnet-rules.json
  approved-subnets.json
  dns-suffixes.json

input/
  cybernet-serials.example.csv
  cybernet-known-hosts.example.csv
  cybernet-known-macs.example.csv
  site-subnets.example.csv
```

## Input schemas

### `cybernet-serials.csv`

```csv
Site,Serial,ExpectedHostname,ExpectedMAC,ExpectedRoom,ExpectedStatus,Notes
SITE-A,CN12345678,WNH269OPR009,00-11-22-33-44-55,OR-2,Configured,
SITE-A,CN87654321,,,,Configured,Serial known only
```

The importer must tolerate blank optional fields. Field data is not clean. The script should normalize what exists and produce action items for what is missing.

### `site-subnets.csv`

```csv
Site,Subnet,Description,ApprovedForScan
SITE-A,10.20.30.0/24,OR Cybernet VLAN,true
SITE-A,10.20.31.0/24,Staging VLAN,true
```

This file is the cleanest way to prevent accidental broad scans.

## `cybernet-subnet-rules.json`

```json
{
  "subnetInference": {
    "requireApprovedSubnet": true,
    "allowDnsOnlyIpCandidate": true,
    "allowRouteTableCandidate": true,
    "allowDhcpScopeCandidate": true,
    "allowArpCandidate": true,
    "defaultPrefixLengthWhenUnknown": 24,
    "neverAssumePrefixWithoutEvidence": true
  },
  "confidenceRules": {
    "confirmed": [
      "SerialMatched",
      "HostnameMatchedOrMacMatched",
      "IpResolved",
      "SubnetApproved"
    ],
    "high": [
      "HostnameMatched",
      "IpResolved",
      "SubnetApproved"
    ],
    "medium": [
      "MacMatchedOrIpObserved",
      "SubnetApproved"
    ],
    "weak": [
      "IpObserved",
      "SubnetInferred"
    ],
    "blocked": [
      "IpOrSubnetFound",
      "SubnetNotApproved"
    ],
    "missing": [
      "SerialOnlyNoIdentityBridge"
    ]
  }
}
```

## `cybernet-port-profile.json`

```json
{
  "profiles": {
    "CybernetWindowsEndpoint": {
      "ports": [135, 139, 445, 3389, 5985, 5986, 80, 443, 8080, 8443],
      "defaultRate": 50,
      "defaultConcurrency": 10,
      "timeoutMs": 1000,
      "retries": 1,
      "requireApprovedSubnet": true,
      "allowServiceVersionScan": false,
      "allowFullPortScan": false
    }
  }
}
```

## Discovery command design

```powershell
.\modules\CybernetSubnetDiscovery\Invoke-SASCybernetSubnetDiscovery.ps1 `
  -Site "SITE-A" `
  -SerialInventoryPath ".\input\cybernet-serials.csv" `
  -SiteSubnetsPath ".\input\site-subnets.csv" `
  -UseDns `
  -UseCmd `
  -GenerateSurveyTargets `
  -OutDir ".\evidence\CybernetSubnetDiscovery\SITE-A"
```

Default behavior:

1. Import serial inventory.
2. Normalize serial, hostname, and MAC formats.
3. Detect duplicate serials.
4. Merge known host/MAC data when provided.
5. Resolve hostnames to IPs when hostnames exist.
6. Reverse-resolve IPs when IPs exist.
7. Capture local CMD/PowerShell network context as evidence.
8. Map IPs to approved site subnets.
9. Produce target IP/subnet files for scanner handoff.
10. Produce action items for missing or blocked bridges.

## Discovery outputs

```text
CybernetSubnetDiscovery_NormalizedSerials.csv
CybernetSubnetDiscovery_IdentityMap.csv
CybernetSubnetDiscovery_SubnetsToSurvey.csv
CybernetSubnetDiscovery_TargetIPs.txt
CybernetSubnetDiscovery_Summary.json
CybernetSubnetDiscovery_ActionItems.md
CybernetSubnetDiscovery_EvidenceLog.jsonl
```

### `CybernetSubnetDiscovery_IdentityMap.csv`

```csv
Site,Serial,Hostname,MAC,IP,SubnetCandidate,SubnetSource,Confidence,Evidence
SITE-A,CN12345678,WNH269OPR009,00-11-22-33-44-55,10.20.30.42,10.20.30.0/24,DHCP,Confirmed,"Serial+MAC+IP matched approved subnet"
SITE-A,CN87654321,WNH269OPR014,,10.20.30.88,10.20.30.0/24,DNS,High,"Hostname resolved and IP mapped to approved subnet"
```

### `CybernetSubnetDiscovery_SubnetsToSurvey.csv`

```csv
Site,Subnet,Reason,Confidence,ApprovedForScan
SITE-A,10.20.30.0/24,Matched known Cybernet DNS/IP evidence,High,true
SITE-A,10.20.31.0/24,Matched staging Cybernet hostname evidence,Medium,true
```

## Scanner handoff

Only run scanner passes against approved target files produced by discovery.

### Naabu first-pass survey

Naabu is useful as the fast selected-port pass.

```powershell
naabu `
  -list .\evidence\CybernetSubnetDiscovery\SITE-A\CybernetSubnetDiscovery_TargetIPs.txt `
  -p 135,139,445,3389,5985,5986,80,443,8080,8443 `
  -rate 50 `
  -c 10 `
  -retries 1 `
  -timeout 1000 `
  -json `
  -silent `
  -duc `
  -o .\evidence\CybernetSurvey\SITE-A\CybernetSurvey_Naabu.jsonl
```

### Nmap host discovery fallback

```powershell
nmap `
  -sn `
  -iL .\evidence\CybernetSubnetDiscovery\SITE-A\CybernetSubnetDiscovery_TargetIPs.txt `
  -oX .\evidence\CybernetSurvey\SITE-A\CybernetSurvey_NmapHostDiscovery.xml
```

### Nmap selected-port pass

```powershell
nmap `
  -p 135,139,445,3389,5985,5986,80,443,8080,8443 `
  --open `
  -iL .\evidence\CybernetSubnetDiscovery\SITE-A\CybernetSubnetDiscovery_TargetIPs.txt `
  -oX .\evidence\CybernetSurvey\SITE-A\CybernetSurvey_NmapPorts.xml
```

## Scanner classification

| Classification | Meaning |
| --- | --- |
| `CONFIRMED_BY_INFRASTRUCTURE` | DHCP/IPAM/AD/DNS evidence aligns before scanner confirmation |
| `CONFIRMED_ON_NETWORK` | Approved scanner evidence confirms the resolved target |
| `NAABU_ONLY` | Naabu saw selected ports, but no inventory bridge was supplied |
| `NMAP_ONLY` | Nmap saw target, but no inventory bridge was supplied |
| `DNS_ONLY` | DNS resolves, but no infrastructure or scanner confirmation exists |
| `DHCP_ONLY` | DHCP knows the device, but DNS/scanner confirmation is absent |
| `MANIFEST_ONLY` | Serial exists only in the input manifest |
| `REVIEW_CONFLICT` | Evidence conflicts, such as MAC/IP/hostname/subnet mismatch |
| `BLOCKED_UNAPPROVED_SUBNET` | Evidence points to a subnet that is not approved for scan |
| `ENVIRONMENT_BLOCKED_POLICY` | Scanner or command evidence is blocked by local policy |
| `NETWORK_PREFLIGHT_FAILED` | Current network posture cannot validate target visibility |

## Implementation acceptance criteria

A completed implementation must allow this flow:

```text
Given a Cybernet serial list plus any hostname/MAC/site subnet exports,
produce approved target IPs/subnets,
run Naabu or Nmap only against approved targets,
and output evidence suitable for deployment reconciliation.
```

Required checks:

- Serial normalization works.
- Duplicate serials are reported.
- Known host/MAC data merges cleanly.
- DNS forward and reverse records are parsed.
- CMD evidence is captured and parsed where practical.
- ARP and NetBIOS evidence remain secondary.
- IPs are mapped only to approved or supplied site subnets.
- Public IP ranges are rejected by default.
- Unapproved subnets are blocked by default.
- Naabu command generation is deterministic.
- Nmap command generation is deterministic.
- Exact commands are recorded.
- Raw artifacts are preserved.
- Summary JSON and action Markdown are generated.

## Pester test plan

Add tests for:

- serial normalization
- duplicate serial detection
- manifest import with blank optional fields
- DNS result parsing
- CMD `nslookup` parsing
- `arp -a` parsing
- `nbtstat -A` parsing
- IP-to-approved-subnet mapping
- public IP rejection
- unapproved subnet rejection
- survey target generation
- Naabu command generation
- Nmap command generation
- blocked subnet action items
- missing identity bridge action items
- summary JSON generation

## Practical rule for operators

Use this order:

```text
1. Import serial inventory.
2. Attach any known hostname/MAC/export data.
3. Resolve DNS and local network context.
4. Map IPs to approved subnets.
5. Review generated targets.
6. Run Naabu for fast selected-port visibility.
7. Run Nmap when XML artifacts or host discovery behavior are preferred.
8. Reconcile results against the serial manifest.
```

Do not start with a guessed subnet scan. That is how stale spreadsheets become louder instead of truer.
