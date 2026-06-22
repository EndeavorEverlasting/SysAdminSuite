# Survey Tools

This directory contains Bash-first survey tooling for SysAdminSuite.

## Primary Field Tutorial: Cybernet / Neuron Network Survey

The current priority tutorial for field technicians is:

- [`../START-HERE-CYBERNET-NEURON-SURVEY.md`](../START-HERE-CYBERNET-NEURON-SURVEY.md)
- [`../docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md`](../docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md)

Use that path when a technician needs to survey an approved site subnet for Cybernet or Neuron targets from deployment documentation. The workflow is:

1. Copy approved local target CSVs into `survey/input/`.
2. Run the Bash runtime smoke test.
3. Normalize targets with `sas-survey-targets.sh`.
4. Capture local network context with `sas-device-snapshot.sh`.
5. Run conservative approved Nmap discovery.
6. Resolve Nmap output with `sas-resolve-nmap-evidence.sh`.
7. Package local evidence from `survey/output/`, `survey/artifacts/`, and `logs/nmap/`.

Field rule: this is read-only asset discovery. Do not commit live CSVs, scan output, dashboards, ZIPs, hostnames, MACs, serials, or site evidence.

## Status

- **Northwell workflows:** Bash-first.
- **Expected shell:** Bash on Windows, usually Git Bash or MSYS2 Bash.
- **PowerShell equivalents:** deprecated for Northwell, preserved elsewhere as legacy/reference tooling.
- **Default agent behavior:** add new survey functionality here or in another Bash-oriented path, not under `GetInfo/*.ps1`.

## Runtime Smoke Test

Run this first on a new workstation:

```bash
bash tests/bash/smoke-bash-windows-runtime.sh
```

Expected result:

```text
Smoke test passed. Bash-on-Windows runtime looks usable.
```

## Field Snapshot Tools

### Local Device Snapshot

Use this when a technician needs a quick read-only snapshot of the workstation.

```bash
bash survey/sas-device-snapshot.sh
```

Optional:

```bash
bash survey/sas-device-snapshot.sh --output-dir logs/nsuh
bash survey/sas-device-snapshot.sh --output-file logs/device_survey.txt
bash survey/sas-device-snapshot.sh --no-log
```

The snapshot captures:

- hostname
- current user
- IP configuration
- MAC addresses
- ARP table
- route table
- network interface summary
- IP interface configuration

### Neuron / Cybernet Environment Survey

Use this when a technician needs to probe local network context and one target hostname or IP.

```bash
bash survey/sas-neuron-environment.sh --target <hostname-or-ip>
```

Examples:

```bash
bash survey/sas-neuron-environment.sh --target WNH270OPR123
bash survey/sas-neuron-environment.sh --target 10.10.10.25 --output-dir logs/nsuh
```

The environment survey captures:

- local hostname
- current user
- local IP configuration
- local MAC addresses
- ping result for target
- DNS lookup for target
- ARP table after probe
- route table
- interface summary

## Target Manifest Tool

```bash
./survey/sas-survey-targets.sh
```

This tool prepares a normalized target manifest for Cybernet and Neuron surveys.

It accepts:

- typed target arguments
- TXT files
- CSV files
- JSON files
- optional inventory CSVs to resolve serial/MAC-only targets to hostnames

It outputs:

- CSV manifest with normalized identifiers
- resolved hostname where possible
- original source trace for each target

## Example: Typed Targets

```bash
./survey/sas-survey-targets.sh \
  --device-type Cybernet \
  WMH300OPR001 \
  00:11:22:33:44:55 \
  ABC123SERIAL \
  --output ./survey/output/cybernet_targets.csv
```

## Example: CSV Input with Inventory Resolution

```bash
./survey/sas-survey-targets.sh \
  --device-type Neuron \
  --csv ./survey/input/neuron_targets.csv \
  --inventory ./survey/input/known_devices.csv \
  --output ./survey/output/neuron_targets_resolved.csv
```

## Accepted CSV Columns

The parser accepts flexible column names so field data does not have to be perfect.

| Meaning | Accepted column names |
|---|---|
| Generic identifier | `Identifier`, `Target`, `KnownIdentifier`, `LookupValue` |
| Hostname | `HostName`, `Hostname`, `Host`, `ComputerName`, `Computer`, `Name` |
| Serial | `Serial`, `SerialNumber`, `ServiceTag`, `AssetSerial` |
| MAC | `MACAddress`, `MacAddress`, `MAC`, `Mac`, `EthernetMAC`, `WifiMAC` |
| Device type | `DeviceType`, `Type`, `DeviceClass` |

## Accepted JSON Shapes

```json
[
  "WMH300OPR001",
  "00:11:22:33:44:55",
  "ABC123SERIAL"
]
```

```json
{
  "targets": [
    {
      "HostName": "WMH300OPR001",
      "SerialNumber": "ABC123SERIAL",
      "MACAddress": "00:11:22:33:44:55",
      "DeviceType": "Cybernet"
    }
  ]
}
```

## Output Columns

| Column | Meaning |
|---|---|
| `Identifier` | Original typed or file-provided value |
| `IdentifierType` | `HostName`, `Serial`, `MAC`, or `Unknown` |
| `DeviceType` | `Cybernet`, `Neuron`, `Workstation`, or `Unknown` |
| `HostName` | Normalized hostname when known or resolved |
| `Serial` | Normalized serial number when known |
| `MACAddress` | Normalized MAC address when known |
| `Source` | Where the target came from, including inventory resolution notes |

## Nmap Evidence Resolver

Use this after an approved Nmap run already exists. This wrapper does not run Nmap. It converts existing Nmap XML or normal output into resolver evidence, then compares it with the target manifest.

```bash
bash survey/sas-resolve-nmap-evidence.sh \
  --manifest survey/output/cybernet_targets_resolved.csv \
  --nmap-output logs/nmap/site_discovery_dns.xml \
  --nmap-format xml \
  --output survey/output/site_cybernet_nmap_identity_resolver.csv \
  --dashboard survey/output/site_cybernet_nmap_identity_resolver.html
```

## Field Rule

Do not replace these with ad hoc PowerShell or Linux commands during field work.

If a new probe is needed, add it to:

- `docs/COMMAND_CATALOG.md`
- the relevant Bash script
- a smoke test when applicable

## Next Build Direction

This script currently normalizes and resolves targets. The next Bash layer should perform the actual survey/probe behavior behind clear subcommands, for example:

```bash
sas-survey collect --manifest ./survey/output/neuron_targets_resolved.csv
sas-survey report  --manifest ./survey/output/neuron_targets_resolved.csv
```

Keep this separation. A clean manifest first. Probe second. Report third. No mud wrestling.

## Auto-logon Workstation Assessment (remote batch)

Read-only remote assessment for shared-workstation auto-logon posture. Primary output is HTML (`--dashboard`); CSV is for downstream tools.

```bash
bash survey/sas-assess-autologon.sh \
  --manifest ./survey/output/wbs_targets.csv \
  --preflight \
  --ad-live \
  --output survey/output/autologon_assessment.csv \
  --dashboard survey/output/autologon_dashboard.html \
  --open
```

Contract fixture / CI dry-run:

```bash
bash survey/sas-assess-autologon.sh \
  --manifest survey/fixtures/autologon_manifest.sample.csv \
  --fixture-dry-run \
  --output survey/output/autologon_assessment.csv \
  --dashboard survey/output/autologon_dashboard.html
```

See `docs/AUTOLOGON_ASSESSMENT.md` for lifecycle rules, OverallStatus values, and evidence columns.
