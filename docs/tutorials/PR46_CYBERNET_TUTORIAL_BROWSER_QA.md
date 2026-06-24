# PR #46 — Cybernet Dashboard Tutorial Browser QA

Branch: `agent/20260623-pr46-fix-cybernet-tutorial`  
PR: [#46 — Add Cybernet target acquisition tutorial to dashboard](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/46)

Use this checklist before merging PR #46. Automated CI covers parser smoke and JS syntax only; tutorial UI behavior requires manual browser verification.

## Preconditions

- Serve or open `dashboard/index.html` from the PR branch (local file or `python server.py` if used).
- Use a Chromium-based browser (Edge or Chrome) for clipboard tests.
- Confirm `dashboard/js/bundle.js` was built from `dashboard/js/app.js` (`node dashboard/build-bundle.js`) with no drift.

## Targets intake doctrine (terminology)

| Term | Meaning |
|------|---------|
| **Target source** | Local workbook or list used to build a manifest (`targets/` hub or ignored `targets/local/`, `logs/targets/`) |
| **Target manifest** | Normalized CSV (`Identifier,IdentifierType,DeviceType,HostName,Serial,MACAddress,Source`) — acquisition handoff, **not** evidence |
| **Evidence** | Network preflight, workstation identity, printer probe — live observation artifacts |
| **Review artifact** | Dashboard-loaded CSV the operator classifies before deciding next steps |

- Target intake starts in `targets/` (tracked docs/schemas/fixtures) or ignored local paths such as `targets/local/` and preserved `logs/targets/`.
- Runtime staging may still use `survey/input/` (gitignored).
- Cybernet target manifest dashboard import remains **deferred** unless PR #54 lands.

## Surface presence

| # | Check | Pass |
|---|-------|------|
| 1 | Section `#cybernet-tutorial` renders below the live-mode banner | [ ] |
| 2 | Heading reads "Acquire Cybernet targets without guessing" | [ ] |
| 3 | Stepper pills show 5 steps (titles match `CYBERNET_TUTORIAL_STEPS` in `dashboard/js/app.js`) | [ ] |
| 4 | Command textarea, step checks list, and step note populate on load / navigation | [ ] |

## Step-through (all 5 steps)

| Step | Title | Command contract | Pass |
|------|-------|------------------|------|
| 1 | Prepare your target list | Local `mkdir` / `printf` only; no remote probing | [ ] |
| 2 | Prove network posture first | `sas-network-preflight.sh` uses `--targets-file` (not `--file`) | [ ] |
| 3 | Acquire Cybernet identity evidence | `sas-workstation-identity.sh` uses `--targets-file` | [ ] |
| 4 | Normalize the acquisition list | `sas-survey-targets.sh` uses `--file` and `--device-type Cybernet` | [ ] |
| 5 | Load, review, then decide | References only `network_preflight.csv` and `workstation_identity.csv` for drag-and-drop; normalized manifest called out as **not** a dashboard import yet | [ ] |

For each step, confirm:

- **Back** / **Next** navigation updates kicker (`Step N of 5`), title, body, checks, command, and note.
- Clicking a stepper pill jumps to that step and marks it `aria-current="step"`.
- **Finish** appears on step 5; **Back** is disabled on step 1.

## Copy and clipboard

| # | Check | Pass |
|---|-------|------|
| 5 | **Copy current command** copies the textarea contents; success toast appears | [ ] |
| 6 | If `navigator.clipboard` is blocked, fallback copy still works (or shows a clear manual-copy instruction) | [ ] |
| 7 | **Start tutorial** resets to step 1 | [ ] |

## Keyboard and focus

| # | Check | Pass |
|---|-------|------|
| 8 | Tab reaches Start, Copy, stepper pills, Back, and Next in logical order | [ ] |
| 9 | Enter / Space activates focused stepper pill and nav buttons | [ ] |
| 10 | Focus ring visible on interactive controls (no `outline: none` traps) | [ ] |

## Responsive layout

| # | Check | Pass |
|---|-------|------|
| 11 | At 320px viewport width, no horizontal page scroll from the tutorial section | [ ] |
| 12 | Command textarea wraps long lines; step card remains readable | [ ] |

## Bundle / HTML alignment

| # | Check | Pass |
|---|-------|------|
| 13 | `dashboard/index.html` element IDs match those referenced in `initCybernetTutorial()` | [ ] |
| 14 | Tutorial behavior matches when loading `bundle.js` (production path) | [ ] |

## Out of scope (do not fail PR #46 on these)

- Pester CI red — pre-existing baseline lane.
- Cybernet target manifest CSV ingestion — deferred until PR #54.
- XLSX drag-and-drop — browser-only manual check.

## Automated validation (run before browser QA)

```bash
node --check dashboard/js/app.js
node --check dashboard/js/bundle.js
node dashboard/smoke-test.js
node dashboard/build-bundle.js
python -m py_compile server.py
git diff --check
```

## Sign-off

| Field | Value |
|-------|-------|
| Tester | |
| Date | |
| Browser / OS | |
| Branch SHA | |
| Result | [ ] Pass [ ] Fail |

Notes:
