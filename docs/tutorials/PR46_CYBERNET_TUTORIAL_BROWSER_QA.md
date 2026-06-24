# PR #46 ΓÇö Cybernet Dashboard Tutorial Browser QA

Branch: `codex/prepare-tutorial-for-cybernet-target`  
PR: [#46 ΓÇö Add Cybernet target acquisition tutorial to dashboard](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/46)

Use this checklist before merging PR #46. Automated CI covers parser smoke and JS syntax only; tutorial UI behavior requires manual browser verification.

## Preconditions

- Serve or open `dashboard/index.html` from the PR branch (local file or `python server.py` if used).
- Use a Chromium-based browser (Edge or Chrome) for clipboard tests.
- Confirm `dashboard/js/bundle.js` was built from `dashboard/js/app.js` (`node dashboard/build-bundle.js`) with no drift.

## Surface presence

| # | Check | Pass |
|---|-------|------|
| 1 | Section `#cybernet-tutorial` renders below the live-mode banner | ΓÿÉ |
| 2 | Heading reads "Acquire Cybernet targets without guessing" | ΓÿÉ |
| 3 | Stepper pills show 5 steps (titles match `CYBERNET_TUTORIAL_STEPS` in `dashboard/js/app.js`) | ΓÿÉ |
| 4 | Command textarea, step checks list, and step note populate on load / navigation | ΓÿÉ |

## Step-through (all 5 steps)

| Step | Title | Command contract | Pass |
|------|-------|------------------|------|
| 1 | Prepare your target list | Local `mkdir` / `printf` only; no remote probing | ΓÿÉ |
| 2 | Prove network posture first | `sas-network-preflight.sh` uses `--targets-file` (not `--file`) | ΓÿÉ |
| 3 | Acquire Cybernet identity evidence | `sas-workstation-identity.sh` uses `--targets-file` | ΓÿÉ |
| 4 | Normalize the acquisition list | `sas-survey-targets.sh` uses `--file` and `--device-type Cybernet` | ΓÿÉ |
| 5 | Load, review, then decide | References only `network_preflight.csv` and `workstation_identity.csv` for drag-and-drop; normalized manifest called out as **not** a dashboard import yet | ΓÿÉ |

For each step, confirm:

- **Back** / **Next** navigation updates kicker (`Step N of 5`), title, body, checks, command, and note.
- Clicking a stepper pill jumps to that step and marks it `aria-current="step"`.
- **Finish Γ£ô** appears on step 5; **Back** is disabled on step 1.

## Copy and clipboard

| # | Check | Pass |
|---|-------|------|
| 5 | **Copy current command** copies the textarea contents; success toast appears | ΓÿÉ |
| 6 | If `navigator.clipboard` is blocked, fallback copy still works (or shows a clear error) | ΓÿÉ |
| 7 | **Start tutorial** resets to step 1 | ΓÿÉ |

## Keyboard and focus

| # | Check | Pass |
|---|-------|------|
| 8 | Tab reaches Start, Copy, stepper pills, Back, and Next in logical order | ΓÿÉ |
| 9 | Enter / Space activates focused stepper pill and nav buttons | ΓÿÉ |
| 10 | Focus ring visible on interactive controls (no `outline: none` traps) | ΓÿÉ |

## Responsive layout

| # | Check | Pass |
|---|-------|------|
| 11 | At 320px viewport width, no horizontal page scroll from the tutorial section | ΓÿÉ |
| 12 | Command textarea wraps long lines; step card remains readable | ΓÿÉ |

## Bundle / HTML alignment

| # | Check | Pass |
|---|-------|------|
| 13 | `dashboard/index.html` element IDs match those referenced in `initCybernetTutorial()` (`cybernet-stepper`, `cybernet-step-command`, etc.) | ΓÿÉ |
| 14 | Tutorial behavior matches when loading `bundle.js` (production path), not only `app.js` in dev | ΓÿÉ |

## Out of scope (do not fail PR #46 on these)

- Pester CI red ΓÇö pre-existing baseline lane; not caused by dashboard tutorial files.
- Cybernet target manifest CSV ingestion ΓÇö deferred; parser extension point exists in `parsers.js` but is not implemented on this branch.
- XLSX drag-and-drop ΓÇö browser-only manual check per `dashboard/smoke-test.js` header comment.

## Automated validation (run before browser QA)

```bash
node --check dashboard/js/parsers.js
node --check dashboard/js/app.js
node --check dashboard/js/bundle.js
node dashboard/smoke-test.js          # expect: 13 passed, 0 failed
node dashboard/build-bundle.js        # expect: no bundle drift vs committed file
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
| Result | ΓÿÉ Pass ΓÿÉ Fail (notes below) |

Notes:
