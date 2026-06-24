# Cybernet XLSX Target Ingestion

Read-only, offline ingester that converts Alejandro-style Cybernet workbooks plus optional enrichment trackers into the normalized survey manifest schema used by SysAdminSuite Bash tooling.

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

```bash
bash survey/sas-cybernet-xlsx-targets.sh \
  --workbook /path/to/local/alejandro-workbook.xlsx \
  --enrichment /path/to/local/active-deployment-tracker.xlsx \
  --enrichment /path/to/local/all-wave-anesthesia-machines.xlsx \
  --output survey/output/cybernet_alejandro_targets.csv \
  --report survey/output/cybernet_alejandro_enrichment_report.csv \
  --gaps survey/output/cybernet_alejandro_gaps.csv \
  --device-type Cybernet
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
