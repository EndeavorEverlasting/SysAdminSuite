# PR69 Browser QA Status

Branch: `fix/pr54-cybernet-manifest-ready` (merged to `main` via PR #69 @ `2bca023`)
Date: 2026-06-25
Browser harness: **not run in this lane** (no Playwright/browser automation in CI or agent runtime)

## Result

Overall QA result: **BLOCKED — manual browser pass required**

Automated coverage at merge: dashboard smoke **manifest + AD contracts PASS** (30 shell, 18 tour), `node --check` on parsers/app PASS, CI dashboard-smoke + Pester PASS.

This lane does **not** claim a browser PASS. Shell smoke proves parser wiring and contract language; it does not prove drag/drop UX, viewport layout, or visual separation of review surfaces in a real browser.

## Blocker

| Field | Detail |
|-------|--------|
| **Exact blocker** | No Playwright, Puppeteer, Cypress, or Selenium harness in repo CI or agent runtime. Grep across the worktree finds Playwright mentions only in prior QA docs (`PR66_BROWSER_QA.md`), not in executable test scripts or package dependencies. |
| **Impact** | Evidence separation for AD population (#56), Cybernet manifest (#69), Naabu reachability, and identity panels cannot be verified automatically. Operators cannot rely on this lane for visual/UX proof. |
| **Next human action** | Run the combined manual checklist below in Edge or Chrome on `dashboard/index.html` (local static server or `file://`), loading all three sample fixtures in one session. Record PASS/FAIL per item; attach screenshots only if a failure mode is found. |

## Smoke evidence (automated — not browser proof)

| Check | Result |
|-------|--------|
| Manifest sample detected as Cybernet target manifest | PASS (shell) |
| AD sample detected as `ad-registered-population` | PASS (shell) |
| Naabu parser contracts | PASS (shell) |
| Manifest summary container in `index.html` | PASS (shell) |
| AD summary container separate from Review Results | PASS (shell) |
| No false manifest reachability/serial proof language in contracts | PASS (shell) |
| Broad inventory CSV not misclassified as manifest (false-positive guard) | PASS (shell) |

## Manual browser checklist (operator)

Run in one session. Use synthetic fixtures only.

### First screen and shell (#66 regression guard)

- [ ] First screen shows exactly **3** action controls before opening panels: **Start Cybernet Survey**, **Load Evidence**, **Advanced Tools** (header)
- [ ] **Advanced Tools** section is collapsed by default (`aria-expanded="false"`, `#advanced-section` hidden)
- [ ] QR import controls are **not** on the first screen (QR appears only under Load Evidence → Supported formats, not in hero/header)
- [ ] 320×800 viewport: no horizontal overflow on hero, manifest, AD, or review sections
- [ ] Keyboard navigation: Tab through hero actions and Advanced Tools toggle; focus visible and operable

### Manifest (#69)

- [ ] Load `dashboard/samples/cybernet_targets.sample.csv` via drag/drop or file picker
- [ ] **Cybernet Target Manifest** summary appears (target row count, missing hostname/DNS cues)
- [ ] Manifest copy does **not** claim reachability or serial proof

### AD population (#56 — same session)

- [ ] Load `dashboard/samples/ad_registered_population.sample.csv`
- [ ] **AD Registered Population** summary appears separately from **Review Results** reachability block
- [ ] AD note states population authority only — not serial or reachability proof

### Naabu / network (#68 — same session)

- [ ] Load `dashboard/samples/cybernet_naabu.sample.json` or `dashboard/samples/cybernet_naabu.sample.jsonl`
- [ ] Network/reachability findings appear without replacing or collapsing AD or manifest summaries
- [ ] Reachability panel does not imply AD or manifest prove live hosts

### Evidence separation (combined)

- [ ] All four surfaces remain visible and semantically distinct: manifest targets, AD population, reachability/network, identity (load `dashboard/samples/workstation_identity.csv` if identity panel is in scope)
- [ ] No summary language conflates population authority with hardware identity or live reachability
- [ ] Load a broad inventory CSV (e.g. `dashboard/samples/NeuronNetworkInventory_20241115.csv`) — confirm it is **not** misclassified as Cybernet manifest

## Notes

- Manifest rows are **target list authority**, not survey evidence or reachability proof.
- AD population is **population authority**, not hardware identity or reachability proof.
- Naabu JSON/JSONL is **reachability/network findings**, separate from AD and manifest.
- Prior PR #66 browser PASS (`PR66_BROWSER_QA.md`) used a one-off Playwright session; that script is not checked into CI and does not satisfy this lane.
- Synthetic fixtures only; no live AD exports or field hostnames in repo.
