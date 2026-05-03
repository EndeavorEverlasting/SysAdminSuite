# SysAdminSuite -- Consolidated v2.0

> **Primary development branch:** `main` (feature branches merge here; older names like `consolidate/v2.0` are historical only.)
> **Merged from:** 8 branches across the full history of this repo.
> **Constraint:** All tools must support offline / non-AD environments and provide dry-run capability before touching production machines.

---

## Runtime policy (C# / native first)

- **Primary supported path for restricted endpoints:** **compiled** tooling — **.NET (C#)** for the GUI and most automation, and **native C++** under [`mapping/native`](mapping/native/README.md) for printer mapping where `powershell.exe` is blocked or scripting policy is strict. Artifact and CLI contracts are documented in [`mapping/native/CONTRACT.md`](mapping/native/CONTRACT.md).
- **PowerShell scripts** (`.ps1` / `.psm1`) remain in the repository as **maintained, optional** tooling for environments that allow them (labs, build hosts, less restricted sites). They are kept for parity checks, migration reference, and future rollout — not removed.
- **Unit tests:** managed code is covered by **`dotnet test`** on [`SysAdminSuite.sln`](SysAdminSuite.sln) (projects under [`src/`](src/) and [`managed-tests/`](managed-tests/)); script behavior continues to be covered by the **Pester** suite under [`Tests/Pester`](Tests/Pester).

---

## Repository Layout

```
SysAdminSuite/
├── src/                        # .NET class libraries (managed tooling foundation)
├── managed-tests/              # .NET unit tests (xUnit; separate folder — `Tests/` is reserved for Pester on Windows)
├── SysAdminSuite.sln           # Managed solution entrypoint
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
│   ├── native/                 # C++ mapping Worker + Controller (no CLR; see native/README.md)
│   └── CHANGELOG.md
│
├── GetInfo/                    # Hardware & printer inventory
│   ├── Get-MachineInfo.ps1         ← Parallel WMI: serial, IP, MAC, monitors
│   ├── Get-RamInfo.ps1             ← Parallel CIM: per-DIMM capacity, speed, type, form factor, voltages
│   ├── Get-KronosClockInfo.ps1     ← Probe/lookup Kronos or other clocks by IP, MAC, serial, hostname
│   ├── Get-MonitorInfo.psm1        ← Monitor identity, display number, dock EDID cache tools
│   ├── Get-PrinterMacSerial.ps1    ← Printer MAC + serial via SNMP/WMI
│   ├── QueueInventory.ps1          ← List all queues on a print server
│   ├── ZebraPrinterTest.ps1        ← Zebra label printer connectivity test
│   └── Get-WindowsKey.ps1          ← Pull Windows product key (WMI + registry fallback)
│
├── GUI/                        # WinForms control center (start here)
│   └── Start-SysAdminSuiteGui.ps1  ← Printer mapping, Kronos lookup, Machine Info probe, guided tutorial
│
├── Config/                     # Environment setup & software inventory
│   ├── Inventory-Software.ps1      ← ARP registry scan → CSV + HTML report
│   ├── Run-Preflight.ps1           ← Pre-deployment checklist runner
│   ├── Build-FetchMap.ps1          ← Builds installer fetch manifest
│   ├── Fetch-Installers.ps1        ← Downloads installers from sources.yaml
│   ├── Fetch-DRYRUN.ps1            ← Dry-run version of Fetch-Installers
│   ├── GoLiveTools.ps1             ← Go-live deployment helper
│   ├── Stage-To-Clients.ps1        ← Stages files to client machines
│   ├── ImpactS-FixShortcuts.ps1    ← Repairs ImpactS application shortcuts
│   ├── sources.yaml                ← Installer source definitions (authoritative)
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
├── QRTasks/                    # QR-friendly task runner (scan-to-run extension)
│   ├── Invoke-TechTask.ps1        ← Central dispatcher: QR points here with -Task name
│   ├── Get-RAMProfile.ps1         ← Local per-DIMM RAM snapshot → Desktop txt
│   ├── Get-ModelInfo.ps1          ← Local manufacturer/model/serial → Desktop txt
│   ├── Get-NetworkInfo.ps1        ← Local adapter/IP/MAC/DNS snapshot → Desktop txt
│   └── Get-Serials.ps1            ← BIOS + product + monitor serials → Desktop txt
│
├── OCR/                        # Python OCR tools for printer label extraction
│   ├── locus_mapping_ocr.py
│   ├── build_host_unc_csv.py
│   └── printer_lookup.csv
│
├── Tests/
│   ├── Preflight.ps1               ← Manual preflight checklist
│   └── Pester/                     ← PowerShell contract tests (Invoke-Pester)
│       ├── Utilities.Tests.ps1     ← Test-Network, Map-Printer, Invoke-FileShare
│       ├── Mapping.Tests.ps1       ← CSV schema, worker script contracts
│       ├── GetInfo.Tests.ps1       ← Get-MachineInfo, Get-RamInfo, QueueInventory, Kronos lookup, Windows key contracts
│       ├── ActiveDirectory.Tests.ps1 ← OU analysis, Preflight OU checks, Add-Computers-To-PrintingGroup contracts
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
| **QR Scan-to-Run Tasks** | Run field diagnostics by scanning a QR code — available tasks, deployment, adding new tasks |
| **PS Version Pivot** | How tools detect and switch between PS 5.1 and PS 7 |

**GUI tabs:**

| Tab | What it does |
|-----|-------------|
| **Run Control** | Configure and launch printer-mapping runs (Recon, Plan, Full Run), monitor live status, undo/redo changes |
| **Kronos Lookup** | Probe network clocks by IP, collect MAC/serial/model, search saved inventories |
| **Machine Info** | Run GetInfo probes or use Offline QR Text Generator — enter targets/text, pick output path, view results inline/QR |
| **UTF-8 BOM Sync** | Scan repo for files with/without UTF-8 BOM, move files between panels, and sync to apply BOM to all selected files |

All path fields (Stop signal, Status, History, CSV paths) are clickable — click them to open a file browser.

### Offline QR Generation In GUI

No internet service is required for QR generation. In the **Machine Info** tab:

1. Set **Script** to `QR Text Generator  (offline text to QR image)`.
2. Paste any text payload into the **Targets** box.
3. Click **Generate QR**.

The app generates and saves both:
- a UTF-8 text artifact (`...QRGenerator_Output.txt`)
- a local PNG QR image (`...QRGenerator_Output.png`)

The generated QR also appears in the built-in QR pane for immediate screen scanning by technicians.

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
# Canonical runner: fails fast if Pester 5 is missing
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1

# Direct invocation (if Pester 5 is already loaded)
Invoke-Pester .\Tests\Pester\
```

Managed (.NET) unit tests (no PowerShell required):

```bat
dotnet test SysAdminSuite.sln -c Release
```

(`managed-tests/` holds xUnit projects; `Tests/Pester/` is the PowerShell suite.)

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

### QR Tasks — Scan-to-Run Field Scripts

The `QRTasks/` module separates **launcher from payload**. QR codes encode a
short launch string (~100 chars); the real scripts live on a central share or
in this repo.

```powershell
# QR payload for RAM profile (fits in a small QR code):
powershell.exe -NoP -EP Bypass -File "\\server\Scripts\QRTasks\Invoke-TechTask.ps1" -Task RAMProfile

# Other tasks: ModelInfo, NetworkInfo, Serials, NeuronTrace, WinOptionalFeatures
powershell.exe -NoP -EP Bypass -File "\\server\Scripts\QRTasks\Invoke-TechTask.ps1" -Task ModelInfo

# List available tasks:
.\QRTasks\Invoke-TechTask.ps1 -Task ?

# Safety timeout (force-stop a hung probe after 90 seconds):
.\QRTasks\Invoke-TechTask.ps1 -Task NeuronTrace -TaskTimeoutSec 90
```

Each task script runs locally, prints results to console, and saves a
timestamped text file to the tech's Desktop — no terminal smoke.

#### File-share deployment + ready-to-send launcher snippets

If you publish the repo to a central share such as `\\server\Scripts\SysAdminSuite`,
you can send a tech a single copy/paste command that works on any workstation
with PowerShell 5.1+.

```powershell
# Launch the full GUI from a file share
powershell.exe -STA -NoP -EP Bypass -File "\\server\Scripts\SysAdminSuite\GUI\Start-SysAdminSuiteGui.ps1"

# Run a QR-style local diagnostic without typing script paths
powershell.exe -NoP -EP Bypass -File "\\server\Scripts\SysAdminSuite\QRTasks\Invoke-TechTask.ps1" -Task RAMProfile
powershell.exe -NoP -EP Bypass -File "\\server\Scripts\SysAdminSuite\QRTasks\Invoke-TechTask.ps1" -Task ModelInfo
powershell.exe -NoP -EP Bypass -File "\\server\Scripts\SysAdminSuite\QRTasks\Invoke-TechTask.ps1" -Task NetworkInfo
powershell.exe -NoP -EP Bypass -File "\\server\Scripts\SysAdminSuite\QRTasks\Invoke-TechTask.ps1" -Task Serials
powershell.exe -NoP -EP Bypass -File "\\server\Scripts\SysAdminSuite\QRTasks\Invoke-TechTask.ps1" -Task NeuronTrace
powershell.exe -NoP -EP Bypass -File "\\server\Scripts\SysAdminSuite\QRTasks\Invoke-TechTask.ps1" -Task WinOptionalFeatures
```

Practical uses:

- send a **RAMProfile** snippet when a user reports slowness or upgrade questions
- send a **NetworkInfo** snippet before printer, DNS, or Kronos troubleshooting
- send a **Serials** snippet when you need BIOS/product/monitor identifiers for asset work
- send **WinOptionalFeatures** (elevated) when you need a quick list of enabled optional Windows components on the workstation
- send the **GUI launcher** when you want the user or a tech to work through guided tabs instead of raw commands

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

### OCR Fixture Notes

- `OCR/Jude's 2026 Buildout Project.pdf` is a **known-bad OCR sample** kept for negative testing.
- The fixture is intentionally unsuitable for practical extraction quality in `OCR/locus_mapping_ocr.py`.
- For production OCR mapping, use higher-resolution annotated source maps (clear labels, readable circle IDs, no heavy compression).
- To replace this fixture later, add a new sample under `OCR/` and update the OCR fixture tests to validate positive extraction behavior for that file.

### Experimental PDF Map Parsers

Use these parsers to prototype workstation/printer extraction from PDF or image maps:

```powershell
# Workstation map parser (red markers -> WorkstationID,x,y)
python .\OCR\parse_workstation_map.py `
  --map ".\OCR\Jude's 2026 Buildout Project.pdf" `
  --out-csv .\OCR\workstations.csv `
  --out-html .\OCR\workstations.html `
  --out-overlay .\OCR\workstations_overlay.png `
  --out-summary-json .\OCR\workstations_summary.json `
  --confidence-threshold 0.75 `
  --legend-keyword workstation

# Printer map parser (green markers -> PrinterID,x,y)
python .\OCR\parse_printer_map.py `
  --map ".\OCR\Jude's 2026 Buildout Project.pdf" `
  --out-csv .\OCR\printers.csv `
  --out-html .\OCR\printers.html `
  --out-overlay .\OCR\printers_overlay.png `
  --out-summary-json .\OCR\printers_summary.json `
  --confidence-threshold 0.75 `
  --legend-keyword printer
```

Notes:
- PDF input requires `pypdfium2` to render pages (`pip install pypdfium2`).
- OCR still relies on `pytesseract`; quality is constrained by source-map resolution.
- These are starter engines for layout-aware parsing and can be tuned per site map style.
- Each parser now emits per-point confidence (`confidence`, `status`) so uncertain detections can be triaged (`status=ambiguous`).
- Parsers OCR the right-side legend region, derive legend totals for `--legend-keyword`, and compare engine totals vs legend counts (`mismatch` in summary JSON).
- Parsers generate a suite-style universal HTML report paired with CSV output (`--out-html` optional; defaults to same base name as `--out-csv`).
- Confidence interpretation:
  - `certain`: confidence >= threshold (default `0.75`)
  - `ambiguous`: confidence < threshold and should be reviewed manually

---

## Branch and Artifact Workflow

### Current Branch Posture
- Baseline branch for rebuild and active consolidation: `main`.
- Historical branch harvest decisions are tracked in:
  - `docs/MIGRATION_LEDGER.md`
  - `docs/BRANCH_HARVEST.md`

### Development vs Deployment
- Development happens from repository branches.
- Deployment to restricted endpoints should use versioned artifacts, not ad hoc `git pull`/`winget` workflows.
- Artifact contract and operator workflow are defined in `docs/DEPLOYMENT_ARTIFACTS.md`.

### Build Portable Artifact
Run from a trusted build machine:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\build\New-PortableArtifact.ps1 -Version 0.1.0
```

Output:
- `dist/SysAdminSuite-Portable-v0.1.0.zip`

### Runtime Launch
- Repository launch: `Launch-SysAdminSuite.bat`
- Packaged runtime launch: `Launch-SysAdminSuite-Runtime.bat`

### `push.ps1` helper
Default autogenerated branch name:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\push.ps1
```

Provide your own branch slug:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\push.ps1 -BranchName "feat/printer-mapping-r164"
```
