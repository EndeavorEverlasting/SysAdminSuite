# SAS Artifact Delivery Companion

## Purpose

`SAS Artifact Delivery Companion` prepares messy operational inputs for the Cybernet Nmap Workstation Survey.

It is not a scanner. It does not touch endpoints. It does not update workbook files. It turns operator evidence into clean CSV artifacts that can be validated, reviewed, packaged, and handed off.

The pipeline is:

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

The Cybernet Nmap Workstation Survey answers the network question: what targets can be surveyed, what evidence was observed, and how that evidence reconciles.

This companion sprint answers the artifact question: how does the operator prepare inputs before survey work and package outputs after reconciliation.

The split is intentional:

| Sprint | Responsibility |
|---|---|
| Cybernet Nmap Workstation Survey | Survey target network evidence in a read-only way |
| SAS Artifact Delivery Companion | Normalize, validate, review, package, document, and hand off CSV artifacts |

## Safety posture

Hard rules:

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
- Do not commit real hostnames, serials, MACs, IPs, locations, or site data.
- Use fake or sample data only in committed files.
- Treat operator-provided files as source evidence, not final truth.

The operator is the final review point. The scripts make artifacts cleaner. They do not make business decisions.

## Input artifact expectations

Inputs should be CSV-first whenever possible.

Common input sources:

- OpenAI Chat extraction from screenshots
- OpenAI Chat extraction from PDFs
- Excel snippets copied to CSV
- Manual field notes
- Validated local field capture
- Reconciliation output from the survey sprint

Inputs may be messy, partial, duplicated, or contradictory. That is expected. The validator and review queue exist because field data is rarely clean on first contact.

Operator evidence inspected for this sprint included three common source shapes:

- A deployment tracker shape with Cybernet hostname, Cybernet serial, Cybernet MAC, room, location/unit, device type, and associated Neuron fields.
- An all-wave workstation/Neuron/Cybernet shape with an upper summary block before the real header row, then site, location, PC name, PC/Cybernet serial, Neuron name, Neuron serial, Neuron MAC, TDR, and notes fields.
- A ticket tracker shape where one ticket row can contain many newline-separated hostnames in one cell.

Those observations shaped the extraction helper and the documentation, but no literal operational rows, hostnames, serials, MACs, IPs, locations, or site values belong in committed fixtures.

## Using OpenAI Chat to extract messy artifacts into clean CSV

Use Chat as an extraction helper, not as final authority.

### Step 1

Attach messy artifacts to OpenAI Chat.

Examples:

- PDF export
- Screenshot of a tracker
- Excel snippet
- Manually typed field notes
- Sign-off picture
- Local capture notes

### Step 2

Ask Chat to extract workstation/source rows into the `workstation_source_template.csv` shape.

Useful prompt:

```text
Extract these workstation rows into CSV using exactly these headers:
SourceFile,SourceRow,SiteCode,SiteName,Location,Room,Workstation,Hostname,IPAddress,MACAddress,SerialNumber,DeviceType,AssociatedNeuron,Notes

Preserve source row references where visible.
Leave unknown cells blank.
Do not infer missing serials, MACs, IPs, hostnames, rooms, or locations.
Return CSV only.
```

### Step 2a

When the source is an exported CSV from a known workbook shape, use the source extraction helper before validation.

Known profiles:

| Profile | Use when | Important behavior |
|---|---|---|
| `deployment-tracker` | Exported deployment tracker tab | Maps Cybernet hostname, serial, MAC, room, location, device type, and associated Neuron fields. |
| `all-wave-neuron-cybernet` | Exported all-wave workstation/Neuron/Cybernet tab | Maps PC name, PC/Cybernet serial, site, location, device type, and associated Neuron fields. |
| `ticket-tracker` | Exported ticket tracker tab | Splits newline, semicolon, or comma-separated hostname lists into one workstation row per hostname. |
| `generic-workstation` | Already-close CSV extracts | Uses broad header aliases without assuming a specific workbook. |

Example:

```bash
python survey/sas-artifact-source-extract.py \
  --input artifacts/deployment_tracker_export.csv \
  --profile deployment-tracker \
  --source-file source_workbook.xlsx::exported_tab_name \
  --output artifacts/workstations.csv
```

This helper still does not decide truth. It reshapes evidence into the template so validation and review can happen cleanly.

### Step 3

Save the extracted CSV locally.

Example path:

```bash
artifacts/workstations.csv
```

### Step 4

Validate it:

```bash
python survey/sas-artifact-validate.py --input artifacts/workstations.csv --artifact-type workstation-source --output survey/output/workstations_clean.csv --errors survey/output/workstations_errors.csv --warnings survey/output/workstations_warnings.csv
```

### Step 5

Use the clean CSV as input to the Nmap workstation survey sprint.

### Step 6

After reconciliation, build the review queue:

```bash
python survey/sas-review-queue-build.py --reconciliation survey/output/cybernet_workstation_reconciliation.csv --output survey/output/review_queue.csv
```

