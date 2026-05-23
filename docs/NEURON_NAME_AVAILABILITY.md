# Neuron Name Availability Workflow

## Purpose

Neuron names are tedious to manage manually when each site uses a sequential alphabetic suffix convention.

Examples:

- `LIJ-MACH-A`, `LIJ-MACH-B`, ..., `LIJ-MACH-Z`, `LIJ-MACH-AA`, `LIJ-MACH-AB`
- `CCMC-MACH-A`, `CCMC-MACH-B`, ..., `CCMC-MACH-Z`, `CCMC-MACH-AA`, `CCMC-MACH-AB`

This workflow analyzes saved naming evidence and reports:

- occupied names
- first available gap
- next available name after the highest observed suffix
- candidate lists for each naming convention
- a local HTML dashboard for operator review

## Files

| File | Role |
|---|---|
| `survey/sas-neuron-name-availability.py` | Main analyzer for naming convention availability |
| `survey/fixtures/neuron_name_availability_sample.xml` | Sample-safe nmap XML fixture |
| `deployment-audit/tests/test_neuron_name_availability_contracts.sh` | Contract test for suffix logic and dashboard output |

## Evidence posture

The analyzer does not scan the network.

It consumes saved evidence, such as:

- nmap XML files containing hostnames
- text lists of known names
- CSV exports from AD, DNS, tracker, or machine-info inventory

This preserves the existing SysAdminSuite pattern:

```text
Probe once
Preserve artifacts
Parse many times
```

## Example command

```bash
python3 survey/sas-neuron-name-availability.py \
  --convention LIJ-MACH- \
  --convention CCMC-MACH- \
  --nmap-xml survey/artifacts/site_neuron_discovery.xml \
  --used-names exports/ad_neuron_names.csv \
  --summary-output survey/output/neuron_name_availability_summary.csv \
  --detail-output survey/output/neuron_name_availability_detail.csv \
  --dashboard survey/output/neuron_name_availability.html \
  --candidate-count 10
```

## Output files

| Output | Meaning |
|---|---|
| Summary CSV | One row per naming convention with first gap and next-after-highest recommendation |
| Detail CSV | Occupied names and computed available candidates |
| Dashboard HTML | Local review dashboard with cards and filterable detail table |

## Recommendation fields

| Field | Meaning |
|---|---|
| `FirstGapName` | First missing suffix inside the observed sequence |
| `NextAfterHighestName` | First suffix after the highest observed occupied name |
| `GapCandidates` | Additional available gaps inside the observed sequence |
| `NextCandidates` | Names after the highest observed suffix |

## Operating rule

Use `FirstGapName` when the goal is to close sequence gaps.

Use `NextAfterHighestName` when stale AD/DNS objects may exist and reuse is risky.

Cold judge ruling: network evidence alone is not enough for final production renaming. Validate against AD/DNS before applying a name to a live device.

## Suffix model

The suffix uses Excel-style alphabetic numbering:

| Suffix | Ordinal |
|---|---:|
| `A` | 1 |
| `B` | 2 |
| `Z` | 26 |
| `AA` | 27 |
| `AB` | 28 |
| `ZZ` | 702 |
| `AAA` | 703 |

## Test

```bash
bash deployment-audit/tests/test_neuron_name_availability_contracts.sh
```

The test verifies:

- LIJ gap detection
- LIJ next-after-highest detection
- CCMC gap detection
- CCMC next-after-highest detection
- occupied/detail records
- dashboard rendering

## Privacy / artifact handling

Generated outputs may contain real hostnames and site information. Do not commit live outputs.

Keep generated CSV and HTML files under ignored output directories such as:

```text
survey/output/
```
