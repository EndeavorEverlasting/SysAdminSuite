# SysAdminSuite — Consolidated v2.0

> **Branch:** `consolidate/v2.0`
> **Merged from:** 8 branches across the full history of this repo.
> **Constraint:** All tools must support offline / non-AD environments and provide dry-run capability before touching production machines.

---

## Repository Layout

```
SysAdminSuite/
├── Mapping/                    # Printer mapping — the primary toolset
│   ├── Controllers/            # Orchestrators (run these)
│   │   ├── RPM-Recon.ps1           ← Zero-risk recon: ListOnly + Preflight
│   │   ├── Run-WCC-Mapping.ps1     ← WCC site-specific batch runner
│   │   ├── Enforce-SingleHost.ps1  ← Push mapping to one host via SCHTASKS
│   │   └── Map-Run-Controller.ps1  ← General-purpose controller
│   ├── Workers/                # Transport engines (called by Controllers)
│   │   ├── Map-MachineWide.ps1         ← WinRM transport (PS7 → PS7)
│   │   ├── Map-MachineWide.NoWinRM.ps1 ← SMB + SCHTASKS (no WinRM needed) ✅
│   │   └── Map-MachineWide.v5Compat.ps1← PS5.1 compatible variant
│   ├── Config/                 # Host lists, queue CSVs, run sets
│   │   ├── host-mappings.csv       ← Host → UNC queue mapping table
│   │   ├── wcc_printers.csv        ← WCC printer inventory
│   │   ├── hosts.txt               ← Full host list
│   │   ├── hosts_smoke.txt         ← Smoke-test subset (2–3 hosts)
│   │   ├── templates/              ← Blank CSV templates
│   │   └── runs/                   ← Per-run host subsets (checkin/checkout)
│   ├── Archive/                # Legacy VBS + deprecated PS scripts (read-only)
│   ├── Logs/                   ← Runtime output (git-ignored, .gitkeep present)
│   ├── docs/
│   │   └── Runbook-WCC-R164.md     ← Step-by-step deployment runbook
│   └── CHANGELOG.md
│
├── GetInfo/                    # Hardware & printer inventory
│   ├── Get-MachineInfo.ps1         ← Parallel WMI: serial, IP, MAC, monitors
│   ├── Get-KronosClockInfo.ps1     ← Probe/lookup Kronos or other clocks by IP, MAC, serial, hostname
│   ├── Get-MonitorInfo.psm1        ← Monitor serial via WmiMonitorID
│   ├── Get-PrinterMacSerial.ps1    ← Printer MAC + serial via SNMP/WMI
│   ├── QueueInventory.ps1          ← List all queues on a print server
│   └── ZebraPrinterTest.ps1        ← Zebra label printer connectivity test
│
├── GUI/                        # Simple WinForms launcher for testing backend contracts
│   └── Start-SysAdminSuiteGui.ps1  ← Stop/status/history harness + Kronos lookup
│
├── Config/                     # Environment setup & software inventory
│   ├── Inventory-Software.ps1      ← ARP registry scan → CSV + HTML report
│   ├── Run-Preflight.ps1           ← Pre-deployment checklist runner
│   ├── Build-FetchMap.ps1          ← Builds installer fetch manifest
│   ├── Fetch-Installers.ps1        ← Downloads installers from sources.csv
│   ├── Fetch-DRYRUN.ps1            ← Dry-run version of Fetch-Installers
│   ├── GoLiveTools.ps1             ← Go-live deployment helper
│   ├── Stage-To-Clients.ps1        ← Stages files to client machines
│   ├── ImpactS-FixShortcuts.ps1    ← Repairs ImpactS application shortcuts
│   ├── sources.csv                 ← Installer source URLs
│   └── archive/                    ← Legacy versions
│
├── ActiveDirectory/            # AD group management
│   └── Add-Computers-To-PrintingGroup.ps1
│
├── EnvSetup/                   # Workstation environment setup
│   ├── Deploy-Shortcuts.ps1
│   └── Deploy-Shortcuts.bat
│
├── Utilities/                  # Shared helper functions
│   ├── Test-Network.ps1            ← Ping wrapper (fixed: was $Host collision)
│   ├── Map-Printer.ps1             ← Per-user Add-Printer wrapper (+WhatIf)
│   ├── Invoke-UndoRedo.ps1         ← Reversible action/session foundation for GUI-safe ops
│   ├── Invoke-FileShare.ps1        ← UNC share reachability check
│   ├── Take-Screenshot.ps1         ← Screen capture utility
│   └── Unblock-All.ps1             ← Unblock downloaded PS files
│
├── OCR/                        # Python OCR tools for printer label extraction
│   ├── locus_mapping_ocr.py
│   ├── build_host_unc_csv.py
│   └── printer_lookup.csv
│
├── Tests/
│   ├── Preflight.ps1               ← Manual preflight checklist
│   └── Pester/                     ← Automated offline unit tests
│       ├── Utilities.Tests.ps1     ← Test-Network, Map-Printer, Invoke-FileShare
│       ├── Mapping.Tests.ps1       ← CSV schema, worker script contracts
│       ├── GetInfo.Tests.ps1       ← Get-MachineInfo, QueueInventory, Kronos lookup contracts
│       └── Gui.Tests.ps1           ← GUI entry-point contract checks
│
└── Bug-Log.md                  ← Known bugs and fixes (coding standard)
```