### Step 7

Package deliverables:

```bash
python survey/sas-artifact-package.py --manifest survey/output/workstation_target_manifest.csv --nmap-evidence survey/output/nmap_workstation_evidence.csv --reconciliation survey/output/cybernet_workstation_reconciliation.csv --dashboard survey/output/cybernet_nmap_survey_dashboard.html --review-queue survey/output/review_queue.csv --output-dir delivery --package-name cybernet_survey_delivery
```

### Step 8

Use `workbook_import_notes.md` to update the working workbook manually.

Manual means manual. No script should write into the workbook.

## Hardening behavior

- Validation and review queue CSV writers prefix spreadsheet-formula-like cells with an apostrophe before writing output.
- Dashboard rendering fails when required inputs are missing instead of silently creating an empty dashboard.
- Package creation fails when required inputs are missing instead of producing an incomplete handoff.
- Raw Nmap output is excluded unless `--include-raw` is passed.
- When raw Nmap output is included, it is copied with a raw-specific filename such as `02_nmap_workstation_evidence_raw.txt` instead of being mislabeled as CSV.
- Dashboard review tables include `SourceFile`, `SourceRow`, and `Owner` for provenance and assignment.

## Template descriptions

Templates live under:

```text
survey/templates/
```

### `workstation_source_template.csv`

Operator-facing template for workstation source artifacts.

Use it when the source is a workbook extract, screenshot extraction, PDF extraction, or manually assembled site list.

Columns:

```text
SourceFile,SourceRow,SiteCode,SiteName,Location,Room,Workstation,Hostname,IPAddress,MACAddress,SerialNumber,DeviceType,AssociatedNeuron,Notes
```

### `serial_prefix_template.csv`

Operator-facing template for approved Cybernet serial prefixes.

Use it to define what serial prefixes are expected before reconciliation or review queue generation.

Columns:

```text
PrefixName,SerialPrefix,DeviceType,Confidence,Notes
```

### `field_capture_template.csv`

Template for manual or local field captures when serial evidence is obtained outside of Nmap.

Use it when a technician captures serial, MAC, model, or computer name locally.

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

## Source extraction workflow

Script:

```text
survey/sas-artifact-source-extract.py
```

Purpose:

- Convert exported source CSVs into the `workstation_source_template.csv` shape.
- Preserve `SourceFile` and `SourceRow`.
- Normalize obvious hostnames, MACs, and serial strings before validation.
- Expand ticket rows where many hostnames were stored inside one cell.

Examples:

```bash
python survey/sas-artifact-source-extract.py \
  --input artifacts/all_wave_export.csv \
  --profile all-wave-neuron-cybernet \
  --source-file source_workbook.xlsx::exported_tab_name \
  --output artifacts/workstations.csv
```

```bash
python survey/sas-artifact-source-extract.py \
  --input artifacts/ticket_tracker_export.csv \
  --profile ticket-tracker \
  --source-file ticket_tracker.xlsx::general \
  --output artifacts/ticket_hosts_workstations.csv
```

After extraction, run validation. Extraction is not approval. Validation is not approval. Operator review is where the blade falls.

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
python survey/sas-artifact-validate.py \
  --input artifacts/workstations.csv \
  --artifact-type workstation-source \
  --output survey/output/workstations_clean.csv \
  --errors survey/output/workstations_errors.csv \
  --warnings survey/output/workstations_warnings.csv
```

### Output files

Clean output:

- Normalized valid rows
- Excel-friendly headers
- Source tracing preserved where possible

Errors output:

```text
SourceFile,SourceRow,Field,ErrorType,ErrorMessage,RawValue
```

Warnings output:

```text
SourceFile,SourceRow,Field,WarningType,WarningMessage,RawValue
```

### Pass-through mode

Use `--pass-thru` when the operator needs a normalized file containing rows even if some rows failed validation.

This is useful for review sessions. Do not feed pass-through output into final survey runs without reviewing errors.

### Production mode

Use `--production-mode` for serial prefix validation when sample placeholders must fail hard.

Example:

```bash
python survey/sas-artifact-validate.py \
  --input artifacts/serial_prefixes.csv \
  --artifact-type serial-prefixes \
  --output survey/output/serial_prefixes_clean.csv \
  --errors survey/output/serial_prefixes_errors.csv \
  --warnings survey/output/serial_prefixes_warnings.csv \
  --production-mode
