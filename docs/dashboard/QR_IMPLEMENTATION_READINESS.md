# QR Implementation Readiness

Date: 2026-06-25  
Branch: `plan/qr-advanced-tools-readiness-2026-06`  
Worktree: `SysAdminSuite-qr-readiness`  
Base: `origin/main` after PR #66 (Cybernet-first dashboard)  
Related: [QR Convergence Plan](./QR_CONVERGENCE_PLAN.md)

## Purpose

This document is the implementation gate for dashboard QR. It records why open PRs #47 and #43 must not merge as-is, what placement and field constraints apply, what must be verified before coding starts, and what smoke coverage to add when QR is built.

**Do not implement QR UI on this branch.** This is readiness and contract documentation only.

---

## Why PR #47 and PR #43 Must Not Merge As-Is

### PR #47 — `feature/web-qr-builder` (web dashboard QR Payload Builder)

| Blocker | Detail |
|---------|--------|
| Pre-PR #66 dashboard shape | Branch predates the merged Cybernet-first shell. Rebasing alone does not fix architecture drift. |
| Standalone after-bundle injection | Adds `dashboard/js/panel-qr-standalone.js` loaded **after** `bundle.js`, bypassing `build-bundle.js`, `app.js`, and `tour.js`. |
| Not a first-class panel module | Current dashboard panels live in the bundle pipeline (`panel-network.js`, `panel-tasks.js`, etc.). Standalone injection was useful for isolated review, not for merge. |
| Missing smoke contract | No assertions for Advanced Tools placement, first-screen budget, or QR panel wiring in `dashboard/smoke-test.js`. |
| CDN as operational fallback | Vendored `qrcode.min.js` exists on the branch, but CDN remains a runtime path. Field policy requires local renderer as the **supported** path with degraded-mode UX when missing. |
| Conflicting / stale integration | Tab injection via `injectQrTab()` assumes pre-#66 DOM layout. Current `main` places `#tabs` inside `#advanced-section` (hidden until Advanced Tools opens). |

**Keep from PR #47 (rebuild, do not merge):**

- Bash-first target-list payloads with PowerShell entries labeled legacy
- Exact payload preview before QR rendering
- Manual `.txt` and `.csv` target loading (first CSV column)
- Copy, download, and large QR modal affordances
- Local vendored QR renderer (pinned, license-reviewed)

**Change before landing:**

- `dashboard/js/panel-qr.js` as a normal module in `build-bundle.js`
- QR tab and panel registered through `app.js` like other Advanced Review Panels
- No post-`bundle.js` script tag for production shape
- Dashboard smoke + browser QA for placement and offline renderer

### PR #43 — `feature/qr-generator-tab-2026-05` (WinForms PowerShell GUI)

| Blocker | Detail |
|---------|--------|
| Wrong product surface | Modifies `GUI/Start-SysAdminSuiteGui.ps1` — a Windows WinForms GUI tab, not the web dashboard. |
| No dashboard convergence | Does not address PR #66 shell, `#advanced-section`, bundle pipeline, or dashboard smoke tests. |
| Parallel legacy path | Preserves PowerShell GUI QR while dashboard convergence needs a browser panel under Advanced Tools. |
| Policy overlap without integration | Updates `docs/QR_GUI_AND_RUNNER_POLICY.md` and `bash/qr/README.md` but does not wire into dashboard operator workflow. |

**Disposition:** Close or supersede PR #43 **for dashboard QR convergence**. Treat it as a separate Windows GUI / PowerShell legacy discussion. Do not block or substitute dashboard QR implementation on PR #43 merging.

### Summary

Neither PR is merge-ready for dashboard QR on current `main`:

- **#47** has the right *concept* (web payload builder) but the wrong *integration shape*.
- **#43** is the wrong *surface* entirely for dashboard convergence.

Supersede both with a new implementation PR from current `main` following this readiness doc and [QR Convergence Plan](./QR_CONVERGENCE_PLAN.md).

---

## Advanced Tools Placement Requirements

