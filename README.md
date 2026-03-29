# SysAdminSuite -- Consolidated v2.0

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
│   ├── Get-RamInfo.ps1             ← Parallel CIM: per-DIMM capacity, speed, type, form factor, voltages
│   ├── Get-KronosClockInfo.ps1     ← Probe/lookup Kronos or other clocks by IP, MAC, serial, hostname
│   ├── Get-MonitorInfo.psm1        ← Monitor identity, display number, dock EDID cache tools
│   ├── Get-PrinterMacSerial.ps1    ← Printer MAC + serial via SNMP/WMI
│   ├── QueueInventory.ps1          ← List all queues on a print server
│   └── ZebraPrinterTest.ps1        ← Zebra label printer connectivity test
│
├── GUI/                        # WinForms control center (start here)
│   └── Start-SysAdminSuiteGui.ps1  ← Printer mapping, Kronos lookup, Machine Info probe, guided tutorial
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
├── tools/                      # Repo maintenance utilities
│   ├── Invoke-RepoFileHealth.ps1   ← BOM enforcement, lock removal, line-ending normalisation
│   ├── Add-Utf8Bom.ps1             ← Standalone UTF-8 BOM enforcement tool
│   ├── Test-ScriptHealth.ps1       ← Parse check + BOM check + non-ASCII scan
│   └── Resolve-PSRuntime.ps1       ← PS version detection and pivot (5.1 vs 7+)
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
│       ├── GetInfo.Tests.ps1       ← Get-MachineInfo, Get-RamInfo, QueueInventory, Kronos lookup contracts
│       └── Gui.Tests.ps1           ← GUI entry-point contract checks
│
├── Launch-SysAdminSuite.bat     ← Double-click to open the GUI (no command to memorize)
└── Bug-Log.md                  ← Known bugs and fixes (coding standard)
```

---

## Quick Start

### Launch the GUI (recommended starting point)

The easiest way to launch the GUI is to **double-click** the batch file at the repo root:

```
Launch-SysAdminSuite.bat
```

Or from PowerShell:

```powershell
powershell.exe -STA -File .\GUI\Start-SysAdminSuiteGui.ps1
```

> **Why `-STA`?** WinForms requires Single Threaded Apartment mode. Without it the window won't render.

On first launch a **menu-based tutorial** appears with 12 use-case tracks. Pick the one you need and follow 3-5 focused steps that end with real example output. Reopen anytime with **Ctrl+T** or the **Tutorial** button in the status bar.

**Tutorial tracks:**

| Track | What it teaches |
|-------|----------------|
| **Printer Mapping** | Load example, run Recon, see Results.csv output |
| **Kronos Clock** | Probe a clock IP, read MAC/serial table, search inventory |
| **Neuron MachineInfo** | Use the Machine Info tab, probe Neuron PCs, get serial/IP/MAC CSV |
| **Printer MachineInfo** | Use the Machine Info tab, probe printers, get MAC/serial via SNMP |
| **Cybernet / Workstation Info** | Same as Neuron but for Cybernet or any Windows PC (all in the GUI) |
| **Printer Layout (Recon)** | Snapshot existing printers before deciding what to map |
| **Repo File Health** | Fix BOM, encoding, locks, and line endings across the repo |
| **Software Inventory** | Audit installed software across machines with CSV output |
| **Network Testing** | Test connectivity, DNS, and ports before running probes |
| **AD Printing Group** | Bulk-add computers to AD printing security groups |
| **Monitor Identification** | Identify displays, diagnose dock phantom monitors, export HTML report |
| **PS Version Pivot** | How tools detect and switch between PS 5.1 and PS 7 |

**GUI tabs:**

| Tab | What it does |
|-----|-------------|
| **Run Control** | Configure and launch printer-mapping runs (Recon, Plan, Full Run), monitor live status, undo/redo changes |
| **Kronos Lookup** | Probe network clocks by IP, collect MAC/serial/model, search saved inventories |
| **Machine Info** | Run Get-MachineInfo or Get-PrinterMacSerial from the GUI — enter targets, pick output path, view results inline |
| **UTF-8 BOM Sync** | Scan repo for files with/without UTF-8 BOM, move files between panels, and sync to apply BOM to all selected files |

All path fields (Stop signal, Status, History, CSV paths) are clickable — click them to open a file browser.

### Tutorial Architecture (for contributors)

The tutorial system lives in `GUI/Start-SysAdminSuiteGui.ps1` and is designed for easy extension:

- **`$script:TutorialTracks`** — ordered hashtable of track definitions. Each key maps to `Label`, `Desc`, `Color`, and `Steps` (array of step hashtables).
- **Each step** has `Title`, `Body`, and `Highlights` (array of control variable names to pulse).
- **`Show-TutorialMenu`** renders the track picker. **`Start-TutorialTrack`** loads a track's steps.
- **Highlight system** pulses gold/yellow on most controls; green START and red STOP buttons keep their identity color and pulse text instead.
- To **add a new track**: add an entry to `$script:TutorialTracks` with the same structure. The menu rebuilds automatically.

---

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

### RAM Info — Per-DIMM Hardware Inventory

```powershell
# Probe all machines in a host list and export a per-DIMM CSV
powershell.exe -File .\GetInfo\Get-RamInfo.ps1 `
    -ListPath .\hosts.txt `
    -OutputPath C:\Temp\RamInfo.csv