```

## Validation rules

### Workstation source

- At least one of `Hostname`, `IPAddress`, `MACAddress`, or `SerialNumber` should exist per row.
- `Hostname` normalizes to uppercase.
- `MACAddress` normalizes to colon-separated uppercase where possible.
- `IPAddress` must be valid IPv4 when present.
- `SerialNumber` normalizes to uppercase with whitespace removed.
- `SourceFile` and `SourceRow` are preserved when present.
- Missing `SiteCode` is a warning.
- Missing `Location` or `Room` is a warning.

### Serial prefixes

- `SerialPrefix` is required.
- Prefixes normalize to uppercase.
- Duplicate prefixes are warnings.
- Empty prefixes are errors.
- Placeholder prefixes beginning with `REPLACE_WITH` are warnings by default.
- Placeholder prefixes beginning with `REPLACE_WITH` are errors with `--production-mode`.

### Field capture

- `SerialNumber` is strongly preferred.
- `ComputerName` or `Workstation` is required when `SerialNumber` is missing.
- `CapturedAt` should be parseable when present.
- Missing `TechInitials` is a warning.
- Duplicate `SerialNumber` rows are warnings.

### Review queue

- `IssueType` is required.
- `Severity` must be one of `low`, `medium`, `high`, or `critical`.
- `ReviewStatus` must be one of `New`, `In Review`, `Resolved`, `Deferred`, or `Rejected`.

## Review queue workflow

Script:

```text
survey/sas-review-queue-build.py
```

Example:

```bash
python survey/sas-review-queue-build.py \
  --reconciliation survey/output/cybernet_workstation_reconciliation.csv \
  --output survey/output/review_queue.csv
```

Review queue rows are created for:

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
- Confidence values of low, conflict, or none
- Missing room
- Missing site
- Notes cleanup

### Severity rules

Critical:

- Serial conflict
- MAC conflict
- Duplicate serial

High:

- Needs manual review
- Windows-like endpoint seen but no serial evidence
- Field capture needed for an expected Cybernet-related row

Medium:

- Surveyed unreachable
- Missing hostname/IP
- Low confidence

Low:

- Missing room
- Missing site
- Notes cleanup

The review queue should be handled before workbook updates. It is where ugly truth goes to be judged. Glorious bureaucracy, but useful.

## Dashboard workflow

Script:

```text
deployment-audit/sas-render-artifact-delivery-dashboard.py
```

Example:

```bash
python deployment-audit/sas-render-artifact-delivery-dashboard.py \
  --review-queue survey/output/review_queue.csv \
  --reconciliation survey/output/cybernet_workstation_reconciliation.csv \
  --output survey/output/cybernet_nmap_survey_dashboard.html
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

The dashboard includes this warning banner:

```text
Local operational artifact. Do not commit dashboards or CSVs containing real hostnames, IPs, MACs, serials, locations, or tracker data.
```

## Delivery package workflow

Script:

```text
survey/sas-artifact-package.py
```

Example:

```bash
python survey/sas-artifact-package.py \
  --manifest survey/output/workstation_target_manifest.csv \
  --nmap-evidence survey/output/nmap_workstation_evidence.csv \
  --reconciliation survey/output/cybernet_workstation_reconciliation.csv \
  --dashboard survey/output/cybernet_nmap_survey_dashboard.html \
  --review-queue survey/output/review_queue.csv \
  --output-dir delivery \
  --package-name cybernet_survey_delivery
```

Package output structure:

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

Raw Nmap output is excluded unless `--include-raw` is passed.

The script does not zip by default. Add `--zip` if a local ZIP is needed:

```bash
python survey/sas-artifact-package.py \
  --manifest survey/output/workstation_target_manifest.csv \
  --nmap-evidence survey/output/nmap_workstation_evidence.csv \
  --reconciliation survey/output/cybernet_workstation_reconciliation.csv \
  --dashboard survey/output/cybernet_nmap_survey_dashboard.html \
  --review-queue survey/output/review_queue.csv \
  --output-dir delivery \
  --package-name cybernet_survey_delivery \
  --zip
```

## Workbook import guidance

Use `workbook_import_notes.md` from the generated package.

Recommended posture:

1. Open reconciliation CSV.
2. Filter out conflicts and low-confidence rows.
3. Open review queue next to the workbook.
4. Resolve critical and high items first.
5. Paste reviewed values manually.
6. Preserve `SourceFile` and `SourceRow` wherever possible.
7. Do not paste raw Nmap output into the workbook.
8. Do not let scripts update workbook files.

The workbook should receive reviewed answers, not raw noise.

## Known limitations

- CSV-first only. The extraction helper expects CSV exports, not direct `.xlsx` parsing.
- No Excel workbook writing.
- No live network scanning.
- No AD, DNS, registry, SCCM, Intune, WMI, or ServiceNow dependency.
- Data warnings are heuristic. They help catch obvious mistakes but cannot prove a file is safe to commit.
- Review queue generation is rules-based. Operator judgment still matters.
- OpenAI extraction from screenshots and PDFs must be reviewed against the original artifact. The same applies to exported workbook tabs.
- Duplicate detection depends on values present in the reconciliation CSV.
- Dashboard HTML is local and static. Do not commit dashboards generated from real operational data.

## Test command

Run the artifact delivery tests with:

```bash
python -m unittest discover tests/survey
```

Current focused coverage includes source extraction, validation, formula-safe CSV writing, review queue generation, package failure behavior, raw-output naming, dashboard rendering, and input immutability.
