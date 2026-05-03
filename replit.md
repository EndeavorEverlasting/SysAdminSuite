# SysAdminSuite v2.0

## Overview

A consolidated SysAdmin toolkit targeting Northwell environments. The project is **Bash-first** for new Northwell work; PowerShell scripts are **active production tooling** used daily in Windows environments (WMI, printer mapping, AD, deployment tracking, GUI). A Python web server (`server.py`) provides an overview page and the SysAdmin Suite Dashboard in the Replit preview pane.

## Architecture

- **Bash scripts** (`survey/`, `deployment-audit/`, `bash/`) — primary operational tooling for Northwell
- **Python scripts** (`OCR/`) — floorplan OCR, printer/workstation layout mapping
- **.NET 8 C#** (`src/SysAdminSuite.Core`, `managed-tests/`) — shared managed library + xUnit tests
- **PowerShell** (`mapping/`, `GetInfo/`, `GUI/`, `Config/`, `ActiveDirectory/`, `QRTasks/`, `Utilities/`, `tools/`) — active production tooling, Windows environments
- **`dashboard/`** — SysAdmin Suite Dashboard: served by server.py at `/dashboard/`. The runtime entry point is `dashboard/js/bundle.js` (a generated non-module concatenation of all JS sources — works on file:// URLs too). Source modules remain in `dashboard/js/*.js` for development; regenerate the bundle after any JS change: `node dashboard/build-bundle.js`
- **`server.py`** — Python HTTP server; serves overview at `/` and dashboard at `/dashboard/` (port 5000)

## Replit Setup

- **Workflow:** "Start application" — runs `python3 server.py` on port 5000
- **Language:** Python 3.12 (Replit module), Bash
- **Port:** 5000 (webview)
- **Dashboard URL:** `/dashboard/`

## Key Files

- `server.py` — Replit web overview server (port 5000, host 0.0.0.0); serves `/dashboard/` as static files
- `dashboard/index.html` — SysAdmin Suite Dashboard entry point (standalone, no build required)
- `dashboard/css/style.css` — dark-mode dashboard styles
- `dashboard/js/app.js` — main dashboard controller (ES module)
- `dashboard/js/parsers.js` — file type detection and data normalization
- `dashboard/js/utils.js` — CSV parsing, export, sorting, filtering utilities
- `dashboard/js/panel-printer.js` — Printer Mapping panel
- `dashboard/js/panel-inventory.js` — Hardware Inventory panel
- `dashboard/js/panel-tasks.js` — Remote Task / QR Activity panel
- `dashboard/js/panel-network.js` — Network & Protocol Trace panel
- `dashboard/js/panel-software.js` — Software Tracker panel (sources.yaml / JSON drag-drop)
- `dashboard/samples/` — sample data files for testing each panel
- `survey/sas-survey-targets.sh` — Bash survey target resolver (Cybernet/Neuron)
- `deployment-audit/sas-audit-deployments.sh` — deployment tracker audit
- `OCR/locus_mapping_ocr.py` — floorplan OCR for printer/workstation mapping
- `src/SysAdminSuite.Core/` — .NET 8 core library
- `managed-tests/` — xUnit test project
- `SysAdminSuite.sln` — .NET solution file
- `GUI/Start-SysAdminSuiteGui.ps1` — WinForms GUI (Windows only)
- `AGENTS.md` — agent instructions (Bash-first policy)

## Dashboard — Supported File Types

| Filename Pattern | Panel | Schema |
|---|---|---|
| `Preflight.csv` | Printer Mapping | SnapshotTime, ComputerName, Type, Target, PresentNow, InDesired |
| `Results.csv` | Printer Mapping | Timestamp, ComputerName, Type, Target, Driver, Port, Status |
| `printer_probe.csv` | Printer Mapping + Network | Timestamp, Target, PingStatus, MAC, Serial, Source |
| `workstation_identity.csv` | Network Trace | Timestamp, Target, TransportUsed, IdentityStatus, ObservedHostName, … |
| `network_preflight.csv` | Network Trace | Timestamp, Target, PingStatus, Port, PortStatus |
| `MachineInfo_Output.csv` | Hardware Inventory | Timestamp, HostName, Serial, IPAddress, MACAddress, MonitorSerials |
| `RamInfo_Output.csv` | Hardware Inventory | Timestamp, HostName, DeviceLocator, CapacityGB, Speed, MemoryType |
| `NeuronNetworkInventory_*.csv/.json` | Hardware Inventory | Timestamp, TargetHost, IPAddress, MACAddress, SerialNumber, Model |
| `status.json` | Status Footer | State, Stage, Message, Timestamp |
| QRTask / RunControl logs | Remote Tasks | Timestamp, Machine, TaskName, Outcome |
| `smb_readonly_recon.csv` | Network Trace | Target, Share, Reachable, ListStatus |
| `sources.yaml` | Software Tracker | apps list (name, source, repo, strategy, version, type, detect…) |
| `*.json` from `sas-list-apps.sh --json` | Software Tracker | Array of app objects matching sources.yaml schema |

## Running Components in This Environment (Linux/Replit)

- Bash scripts: `survey/`, `deployment-audit/`, `bash/`
- Python OCR tools: `OCR/*.py` (requires opencv, pytesseract, pandas)
- .NET managed code: requires `dotnet` SDK (not pre-installed)
- PowerShell scripts: require Windows or `pwsh` on Linux

## Language Hierarchy

The project hierarchy is Bash → PowerShell → Linux native → C → Rust → Lua (in planned order).

## Agent Policy (from AGENTS.md)

### Bash
- Default to Bash for new operational features
- New features go in `survey/`, `bash/`, `bin/`, or `scripts/`

### PowerShell — NEVER treat as dead code
- PowerShell scripts are **active, production-relevant tooling** used in real corporate
  Windows environments daily (WMI hardware queries, printer mapping, AD lookups,
  deployment tracking, GUI)
- Do **not** remove, truncate, or label PowerShell files as "legacy" or "deprecated"
  unless the user explicitly says so
- AI models tend to delete PowerShell silently — this must be actively resisted
- Always generate PowerShell commands alongside Bash commands in documentation and dashboards
- When in doubt: keep the PowerShell file, add a Bash equivalent beside it

### Dashboard Live Mode command order
Always: **1 — Bash**, **2 — PowerShell**, **3 — Linux native**. Never omit PowerShell.
