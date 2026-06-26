# Survey Tools

This directory contains Bash-first survey tooling for SysAdminSuite.

## Primary Field Tutorial: Cybernet / Neuron Network Survey

**Default front door:** double-click [`../START-HERE-SysAdminSuite-Dashboard.bat`](../START-HERE-SysAdminSuite-Dashboard.bat) and use **Start Cybernet Survey** in the dashboard. On first run the launcher may **automatically prepare (build) the dashboard app** before opening the browser; field users do not run any command by hand. Machines **without the .NET SDK** should use the dashboard field release package ([`../docs/DASHBOARD_FIELD_RELEASE.md`](../docs/DASHBOARD_FIELD_RELEASE.md)), not a source clone. CLI is available for specific advanced survey use cases only.

The current priority tutorial for field technicians is:

- [`../START-HERE-SysAdminSuite.md`](../START-HERE-SysAdminSuite.md) — what to double-click and what opens
- [`../START-HERE-CYBERNET-NEURON-SURVEY.md`](../START-HERE-CYBERNET-NEURON-SURVEY.md) — advanced CLI orchestrator path
- [`../docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md`](../docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md) — full step-by-step runbook

Use the CLI path below only when the dashboard or a lead explicitly asks for Bash orchestration. Start with the workflow diagram in `../START-HERE-CYBERNET-NEURON-SURVEY.md` when you need the one-page field path before the command details. Mermaid source: [`../docs/diagrams/cybernet-neuron-survey-flow.mmd`](../docs/diagrams/cybernet-neuron-survey-flow.mmd). The workflow is:

1. Copy approved local target CSVs into `survey/input/`.
2. Run the Bash runtime smoke test.
3. Run `sas-cybernet-subnet-survey.sh` modes (or individual scripts below).
4. Normalize targets with `sas-survey-targets.sh`.
5. Package local evidence from `survey/artifacts/` and `logs/nmap/`.

Field rule: this is read-only asset discovery. Do not commit live CSVs, scan output, dashboards, ZIPs, hostnames, MACs, serials, or site evidence.

## Cybernet Subnet Survey Runner

Bash-first orchestrator for the urgent field path. Read-only. No endpoint mutation.

```bash
bash survey/sas-cybernet-subnet-survey.sh --site nsuh --mode local-context-only
bash survey/sas-cybernet-subnet-survey.sh --site nsuh --mode dns-list-only --subnet-file survey/output/local_subnet_finder/nsuh_<run-id>/subnet_candidates.txt
bash survey/sas-cybernet-subnet-survey.sh --site nsuh --mode discover --cidr 10.10.10.0/24
bash survey/sas-cybernet-subnet-survey.sh --site nsuh --mode resolve-only --manifest survey/output/cybernet_targets_resolved.csv
bash survey/sas-cybernet-subnet-survey.sh --site nsuh --mode confirm-windows --host-file survey/output/cybernet_subnet_survey/nsuh_<run-id>/hosts/<cidr>_up.txt
bash survey/sas-cybernet-subnet-survey.sh --site nsuh --mode package-only --manifest survey/output/cybernet_targets_resolved.csv
```

| Mode | Purpose |
|---|---|
| `local-context-only` | Subnet finder + copy context to `logs/network_context/` |
| `dns-list-only` | `nmap -sL` DNS/list sanity (not host proof) |
| `discover` | Dual `nmap -sn` discovery (no-DNS + system-DNS) |
| `confirm-windows` | Narrow TCP/Naabu ports against a host file only |
| `resolve-only` | Manifest + Nmap XML via `sas-resolve-nmap-evidence.sh` |
| `package-only` | Bundle artifacts under `survey/artifacts/<site>_<run-id>/` |

Windows launcher: `survey\sas-cybernet-subnet-survey.cmd` (requires Git Bash `bash` on PATH).

Contract test:

```bash
bash Tests/bash/test-cybernet-subnet-survey-contracts.sh
bash Tests/bash/test_cybernet_detect_contracts.sh
bash Tests/bash/test_naabu_pipeline_contracts.sh
bash Tests/bash/test_naabu_package_contracts.sh
bash Tests/bash/test_packet_probe_contracts.sh
bash Tests/bash/test_repo_naabu_doctrine_conformance.sh
```

## Cybernet Subnet Location Inference Map

Read-only enrichment: maps approved hostname/IP CSV evidence to likely site subnets. **Not** the subnet survey runner above — no Naabu, Nmap, ping sweeps, or host discovery.