Current `dashboard/index.html` structure (post-PR #66):

- Header: `#advanced-tools-toggle` — one of exactly **three** first-screen action controls.
- Hero: `#hero-start-survey` (primary), `#hero-load-evidence` (secondary).
- `#advanced-section` starts with class `hidden`; panels and tabs are not visible until the operator opens Advanced Tools.
- `#tabs` lives **inside** `#advanced-section` under "Advanced Review Panels" (Network, Printer, Hardware Inventory, Remote Tasks, Software Tracker).

### Required placement for QR Builder

| Requirement | Rationale |
|-------------|-----------|
| Add `QR Builder` as an **Advanced Review Panel** tab | Matches PR #66 rule: detailed panels stay behind Advanced Tools. |
| Place tab near **Remote Tasks** (after `data-tab="tasks"` or adjacent in tab order) | QR payloads align with remote/command workflows; keep related tools grouped. |
| Add matching `#panel-qr` (or `data-panel="qr"`) in `#content` | Same panel contract as existing tabs. |
| **No** hero CTA, header button, or first-screen tab for QR | Preserves three-button first-screen budget from [CYBERNET_FIRST_UI_PLAN.md](./CYBERNET_FIRST_UI_PLAN.md). |
| **No** `#hero-open-advanced` or tour step promoting QR specifically | Advanced Tools remains the intentional gate; QR is discoverable after expand. |
| Register panel in `app.js` / bundle, not post-load injection | Ensures tab switching, evidence store, and tour targets stay consistent. |
| Keep `#advanced-section` collapsed on first load | QR must not appear in DOM-visible first paint (section hidden, not merely off-screen). |

### Forbidden placements

- Hero primary or secondary button row
- Header bar (besides existing Advanced Tools toggle)
- Cybernet wizard steps or progress rail
- Auto-tour first step
- Standalone script loaded after `bundle.js` in `index.html` (production shape)

---

## Local / Offline Renderer Requirement (Field Use)

Hospital and corporate field networks often block external CDNs, log third-party requests, or operate offline. QR generation is a field technician capability; it cannot depend on network access to `cdn.jsdelivr.net`.

### Supported path (required)

- Vendored renderer at `dashboard/js/vendor/qrcode.min.js` (or equivalent pinned artifact).
- Version pinned in repo; license reviewed and recorded in vendor README or dashboard docs.
- Loaded from same origin as `dashboard/index.html` — no runtime fetch to CDN for normal operation.
- `build-bundle.js` or `index.html` script order must guarantee local script availability before QR canvas render.

### Degraded mode (allowed, must be visible)

When the local renderer is missing or fails to load:

- Panel **must still** show exact payload preview, copy, and download TXT.
- UI **must** show explicit degraded-mode indicator (e.g. "QR image unavailable — payload text only").
- **Must not** silently fail or appear to generate a scannable QR with an empty canvas.

### CDN fallback (development only)

- CDN may exist for developer convenience when vendored file is absent locally.
- CDN success **does not** prove field readiness.
- Guest-network CDN success classifies as `ENVIRONMENT_BLOCKED_GUEST_NETWORK` for field validation, not product PASS.
- Implementation PR must document that CDN is non-required and excluded from field sign-off.

### Pre-land verification

Before merging dashboard QR:

1. Confirm vendored file present and checksum or version pinned.
2. Run smoke or browser check with **no network** (or CDN host blocked) and confirm scannable QR renders.
3. Run degraded-mode check with vendored file renamed/absent and confirm visible warning + text affordances.

---

## Prerequisites Before Implementation

Do not start QR panel coding until these gates are satisfied or explicitly waived by maintainers.

### 1. Browser QA baseline on current `main`

- Follow [PR66_BROWSER_QA.md](./PR66_BROWSER_QA.md) or [BROWSER_QA_STATUS.md](./BROWSER_QA_STATUS.md) checklist.
- Confirm first-screen button count remains **3** before QR work begins.
- Confirm Advanced Tools expand/collapse and existing five panel tabs work in target browser (Edge/Chrome).

### 2. Parser and evidence boundaries

QR target-list parsing is **panel-local**, not evidence ingestion:

| Boundary | Rule |
|----------|------|
| `.txt` / `.csv` target import in QR panel | Uses first CSV column or line-per-target; does **not** auto-route through `detectFileType` / evidence store. |
| Evidence drop zone / Load Evidence | Unchanged; QR must not hijack cybernet manifest, AD population, or naabu parsers. |
| `parsers.js` | Add new types only if QR exports structured evidence files operators load back via Load Evidence — not for ephemeral scan payloads. |
| Payload content | Plain text, reviewable before scan; no `Invoke-Expression`, encoded commands, or download-execute patterns. |
| AD vs Nmap posture | AD = registered population source; network probes = reachability validation only (per PR #47 design intent). |

Document parser boundaries in the QR panel module header and operator doc (`docs/dashboard/` or `docs/QR_WEB_INTERFACE.md` successor).

### 3. Bundle pipeline readiness

- Read `dashboard/build-bundle.js` insertion order (dependencies before `app.js`).
- Plan `panel-qr.js` exports consistent with other `panel-*.js` files.
- Rebuild `bundle.js` in CI; no manual-only bundle updates.

### 4. Tour and copy

- If QR appears in tour, step must target `#advanced-section` / QR tab only **after** Advanced Tools is opened — never as a first-screen tour stop.
- No resurrection of pre-PR #66 stale copy (`Log Mode vs Live`, etc.).

### 5. Open PR disposition

- Mark PR #47 superseded or request rebuild targeting Advanced Tools architecture.
- Mark PR #43 out of scope for dashboard convergence (GUI path separate).

---

## Smoke Assertions to Add When QR Is Built

Extend `dashboard/smoke-test.js` (and CI `dashboard-smoke` job) with the following when `panel-qr.js` lands. **Do not add these on the readiness branch** — list is the contract for the implementation PR.

### Shell checks (`index.html` / `app.js` text, no DOM)

| Assertion | Intent |
|-----------|--------|
| `#advanced-section` contains QR tab button (`data-tab="qr"` or agreed id) | Tab inside Advanced Tools, not hero |
| `#panel-qr` or `data-panel="qr"` in `#content` | Panel registered |
| **Absence** of `panel-qr-standalone.js` in `index.html` | No post-bundle injection |
| **Absence** of `QR Builder` string in `#cybernet-hero` block | No first-screen QR promotion |
| **Absence** of QR-specific button in header outside `#advanced-section` | Preserves button budget |
| `panel-qr.js` listed in `build-bundle.js` `files` array | Bundle pipeline membership |
| `dashboard/js/vendor/qrcode.min.js` referenced from HTML or bundle | Local renderer wired |

### QR module contract checks (`panel-qr.js` or bundled output)

| Assertion | Intent |
|-----------|--------|
| Payload preview string built before QR render call | Review-before-scan contract |
| Bash-first payload templates present | Northwell posture |
| Legacy / PowerShell label marker in source | Legacy boundary visible in UI code |
| Degraded-mode message when renderer unavailable | Offline honesty |
| No `cdn.jsdelivr.net` as **only** renderer path (local path attempted first) | Field-first load order |

### Target parser unit checks (Node-safe, no DOM)

Add sample files under `dashboard/samples/` or inline tests:

| Case | Expected |
|------|----------|
| `.txt` one hostname per line | Target count matches non-empty lines |
| `.csv` with header, hosts in column 1 | First column extracted, header skipped |
| Empty file | Zero targets, no throw |
| BOM-prefixed CSV | BOM stripped (reuse `parseCSV` behavior) |

### Tour checks (if QR tour step added)

| Assertion | Intent |
|-----------|--------|
| QR tour target selector inside `#advanced-section` or `#tabs` | No first-screen tour anchor |
| **Absence** of QR target in first three tour steps | Cybernet-first tour order preserved |

### Browser-only checks (manual or Playwright, not in Node smoke)

- Open Advanced Tools → QR Builder tab → select payload type → preview updates.
- Load sample targets from `dashboard/targets/examples/` → count updates.
- Show Large QR modal → scannable code with **network disabled**.
- Degraded mode without vendored file → warning visible, copy/download still work.

---

## Suggested Branch / Worktree Naming (Implementation Lane)

When implementation starts, use a **new** branch and worktree from current `main` — not this readiness branch.

| Artifact | Suggested name |
|----------|----------------|
| Implementation branch | `feature/dashboard-qr-advanced-tools-2026-06` |
| Implementation worktree directory | `SysAdminSuite-qr-impl` |
| Planning branch (this doc) | `plan/qr-advanced-tools-readiness-2026-06` |
| Planning worktree | `SysAdminSuite-qr-readiness` |

### Worktree commands (reference)

```bash
git fetch origin
git worktree add ../SysAdminSuite-qr-impl -b feature/dashboard-qr-advanced-tools-2026-06 origin/main
```

### Implementation PR title (suggested)

`feat(dashboard): QR Builder panel under Advanced Tools`

### Merge criteria (implementation PR)

- [ ] All smoke assertions in this doc added and CI green
- [ ] Browser QA checklist completed (Advanced Tools placement + offline QR)
- [ ] PR #47 superseded; PR #43 explicitly out of scope for dashboard
- [ ] Operator workflow documented under `docs/dashboard/`
- [ ] First-screen button budget unchanged (3 actions)

---

## Cross-References

- [QR Convergence Plan](./QR_CONVERGENCE_PLAN.md) — strategic merge disposition for #47 / #43
- [CYBERNET_FIRST_UI_PLAN.md](./CYBERNET_FIRST_UI_PLAN.md) — first-screen button budget and control classification
- [PR66_BROWSER_QA.md](./PR66_BROWSER_QA.md) — browser QA template for dashboard changes
- [BROWSER_QA_STATUS.md](./BROWSER_QA_STATUS.md) — lane tracking for dashboard features
- PR #47 — concept reference only; do not merge
- PR #43 — GUI legacy path; do not merge for dashboard convergence
