# SAS Artifact Delivery Companion

## Purpose

`SAS Artifact Delivery Companion` prepares messy field inputs and survey outputs for the Cybernet Nmap Workstation Survey. It is an artifact pipeline, not a live scanning sprint.

The working flow is:

```text
Messy source artifacts
-> normalized source templates
-> survey-ready manifests
-> workbook-ready imports
-> review queue artifacts
-> dashboard/report handoff
-> operator documentation
```

## How this complements the Cybernet Nmap Workstation Survey

The Cybernet Nmap Workstation Survey surveys targets. This companion sprint prepares, validates, packages, explains, and delivers the artifacts needed before and after that survey.

| Sprint | Responsibility |
|---|---|
| Cybernet Nmap Workstation Survey | Read-only target surveying and reconciliation evidence |
| SAS Artifact Delivery Companion | CSV normalization, validation, review queues, packaging, dashboard handoff, and operator docs |

## Input artifact expectations

Inputs should be treated as source evidence, not final truth. Typical inputs include:

- OpenAI Chat extraction from screenshots, PDFs, or pasted Excel ranges
- CSV exports
- Manual notes
- Local field captures
- Reconciliation output from the survey sprint

Keep committed fixtures fake. Never commit real hostnames, real serials, real MACs, real IPs, real locations, tracker data, or site data.

## Using OpenAI Chat to turn PDFs, screenshots, and Excel snippets into clean CSV

Use Chat for extraction, not judgment.

Prompt shape:

```text
Extract these workstation rows into CSV using exactly these headers:
SourceFile,SourceRow,SiteCode,SiteName,Location,Room,Workstation,Hostname,IPAddress,MACAddress,SerialNumber,DeviceType,AssociatedNeuron,Notes

Preserve source row references where visible.
Leave unknown cells blank.
Do not infer missing serials, MACs, IPs, hostnames, rooms, or locations.
Return CSV only.
```

## Template descriptions

Templates live under `survey/templates/`.

### `workstation_source_template.csv`

Operator-facing template for workstation source artifacts.

Columns:

```text
SourceFile,SourceRow,SiteCode,SiteName,Location,Room,Workstation,Hostname,IPAddress,MACAddress,SerialNumber,DeviceType,AssociatedNeuron,Notes
```

### `serial_prefix_template.csv`

Operator-facing template for approved Cybernet serial prefixes.

Columns:

```text
PrefixName,SerialPrefix,DeviceType,Confidence,Notes
```

### `field_capture_template.csv`

Template for manual or local field captures when serial evidence is obtained outside of Nmap.

Columns:

```text
CapturedAt,CaptureMethod,TechInitials,SiteCode,SiteName,Location,Room,Workstation,ComputerName,IPAddress,MACAddress,SerialNumber,Manufacturer,Model,AssociatedNeuron,Notes
```

### `review_queue_template.csv`

Template for anything requiring operator judgment before workbook update.

Columns:

```text
ReviewID,SourceFile,SourceRow,SiteCode,Location,Room,Workstation,Hostname,IPAddress,MACAddress,SerialNumber,IssueType,Severity,EvidenceSummary,RecommendedAction,Owner,ReviewStatus,Notes
```

## Validation workflow

Script:

```text
survey/sas-artifact-validate.py
```

Supported artifact types:

- `workstation-source`
- `serial-prefixes`
- `field-capture`
- `review-queue`

Example:

```bash
python survey/sas-artifact-validate.py --input artifacts/workstations.csv --artifact-type workstation-source --output survey/output/workstations_clean.csv --errors survey/output/workstations_errors.csv --warnings survey/output/workstations_warnings.csv
```

The clean output contains normalized valid rows. Errors and warnings are exported as CSV with source tracing.

Use `--pass-thru` only when the operator needs normalized rows even if row-level errors exist. Use `--production-mode` for serial prefix validation when placeholders must fail.

## Review queue workflow

Build a review queue from reconciliation output:

```bash
python survey/sas-review-queue-build.py --reconciliation survey/output/cybernet_workstation_reconciliation.csv --output survey/output/review_queue.csv
```

Review rows are created for:

- Missing serial evidence
- Needs field capture
- Needs manual review
- Surveyed unreachable
- Hostname/IP missing
- Serial prefix conflict
- MAC conflict
- Duplicate serial
- Duplicate hostname
- Windows-like endpoint seen but no serial evidence
- Low, conflict, or none confidence
- Missing room
- Missing site
- Notes cleanup

Severity rules:

| Severity | Conditions |
|---|---|
| critical | serial conflict, MAC conflict, duplicate serial |
| high | needs manual review, Windows-like endpoint with no serial evidence, field capture needed for expected Cybernet-related row |
| medium | surveyed unreachable, missing hostname/IP, low confidence |
| low | missing room, missing site, notes cleanup |

## Dashboard workflow

Render the artifact delivery dashboard:

```bash
python deployment-audit/sas-render-artifact-delivery-dashboard.py --review-queue survey/output/review_queue.csv --reconciliation survey/output/cybernet_workstation_reconciliation.csv --output survey/output/cybernet_nmap_survey_dashboard.html
```

Dashboard sections:

- Total artifact rows
- Review items
- Critical items
- High severity items
- Missing serial evidence
- Needs field capture
- Unreachable targets
- Low confidence rows
- Site summary
- Issue type summary
- Full review queue table

The dashboard contains this warning banner:

```text
Local operational artifact. Do not commit dashboards or CSVs containing real hostnames, IPs, MACs, serials, locations, or tracker data.
```

## Delivery package workflow

Package deliverables locally:

```bash
python survey/sas-artifact-package.py --manifest survey/output/workstation_target_manifest.csv --nmap-evidence survey/output/nmap_workstation_evidence.csv --reconciliation survey/output/cybernet_workstation_reconciliation.csv --dashboard survey/output/cybernet_nmap_survey_dashboard.html --review-queue survey/output/review_queue.csv --output-dir delivery --package-name cybernet_survey_delivery
```

Package structure:

```text
delivery/<package-name>_<timestamp>/
  01_workstation_target_manifest.csv
  02_nmap_workstation_evidence.csv
  03_cybernet_workstation_reconciliation.csv
  04_review_queue.csv
  05_dashboard.html
  ARTIFACT_INDEX.md
  handoff_summary.md
  workbook_import_notes.md
```

Raw Nmap output is excluded unless `--include-raw` is passed. The script does not zip by default. Add `--zip` when a local ZIP is needed.

## Operator workflow

Step 1: Attach messy artifacts to OpenAI Chat.

Step 2: Ask Chat to extract workstation/source rows into the `workstation_source_template.csv` shape.

Step 3: Save the extracted CSV locally.

Step 4: Validate it:

```bash
python survey/sas-artifact-validate.py --input artifacts/workstations.csv --artifact-type workstation-source --output survey/output/workstations_clean.csv --errors survey/output/workstations_errors.csv --warnings survey/output/workstations_warnings.csv
```

Step 5: Use the clean CSV as input to the Nmap workstation survey sprint.

Step 6: After reconciliation, build the review queue:

```bash
python survey/sas-review-queue-build.py --reconciliation survey/output/cybernet_workstation_reconciliation.csv --output survey/output/review_queue.csv
```

Step 7: Package deliverables:

```bash
python survey/sas-artifact-package.py --manifest survey/output/workstation_target_manifest.csv --nmap-evidence survey/output/nmap_workstation_evidence.csv --reconciliation survey/output/cybernet_workstation_reconciliation.csv --dashboard survey/output/cybernet_nmap_survey_dashboard.html --review-queue survey/output/review_queue.csv --output-dir delivery --package-name cybernet_survey_delivery
```

Step 8: Use `workbook_import_notes.md` to update the working workbook manually.

## Workbook import guidance

- Open `03_cybernet_workstation_reconciliation.csv` in Excel.
- Filter out conflicts and low-confidence rows.
- Open `04_review_queue.csv` next to the workbook.
- Resolve critical and high-severity items first.
- Paste only reviewed values into the workbook.
- Preserve `SourceFile` and `SourceRow` where possible.
- Do not paste raw Nmap output into the tracker.
- Do not let scripts update workbook files.

## Safety rules

- Read-only only.
- Do not mutate endpoints.
- Do not mutate AD.
- Do not mutate DNS.
- Do not mutate registry.
- Do not auto-update tracker or workbook files.
- Do not require ServiceNow.
- Do not require SCCM.
- Do not require Intune.
- Do not require remote WMI.
- Do not commit real operational data.
- Use fake/sample data only in committed files.

## Known limitations

- CSV-first only.
- No Excel workbook writing.
- No live scanning.
- Safety warnings are heuristic and cannot prove a file is safe.
- Review queue generation is rules-based. Operator judgment still wins.
- OpenAI extraction must be reviewed against the original artifact.

## Tests

Run:

```bash
python -m unittest discover tests/survey
```
