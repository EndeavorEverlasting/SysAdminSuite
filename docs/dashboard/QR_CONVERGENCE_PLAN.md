# QR Convergence Plan

Date: 2026-06-24
Branch: `feature/qr-dashboard-convergence-plan-2026-06`
Base: `origin/main` at `2f526ed` or newer after fetch

Implementation gate: [QR Implementation Readiness](./QR_IMPLEMENTATION_READINESS.md) (`plan/qr-advanced-tools-readiness-2026-06`).

## Scope

This is a planning-only handoff for converging the open QR work after the Cybernet-first dashboard UI from PR #66. Do not merge PR #47 or PR #43 as part of this plan, and do not modify dashboard UI in this branch.

Reviewed remote PRs:

- PR #47, `feature/web-qr-builder`: web dashboard QR Payload Builder.
- PR #43, `feature/qr-generator-tab-2026-05`: WinForms PowerShell GUI QR Generator tab.
- PR #66, `feature/cybernet-first-dashboard-ui-2026-06`: merged Cybernet-first dashboard baseline.

## Recommendation

Build the dashboard QR feature from PR #47's web payload-builder concept, but land it as a new current-main implementation under **Advanced Tools**. Do not merge PR #47 as-is because it is conflicting, standalone-after-bundle code from the pre-PR #66 dashboard shape. Close or supersede PR #43 for dashboard convergence because it is a Windows GUI feature, not a web dashboard convergence path.

Keep these pieces from PR #47:

- Bash-first target-list payloads.
- Exact payload preview before QR rendering.
- Manual `.txt` and `.csv` target loading.
- Copy/download/large QR affordances.
- Local vendored QR renderer.

Change these pieces before landing:

- Integrate as a normal dashboard panel/module, not an after-`bundle.js` standalone injector.
- Place QR behind `Advanced Tools`; do not add a hero CTA or first-screen tab.
- Add dashboard smoke coverage for the QR panel contract.
- Treat CDN rendering as a development fallback only, never the field requirement.

## First-Screen Button Budget

PR #66 defines the first-screen budget as exactly three visible actions:

1. `Advanced Tools`
2. `Start Cybernet Survey`
3. `Load Evidence`

PR #47 can preserve that budget only after rebasing onto current `main` and keeping QR inside the collapsed Advanced Tools area. Its `injectQrTab()` code adds a `QR Builder` tab to `#tabs`, and current `main` places `#tabs` inside `#advanced-section`, which is hidden until `Advanced Tools` is opened.

Do not promote QR to the hero, header, or first screen. QR should be discoverable after the operator intentionally opens Advanced Tools.

## PR #43 Versus PR #66

PR #43 does not directly conflict with PR #66's web dashboard files. It modifies the PowerShell WinForms GUI (`GUI/Start-SysAdminSuiteGui.ps1`), PowerShell GUI tests, README guidance, `bash/qr/README.md`, and QR policy documentation.

It does conflict with the dashboard convergence goal:

- It adds a Windows GUI tab, not a dashboard panel.
- It is PowerShell-centered by implementation, even though it labels Northwell Bash-forward posture.
- It does not address the PR #66 Cybernet-first dashboard shell, Advanced Tools placement, dashboard bundling, or dashboard smoke tests.

Treat PR #43 as a separate Windows GUI legacy/PowerShell discussion. It should not be the basis for dashboard QR convergence.

## Closest Architecture Match

PR #47 is closer to the current dashboard product surface because it targets `dashboard/index.html` and a browser-based QR builder. However, its implementation is not the preferred current dashboard architecture:

- Current dashboard source is organized through `dashboard/js/app.js`, panel modules, `dashboard/js/tour.js`, and `dashboard/build-bundle.js`.
- PR #47 adds `dashboard/js/panel-qr-standalone.js` and loads it after `dashboard/js/bundle.js`.
- Standalone injection was useful for isolated review, but it bypasses the normal module and bundle path.

The convergence branch should create a first-class dashboard QR module and add it to the bundle pipeline. If a short-lived standalone spike is retained, it should be explicitly temporary and not the final merge shape.

## Advanced Tools Placement

QR can and should live under **Advanced Tools**.

Recommended placement:

- Add `QR Builder` as an Advanced Review Panel tab, near `Remote Tasks`.
- Keep Advanced Tools collapsed on first load.
- Preserve `Start Cybernet Survey` as the primary front door.
- Keep QR target-list import and payload generation subordinate to survey/review workflows.

This matches PR #66's rule that detailed panels, command generation, and non-primary workflows stay behind Advanced Tools.

## CDN And Offline Field Concerns

PR #47 originally called out QR rendering as a dependency and later added a vendored local renderer at `dashboard/js/vendor/qrcode.min.js` with a CDN fallback.

For field use, the local vendored renderer must be the supported path:

- Locked-down hospital or corporate networks may block `cdn.jsdelivr.net`.
- Guest networks are not valid evidence for internal access, and CDN success does not prove field readiness.
- A CDN fallback may leak dashboard usage metadata to a third party.
- Offline dashboard use must still generate scannable QR codes.
- If the local renderer is unavailable, the dashboard may preview/copy/download payload text, but that is degraded mode and should be visible to the technician.

Before landing a QR dashboard PR, verify the vendored file is pinned, license-reviewed, and covered by a no-network smoke or browser check.

## Branch Action

Recommended branch handling:

- Close/supersede PR #43 for dashboard QR convergence. It is not the dashboard path.
- Supersede PR #47 with a new current-main dashboard QR PR, or rebuild PR #47 so it targets PR #66's Advanced Tools architecture before review.

Do not merge either PR directly into `main` in its current state.

## Proposed Convergence Steps

1. Start from current `origin/main`.
2. Add `dashboard/js/panel-qr.js` as a normal dashboard module.
3. Add the QR panel to `dashboard/build-bundle.js`.
4. Add a `QR Builder` tab inside `#advanced-section`, not the hero.
5. Vendor and pin the QR renderer locally; keep CDN fallback non-required.
6. Add dashboard smoke assertions for Advanced Tools placement and no first-screen QR control.
7. Document the operator workflow under `docs/dashboard/`.

