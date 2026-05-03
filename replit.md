# SysAdminSuite v2.0

## Overview

A consolidated SysAdmin toolkit targeting Northwell environments. The project is **Bash-first** for new Northwell work; PowerShell scripts are retained as legacy/reference tooling. A Python web server (`server.py`) provides an overview page in the Replit preview pane.

## Architecture

- **Bash scripts** (`survey/`, `deployment-audit/`, `bash/`) — primary operational tooling for Northwell
- **Python scripts** (`OCR/`) — floorplan OCR, printer/workstation layout mapping
- **.NET 8 C#** (`src/SysAdminSuite.Core`, `managed-tests/`) — shared managed library + xUnit tests
- **PowerShell** (`mapping/`, `GetInfo/`, `GUI/`, `Config/`, `ActiveDirectory/`, `QRTasks/`, `Utilities/`, `tools/`) — legacy/reference, Windows-only
- **`server.py`** — simple Python HTTP server serving the project overview at port 5000

## Replit Setup

- **Workflow:** "Start application" — runs `python3 server.py` on port 5000
- **Language:** Python 3.12 (Replit module), Bash
- **Port:** 5000 (webview)

## Key Files

- `server.py` — Replit web overview server (port 5000, host 0.0.0.0)
- `survey/sas-survey-targets.sh` — Bash survey target resolver (Cybernet/Neuron)
- `deployment-audit/sas-audit-deployments.sh` — deployment tracker audit
- `OCR/locus_mapping_ocr.py` — floorplan OCR for printer/workstation mapping
- `src/SysAdminSuite.Core/` — .NET 8 core library
- `managed-tests/` — xUnit test project
- `SysAdminSuite.sln` — .NET solution file
- `GUI/Start-SysAdminSuiteGui.ps1` — WinForms GUI (Windows only)
- `AGENTS.md` — agent instructions (Bash-first policy)

## Running Components in This Environment (Linux/Replit)

- Bash scripts: `survey/`, `deployment-audit/`, `bash/`
- Python OCR tools: `OCR/*.py` (requires opencv, pytesseract, pandas)
- .NET managed code: requires `dotnet` SDK (not pre-installed)
- PowerShell scripts: require Windows or `pwsh` on Linux

## Agent Policy (from AGENTS.md)

- Default to Bash for new features
- Do not edit PowerShell files unless explicitly asked
- PowerShell = legacy/reference for Northwell; acceptable for other environments
- New features go in `survey/`, `bash/`, `bin/`, or `scripts/`
