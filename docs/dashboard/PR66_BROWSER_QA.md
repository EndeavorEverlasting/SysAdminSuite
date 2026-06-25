# PR66 Browser QA Status

Branch: `feature/cybernet-first-dashboard-ui-2026-06` (merged to `main` via PR #66)
QA doc commits: `376f5da` (blocker note) → `8c5fbf8` / `1b1557f` (PASS); merged on `main` @ `9e51130`
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

**Completed (2026-06-25):** PR #65 merged, PR #66 rebased and merged to `main` @ `9e51130`. Browser QA **PASS** stands.

## Follow-up (non-blocking)

- Naabu JSON parser for review summary — **PR #68** (`feature/dashboard-naabu-json-review-2026-06`).
- Tour refresh for Cybernet-first DOM — **PR #67** (`feature/dashboard-tour-refresh-2026-06`).

## Agent harness notes

### Playwright first-run failure (resolved before PASS)

An early background browser-QA attempt **failed with exit code 2** before the recorded PASS:

- The QA harness copied the Playwright script into a **temp directory** and lost the **repo root**.
- The static file server could not serve `dashboard/index.html`; the run **timed out waiting for `#app`**.
- **Fix:** run the harness from the repo (or set repo root explicitly for the file server), correct clipboard mocking and wizard contract assertions, then re-run Edge headless.
- The successful PASS is recorded above; do not treat the first failed background task as the final QA verdict.

### Background terminal: `gh pr checks` exit code 8

When agents poll GitHub CI in a **background shell** (example: `Start-Sleep 50; gh pr checks 68`), the task may report **`exit_code: 8`** even though CI is still healthy:

| Observation | Meaning |
|-------------|---------|
| `gh pr checks` exit code **8** | One or more checks are **pending or failed** — not a PowerShell crash |
| `test` line shows `pending` | Job still running; wait and poll again |
| `dashboard-smoke` `pass` | Required dashboard smoke already green |
| `CodeRabbit` `pending` | Non-blocking review bot; does not block merge |

**Example (2026-06-25, PR #68):** after a 50s background poll, `test` was still `pending` while `dashboard-smoke` had passed. The background task exited **8** and was surfaced as `status: error`. **`test` completed PASS** ~1m50s later on re-check.

**Agent rule:** do not treat `gh pr checks` exit code 8 alone as CI failure. Read per-check status lines or re-run `gh pr checks <n>` until required jobs show `pass`.

### PR #66 body checklist alignment

- PR #66 test plan: **Manual QA at 1366px and 320px** — checked, with pointer to this doc.
- PR #66 QA comment on GitHub documents Edge 149 headless PASS at `8c5fbf8`.
- This file and the PR body are **aligned**; PR #66 is **merged**.
