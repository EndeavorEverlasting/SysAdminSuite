# Neuron Name Directory Check

## Purpose

Network discovery alone cannot prove that a Neuron name is safe to reuse. A name may be absent from live discovery but still exist as a stale object in Active Directory, DNS, a tracker export, or another naming source.

This lane checks computed Neuron name candidates against saved directory/name evidence before recommending a production name.

## Files

| File | Role |
|---|---|
| `survey/sas-neuron-name-directory-check.py` | Checks naming candidates against saved AD/DNS/name evidence |
| `survey/fixtures/neuron_name_directory_evidence.sample.txt` | Sample-safe stale-object evidence fixture |
| `deployment-audit/tests/test_neuron_name_availability_contracts.sh` | Covers stale-object blocking and recommendation advancement |

## Workflow

```text
Network/name evidence
  -> sas-neuron-name-availability.py
  -> neuron_name_availability_detail.csv
  -> saved AD/DNS/name exports
  -> sas-neuron-name-directory-check.py
  -> final candidate check CSV
  -> final recommendation summary
  -> local HTML dashboard
```

## Example

```bash
python3 survey/sas-neuron-name-directory-check.py \
  --detail survey/output/neuron_name_availability_detail.csv \
  --directory-evidence exports/ad_neuron_names.csv \
  --directory-evidence exports/dns_neuron_names.txt \
  --output survey/output/neuron_name_directory_check.csv \
  --summary-output survey/output/neuron_name_directory_check_summary.csv \
  --dashboard survey/output/neuron_name_directory_check.html
```

## Statuses

| Status | Meaning |
|---|---|
| `CLEAR_IN_SUPPLIED_DIRECTORY_EVIDENCE` | Candidate was not found in supplied AD/DNS/name evidence |
| `BLOCKED_BY_DIRECTORY_EVIDENCE` | Candidate exists in supplied directory/name evidence and must not be reused |
| `OCCUPIED_IN_NETWORK_EVIDENCE` | Candidate conflicts with occupied network/name evidence |

## Recommendation rule

The summary selects the lowest ordinal candidate that is clear in supplied evidence.

A clear result is not an authorization to rename. It means only that the candidate was not found in the supplied evidence files. Validate against production AD and DNS immediately before applying a name.

## Existing AD support

SysAdminSuite already includes `survey/sas-ad-identity-export.ps1` for read-only AD identity evidence. AD or DNS exports from approved tools can be supplied directly to this checker as CSV or text evidence.

## Test

```bash
bash deployment-audit/tests/test_neuron_name_availability_contracts.sh
```

The fixture intentionally blocks the first apparent LIJ and CCMC gaps, proving that the recommendation advances to the next clear candidate.
