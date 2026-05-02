# Deployment Audit

Bash-first tooling for auditing the `Deployments` tab in the deployment tracker.

This audit does **not** trust Excel conditional formatting. It reads workbook cell values directly and builds reports from the data itself.

## Core Duplicate Rule

A duplicate is only real when:

1. Both/all matching records have `Deployed = Yes`.
2. The same unique identifier appears on more than one deployed row.
3. The rows represent different deployment locations unless same-location warnings are explicitly requested.

Repeated identifiers on non-deployed, spare, staged, historical, placeholder, or incomplete rows are not automatically real duplicates.

## Full Workflow

### 1. Audit the Deployments tab

```bash
./deployment-audit/sas-audit-deployments.sh \
  --workbook data/raw/DeploymentTracker_2026-04-20_SOURCE.xlsx \
  --sheet Deployments \
  --output-dir data/outputs/deployment_audit_2026-05-02
```

### 2. Build a remote survey manifest from duplicate-resolution requests

```bash
./deployment-audit/sas-build-survey-manifest.sh \
  --requests data/outputs/deployment_audit_2026-05-02/survey_requests_duplicate_resolution.csv \
  --output data/outputs/deployment_audit_2026-05-02/remote_survey_manifest.csv
```

### 3. Normalize the survey targets

```bash
./survey/sas-survey-targets.sh \
  --device-type Cybernet \
  --csv data/outputs/deployment_audit_2026-05-02/remote_survey_manifest.csv \
  --output data/outputs/deployment_audit_2026-05-02/normalized_remote_survey_targets.csv
```

### 4. Collect remote Cybernet evidence

```bash
./survey/sas-collect-cybernet-evidence.sh \
  --manifest data/outputs/deployment_audit_2026-05-02/remote_survey_manifest.csv \
  --output data/outputs/deployment_audit_2026-05-02/cybernet_evidence.csv
```

SSH is disabled by default. If an approved SSH-capable path exists, enable it explicitly:

```bash
./survey/sas-collect-cybernet-evidence.sh \
  --manifest data/outputs/deployment_audit_2026-05-02/remote_survey_manifest.csv \
  --output data/outputs/deployment_audit_2026-05-02/cybernet_evidence.csv \
  --allow-ssh \
  --ssh-user approved_user \
  --ssh-key ~/.ssh/approved_key
```

## Outputs

| Output | Purpose |
|---|---|
| `deployed_records_normalized.csv` | Normalized deployed rows only |
| `real_duplicate_values_deployed_yes.csv` | Identifier values repeated across deployed records |
| `real_duplicate_pairs_deployed_yes.csv` | Row-pair view of real duplicate conflicts |
| `real_duplicate_clusters.csv` | Connected duplicate row groups |
| `survey_requests_duplicate_resolution.csv` | Rows that need remote Cybernet survey before any physical revisit |
| `remote_survey_manifest.csv` | Target list generated from survey requests |
| `cybernet_evidence.csv` | Remote evidence and revisit recommendation |
| `ref_errors.csv` | `#REF!` failures found in the deployment tab |
| `audit_summary.txt` | Human-readable summary |

## Evidence Verdicts

| EvidenceStatus | Meaning | Revisit posture |
|---|---|---|
| `Confirmed` | Expected Cybernet evidence matches collected evidence | No revisit needed |
| `Conflict` | Collected Cybernet evidence conflicts with tracker expectation | Revisit or privileged remote review justified |
| `ReachableNeedsPrivilegedSurvey` | Device responds, but current transport cannot collect serial/MAC | Try approved remote-management path before revisit |
| `Unreachable` | Target cannot be resolved/reached by lightweight checks | Revisit only after network/remote-management path is exhausted |

## Risks Addressed

| Risk | Mitigation |
|---|---|
| Conditional formatting rule drift | Audit reads workbook values directly instead of relying on Excel CF |
| False duplicates from staged/spare rows | Audit only treats `Deployed = Yes` rows as real duplicate candidates |
| False duplicates from shared part numbers/cables | Default key list excludes connector cable fields |
| Duplicate caused by moved anesthesia workstation | Audit generates remote Cybernet survey requests before physical revisit |
| Raw tracker corruption | Data policy requires raw files to remain untouched, with backups and candidate outputs separated |
| Public repo data leakage | `.gitignore` blocks live workbooks, CSVs, ZIPs, and output artifacts by default |
| Human interpretation gap | Outputs include row numbers, conflict field/value, location context, and missing resolution fields |
| Weak revisit justification | Evidence collector emits a revisit recommendation instead of leaving a vague duplicate flag |
| Unsafe remote actions | Collector is read-only; SSH is disabled unless explicitly enabled |

## Known Limitations

| Limitation | Impact | Current Handling |
|---|---|---|
| Location text may differ for the same physical room | Can flag a same-room wording mismatch as a real conflict | Output includes both location strings for human review |
| `Deployed` must equal `Yes` exactly after trimming/case normalization | Other values like `Y`, `TRUE`, or `1` are not currently treated as deployed | Keep tracker values standardized or extend parser deliberately |
| XLSX formulas are not recalculated | The audit reads stored workbook values, not Excel's live calculation engine | Open/save in Excel first when formulas are stale |
| Hidden rows are still read | Hidden bad records can be surfaced, which is usually desirable | Treat hidden data as auditable unless a future flag excludes it |
| Merged cells can produce sparse values | Some context fields may appear blank if Excel stores the value only once | Use row numbers and tracker review to confirm |
| Remote survey may fail if host is offline or unreachable | The tool can generate targets, but cannot guarantee remote reachability | Revisit requires failed remote survey or conflicting remote evidence |
| Lightweight probes cannot always collect serial/MAC | Ping/DNS may prove reachability without proving identity | Use approved privileged remote path before physical revisit |
| SSH collection is environment-dependent | Many Cybernet/Windows targets will not support SSH | SSH is optional and explicit; future collectors can add WMI/RPC/SNMP/API paths |
| Public repo cannot safely store live trackers | Real hostnames, MACs, serials, and locations may be sensitive | Store live data locally, encrypted, or in a private repo |

## Physical Revisit Standard

Do not approve a physical revisit merely because a duplicate appears.

A revisit is justified only when at least one of these is true:

1. Remote Cybernet survey cannot reach the target after approved network/remote-management checks.
2. Remote survey returns conflicting Cybernet identifiers.
3. Tracker says deployed, but no network/device evidence supports the deployment.
4. The client explicitly requests onsite validation.
5. The duplicate affects a patient-care workflow and cannot be resolved through available data.

Otherwise, the next action is remote reconciliation.

## Data Hygiene Rule

Use the `data/` workspace contract:

```text
data/raw/          untouched source workbooks
data/backups/      timestamped backup copies
data/experiments/  scratch workbooks and parser tests
data/outputs/      generated audit outputs
data/updated/      candidate fixed workbooks
```

Never modify `data/raw/`.
