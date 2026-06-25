# PR56 Browser QA Status

Branch: `feature/ad-registered-population-integration`
Base: `main @ 2f526ed` (rebased)
Date: 2026-06-25
Browser harness: **not run in this lane** (no Playwright/browser automation invoked in agent runtime)

## Result

Overall QA result: **BLOCKED — manual browser pass required**

Automated coverage: dashboard smoke **64/64 PASS** (18 parser + 24 shell + 18 tour + ad contracts), targets policy PASS, `Tests/bash/smoke-ad-reconcile.sh` PASS.

## Smoke evidence (automated)

| Check | Result |
|-------|--------|
| AD sample detected as `ad-registered-population` | PASS |
| `store.adRegisteredPopulation` wiring in app.js | PASS |
| AD summary container in index.html | PASS |
| No false AD serial/reachability proof language | PASS |
| Naabu parser contracts | PASS (no regression) |
| Cybernet-first shell + tour | PASS (no regression) |

## Manual browser checklist (operator)

- [ ] First screen still has exactly 3 actions: Start Cybernet Survey, Load Evidence, Advanced Tools
- [ ] Load `dashboard/samples/ad_registered_population.sample.csv`
- [ ] Load Naabu sample JSON/JSONL
- [ ] Confirm AD Registered Population summary appears separately from Review Results reachability block
- [ ] Confirm UI does not claim AD proves serial or reachability
- [ ] 320px viewport: no horizontal overflow on hero/review sections
- [ ] Keyboard navigation through hero actions and Advanced Tools toggle
- [ ] Advanced Tools panels still behave

## Notes

- AD population is **population authority**, not hardware identity or reachability proof.
- Synthetic fixtures only; no live AD exports committed.
- `logs/targets/` not touched in PR branch (`.gitkeep` removed per policy).
