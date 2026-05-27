# Hostname Availability Workflow

## Purpose

Find the next available hostname for fixed naming conventions such as `WNH270OPR###` (three-digit suffix) or alphabetic site patterns. The workflow unions evidence from:

- Active Directory (prefix export, read-only)
- Deployment and ticket trackers
- Optional forward DNS checks on candidates and occupied names

It reports **both** recommendations:

| Field | When to use |
|-------|-------------|
| `FirstGapName` | Lowest missing suffix in the observed sequence |
| `NextAfterHighestName` | First suffix after the highest observed name (safer when stale AD/DNS objects exist) |

## Files

| File | Role |
|------|------|
| `survey/sas-hostname-availability.py` | Analyzer (numeric or alphabetic suffix modes) |
| `survey/sas-survey-hostname-availability.sh` | Field wrapper: AD export, tracker extract, DNS, analyze |
| `survey/sas-ad-computer-prefix-export.ps1` | Read-only AD `Name -like Prefix*` export |
| `survey/sas-extract-tracker-hostnames.sh` | Read-only tracker hostname column extract |
| `survey/sas-dns-hostname-evidence.sh` | Read-only forward DNS evidence |
| `survey/fixtures/hostname_availability_sample.txt` | Sample-safe fixture |
| `deployment-audit/tests/test_hostname_availability_contracts.sh` | Contract test |

Neuron-specific alphabetic tooling remains in `survey/sas-neuron-name-availability.py` and `docs/NEURON_NAME_AVAILABILITY.md`.

## Evidence posture

```text
Collect evidence (AD, tracker, optional DNS)
        |
        v
Analyze once (gaps + next-after-highest)
        |
        v
Optional DNS re-pass if --dns-check
```

Default recommended mode: saved evidence (`--used-names`) or `--ad-export` from an admin workstation with RSAT/AD module access.

## Example: WNH270OPR numeric

```bash
bash survey/sas-survey-hostname-availability.sh \
  --convention WNH270OPR \
  --suffix-mode numeric \
  --width 3 \
  --ad-export \
  --tracker-workbook /path/to/ActiveDeploymentTracker.xlsx \
  --ticket-workbook /path/to/ActiveTicketTracker.xlsx \
  --dns-check \
  --output-dir survey/output/wnh270opr-availability
```

Fixture-only (no live AD):

```bash
bash survey/sas-survey-hostname-availability.sh \
  --convention WNH270OPR \
  --suffix-mode numeric \
  --width 3 \
  --used-names survey/fixtures/hostname_availability_sample.txt
```

## Suffix modes

| Mode | Example | Notes |
|------|---------|-------|
| `numeric` | `WNH270OPR001` | `--width` sets digit count (default 3) |
| `alphabetic` | `LIJ-MACH-A` | Excel-style A, B, … Z, AA (same model as Neuron tool) |

## Operating rule

Network or AD evidence alone is not enough for final production naming. Validate the chosen name against AD, DNS, and the deployment tracker before assignment.

## Test

```bash
bash deployment-audit/tests/test_hostname_availability_contracts.sh
```

## Privacy

Do not commit live outputs under `survey/output/` or `survey/artifacts/`.