# Run against a single machine by putting just that name in a temp file
'WKS-001' | Set-Content C:\Temp\single.txt
powershell.exe -File .\GetInfo\Get-RamInfo.ps1 `
    -ListPath C:\Temp\single.txt `
    -OutputPath C:\Temp\RamInfo.csv
```

Each row in the CSV represents **one physical memory stick**. Every machine always appears in the output — offline and unreachable hosts land as placeholder rows so nothing is silently skipped.

**Output columns:**

| Column | Description |
|--------|-------------|
| `Timestamp` | Date/time the query ran |
| `HostName` | Machine name from the host list |
| `DeviceLocator` | Slot label (e.g. `DIMM_A1`, `ChannelA-DIMM0`) |
| `BankLabel` | Bank label reported by firmware |
| `Manufacturer` | DIMM manufacturer (e.g. Samsung, Micron, Hynix) |
| `PartNumber` | Manufacturer part number |
| `SerialNumber` | DIMM serial number |
| `CapacityGB` | Stick size rounded to 2 decimal places |
| `Speed` | Rated speed in MHz |
| `ConfiguredClockSpeed` | Actual running clock speed in MHz |
| `MemoryType` | Human-readable type (DDR4, DDR5, LPDDR4, etc.) |
| `FormFactor` | Physical form (DIMM, SODIMM, etc.) |
| `TotalWidth` | Total bus width in bits (data + ECC) |
| `DataWidth` | Data bus width in bits |
| `ConfiguredVoltage` | Running voltage in millivolts |
| `MinVoltage` / `MaxVoltage` | Supported voltage range in millivolts |
| `InterleavePosition` / `InterleaveDataDepth` | Memory interleave configuration |
| `PositionInRow` | Position within the memory row |
| `Attributes` | Firmware attribute flags |
| `Status` | `OK`, `Offline`, `Query Failed`, or `No Sticks Reported` |
| `ErrorMessage` | Exception detail when `Status` is `Query Failed`, empty otherwise |

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ListPath` | `C:\Temp\hostlist.txt` | Plain-text file, one hostname per line |
| `-OutputPath` | `C:\Temp\RamInfo.csv` | Destination CSV (directory is created if missing) |
| `-Throttle` | `15` | Maximum concurrent background jobs |

### Monitor Identification & Dock EDID Analysis

```powershell
# See which physical monitor is Display 1 / 2 / 3 in Windows Settings
Import-Module .\GetInfo\Get-MonitorInfo.psm1 -Force
Get-MonitorInfo | Format-List

# Before/after diff — interactive: prompts you to swap cables, then compares
Invoke-MonitorDiff

# Flush stale EDID from a DisplayLink dock (requires elevation)
Reset-DisplayDeviceCache
Get-MonitorInfo | Format-List   # now reflects only physically-connected monitors
```

`Get-MonitorInfo` bridges WMI monitor hardware data (model, serial, manufacturer) with the Windows display topology (Settings display number, primary status, screen coordinates) by calling `QueryDisplayConfig` via P/Invoke.

**Functions in `Get-MonitorInfo.psm1`:**

| Function | Purpose |
|----------|---------|
| `Get-MonitorInfo` | Returns per-monitor objects with `DisplayNumber`, `IsPrimary`, `Model`, `Serial`, `Manufacturer`, `Resolution`, `ScreenBounds`, `Connection`, `DevicePath`, `Adapter` |
| `Reset-DisplayDeviceCache` | Cycles DisplayLink PnP adapters (disable → enable → rescan) to flush cached EDID. Requires elevation |
| `Invoke-MonitorDiff` | Captures before/after snapshots and outputs structured diff (`Appeared` / `Disappeared` / `Changed` / `Unchanged`). Accepts `-Reset` for automated cache flush or `-BeforeSnapshot` for scripted pipelines |

#### ThinkPad Hybrid USB-C Dock — EDID Caching Behaviour

The **Lenovo ThinkPad Hybrid USB-C with USB-A Dock** (DisplayLink `VID_17E9&PID_6015`) exposes two display adapter interfaces (`MI_00`, `MI_01`) as separate video controllers. Cable-swap analysis revealed the following driver behaviour:

| Observation | Detail |
|-------------|--------|
| **Phantom monitors** | The dock's `MI_00` interface retains the EDID identity of the last-connected monitor even after it is physically unplugged. WMI reports it as `Active=True`, `Status=OK`, `Present=True`. Only cycling the adapter via `Reset-DisplayDeviceCache` (or physically reconnecting the dock) clears the phantom |
| **UIDs are port-bound** | Each physical output on the dock has a fixed UID (e.g. `UID256`, `UID257`). Swapping cables between ports swaps which monitor receives which UID — the UID follows the port, not the monitor |
| **Display numbers follow ports** | Windows assigns Settings display numbers (1, 2, 3) by `QueryDisplayConfig` source-ID order, which is tied to the GDI device name (e.g. `\\.\DISPLAY40`). After a cable swap, the display number stays with the port and the monitor identity behind it changes |
| **Primary follows the monitor** | Windows tracks the "main display" preference by monitor hardware identity (PnP Device ID), not by port. After a cable swap, the primary designation moves with the monitor to its new display number |

> **Practical impact:** If your dock is holding a phantom Display 1 from a previously-connected TV, run `Reset-DisplayDeviceCache` in an elevated session to force re-enumeration. Then `Get-MonitorInfo` will show only what is physically present.

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

### Launch the GUI (see Quick Start above for full walkthrough)
```powershell
powershell.exe -STA -File .\GUI\Start-SysAdminSuiteGui.ps1
```

- The GUI is safe-by-default: WhatIf is ON, Run Mode defaults to Recon Only, and Preflight is checked.
- An interactive tutorial auto-launches on first open and at key checkpoints (e.g., switching to the Kronos tab). Reopen it anytime with **Ctrl+T**.
- All path fields are clickable — click them to open a file browser, or use the **[...]** buttons.

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

### Repo File-Health Tools

```powershell
# All-in-one: dry-run (safe, read-only)
.\tools\Invoke-RepoFileHealth.ps1

# All-in-one: apply fixes (BOM + locks + line endings)
.\tools\Invoke-RepoFileHealth.ps1 -Fix

# BOM only: dry-run
.\tools\Add-Utf8Bom.ps1

# BOM only: apply
.\tools\Add-Utf8Bom.ps1 -Fix

# Validate scripts: parse errors + BOM + non-ASCII scan
.\tools\Test-ScriptHealth.ps1

# Target LF line endings instead of CRLF
.\tools\Invoke-RepoFileHealth.ps1 -Fix -LineEnding LF
```

| Tool | Purpose |
|------|---------|
| **Invoke-RepoFileHealth.ps1** | All-in-one: BOM, locks, line endings, non-ASCII scan |
| **Add-Utf8Bom.ps1** | Standalone BOM enforcement (fast, targeted) |
| **Test-ScriptHealth.ps1** | Validation only: parse check + BOM check + non-ASCII scan |
| **Resolve-PSRuntime.ps1** | Dot-source in scripts to detect PS version and pivot when needed |

What Invoke-RepoFileHealth checks:

| Check | Extensions | Action |
|-------|-----------|--------|
| **UTF-8 BOM** | `.ps1`, `.psm1`, `.psd1`, `.csv` | Prepends `EF BB BF` so PowerShell 5.1 and Excel read them correctly |
| **Zone.Identifier lock** | all scanned | Calls `Unblock-File` and removes the ADS so Windows stops showing security warnings |
| **Line endings** | all scanned | Normalises to CRLF (default) or LF to prevent mixed-ending diffs |
| **Non-ASCII chars** | `.ps1`, `.psm1`, `.psd1` | Flags characters > U+007F that break PS 5.1 without BOM |

### PowerShell Version Pivot

Scripts that need a specific PS version can dot-source `Resolve-PSRuntime.ps1`:

```powershell
. "$PSScriptRoot\..\tools\Resolve-PSRuntime.ps1"

# Check which engine we are on
if ($PSRuntimeIs5) { Write-Host "Running on Windows PowerShell 5.1" }
if ($PSRuntimeIs7) { Write-Host "Running on PowerShell 7+" }

# Auto-pivot to PS7 if needed
Invoke-PSPivot -RequiredVersion 7 -ScriptPath $PSCommandPath -Arguments $PSBoundParameters
```

When a pivot occurs, the user sees a magenta log line:
```
[Resolve-PSRuntime] PIVOT: PS 5 -> PS 7 | Script: C:\...\MyScript.ps1 | Engine: C:\...\pwsh.exe
```

---

## Requirements

- **Controller machine:** PowerShell 7.2+ (for `ForEach-Object -Parallel`)
- **Target machines:** Windows 10/11, PowerShell 5.1+ (no WinRM required with NoWinRM worker)
- **Tests:** Pester 5.0+ (`Install-Module Pester -Scope CurrentUser`)
- **OCR tools:** Python 3.8+, `pytesseract`, `Pillow`
