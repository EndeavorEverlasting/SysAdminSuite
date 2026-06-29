# Field network preflight

This is the durable Northwell field path for read-only network posture checks against approved Cybernet / Neuron target files.

## Shell rule

Use **Windows PowerShell** for this workflow.

Do not use Git Bash / MINGW64 for field preflight. Do not use CMD for PowerShell blocks. Do not paste Bash commands into the Windows PowerShell window.

CMD is only acceptable for simple Windows launcher commands, such as double-clicking or starting a `.bat` file that opens the dashboard.

## Folder doctrine

| Folder | Role |
|---|---|
| `targets/` | Tracked policy, schemas, and sanitized fixtures only |
| `targets/local/` | Preferred ignored live intake for approved source CSVs, AD exports, trackers, and raw target material before normalization |
| `logs/targets/` | Preserved ignored local target and evidence store |
| `survey/input/` | Normalized runtime staging only |
| `survey/output/` | Generated survey outputs |
| `logs/nmap/` | Generated network probe output |
| `survey/artifacts/` | Generated local artifacts |

Do not type demo hostnames manually for live work. Do not use `C:\Temp` as the live workflow. Use approved target files from `targets/local/` or `logs/targets/` first. Use `survey/input/` only when a prior SysAdminSuite step produced normalized staging.

## Spreadsheet-first doctrine

The deployment spreadsheet/workbook remains the primary field artifact when it defines the Cybernet / Neuron population.

The repo should not expect technicians to hand-build `.txt` files from that workbook. A SysAdminSuite ingestion/normalization step must convert the approved workbook or exported tab into the machine-readable artifacts needed by later lanes.

Expected engine path:

```text
approved workbook / exported tracker tab
  -> XLSX/CSV ingestion and normalization engine
  -> manifest / progress / gap reports under survey/output/
  -> probe-ready staged target file under survey/input/
  -> delta preflight planner
  -> network preflight only for the reduced staged target file
```

The staged text file is a runtime handoff artifact, not a replacement source of truth. If the spreadsheet and staged targets disagree, the spreadsheet-backed manifest and delta plan must explain the mismatch.

## Field flow

1. Start from the approved spreadsheet/workbook, deployment tracker tab, AD export, or other approved source of record.
2. Run the appropriate SysAdminSuite ingestion/normalization engine. Do not manually retype targets into `.txt` files for live work.
3. Confirm the generated manifest, progress summary, and gap/review files under `survey/output/`.
4. Run the delta preflight planner to compare the requested population against local evidence.
5. Review skipped / probe / review counts from `survey/output/delta_preflight/<run_id>/`.
6. Use the planner-staged target file under `survey/input/delta_preflight/<run_id>/to_probe_targets.txt`.
7. Run the PowerShell network preflight only against that staged `to_probe_targets.txt` file.
8. Review the generated CSV under `survey/output/network_preflight/`.
9. Load the CSV into the dashboard through **Load Evidence**.

## Delta preflight first

Before sending new ping/TCP packets, compare the requested serial/target population against local evidence.

See [`DELTA_PREFLIGHT_EVIDENCE_CACHE_SPRINT.md`](DELTA_PREFLIGHT_EVIDENCE_CACHE_SPRINT.md) for the implementation contract.

The planner is a no-network step. It should answer:

```text
What do we already know locally?
What evidence is still fresh?
What is stale or conflicting?
What still deserves packets?
```

Expected future planner report output:

```text
survey/output/delta_preflight/<run_id>/delta_preflight_plan.csv
survey/output/delta_preflight/<run_id>/skipped_recent_evidence.csv
survey/output/delta_preflight/<run_id>/review_required.csv
survey/output/delta_preflight/<run_id>/delta_summary.json
```

Expected future staged preflight handoff file:

```text
survey/input/delta_preflight/<run_id>/to_probe_targets.txt
```

Only the staged `survey/input/.../to_probe_targets.txt` file should feed the network preflight unless the preflight script is explicitly updated later to trust generated delta output roots.

## Spreadsheet source on X:\

Do not probe a spreadsheet directly from `X:\` unless an existing tested ingestion path explicitly supports that source.

Preferred path:

1. Use the approved workbook or export the approved tab only if the ingestion engine requires CSV.
2. Place the workbook/export under `targets/local/` or reference its approved local path directly if the ingester supports explicit workbook arguments.
3. Run the workbook/CSV ingestion engine; do not manually create target text files.
4. Run the delta preflight planner against the normalized manifest.
5. Run the PowerShell preflight against the planner's staged `survey/input/delta_preflight/<run_id>/to_probe_targets.txt`.

## Select a target file

Run in Windows PowerShell:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1
```

With no `-TargetFile`, the script lists candidate `.txt` and `.csv` files from `targets/local/` and `logs/targets/`, explains what the operator must select, and stops without probing.

## Run the network preflight

Run in Windows PowerShell:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1 -TargetFile .\survey\input\delta_preflight\<run_id>\to_probe_targets.txt -Ports 135,445,3389,9100
```

Direct approved source roots are still accepted when the delta planner is not available yet:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1 -TargetFile .\targets\local\approved_targets.csv -Ports 135,445,3389,9100
```

Alternative approved source root:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1 -TargetFile .\logs\targets\approved_confirm_hosts.txt -Ports 135,445,3389,9100
```

The script prints the selected target file, target count, selected ports, output path, stage progress, `[n/total]` progress, percent complete, and final CSV path.

## Accepted target files

### `.txt`

One hostname, IP address, or probe-ready identifier per line.

Rules:

- blank lines ignored
- lines beginning with `#` ignored
- whitespace trimmed
- non-probe-ready values skipped

### `.csv`

Preferred target columns:

- `HostName`
- `Hostname`
- `ComputerName`
- `DeviceName`
- `Name`

Also accepted when probe-ready or explicitly typed as a hostname/IP:

- `Target`
- `Identifier`

Serial-only rows are not network targets. If a CSV only contains serials, enrich or normalize it to hostnames first.

## Evidence interpretation

Ping/TCP preflight is reachability evidence only.

Do not treat ping failure as proof that no useful evidence exists. Preserve separate paths for:

- ping reachable
- DNS only / no ping
- identity observed / no ping
- AD registered
- AD candidate only
- offline fixture
- unreachable or silent
- conflicting evidence
- manual review

## Outputs

Default output folder:

```text
survey/output/network_preflight/
```

Output file pattern:

```text
network_preflight_<timestamp>.csv
```

Generated outputs are local and ignored. Do not commit live target lists, serial lists, AD exports, or probe results.

## Safety boundary

This preflight is read-only. It does not add credentials, mutate targets, install software, create remote tasks, or broaden scope beyond the selected approved target file.

The delta planner that precedes this step must also be read-only and must perform no network activity.
