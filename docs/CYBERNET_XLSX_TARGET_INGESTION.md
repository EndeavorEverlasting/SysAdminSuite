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

## Alejandro vs deployment tracker diff

When Alejandro's workbook is the authoritative Cybernet serial source, compare its unique serial
inventory against the latest deployment tracker before probing anything live:

```bash
bash survey/sas-cybernet-tracker-diff.sh \
  --alejandro "logs/targets/Cybernet sources/Alejandro's list of Cybernets.xlsx" \
  --tracker "logs/targets/Cybernet sources/Active Deployment Tracker 2026-05-17 - 6-25-2026.xlsx" \
  --output-prefix survey/output/cybernet
```

The diff is read-only against both workbooks and writes local operational CSVs:

- `survey/output/cybernet_alejandro_unique_serials.csv`
- `survey/output/cybernet_tracker_unique_serials.csv`
- `survey/output/cybernet_alejandro_already_tracked.csv`
- `survey/output/cybernet_alejandro_untracked.csv`
- `survey/output/cybernet_tracker_duplicate_exceptions.csv`

Comparison rules:

- Normalize serials by trimming whitespace and uppercasing.
- Treat Alejandro rows as a unique serial inventory; duplicate Alejandro rows collapse into one serial with a row count.
- Exclude an Alejandro serial from the untracked manifest when that serial already appears in the deployment tracker.
- Emit duplicate exceptions only when the same normalized hostname, serial, or MAC appears in more than one tracker row marked `Deployed = Yes`.
- Repeated non-deployed tracker identifiers are planning history, not duplicate exceptions.

`cybernet_alejandro_untracked.csv` uses the same manifest schema as the ingester. Serial-only rows
are retained for tracking, but only rows with a resolved `HostName` are ready for live WMI/ping
identity checks.

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

For host-resolved untracked rows, prefer the read-only WMI/ping identity path before considering
SSH. SSH is disabled by default in the transport adapter and a blocked SSH path is environment or
policy evidence, not a product failure:

```bash
python - <<'PY'
import csv
with open("survey/output/cybernet_alejandro_untracked.csv", newline="", encoding="utf-8-sig") as src, \
     open("survey/output/cybernet_untracked_host_targets.txt", "w", encoding="utf-8") as dst:
    for row in csv.DictReader(src):
        if row.get("HostName"):
            dst.write(row["HostName"].strip() + "\n")
PY

bash bash/transport/sas-workstation-identity.sh \
  --targets-file survey/output/cybernet_untracked_host_targets.txt \
  --allow-wmi \
  --output survey/output/cybernet_untracked_wmi_identity.csv
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
