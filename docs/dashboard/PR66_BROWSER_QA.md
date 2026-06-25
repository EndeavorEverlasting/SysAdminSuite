# PR66 Browser QA Status

Branch: `feature/cybernet-first-dashboard-ui-2026-06`  
SHA: `376f5da7c231c2bc89d443c758f046195d299b7d` (QA run; branch advances with this QA doc commit)
Date: 2026-06-24  
Browser: Microsoft Edge 149.0.4022.80 (Playwright `msedge` channel, headless)
OS: Windows 10.0.26200

## Result

Overall QA result: **PASS**

PR #66 addresses the user complaint that the dashboard had too many first-screen choices. The Cybernet survey path is now the obvious front door with exactly three first-screen action buttons.

## Viewport checks

| Check | Result |
|-------|--------|
| Desktop 1366×768 | PASS |
| Mobile 320×800 | PASS — no dashboard-shell horizontal overflow; hero buttons stack |

## First-screen button count

**3** visible action buttons before opening advanced sections:

1. Advanced Tools (header)
2. Start Cybernet Survey (hero primary)
3. Load Evidence (hero secondary)

Forbidden first-screen controls not visible: Log Mode, Live Mode, Command-Gen, Generate Probe Commands, Naabu, Clear All, Paste / Type, Load Sample Data, Watch Folder, five panel tabs.

## Primary CTA

**PASS** — `Start Cybernet Survey` uses `btn-primary` styling and is the dominant hero action.

## Wizard result

**PASS**

- One step visible at a time.
- Passive progress rail (`ol.cybernet-progress-rail`); no clickable step pills.
- Copy Command, Back, and Next are present and usable.
- Step 4 labeled **Optional reachability check (optional)** with `keyports_cybernet_json` in command.
- Show details disclosure keeps advanced checks subordinate.

### Command contract (Bash mode selected)

Verified with `cybernet-os-preflight.js` OS selector set to **Linux/macOS/WSL Bash**:

| Step | Contract | Result |
|------|----------|--------|
| Network posture | `--targets-file` | PASS |
| Identity evidence | `--targets-file` | PASS |
| Normalize reference | `--file /tmp/sas-cybernet/targets.txt` in step details | PASS |
| Optional reachability | `keyports_cybernet_json` | PASS |
| Manifest import claim | states **not dashboard-importable** | PASS |

**Note:** Default Windows PowerShell mode (OS preflight selector) intentionally substitutes PowerShell posture/identity commands without `--targets-file` flags. Bash-first contract is preserved in Bash mode and in Advanced → Generate Survey Commands.

## Evidence loader result

**PASS**

- Single Load Evidence entry point.
- Drop zone, paste, and clear evidence live inside the loader.
- Sample data and watch folder are under **More import options**.
- Safe sample data loads successfully; evidence chips render with section/type/row metadata.

## Review summary result

**PASS**

- Cybernet review summary appears after sample evidence load.
- Summary shows preflight/identity counts and next action without requiring tab guessing.
- Advanced panel tabs remain reachable via Advanced Tools.

## Advanced Tools result

**PASS**

- Opens and collapses without permanently cluttering the main UI.
- Five legacy review panels remain reachable.
- Generate Survey Commands and low-noise reachability handoff remain in Advanced.

## Keyboard result

**PASS**

- Tab order reaches hero/header controls (`hero-start-survey`, `hero-load-evidence`, `advanced-tools-toggle`).
- Enter on **Start Cybernet Survey** opens the wizard.
- No keyboard trap observed in wizard, evidence loader, or advanced section during automated pass.

## Recommended PR action

1. Merge PR #65 (low-noise doctrine) first.
2. Rebase or update PR #66 onto updated `main`.
3. Merge PR #66 — browser QA **PASS**.

## Follow-up (non-blocking)

- Naabu JSON parser for review summary (filename match today).
- Tour refresh for Cybernet-first DOM (`tour.js`).
