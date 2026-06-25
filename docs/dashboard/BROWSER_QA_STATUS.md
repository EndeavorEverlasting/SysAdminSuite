# Browser QA Status — Dashboard Review Lanes

Last updated: 2026-06-25  
Harness: **no Playwright/browser automation in CI or agent runtime**

---

## Summary

| Lane | PR / feature | Automated smoke | Browser QA | Status |
|------|--------------|-----------------|------------|--------|
| AD population | #56 (merged `e8ad69f`) | PASS | Not run | **BLOCKED — manual pass required** |
| Cybernet manifest | #69 (merged `2bca023`) | PASS | Not run | **BLOCKED — manual pass required** |
| Naabu JSON | #68 (merged) | PASS | Not run | Covered by smoke contracts only |
| Cybernet-first shell/tour | #66/#67 (merged) | PASS | Partial (`PR66_BROWSER_QA.md`) | Manual corp-network pass still needed |

**Overall:** smoke contracts green on `main`; **real browser QA still required** for review separation and drag/drop UX.

### Status semantics

| Label | Meaning |
|-------|---------|
| **BLOCKED (#56)** | AD population browser proof was never completed; lane is blocked on a human manual pass. See [`PR56_BROWSER_QA.md`](PR56_BROWSER_QA.md). |
| **BLOCKED (#69)** | Manifest + combined evidence-separation browser proof was never completed; same harness gap. See [`PR69_BROWSER_QA.md`](PR69_BROWSER_QA.md). |
| **NOT RUN** | No operator has executed the manual checklist for that lane in a browser session yet (automation did not substitute). |
| **Combined session** | Recommended next step: one browser session loading AD + manifest + Naabu (+ identity) samples and verifying all summaries stay separate. Neither #56 nor #69 is satisfied until that session is recorded. |

---

## What browser QA must prove

Operators must confirm these review surfaces stay **visually and semantically separate**:

1. **AD Registered Population** — population authority; does not prove serial or reachability.
2. **Cybernet Target Manifest** — target list rows; not evidence of live reachability.
3. **Reachability / network findings** (Naabu, preflight, printer probe) — separate from AD population.
4. **Identity / serial evidence** (workstation identity, WMI) — separate from AD population.

### Failure modes to watch

- AD summary language implying serial or reachability proof.
- Manifest rows presented as if they were survey evidence.
- Naabu or network panels overwriting or collapsing AD/manifest summaries.
- Horizontal overflow at 320px on hero/review sections.
- Advanced Tools toggle hiding evidence loaders operators still need.

---

## PR #56 — AD population (BLOCKED)

Branch was `feature/ad-registered-population-integration` (merged).

Automated evidence at merge time:

- Dashboard smoke: parser + shell + tour + AD contracts PASS
- `Tests/bash/smoke-ad-reconcile.sh` PASS
- Targets folder policy PASS

See also: [`PR56_BROWSER_QA.md`](PR56_BROWSER_QA.md)

### Manual checklist (#56)

- [ ] First screen: Start Cybernet Survey, Load Evidence, Advanced Tools only
- [ ] Load `dashboard/samples/ad_registered_population.sample.csv`
- [ ] AD summary appears separately from Review Results reachability block
- [ ] UI does not claim AD proves serial or reachability
- [ ] 320px viewport: no horizontal overflow
- [ ] Keyboard navigation through hero + Advanced Tools

---

## PR #69 — Cybernet manifest + evidence separation (BLOCKED)

Branch was `fix/pr54-cybernet-manifest-ready` (merged).

Automated evidence at merge time:

- Dashboard smoke: manifest + AD contracts PASS (30 shell, 18 tour)
- `node --check` parsers/app PASS
- CI dashboard-smoke + Pester PASS

**Browser QA:** NOT RUN — no automated harness; manual pass required before treating manifest separation as proven.

See also: [`PR69_BROWSER_QA.md`](PR69_BROWSER_QA.md)

### Manual checklist (#69)

- [ ] Load `dashboard/samples/cybernet_targets.sample.csv` via drag/drop or file picker
- [ ] Manifest summary appears in Cybernet review area (target row count, missing hostname/DNS)
- [ ] Load AD sample in same session — both AD and manifest summaries visible without collision
- [ ] Load Naabu sample — network findings do not replace AD/manifest summaries
- [ ] Confirm manifest copy does not claim reachability or serial proof
- [ ] Confirm broad inventory CSV (non-manifest) is **not** misclassified as manifest (false-positive check)
- [ ] Advanced Tools collapsed by default; QR not on first screen
- [ ] 320px viewport and keyboard nav (see PR69 doc for full list)

---

## Combined session checklist (recommended next QA lane)

Run one browser session loading **all** of:

1. `dashboard/samples/ad_registered_population.sample.csv`
2. `dashboard/samples/cybernet_targets.sample.csv`
3. Naabu JSON/JSONL sample (`dashboard/samples/cybernet_naabu.sample.json` or `.jsonl`)
4. Optional: `dashboard/samples/workstation_identity.csv` for identity separation

Verify separation of AD population, manifest targets, Naabu reachability, and identity evidence.

**Session status:** NOT RUN — completes both #56 and #69 browser lanes when recorded in the PR QA docs.

---

## Harness note

Repository grep (2026-06-25) found **no** Playwright, Puppeteer, Cypress, or Selenium test scripts or CI jobs. `PR66_BROWSER_QA.md` documents a prior one-off Playwright session for shell/tour UX; that is not a reusable CI harness and does not satisfy #56 or #69 evidence-separation lanes.

---

## Notes

- Synthetic fixtures only; no live AD exports or field hostnames in repo.
- `logs/targets/` policy unchanged.
- Parser false-positive risk documented in [`AGENT_HANDOFF_ADDENDUM.md`](AGENT_HANDOFF_ADDENDUM.md).
