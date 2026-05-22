# SysAdminSuite Nmap Baseline Module

## Purpose

`scripts/sas_nmap_baseline.sh` is the first Nmap-backed baseline module for SysAdminSuite.

It follows:

```text
Recon -> Decide -> Act -> Log -> Export
```

The module is intentionally conservative. It is for authorized internal IT diagnostics, not broad scanning, stealth scanning, vulnerability testing, brute-force behavior, or evasion.

## Files

```text
scripts/sas_nmap_baseline.sh
scripts/sas_classify_nmap_baseline.sh
```

## Baseline Examples

Local-only baseline:

```bash
bash scripts/sas_nmap_baseline.sh --scan-mode local-only
```

Dry run against localhost:

```bash
bash scripts/sas_nmap_baseline.sh --target 127.0.0.1 --scan-mode common-ports --dry-run
```

Printer-oriented probe:

```bash
bash scripts/sas_nmap_baseline.sh --target 10.10.10.25 --scan-mode printer-ports
```

Workstation-oriented probe:

```bash
bash scripts/sas_nmap_baseline.sh --target WMH300OPR001 --scan-mode workstation-ports
```

Small explicit CIDR ping discovery:

```bash
bash scripts/sas_nmap_baseline.sh --target 10.10.10.0/29 --scan-mode ping-only --allow-subnet --max-targets 8
```

## Classifier Example

After a baseline run completes:

```bash
bash scripts/sas_classify_nmap_baseline.sh \
  --run-dir "$USERPROFILE/SysAdminSuite/Runs/<RUN_FOLDER>"
```

The classifier reads a completed run folder. It does not run scans or mutate targets.

## Scan Modes

| Mode | Behavior |
|---|---|
| `local-only` | Collect local baseline only. Does not run Nmap. |
| `ping-only` | Uses `nmap -sn` for host discovery. |
| `common-ports` | Checks a small workstation/printer/admin set. |
| `printer-ports` | Checks 80, 443, 515, 631, 9100, 161. |
| `workstation-ports` | Checks 135, 139, 445, 3389, 5985, 5986. |
| `custom-ports` | Uses `--ports`. |

## Guardrails

- No `-A`
- No vulnerability scripts
- No brute-force scripts
- No stealth defaults
- No spoofing
- No decoys
- No IDS/firewall evasion flags
- No broad subnet scan by default
- CIDR targets require `--allow-subnet`
- CIDR broader than `/29` is blocked
- Explicit target cap defaults to `16`

## Output Layout

Baseline runs write to:

```text
$USERPROFILE/SysAdminSuite/Runs/SAS_NMAP_BASELINE_<HOSTNAME>_<TIMESTAMP>/
```

Key outputs:

```text
logs/events.jsonl
logs/trace.log
raw/local/
raw/nmap_<target>.nmap
raw/nmap_<target>.xml
exports/run_context.env
exports/scan_index.csv
exports/open_ports_summary.csv
exports/baseline_report.md
exports/baseline_report.json
```

Classifier outputs:

```text
exports/classifications.csv
exports/recommended_actions.md
logs/classifier_events.jsonl
logs/classifier_trace.log
```

## Classifier Signals

| Signal | Advisory Classification |
|---|---|
| `9100/tcp open` | possible printer or print device |
| `515` or `631` open | possible print service |
| `445/tcp open` | possible Windows workstation or server |
| `3389/tcp open` | possible Windows remote access target |
| `5985` or `5986` open | possible Windows management endpoint |
| `80` or `443` open only | possible web admin or appliance endpoint |
| no open ports | inconclusive; validate network/VLAN/firewall/DNS |

The classifier is advisory only. It does not prove device role, ownership, authorization, or health.

## Next Layer

```text
classification -> approved next workflow -> dry-run mutation plan
```

No mutation belongs in this baseline module.
