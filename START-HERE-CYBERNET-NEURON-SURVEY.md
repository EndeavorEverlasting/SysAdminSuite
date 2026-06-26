# Start Here: Cybernet / Neuron Network Survey

This is the field-facing entrypoint for Cybernet / Neuron network survey work.

Use it when you need to validate network posture from an approved target population using a local admin workstation. The dashboard guides the workflow. The operator runs approved commands outside the dashboard and loads the resulting local files back into **Load Evidence**.

## Field shell doctrine

**PowerShell first.**

- Run PowerShell command blocks in **Windows PowerShell**.
- Do not use Git Bash / MINGW64 for the field-tech path.
- Do not use CMD for PowerShell blocks.
- Do not paste Bash commands into the field workflow.
- Do not type demo hostnames manually for live work.
- Do not use `C:\Temp` as the live workflow.

CMD is only for simple Windows launcher actions, such as double-clicking `START-HERE-SysAdminSuite-Dashboard.bat`.

## Folder doctrine

| Path | Purpose |
|---|---|
| `targets/` | Tracked policy, schemas, and sanitized fixtures only |
| `targets/local/` | Preferred ignored live intake for approved source workbooks, AD exports, tracker CSVs, and raw target material before normalization |
| `logs/targets/` | Preserved ignored local target and evidence store |
| `survey/input/` | Normalized runtime staging generated from approved intake |
| `survey/output/` | Generated survey outputs and reports |
| `logs/nmap/` | Generated network probe output |
| `survey/artifacts/` | Generated local artifacts |

Live field preflight reads from `targets/local/` and `logs/targets/` first. `survey/input/` is staging only after an approved normalization step. `survey/output/` is generated output, not the place to invent live targets.

## Workflow at a glance

1. Export or copy the approved spreadsheet, AD export, tracker tab, or target source to `targets/local/` or `logs/targets/`.
2. Normalize if the selected source is not already a `.txt` or `.csv` with probe-ready hostnames/IPs.
3. Run the PowerShell network preflight.
4. Review the CSV under `survey/output/network_preflight/`.
5. Load the CSV into the dashboard with **Load Evidence**.

Network preflight is reachability and posture evidence only. It does not prove serial identity, AD registration, ownership, or deployment completion.

## Dashboard quick path

1. Double-click `START-HERE-SysAdminSuite-Dashboard.bat`.
2. Click **Start Cybernet Survey**.
3. Use the tutorial to select the PowerShell field path.
4. Run the displayed PowerShell command outside the dashboard.
5. Drop the resulting `network_preflight_*.csv` back into **Load Evidence**.

The dashboard never runs probes by itself. It teaches the operator what to run and reads the evidence files afterward.

## Select an approved target file

Run in Windows PowerShell:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1
```

With no `-TargetFile`, the script lists candidate `.txt` and `.csv` files from:

- `targets/local/`
- `logs/targets/`

Then it stops without probing. This is deliberate. The operator must select the approved target file.

## Run network preflight

Run in Windows PowerShell:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1 -TargetFile .\targets\local\approved_targets.csv -Ports 135,445,3389,9100
```

Alternative approved source root:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1 -TargetFile .\logs\targets\approved_confirm_hosts.txt -Ports 135,445,3389,9100
```

The script prints:

- selected target file
- target count
- selected ports
- output path
- current stage
- `[n/total]`
- percent complete
- final CSV path

Default output:

```text
survey/output/network_preflight/network_preflight_<timestamp>.csv
```

## Accepted target files

### Text target files

Rules:

- one hostname, IP address, or probe-ready identifier per line
- blank lines ignored
- lines beginning with `#` ignored
- whitespace trimmed

### CSV target files

Preferred columns:

- `HostName`
- `Hostname`
- `ComputerName`
- `DeviceName`
- `Name`

Also accepted when probe-ready or explicitly typed as hostname/IP:

- `Target`
- `Identifier`

Prefer hostnames over serial-only values when both exist. Serial-only rows are not network targets. Enrich or normalize serial-only material before preflight.

## Spreadsheet source on X:\

Do not probe a spreadsheet directly from `X:\` unless a tested SysAdminSuite ingestion path explicitly supports that source.

Preferred field flow:

1. Export the approved spreadsheet or target tab to CSV.
2. Place the CSV under `targets/local/` or `logs/targets/`.
3. Normalize if needed.
4. Run PowerShell network preflight against the selected CSV.

## Evidence notes

- DNS and ping failures may indicate guest network, wrong VLAN, DNS scope, firewall policy, or offline hosts.
- TCP port results are `Open`, `Closed`, or `NotChecked` when the PowerShell runtime lacks the needed command.
- AD exports define registered population, not live reachability.
- Nmap / Naabu remain reachability validation tools, not population authority.
- Serial matching comes from approved identity sources, trackers, AD/CMDB exports, SCCM/MDM, or operator evidence, not from network preflight alone.

## Hard rules

- Do not commit live target CSVs, scan output, dashboards, ZIPs, serials, MACs, or site evidence.
- Do not run broad scans without approved scope.
- Do not use spoofing, decoys, stealth flags, vuln scripts, brute force, or credential attacks.
- Do not claim network preflight found a serial unless an approved serial evidence source actually produced it.

This workflow is boring on purpose. Boring survives the field.
