# SysAdmin Suite Dashboard

A standalone HTML/JS single-page app — no build step, no backend. Requires a static
web server because browsers block ES modules on `file://` URLs.

## Opening the dashboard

**Replit (recommended):** The "Start application" workflow serves it automatically
at `/dashboard/` via `server.py`. Click the Replit preview URL.

**Locally:** Run a one-liner from the project root:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000/dashboard/` in your browser.

> "Standalone" means **no build step and no backend processing required** — not
> `file://` capable. ES modules require HTTP/HTTPS. The app will display a banner
> if accidentally opened from `file://`.

## Loading experience (Hide the Pain Harold)

Whenever the dashboard makes the user wait, it shows a friendly Harold splash so the tech
stays engrossed instead of staring at a blank screen.

- **Boot splash:** `index.html` paints a full-screen Harold overlay immediately on load and
  hides it once the app wires up (after `DOMContentLoaded`, with a minimum visible time and an
  8s safety timeout). It is self-contained — no module/bundle dependency.
- **In-app waits:** a reusable global hook is exposed:

  ```js
  window.SASHarold.show('Reading your spreadsheet… hang tight.');
  // ... do slow work ...
  window.SASHarold.hide();
  ```

  It is already wired into spreadsheet (`.xlsx` / `.xls`) import in `js/app.js`. Call it from any
  future long-running operation to keep the wait friendly.
- **Asset:** `dashboard/assets/harold.jpg`, served as `image/jpeg` by both the .NET host
  (`DashboardStaticServer`) and `server.py`.
- The legacy PowerShell launcher (`Launch-SysAdminSuiteDashboard.ps1`) shows its own Harold
  WinForms splash while `server.py` starts.

## Live Mode — command-generation workflow

Live Mode does **not** perform browser-side network probing (DNS/ping/TCP/WMI/SNMP
are not available from a browser security context). Instead it generates ready-to-run
probe command suites you copy and run on an admin machine:

1. Enter target hostnames/IPs → click **Generate Probe Commands**
2. Copy the Bash (primary), PowerShell (Windows/WMI), or Linux-native block
3. Run on a machine with network access to the targets
4. Drag the resulting CSV files (`network_preflight.csv`, `workstation_identity.csv`,
   `printer_probe.csv`, `MachineInfo_Output.csv`, `RamInfo_Output.csv`) back into
   the dashboard drop zone — all four panels populate automatically

## Manual smoke-test checklist (one sample per panel)

| Step | File | Expected result |
|------|------|-----------------|
| Drop `samples/Results.csv` | Printer Mapping | Rows appear; Export CSV downloads them |
| Drop `samples/MachineInfo_Output.csv` + `RamInfo_Output.csv` | Hardware Inventory | Hosts merged; RAM column populated |
| Drop `samples/QRTask_log.json` | Remote Tasks | 3 rows; Outcome badge coloured |
| Drop `samples/network_preflight.csv` + `samples/workstation_identity.csv` | Network & Protocol Trace | Protocol ladder renders; sort/filter work |
| Drop `samples/status.json` | Status footer | Footer shows state dot and stage |
| Remove a chip (×) | Any panel | Rows from that file disappear |

## Running the automated parser smoke-test

```bash
node dashboard/smoke-test.js
```

All 13 cases must pass: 11 sample files (detection + row-count assertions), plus an inline RFC-4180 multiline quoted-field test and a BOM-strip test.

## Sample files

| File | Panel |
|------|-------|
| `Preflight.csv` | Printer Mapping |
| `Results.csv` | Printer Mapping |
| `printer_probe.csv` | Printer Mapping + Network |
| `workstation_identity.csv` | Network Trace |
| `network_preflight.csv` | Network Trace |
| `MachineInfo_Output.csv` | Hardware Inventory |
| `RamInfo_Output.csv` | Hardware Inventory |
| `NeuronNetworkInventory_20241115.csv` | Hardware Inventory |
| `status.json` | Status Footer |
| `QRTask_log.json` | Remote Tasks |
| `RunControl_events.json` | Remote Tasks |
