# Software Tracker Install Automation

## Primary Path

For Northwell-targeted Software Tracker install work, the primary path is
**Python + Bash/CMD**:

```bash
bash scripts/sas-software-tracker-install.sh --tracker "Software Tracker.xlsx"
```

or double-click:

```text
Start-SoftwareTrackerInstall.cmd
```

PowerShell remains legacy/reference tooling for other Windows corporate
environments. Do not add new PowerShell-first Software Tracker install workflows
for this Northwell-targeted path. Existing scripts under `scripts/powershell/`
remain intact and should not be deleted.

## What It Does

`scripts/software_tracker_installs.py` reads a Software Tracker workbook and
produces a guarded install plan. It supports:

- `Directories` catalog workbooks with installer paths, URLs, placeholders, and
  folder references.
- `Software Tracker` workbooks with per-host install rows.
- Local reports in JSON, CSV, and readable text.
- Dry-run-first planning, with mutation only when `--execute` is explicitly
  supplied.

The tool is deliberately conservative. A plan can contain `Blocked` or
`ManualReview` rows; those are expected safety outcomes, not parser failures.

## Dry Run First

Dry-run is the default:

```bash
bash scripts/sas-software-tracker-install.sh \
  --tracker "Software Tracker.xlsx" \
  --config Config/software-tracker.example.json \
  --output-dir survey/output/software-tracker-install
```

Reports are written to:

```text
survey/output/software-tracker-install/install-summary.json
survey/output/software-tracker-install/install-summary.csv
survey/output/software-tracker-install/install-log.txt
```

These are local operator outputs. Do not commit reports produced from live
workbooks.

## Catalog/List Mode

If the workbook has a `Directories` sheet, the tool treats it as a catalog. You
can limit planning to a named list or one software name:

```bash
bash scripts/sas-software-tracker-install.sh \
  --tracker "Software Tracker.xlsx" \
  --list workstation-baseline
```

```bash
bash scripts/sas-software-tracker-install.sh \
  --tracker "Software Tracker.xlsx" \
  --software "Google Chrome"
```

## Guarded Execute

Execution is opt-in:

```bash
bash scripts/sas-software-tracker-install.sh \
  --tracker "Software Tracker.xlsx" \
  --software "Known Silent MSI" \
  --execute
```

Safety rules:

- URLs are never opened or executed.
- EXE installers require explicit silent arguments.
- Folder paths are manual-review by default.
- Folder-discovered installers require both `--execute` and
  `--allow-discovered-folder-installs`.
- Commands are executed as an argument list with `shell=False`; the tool does not
  build shell command strings.
- No credentials are read or requested.

Folder discovery is intentionally gated:

```bash
bash scripts/sas-software-tracker-install.sh \
  --tracker "Software Tracker.xlsx" \
  --software "Folder Catalog Entry" \
  --execute \
  --allow-discovered-folder-installs
```

## Path Aliases

Use a local JSON config to map tracker paths to local installer staging paths:

```json
{
  "pathAliases": {
    "\\\\software-share\\installers\\Chrome\\Chrome.msi": "C:/SoftwareRepo/installers/Chrome.msi"
  }
}
```

The committed `Config/software-tracker.example.json` uses only sanitized fixture
paths. Operators should keep real local configs in ignored/private locations
when they include environment-specific paths.

## Keep Real Workbooks Out Of Git

`.gitignore` excludes:

```text
Software Tracker.xlsx
*.real.xlsx
data/private/
```

Do not commit live Software Tracker workbooks, private config, install reports,
credentials, or endpoint evidence. Use local-only ignored output paths for
generated reports.
