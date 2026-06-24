# AD Cybernet Export Contract

This contract defines the minimum CSV shape for **authorized offline AD computer exports** consumed by `survey/sas-ad-reconcile.sh` and `survey/sas-import-ad-computers.py`.

No live AD queries are performed by these tools. An administrator produces the export through approved directory tooling and places it in `logs/targets/` or passes `--ad-csv` explicitly.

## Required semantics

Each row represents one AD computer object. The reconcile tooling normalizes flexible column names but expects these meanings:

| Field | Accepted column names | Required | Notes |
|---|---|---|---|
| Short hostname | `Name`, `HostName`, `Hostname`, `ComputerName`, `CN` | Yes | Normalized to uppercase short name |
| DNS hostname | `DNSHostName`, `DNS Host Name`, `FQDN` | Recommended | Empty values bucket to `ad_missing_dns.csv` |
| Enabled flag | `Enabled`, `AccountEnabled`, `ADEnabled` | Recommended | `false` / `0` → `ad_disabled.csv` |
| Last logon | `LastLogonDate`, `LastLogonTimestamp`, `LastLogon`, `LastSeen` | Recommended | Used for `ad_stale.csv` when older than `--stale-days` |
| Operating system | `OperatingSystem`, `OS` | Optional | Carried into normalized output |
| Description | `Description`, `Comment`, `Notes` | Optional | Useful for Cybernet serial hints in downstream tooling |
| Distinguished name | `DistinguishedName`, `DN`, `CanonicalName` | Optional | Audit trail only |

## Example export command (admin workstation)

PowerShell is used **only at export time** by authorized admins. The reconcile lane does not invoke it.

```powershell
Get-ADComputer -Filter {Name -like 'CYB*'} -Properties DNSHostName,OperatingSystem,LastLogonDate,Enabled,Description |
  Select-Object Name,DNSHostName,OperatingSystem,LastLogonDate,Enabled,Description,DistinguishedName |
  Export-Csv .\logs\targets\ad_cybernet_computers.csv -NoTypeInformation
```

## Synthetic fixture (committed)

Smoke tests use `survey/fixtures/ad_registered_cybernet.sample.csv` with hostnames `CYBTEST001`, `CYBTEST002`, and `WNH000TEST001` only. No live Northwell identifiers.

## Normalized output columns

`ad_registered_normalized.csv` always uses:

```text
HostName,DNSHostName,ADStatus,Enabled,OperatingSystem,LastLogonDate,Description,DistinguishedName,SourceFile,PopulationAuthority,ReconcileBucket
```

- `PopulationAuthority` is always `ad_registered`.
- `ReconcileBucket` is assigned during reconcile (`registered`, `disabled`, `stale`, `missing_dns`, `duplicate`, etc.).

## Supplemental evidence CSVs (optional)

### Manifest / tracker evidence (`--evidence-csv`)

| Meaning | Accepted columns |
|---|---|
| Hostname | `HostName`, `Hostname`, `ComputerName`, `Target` |
| Device type | `DeviceType`, `Type` |
| Serial | `Serial`, `SerialNumber`, `ExpectedCybernetSerial` |
| Source | `Source`, `SourceFile` |

### Network reachability evidence (`--network-csv`)

Pre-validated reachability only. Produced by approved Naabu/Nmap pipelines — **not** by `sas-ad-reconcile.sh`.

| Meaning | Accepted columns |
|---|---|
| Hostname | `HostName`, `Hostname`, `Target` |
| Reachability | `Reachability`, `Status`, `PingStatus` |
| Source | `Source` |

Values containing `reach`, `up`, `open`, or `success` (case-insensitive) classify as reachable. Values containing `silent`, `down`, `unreach`, `timeout`, or `fail` classify as silent.

### Live serial evidence (`--serial-csv`)

| Meaning | Accepted columns |
|---|---|
| Hostname | `HostName`, `Hostname`, `Target`, `ObservedHostName` |
| Serial | `Serial`, `ObservedSerial`, `ResolvedSerial` |
| Probe status | `ProbeStatus`, `SerialProbeStatus`, `serial_probe_status` |
| Source | `Source`, `EvidenceSource` |

Statuses containing `match`, `confirm`, or `found` → matched. Statuses containing `unavail`, `missing`, `fail`, or `no_match` → unavailable.

## Population authority rule

When AD and supplemental evidence disagree:

1. AD registered population defines membership.
2. Evidence-only rows are flagged in `evidence_only.csv` for manual review.
3. AD-only rows remain valid registered targets until evidence proves otherwise.

## Dashboard ingestion

Drop `ad_registered_normalized.csv`, `ad_evidence_matches.csv`, or bucket CSVs into the dashboard. Files are detected as parser type `ad-registered-population`.
