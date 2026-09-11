# Start Here: Cybernet / Neuron Network Survey

This is the field-facing entrypoint for Cybernet / Neuron network survey work.

Use it when you need to validate network posture or Cybernet hardware identity from an approved target population using a local admin workstation. Generated evidence stays local and is loaded back into the dashboard only when useful.

## Finding missing Cybernets specifically

When the mission is **find deployed Cybernet workstations**, do not start with the generic mixed-device port example on this page. TCP 9100 is printer-oriented, and broad web/remote-management port sets surface access points, printers, servers, and other infrastructure that should never become Cybernet hardware-metadata targets.

The primary technician command is now **CMD-first**:

```cmd
C:\SASAL\Probe-Cybernet.cmd HOST01 HOST02
```

That command asks one concrete question: **is each explicit candidate a Windows client workstation, and can it return model + serial for comparison with the approved Cybernet hardware reference?**

It refreshes current `origin/main` through the repository-owned Guest/Internet sync transaction **before target contact**, restores network posture, re-enters the refreshed sealed `C:\SASAL` command, then runs the bounded identity canary. Do not prepend an ad-hoc `git pull`, and do not substitute a generic network probe.

Use [`docs/CYBERNET_LOW_NOISE_CANARY.md`](docs/CYBERNET_LOW_NOISE_CANARY.md) and [`harness/maps/CYBERNET_HARDWARE_IDENTITY_MAP.md`](harness/maps/CYBERNET_HARDWARE_IDENTITY_MAP.md) for the full proof ladder:

1. reuse authoritative non-Cybernet exclusions first;
2. approved **computer** candidates only;
3. TCP **135 + 445** is metadata-candidate evidence only;
4. one read-only DCOM/CIM session only after both ports pass;
5. Windows client `ProductType=1` must be proved before manufacturer/model/serial;
6. model + serial are observed hardware facts;
7. `CONFIRMED_CYBERNET` still requires the approved Cybernet hardware reference.

## Before any live command — complete operator handoff

The Cybernet CMD composes the repository handoff contract: **path → freshness → network intent → command → restoration**.

1. **Canonical path** — use the sealed `C:\SASAL\Probe-Cybernet.cmd` field surface when available.
2. **Repository freshness** — the CMD invokes the canonical refresh transaction before target contact. Remote Git happens only in the Guest/Internet sync cache; the caller checkout is not blindly pulled or reset.
3. **Starting network + restoration** — refresh uses the repository network-intent transaction and returns to the recorded starting posture before the refreshed canary is entered.
4. **Required network intent** — the canary requires approved WAB or an authenticated DomainAuthenticated non-Wi-Fi VPN/LAN posture before target traffic.
5. **Execute one bounded probe** — only explicit candidates, at most five, and only the evidence needed to decide whether workstation hardware identity can be collected.
6. **Preserve evidence** — use the local result/summary/completion artifacts; never promote a failed stage to Cybernet identity proof.

If refresh or network restoration fails, target probing must not begin.

## Field shell doctrine

**CMD first for the bounded Cybernet identity probe.**

- Use `Probe-Cybernet.cmd` for the technician-facing Cybernet identity question.
- Use Windows PowerShell for repository PowerShell-only diagnostics and the generic field-tech preflight below.
- Use Git Bash / Bash-on-Windows only for the optional Naabu PC-signature population-reduction lane.
- Do not paste PowerShell blocks into CMD or Git Bash.
- Do not type demo hostnames into live work; replace placeholders only with explicit approved candidates.
- Do not use `C:\Temp` as the live workflow authority.

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

Live field evidence belongs in ignored local roots. `survey/output/` is generated output, not the place to invent live targets.

## Generic network-preflight workflow

Use this only when the mission is general network posture rather than Cybernet hardware identity:

1. Export or copy the approved spreadsheet, AD export, tracker tab, or target source to `targets/local/` or `logs/targets/`.
2. Normalize if the selected source is not already a `.txt` or `.csv` with probe-ready hostnames/IPs.
3. Run the PowerShell network preflight.
4. Review the CSV under `survey/output/network_preflight/`.
5. Load the CSV into the dashboard with **Load Evidence** when useful.

Network preflight is reachability and posture evidence only. It does not prove serial identity, AD registration, ownership, or deployment completion.

## Dashboard quick path

1. Double-click `START-HERE-SysAdminSuite-Dashboard.bat`.
2. Click **Start Cybernet Survey**.
3. Use the tutorial to select the appropriate field path.
4. Run the approved command outside the dashboard.
5. Load the resulting local evidence only when it answers the current question.

The dashboard never runs probes by itself.

## Select an approved target file for generic preflight

Run in Windows PowerShell:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1
```

With no `-TargetFile`, the script lists candidate `.txt` and `.csv` files from `targets/local/` and `logs/targets/`, then stops without probing so the operator can select the approved source.

## Run generic mixed-purpose network preflight

These examples deliberately ask a different question—workstation/RDP/printer posture—and are **not** the professional first-pass Cybernet hunt.

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1 -TargetFile .\targets\local\approved_targets.csv -Ports 135,445,3389,9100
```

Alternative approved source root:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1 -TargetFile .\logs\targets\approved_confirm_hosts.txt -Ports 135,445,3389,9100
```

Default generic output:

```text
survey/output/network_preflight/network_preflight_<timestamp>.csv
```

## Accepted target files

Text files use one hostname, IP address, or probe-ready identifier per line; blank/comment lines are ignored. CSV sources should prefer `HostName`, `Hostname`, `ComputerName`, `DeviceName`, or `Name`, with `Target`/`Identifier` accepted when explicitly probe-ready. Prefer hostnames over serial-only values when both exist; serial-only rows are not network targets.

## Spreadsheet source on X:\

Do not probe a spreadsheet directly from `X:\` unless a tested SysAdminSuite ingestion path explicitly supports it. Export the approved tab to CSV, place it under `targets/local/` or `logs/targets/`, normalize if needed, then use the appropriate bounded workflow.

## Evidence notes

- DNS and ping failures may indicate guest network, wrong VLAN, DNS scope, firewall policy, or offline hosts.
- AD exports define registered population, not live reachability.
- Nmap / Naabu remain reachability validation tools, not population authority.
- Serial/model matching comes from approved hardware identity sources, not from network preflight alone.
- A hostname, software footprint, open port, subnet clue, or OUI does not by itself exclude or confirm Cybernet hardware.

## Hard rules

- Do not commit live target CSVs, scan output, dashboards, ZIPs, serials, MACs, or site evidence.
- Do not run broad scans without approved scope.
- Do not use spoofing, decoys, stealth flags, vuln scripts, brute force, or credential attacks.
- Do not claim network preflight found a serial unless an approved serial evidence source actually produced it.
- Do not use the generic mixed-purpose 9100/RDP preflight as the default way to hunt missing Cybernets.
- Do not skip the CMD currentness gate merely because the caller checkout appears clean.

This workflow is boring on purpose. Boring survives the field.
