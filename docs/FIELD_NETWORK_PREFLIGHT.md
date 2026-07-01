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

## Alejandro serial list flow

Alejandro's serial list can be used to decide which hosts deserve network preflight, but the suite must not ping serial strings directly.

Use this path when the operator has a serial population and one or more approved evidence exports that bridge those serials to hostnames or IP addresses:

```text
Alejandro serial list
  -> approved serial-to-host/IP evidence
  -> serial preflight planner
  -> survey/input/serial_preflight/<run_id>/to_probe_targets.txt
  -> PowerShell network preflight
```

Run in Windows PowerShell:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-serial-preflight-plan.ps1 `
  -SerialFile .\targets\local\alejandro_serials.csv `
  -EvidenceFile .\targets\local\approved_serial_hostname_bridge.csv `
  -Ports 135,445,3389,9100
```

The planner writes:

```text
survey/output/serial_preflight/<run_id>/serial_preflight_plan.csv
survey/output/serial_preflight/<run_id>/review_required.csv
survey/output/serial_preflight/<run_id>/serial_preflight_summary.json
survey/output/serial_preflight/<run_id>/operator_handoff.txt
survey/input/serial_preflight/<run_id>/to_probe_targets.txt
```

Then run the PowerShell network preflight only against the generated `to_probe_targets.txt`:

```powershell
.\survey\sas-network-preflight.ps1 `
  -TargetFile .\survey\input\serial_preflight\<run_id>\to_probe_targets.txt `
  -Ports 135,445,3389,9100
```

Rules:

- `Serial`, `SerialNumber`, `AlejandroSerial`, `DeviceSerial`, `TargetSerial`, `ComputerSerial`, `AssetSerial`, and `SN` are accepted serial columns.
- `HostName`, `Hostname`, `ComputerName`, `DeviceName`, `DnsName`, `FQDN`, `IPAddress`, `IP`, and `IPv4` are accepted probe target columns when bridged to a serial.
- `Target` is accepted only when it is probe-ready and not explicitly typed as a non-host value.
- `Identifier` is accepted only when `IdentifierType`, `TargetType`, `Type`, or `ValueType` explicitly says it is a host/IP value.
- Serial-only rows go to review, not packets.
- The planner performs no network activity. It only stages a reduced target file.

## Low-noise probe posture

See [`LOW_NOISE_PROBE_PRINCIPLES.md`](LOW_NOISE_PROBE_PRINCIPLES.md) for the full doctrine.

The network sees packets, not the shell. Running a packet tool from CMD rather than PowerShell does not materially reduce network visibility when the same targets, ports, packet types, rates, and retries are used.

Before any probe is staged or run, the workflow should answer:

```text
Should this target be probed at all?
Which exact host/IP should be probed?
Which exact ports answer the survey question?
At what rate?
How many retries?
Is this already fresh in local evidence?
Is this a CDN/WAF/load-balanced/front-door target?
Is this a mystery serial that needs review, not packets?
```

Low-noise work comes from:

```text
smaller scope
fewer ports
lower rate
fewer retries
smarter evidence reuse
avoiding broad scans
avoiding immediate repeat probes when a better time/day would be more informative
```

A fixed retry count is not the goal. Five probes are unnecessary when a device is already recently reachable or identity-confirmed. If a retry is justified, prefer a different time of day and/or different day of week over immediate repetition.

The serial preflight planner must carry this context into its artifacts so the operator can see why packets were or were not justified.

## Dashboard controls gap

The runbook and backend now support serial-first planning, but the dashboard controls must also expose that path.

See [`DASHBOARD_SERIAL_PROBE_CONTROLS_SPRINT.md`](DASHBOARD_SERIAL_PROBE_CONTROLS_SPRINT.md) for the dashboard implementation contract.

Required dashboard direction:

```text
Plan from Alejandro serials
  -> show serial preflight command
  -> load serial preflight outputs
  -> summarize probe-ready targets, review-required rows, and mystery serials
  -> show next staged network preflight command
```

The dashboard must not make manual host/IP target entry feel like the primary Cybernet workflow when the operator is starting from serials.

## Iterative technician handoff

Technicians should be able to keep running the same approved planning command or dashboard action without asking an AI agent for the next command.

See [`TECHNICIAN_ITERATIVE_PROBE_HANDOFFS.md`](TECHNICIAN_ITERATIVE_PROBE_HANDOFFS.md) for the implementation contract.

The repeatable command should:

```text
read Alejandro's serial list
  -> read local evidence and prior probe history
  -> preserve mystery serials
  -> timestamp each attempt
  -> check time-of-day diversity
  -> narrow the next target file
  -> classify stable gaps and repeated non-response
  -> print the next handoff command
```

Important outcomes:

- serial-only mystery rows remain visible as `MYSTERY_SERIAL_NO_BRIDGE`
- repeated failed attempts are classified as non-response evidence, not proof that the serial does not exist
- five attempts in one narrow time window are not equivalent to five diverse attempts
- plateau/no-improvement detection should stop wasteful re-probing and route rows to review

## Field flow

1. Export or copy the approved spreadsheet/workbook, deployment tracker tab, AD export, or other approved source of record into an approved local intake path when required by the selected ingestion engine.
2. Run the appropriate SysAdminSuite ingestion/normalization engine. Do not manually retype targets into `.txt` files for live work.
3. Confirm the generated manifest, progress summary, and gap/review files under `survey/output/`.
4. If starting from Alejandro's serial list, run `survey/sas-serial-preflight-plan.ps1` with approved serial-to-host/IP evidence and use its generated `survey/input/serial_preflight/<run_id>/to_probe_targets.txt` file.
5. For repeated attempts, use the iterative technician handoff doctrine so local evidence and timestamped prior attempts narrow the next run.
6. Run the delta preflight planner to compare the requested population against local evidence when a broader delta evidence cache is available.
7. Review skipped / probe / review counts from `survey/output/delta_preflight/<run_id>/` or `survey/output/serial_preflight/<run_id>/`.
8. Use the planner-staged target file under `survey/input/delta_preflight/<run_id>/to_probe_targets.txt` or `survey/input/serial_preflight/<run_id>/to_probe_targets.txt`.
9. Run the PowerShell network preflight only against that staged `to_probe_targets.txt` file.
10. Review the generated CSV under `survey/output/network_preflight/`.
11. Load the CSV into the dashboard through **Load Evidence**.

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
4. Run the serial preflight planner or delta preflight planner against the normalized manifest.
5. Run the PowerShell preflight against the planner's staged `survey/input/.../<run_id>/to_probe_targets.txt`.

## Select a target file

Run in Windows PowerShell:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1
```

With no `-TargetFile`, the script lists candidate `.txt` and `.csv` files from `targets/local/` and `logs/targets`, explains what the operator must select, and stops without probing.

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

The serial preflight planner and delta planner that precede this step must also be read-only and must perform no network activity.