```bash
bash survey/sas-cybernet-subnet-location-map.sh \
  --identity-csv survey/output/ad_computers_normalized.csv \
  --tracker-csv survey/output/cybernet_alejandro_targets.csv \
  --prefix-config Config/cybernet_location_prefixes.example.csv \
  --output-prefix survey/output/cybernet_subnet_location \
  --html
```

Subnet/location inference narrows review scope; it does not authorize broader scanning by itself. The host evidence output includes serial-first fallback fields so hostname/IP/subnet clues never silently count as serial proof. Runbook: [`docs/CYBERNET_SUBNET_LOCATION_INFERENCE.md`](../docs/CYBERNET_SUBNET_LOCATION_INFERENCE.md).

Contract test:

```bash
bash Tests/bash/test-cybernet-subnet-location-contracts.sh
```

## Naabu CDN-Safe Pipeline

CDN/cloud-aware port confirmation using naabu `-ec -silent`. Auto-installs naabu to `bin/naabu.exe` from GitHub releases when missing.

```bash
bash survey/sas-run-naabu-pipeline.sh --site nsuh --profile keyports_cybernet_pipe \
  --list survey/fixtures/naabu_pipeline/targets.sample.txt \
  --out logs/nmap/nsuh_keyports.txt --pipe-followup

bash survey/sas-run-packet-probe.sh --site nsuh \
  --list survey/fixtures/naabu_pipeline/targets.sample.txt \
  --out logs/nmap/nsuh_packet_probe.json --dry-run

bash survey/sas-cybernet-subnet-survey.sh --site nsuh --mode confirm-windows \
  --confirm-tool naabu --host-file survey/output/cybernet_subnet_survey/nsuh_<run-id>/hosts/<cidr>_up.txt \
  --pipe-followup
```

Profiles are doctrine-defined in [`survey/naabu_profiles.json`](naabu_profiles.json) and generated into the runtime config [`Config/cybernet-naabu-profiles.json`](../Config/cybernet-naabu-profiles.json) via [`survey/sas-generate-naabu-runtime-profiles.sh`](sas-generate-naabu-runtime-profiles.sh). Default profile: `keyports_cybernet_json`. Field guide: [`docs/NAABU_CYBERNET_PROFILES.md`](../docs/NAABU_CYBERNET_PROFILES.md). Doctrine: [`docs/LOW_NOISE_SURVEY_DOCTRINE.md`](../docs/LOW_NOISE_SURVEY_DOCTRINE.md). Go normalizer: [`probe/packet-expenditure/README.md`](../probe/packet-expenditure/README.md).

## Cybernet-detect enrichment

Canonical local enrichment for naabu `-silent` host:port pipelines:

```bash
naabu -list logs/targets/nsuh_confirm_hosts.txt -silent -ec \
  | bash survey/sas-cybernet-detect.sh --site nsuh --stdin --jsonl \
  > logs/nmap/nsuh_<runid>_cybernet_detect.jsonl
```

Contract test: `bash Tests/bash/test_cybernet_detect_contracts.sh`

See [`../START-HERE-CYBERNET-NEURON-SURVEY.md`](../START-HERE-CYBERNET-NEURON-SURVEY.md) for the correlated `--run-id` example.

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

## Fast Subnet Finder

Use this when you need the likely local CIDRs from the connected admin workstation before the broader Cybernet / Neuron workflow.

```bash
bash survey/sas-find-local-subnets.sh --site <site-code>
```

Example:

```bash
bash survey/sas-find-local-subnets.sh --site nsuh
```

The finder writes a timestamped run under:

```text
survey/output/local_subnet_finder/<site>_<timestamp>/
```

Key outputs:

| File | Purpose |
|---|---|
| `subnet_candidates.txt` | Plain candidate CIDR list for the next approved discovery step |
| `subnet_candidates.csv` | Candidate CIDRs with adapter/source notes |
| `context/ipconfig_all.txt` | Local adapter configuration evidence |
| `context/route_print.txt` | Local route table evidence |
| `context/arp_initial.txt` | Starting ARP table evidence |
| `SUMMARY.md` | Human-readable run summary |

You can also normalize explicit approved CIDRs without relying on local adapter detection:

```bash
bash survey/sas-find-local-subnets.sh \
  --site nsuh \
  --cidr 10.10.10.0/24 \
  --cidr 10.10.11.0/24
```

Contract test:

```bash
bash tests/bash/test-local-subnet-finder-contracts.sh
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
