# Cybernet XLSX Target Ingestion

Read-only, offline ingester that converts Alejandro-style Cybernet workbooks plus optional enrichment trackers into the normalized survey manifest schema used by SysAdminSuite Bash tooling.

## Targets intake doctrine

| Location | Role |
|----------|------|
| `targets/` | Official tracked intake hub (docs, schemas, sanitized fixtures only) |
| `targets/local/` | Preferred **gitignored** local intake beside the hub |
| `logs/targets/` | Preserved historical local evidence — **do not delete, move, or commit** |
| `survey/input/` | Runtime staging (gitignored) |
| `survey/output/` | Generated manifests and reports (gitignored) |

- The ingester reads **explicit workbook paths** wherever they live locally.
- You do **not** need to migrate existing `logs/targets/` files; point `--workbook` and `--enrichment` at their current paths.
- Outputs are target **manifests**, not network evidence. Do not treat them as proof of reachability.

## Prerequisites

- Python 3 with `openpyxl` (`pip install openpyxl`)
- Git Bash or MSYS2 Bash on Windows (wrapper is Bash-first)

## Primary workbook (Alejandro list)

Expected sheets:

| Sheet pattern | Columns | Notes |
|---|---|---|
| `AKBAR WAVE …` | A = serial | Serial-only wave rows |
| `PO …` | A = hostname, B = serial | Blank rows skipped |

## Enrichment workbooks (optional, repeatable)

Recognized sheets:

| Sheet | Purpose |
|---|---|
| `Deployments` | Cybernet hostname, serial, MAC from deployment tracker |
| `SSUH Configs` | Configured Cybernet / Neuron identity pairs |
| `configured cybernets*` | Hostname-centric configured Cybernet rows |
| `CDW Stock` | Serial numbers from stock tab |
| `SSUH Host` | Hostname list (column A) |
| `Neuron Cybernet` | PC name + Cybernet serial (+ Neuron MAC when present) |

Pass each enrichment file with `--enrichment`. The ingester merges by normalized serial or hostname.

## Command

Example using ignored local intake under `targets/local/` (preferred for new work):

```bash
bash survey/sas-cybernet-xlsx-targets.sh \
  --workbook "targets/local/Cybernet sources/Alejandro's list of Cybernets.xlsx" \
  --enrichment "targets/local/Cybernet sources/Active Deployment Tracker 2026-05-17 (1).xlsx" \
  --enrichment "targets/local/Cybernet sources/ALL WAVE ANESTHESIA MACHINES (1).xlsx" \
  --output survey/output/cybernet_alejandro_targets.csv \
  --report survey/output/cybernet_alejandro_enrichment_report.csv \
  --gaps survey/output/cybernet_alejandro_gaps.csv \
  --device-type Cybernet
```

Historical local evidence under `logs/targets/` remains valid — pass those paths instead if you have not migrated:

```bash
bash survey/sas-cybernet-xlsx-targets.sh \
  --workbook "/path/to/logs/targets/Cybernet sources/Alejandro's list of Cybernets.xlsx" \
  --enrichment "/path/to/logs/targets/Cybernet sources/Active Deployment Tracker 2026-05-17 (1).xlsx" \
  --output survey/output/cybernet_alejandro_targets.csv
```

Defaults write to `survey/output/cybernet_alejandro_*.csv` when `--output`, `--report`, or `--gaps` are omitted.

## Outputs

### Manifest CSV

Schema (handoff to `sas-survey-targets.sh` and field survey scripts):

```text
Identifier,IdentifierType,DeviceType,HostName,Serial,MACAddress,Source
```

### Enrichment report

Per-target resolution after cross-source merge:

- `ResolutionStatus`: `FULL` (host + serial + MAC), `PARTIAL` (two of three), `MINIMAL` (one or none)
- Input vs resolved hostname, serial, and MAC columns
- `GapNote` when fields remain missing

### Gap CSV

Subset of targets that did not reach `FULL` resolution, with `GapReason` (for example `missing:HostName,MACAddress`).

## Next step — survey manifest resolver

After ingestion, optionally pass the manifest through the Bash resolver:

```bash
bash survey/sas-survey-targets.sh \
  --device-type Cybernet \
  --csv survey/output/cybernet_alejandro_targets.csv \
  --output survey/output/cybernet_targets_resolved.csv
```

## Contract test

```bash
bash Tests/bash/test-cybernet-xlsx-targets-contracts.sh
```

Builds tiny fixture workbooks, runs the wrapper, and verifies manifest/report/gap outputs.

## Safety

- Read-only: does not modify source `.xlsx` files
- Offline: no network calls
- Treat output CSVs as operational data; keep them out of git (repo ignores `*.csv` / `survey/output/*`)
