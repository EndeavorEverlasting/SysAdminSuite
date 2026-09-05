# Survey Tools

This directory contains survey tooling for SysAdminSuite. Network scanner/orchestrator lanes are Bash-first; bounded Windows metadata identity may use repository-owned Windows PowerShell when that is the canonical surface for the use case.

## Primary Field Tutorial: Cybernet / Neuron Network Survey

**Default front door:** double-click [`../START-HERE-SysAdminSuite-Dashboard.bat`](../START-HERE-SysAdminSuite-Dashboard.bat) and use **Start Cybernet Survey** in the dashboard. On first run the launcher may **automatically prepare the dashboard app** before opening the browser; field users do not run any command by hand. Source clones can bootstrap official Microsoft .NET dependencies when downloads and administrator approval are available. Locked-down PCs should use the dashboard field release package ([`../docs/DASHBOARD_FIELD_RELEASE.md`](../docs/DASHBOARD_FIELD_RELEASE.md)). CLI is available for specific advanced survey use cases only.

The current priority tutorial for field technicians is:

- [`../START-HERE-SysAdminSuite.md`](../START-HERE-SysAdminSuite.md) — what to double-click and what opens
- [`../START-HERE-CYBERNET-NEURON-SURVEY.md`](../START-HERE-CYBERNET-NEURON-SURVEY.md) — advanced CLI orchestrator path
- [`../docs/CYBERNET_LOW_NOISE_CANARY.md`](../docs/CYBERNET_LOW_NOISE_CANARY.md) — professional missing-Cybernet population → PC-signature → metadata funnel
- [`../docs/SURVEY_LANES.md`](../docs/SURVEY_LANES.md) — manifest lane vs subnet lane; serial vs hostname vs MAC
- [`../docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md`](../docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md) — full step-by-step runbook

Use the CLI path below only when the dashboard or a lead explicitly asks for orchestration. Start with the workflow diagram in `../START-HERE-CYBERNET-NEURON-SURVEY.md` when you need the one-page field path before the command details. Mermaid source: [`../docs/diagrams/cybernet-neuron-survey-flow.mmd`](../docs/diagrams/cybernet-neuron-survey-flow.mmd). The generic orchestration workflow is:

1. Copy approved local target CSVs into `survey/input/`.
2. Run the Bash runtime smoke test when using a Bash scanner lane.
3. Run `sas-cybernet-subnet-survey.sh` modes (or individual scripts below) only when that broader lane is actually required.
4. Normalize targets with `sas-survey-targets.sh`.
5. Package local evidence from `survey/artifacts/` and `logs/nmap/`.

Field rule: this is read-only asset discovery. Do not commit live CSVs, scan output, dashboards, ZIPs, hostnames, MACs, serials, or site evidence.

## Professional missing-Cybernet hunt

Do **not** start a missing-Cybernet hunt with the generic seven-port profile or a mixed subnet scan merely because those tools exist. Prefer an approved computer population from AD, tracker/inventory, prior evidence, DNS/DHCP correlation, CMDB/SCCM, or endpoint inventory.

### Stage 1 — minimal PC-signature scan

Operator terminal: **Git Bash / Bash-on-Windows**.

```bash
bash survey/sas-run-windows-pc-signature.sh --list targets/local/approved_computers.txt
```

This dedicated wrapper:

- uses only TCP 135 and 445;
- sets Naabu retries to `0` and default rate to `50`;
- delegates protected-network admission to the canonical PowerShell gate, including supported DomainAuthenticated non-Wi-Fi VPN/LAN;
- performs no metadata query;
- promotes only hosts where both 135 and 445 were observed;
- keeps evidence local and ignored.

Web-only access points, printers exposing HTTP/HTTPS/9100, RPC-only responders, and SMB-only responders do not graduate to metadata candidacy.

### Stage 2 — bounded workstation metadata canary

Operator terminal: **Windows PowerShell**.

```powershell
sas cybernet canary HOST01 HOST02
```

The canary accepts at most five explicit candidates. It requires both 135 and 445, then creates at most one read-only DCOM/CIM session. `Win32_OperatingSystem.ProductType` must equal `1` before manufacturer/model/BIOS serial are queried. A server/DC or unresolved OS class stops before hardware metadata.

This PowerShell canary is a current Northwell survey/identity surface. It is **not** a deprecated equivalent of a Bash scanner. Bash owns the packet-oriented signature lane; Windows PowerShell owns the bounded metadata identity lane.

Model + serial still require comparison with the approved Cybernet hardware reference before `CONFIRMED_CYBERNET` may be claimed.

## Cybernet Subnet Survey Runner

Bash-first orchestrator for an explicitly approved subnet-discovery field path. Read-only. No endpoint mutation. It is a broader fallback when approved computer population sources are incomplete; it is not the preferred first-pass missing-Cybernet hunt.

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

Profiles are doctrine-defined in [`survey/naabu_profiles.json`](naabu_profiles.json) and generated into the runtime config [`Config/cybernet-naabu-profiles.json`](../Config/cybernet-naabu-profiles.json) via [`survey/sas-generate-naabu-runtime-profiles.sh`](sas-generate-naabu-runtime-profiles.sh). Default generic profile: `keyports_cybernet_json`. Professional missing-Cybernet hunting deliberately selects `windows_pc_signature_json` instead. Field guide: [`docs/NAABU_CYBERNET_PROFILES.md`](../docs/NAABU_CYBERNET_PROFILES.md). Doctrine: [`docs/LOW_NOISE_SURVEY_DOCTRINE.md`](../docs/LOW_NOISE_SURVEY_DOCTRINE.md). Go normalizer: [`probe/packet-expenditure/README.md`](../probe/packet-expenditure/README.md).

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

- **Network scanner/orchestrator lanes:** Bash-first on Windows, usually Git Bash or MSYS2 Bash.
- **Professional Cybernet hardware-metadata canary:** Windows PowerShell through the installed `sas cybernet canary` front door.
- **PowerShell posture:** active where it is the repository-owned identity/preflight surface; do not globally label PowerShell deprecated.
- **Default agent behavior:** select the tracked runtime by use case. Do not recreate scanner behavior ad hoc in PowerShell, and do not replace the current metadata canary with an unrelated Bash probe.

## Runtime Smoke Test

Run this first on a new workstation before a Bash scanner/orchestrator lane:

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

Do not replace tracked scanner or identity surfaces with ad hoc PowerShell, Bash, or Linux commands during field work. Use the repository-owned runtime for the lane:

- Bash wrapper/profile for packet-oriented network survey;
- Windows PowerShell `sas cybernet canary` for bounded workstation hardware metadata.

If a new probe is needed, add it to:

- `docs/COMMAND_CATALOG.md`
- the relevant tracked script/launcher
- a smoke or contract test when applicable

## Next Build Direction

Future survey composition should continue to hide packet and identity complexity behind clear registered subcommands rather than asking technicians to reconstruct probes by hand.
