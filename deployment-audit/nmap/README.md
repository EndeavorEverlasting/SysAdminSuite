# Cybernet / Neuron Nmap Target Audit

This tool avoids PowerShell entirely. It uses the deployment workbook as the source of truth, creates a unique Nmap target list, detects duplicate identity records by MAC address or serial number, and can match Nmap XML scan results back to the source inventory.

## Why this exists

Some Northwell-managed endpoints block PowerShell. This workflow uses:

- `nmap` for host discovery / probe output
- Python stdlib only for workbook parsing, duplicate analysis, and Nmap XML matching
- `.cmd` / `.sh` launchers instead of `.ps1`

## Inputs

Expected workbook sheet: `Deployments`

Target columns:

- `Neuron IP`
- `Neuron Hostname`
- `Cybernet Hostname`

Identity columns:

- `Neuron MAC`
- `Cybernet MAC`
- `Cybernet Serial`
- `Neuron S/N`
- `Anesthesia S/N`
- `Medical Device S/N`
- `Dialysis S/N`

## Outputs

The audit writes the following files under `output/cybernet-nmap-audit/`:

- `targets.txt` — unique target list for `nmap -iL`
- `unique_targets.csv` — normalized inventory extracted from the workbook
- `duplicate_macs.csv` — rows sharing the same normalized MAC across different source rows
- `duplicate_serials.csv` — rows sharing the same normalized serial across different source rows
- `nmap-discovery.xml` — Nmap host discovery output, when the runner invokes Nmap
- `nmap_probe_matches.csv` — Nmap XML matched back to source inventory
- `audit_summary.json` — counts and output locations

Repeated serial values inside the same source row are ignored as duplicates. A value is considered a duplicate only when it appears across multiple source rows.

## Windows usage, no PowerShell

```bat
cd deployment-audit\nmap
run-cybernet-nmap.cmd "C:\secure-input\cybernet 5.21.xlsx"
```

The launcher first creates `targets.txt`, then runs:

```bat
nmap -sn -n --reason -iL "output\cybernet-nmap-audit\targets.txt" -oX "output\cybernet-nmap-audit\nmap-discovery.xml"
```

Then it parses the Nmap XML and produces duplicate/match reports.

## Manual two-step usage

Create targets and duplicate reports:

```bat
python cybernet_target_audit.py --source-xlsx "C:\secure-input\cybernet 5.21.xlsx" --out-dir output\cybernet-nmap-audit
```

Run Nmap:

```bat
nmap -sn -n --reason -iL output\cybernet-nmap-audit\targets.txt -oX output\cybernet-nmap-audit\nmap-discovery.xml
```

Match the Nmap probe back to inventory:

```bat
python cybernet_target_audit.py --source-xlsx "C:\secure-input\cybernet 5.21.xlsx" --out-dir output\cybernet-nmap-audit --nmap-xml output\cybernet-nmap-audit\nmap-discovery.xml --fail-on-duplicates
```

## Notes and limits

Nmap can usually report endpoint MAC addresses only on the same Layer 2 network/subnet because MAC discovery depends on ARP or local link-layer visibility. Across routed subnets, Nmap may only see the router/firewall MAC or no MAC at all.

Nmap does not normally return BIOS/device serial numbers for Windows endpoints without authenticated management protocols. Serial duplicate detection therefore comes from the source workbook inventory, while Nmap confirms reachability and observed MAC/host identity when available.

Do not commit real Northwell inventory workbooks, Nmap XML, MAC addresses, serials, or generated output reports to the public repo.
