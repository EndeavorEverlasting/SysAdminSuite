# Neuron MAC/Subnet Probe Lane

## Purpose

Third parties may rename Neurons after configuration, making hostname-based probing unreliable.

This lane treats Neuron hostname as a weak hint and uses stronger identifiers first:

1. Expected MAC
2. Expected serial
3. Hostname

## Current implementation

| File | Role |
|---|---|
| `GetInfo/Convert-DeploymentTrackerToTargets.ps1` | Extracts tracked Neuron hosts, MACs, serials, site, room, and notes from the tracker |
| `GetInfo/Config/NeuronTargets.unresolved.csv` | Contains useful Neuron MAC/serial leads when hostnames are missing or unreliable |
| `survey/sas-match-neurons-from-nmap.py` | Matches expected Neuron MACs against saved nmap XML evidence and creates a PowerShell-compatible target CSV |
| `deployment-audit/sas-render-neuron-nmap-dashboard.py` | Renders the Neuron MAC review CSV as a polished local HTML dashboard |
| `GetInfo/Get-NeuronNetworkInventory.ps1` | Uses the resolved IP or hostname target to query inventory evidence and reconcile observed MAC/serial |
| `deployment-audit/tests/test_neuron_nmap_matcher_contracts.sh` | Contract test for matcher output, review classifications, and dashboard rendering |

## Workflow

```text
Tracker workbook
  -> Convert-DeploymentTrackerToTargets.ps1
  -> NeuronTargets.unresolved.csv
  -> approved subnet nmap XML artifact
  -> sas-match-neurons-from-nmap.py
  -> neuron_resolved_targets.csv
  -> neuron_probe_review.csv
  -> optional Neuron MAC/Subnet dashboard
  -> Get-NeuronNetworkInventory.ps1
```

## Example commands

Generate tracker-derived Neuron targets:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\GetInfo\Convert-DeploymentTrackerToTargets.ps1 `
  -WorkbookPath "C:\Path\To\DeploymentTracker.xlsx" `
  -WorksheetName "12 - Device_Configuration" `
  -DeviceType Neuron `
  -OutputPath .\GetInfo\Config\NeuronTargets.csv
```

Run approved nmap host discovery and preserve XML evidence:

```bash
nmap -sn 192.0.2.0/24 -oX survey/artifacts/site_neuron_discovery.xml -oN survey/artifacts/site_neuron_discovery.nmap
```

Match unresolved Neuron MACs to nmap evidence and render the review dashboard:

```bash
python3 survey/sas-match-neurons-from-nmap.py \
  --manifest GetInfo/Config/NeuronTargets.unresolved.csv \
  --nmap-xml survey/artifacts/site_neuron_discovery.xml \
  --output survey/output/neuron_resolved_targets.csv \
  --review-output survey/output/neuron_probe_review.csv \
  --dashboard survey/output/neuron_probe_review.html
```

Dashboard-only rerender from an existing review CSV:

```bash
python3 deployment-audit/sas-render-neuron-nmap-dashboard.py \
  --input survey/output/neuron_probe_review.csv \
  --output survey/output/neuron_probe_review.html
```

Feed resolved targets into the Neuron inventory lane:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\GetInfo\Get-NeuronNetworkInventory.ps1 `
  -ListPath .\survey\output\neuron_resolved_targets.csv `
  -SkipPing
```

## Dashboard review posture

The dashboard is a local operator artifact. It is meant to make review faster, not to replace evidence.

It shows:

- total rows
- resolved-by-MAC count
- MAC conflict count
- serial-only count
- review count
- per-site counts
- grouped, filterable review tables
- evidence cards for resolved and conflicting identities

Do not commit generated dashboards or CSVs containing real hostnames, MACs, serials, locations, or tracker data.

## Classification

| Status | Meaning |
|---|---|
| `MAC_MATCH_RESOLVED` | Expected MAC matched nmap XML evidence and produced a usable target |
| `MAC_NOT_FOUND_IN_NMAP` | Expected MAC was not seen in supplied nmap artifacts |
| `MAC_CONFLICT_MULTIPLE_IPS` | Same MAC appeared on multiple IPs, requiring manual review |
| `SERIAL_ONLY_NO_MAC` | Serial exists, but no MAC was available for nmap matching |
| `NO_USABLE_IDENTIFIER` | No MAC or serial was available; row cannot be probed safely |

## Rules

- Do not discard unresolved Neuron rows. Rows with MAC or serial but no host are leads.
- nmap host discovery may identify current IPs and MACs.
- nmap does not prove BIOS serial by itself.
- Serial-only rows require AD, WMI after IP resolution, vendor evidence, or manual review.
- Prefer saved nmap XML artifacts over repeated live probing.
- Generated artifacts may contain operational identifiers and should not be committed.
- Hostname is a hint, not identity. For this lane, MAC is the network anchor.

## Operating principle

Hostname is a label.
MAC is network evidence.
Serial is hardware evidence.

Use each identifier only where the evidence source can actually observe it.