---

## Quick Start

### Dry-run / Offline Validation (safe on any machine)
```powershell
# Run all Pester tests — no network, no AD, no printers needed
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester .\Tests\Pester\ -Output Detailed
```

### Printer Mapping — Recon (read-only, no changes)
```powershell
# From repo root (PowerShell 7+, elevated)
pwsh -File .\Mapping\Controllers\RPM-Recon.ps1 -HostsPath .\Mapping\Config\hosts_smoke.txt
```

### Undo/Redo Capture — Opt-in reversible action logs
```powershell
# Controller: records scheduled-task create/delete plus remote worker actions
pwsh -File .\Mapping\Controllers\Map-Run-Controller.ps1 `
    -Computers WKS001 `
    -LocalScriptPath .\Mapping\Workers\Map-MachineWide.ps1 `
    -EnableUndoRedo

# Worker: emits printer action history into the artifact bundle as UndoRedo.json
pwsh -File .\Mapping\Workers\Map-MachineWide.ps1 -Queues '\\PRINTSRV\Q01' -EnableUndoRedo
```

### GUI Stop/Status + Replay Hooks
```powershell
# Ask a running controller/worker session to stop gracefully
. .\Utilities\Invoke-RunControl.ps1
Request-RunStop -Path .\Mapping\Output\Stop.json -Reason 'GUI stop button pressed'

# Rehydrate a saved session for GUI history/replay
. .\Utilities\Invoke-UndoRedo.ps1
$session = Import-UndoRedoSession -Path .\Mapping\Output\UndoRedo.Controller.json
Replay-UndoRedoAction -Session $session -Operation Undo -WhatIf
```

- Running work now polls a file-based stop signal, similar to `Ctrl+C`, and emits the latest available `status.json`, results, and undo/redo artifacts before exiting.
- GUI clients can load `UndoRedo.json` / `UndoRedo.Controller.json` to display reversible history and drive top-of-stack undo/redo actions.

### Kronos Clock Identity Inventory + Lookup
```powershell
# Probe one or more clocks and export a reusable inventory CSV
powershell.exe -File .\GetInfo\Get-KronosClockInfo.ps1 `
    -Targets 10.10.40.25,KRONOS-CLOCK-01 `
    -OutCsv .\GetInfo\KronosClockInventory.csv

# Later, resolve any known identifier back to the rest of the identity record
powershell.exe -File .\GetInfo\Get-KronosClockInfo.ps1 `
    -InventoryPath .\GetInfo\KronosClockInventory.csv `
    -LookupBy MAC `
    -LookupValue '00:11:22:33:44:55'
```

- The clock inventory script attempts reverse DNS, ARP, SNMP system identifiers, and HTTP page metadata so you can hand Kronos/UKG a stable packet of details after DHCP reservation.
- Inventory CSVs can be re-used for cross-lookup workflows such as `MAC -> serial/hostname`, `serial -> MAC/IP`, or `hostname -> serial/MAC`.

### Launch the test GUI
```powershell
powershell.exe -STA -File .\GUI\Start-SysAdminSuiteGui.ps1
```

- The GUI is safe-by-default for replay: the Undo/Redo buttons start in `WhatIf` mode.
- It exposes the new Stop/status/history hooks and a simple Kronos lookup panel so you can test the plumbing on an admin box without building a larger front end first.

### Printer Mapping — Live Run (WhatIf first!)
```powershell
# WhatIf dry-run — shows what WOULD happen
& .\Mapping\Workers\Map-MachineWide.NoWinRM.ps1 `
    -HostsPath .\Mapping\Config\hosts_smoke.txt `
    -Queues '\\SWBPNHPHPS01V\LS111-WCC67' `
    -WhatIf

# Real run (elevated, PS7+)
& .\Mapping\Workers\Map-MachineWide.NoWinRM.ps1 `
    -HostsPath .\Mapping\Config\hosts_smoke.txt `
    -Queues '\\SWBPNHPHPS01V\LS111-WCC67' `
    -Verify
```

---

## Known Bugs Fixed (see Bug-Log.md)

| # | Bug | Fix |
|---|-----|-----|
| 1 | `$Host` variable collision | Renamed to `$ComputerName` / `$HostName` / `$TargetHost` throughout |
| 2 | `$PSScriptRoot` misuse | Documented: only valid inside a running script file, not dot-sourced |
| 3 | CSV `.Path` fallacy | `Import-Csv` rows have no `.Path`; use `$_.FullName` from `Get-ChildItem` |

---

## Transport Decision Tree

```
Need to map printers on remote machines?
│
├─ WinRM enabled on targets? ──Yes──► Map-MachineWide.ps1 (fastest)
│
└─ No WinRM (most common) ──────────► Map-MachineWide.NoWinRM.ps1
       Uses: SMB (\\HOST\C$) + SCHTASKS /S HOST
       Requires: Admin share access + RPC port 135/445
       Offline-safe: drops agent, polls for status.json
```

---

## Requirements

- **Controller machine:** PowerShell 7.2+ (for `ForEach-Object -Parallel`)
- **Target machines:** Windows 10/11, PowerShell 5.1+ (no WinRM required with NoWinRM worker)
- **Tests:** Pester 5.0+ (`Install-Module Pester -Scope CurrentUser`)
- **OCR tools:** Python 3.8+, `pytesseract`, `Pillow`
