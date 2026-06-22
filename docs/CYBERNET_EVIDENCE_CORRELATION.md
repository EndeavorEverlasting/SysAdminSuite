# Cybernet Evidence Correlation Workflow

This workflow improves Cybernet discovery accuracy by correlating multiple read-only evidence sources instead of relying on a single subnet scan.

## Goal

Build a Cybernet presence report from:

- normalized Cybernet manifest
- DNS forward/reverse resolution
- optional Active Directory computer export
- optional DHCP lease export
- optional Nmap evidence from approved targeted scans

Nmap is only confirmation evidence. DNS, AD, DHCP, endpoint tools, and tracker data are usually better sources for where a Cybernet should be.

## Safety model

These tools are local-output-only and read-only.

They do not:

- mutate workstations
- authenticate to remote devices
- run vulnerability scripts
- use evasion/stealth/spoofing
- scan wide networks by default

## 1. Build the Cybernet manifest

```bash
bash survey/sas-survey-targets.sh \
  --device-type Cybernet \
  --csv survey/input/cybernet_survey_manifest.csv \
  --output survey/output/cybernet_targets_resolved.csv
```

## 2. Resolve manifest hostnames in DNS

```bash
python survey/sas-resolve-manifest-dns.py \
  --manifest survey/output/cybernet_targets_resolved.csv \
  --output survey/output/cybernet_dns_resolution_report.csv \
  --subnet-summary survey/output/cybernet_dns_subnet_summary.csv \
  --resolved-ips survey/output/cybernet_resolved_ips.txt
```

Optional suffix retries for short names:

```bash
python survey/sas-resolve-manifest-dns.py \
  --manifest survey/output/cybernet_targets_resolved.csv \
  --fqdn-suffix example.local \
  --fqdn-suffix corp.example.local
```

Review:

```bash
start survey/output/cybernet_dns_subnet_summary.csv
```

## 3. Optional: targeted Nmap against resolved Cybernet IPs

Only run this if approved for the resolved IPs.

```bash
nmap -sn -n --reason \
  -iL survey/output/cybernet_resolved_ips.txt \
  -oA logs/nmap/cybernet_dns_ip_discovery
```

Export Nmap evidence:

```bash
python survey/sas-nmap-evidence-export.py \
  --input logs/nmap/cybernet_dns_ip_discovery.xml \
  --output survey/output/nmap_identity_evidence_dns.csv
```

## 4. Optional: normalize AD computer export

Authorized AD export example:

```powershell
Get-ADComputer -Filter * -Properties DNSHostName,OperatingSystem,LastLogonDate,Enabled,Description |
  Select Name,DNSHostName,OperatingSystem,LastLogonDate,Enabled,Description,DistinguishedName |
  Export-Csv .\ad_computers.csv -NoTypeInformation
```

Normalize it:

```bash
python survey/sas-import-ad-computers.py \
  --input survey/input/ad_computers.csv \
  --output survey/output/ad_computers_normalized.csv
```

## 5. Optional: normalize DHCP lease export

Authorized DHCP export example:

```powershell
Get-DhcpServerv4Scope | ForEach-Object {
  Get-DhcpServerv4Lease -ScopeId $_.ScopeId
} | Select HostName,IPAddress,ClientId,AddressState,LeaseExpiryTime,ScopeId |
  Export-Csv .\dhcp_leases.csv -NoTypeInformation
```

Normalize it:

```bash
python survey/sas-import-dhcp-leases.py \
  --input survey/input/dhcp_leases.csv \
  --output survey/output/dhcp_leases_normalized.csv
```

## 6. Merge evidence into final Cybernet report

DNS-only:

```bash
python survey/sas-merge-cybernet-evidence.py \
  --manifest survey/output/cybernet_targets_resolved.csv \
  --dns survey/output/cybernet_dns_resolution_report.csv \
  --output survey/output/cybernet_master_presence_report.csv \
  --manual-review survey/output/cybernet_manual_review.csv
```

DNS + Nmap + AD + DHCP:

```bash
python survey/sas-merge-cybernet-evidence.py \
  --manifest survey/output/cybernet_targets_resolved.csv \
  --dns survey/output/cybernet_dns_resolution_report.csv \
  --nmap survey/output/nmap_identity_evidence_dns.csv \
  --ad survey/output/ad_computers_normalized.csv \
  --dhcp survey/output/dhcp_leases_normalized.csv \
  --output survey/output/cybernet_master_presence_report.csv \
  --manual-review survey/output/cybernet_manual_review.csv
```

Open reports:

```bash
start survey/output/cybernet_master_presence_report.csv
start survey/output/cybernet_manual_review.csv
```

## Status meanings

| Status | Meaning |
|---|---|
| `CONFIRMED_ON_NETWORK` | Nmap matched another source such as DNS, AD, or DHCP. |
| `CONFIRMED_BY_INFRASTRUCTURE` | DHCP matched DNS or AD. Strong evidence even without Nmap. |
| `NMAP_ONLY` | Nmap saw it, but no DNS/AD/DHCP confirmation was supplied. |
| `DHCP_ONLY` | DHCP lease exists, but no DNS/AD/Nmap confirmation was supplied. |
| `DNS_ONLY` | DNS resolves, but no live/network/inventory confirmation was supplied. |
| `AD_ONLY` | AD object exists, but no DNS/DHCP/Nmap confirmation was supplied. |
| `MANIFEST_ONLY` | The device exists only in the manifest/tracker input. |
| `REVIEW_CONFLICT` | Evidence conflicts, such as DNS and DHCP IPs not overlapping or MAC mismatches. |

## Practical interpretation

A one-subnet Nmap scan answering "not found" only means the device was not seen from that subnet. This workflow asks better questions:

- Does DNS know the hostname?
- Which IP/subnet does DNS point to?
- Does DHCP know the hostname or MAC?
- Does AD have a recent object?
- Did an approved targeted Nmap scan confirm the DNS/DHCP IP?
- Is the tracker stale or conflicting?

Use the manual review CSV for technician follow-up, AD/Vision checks, or site/team escalation.
