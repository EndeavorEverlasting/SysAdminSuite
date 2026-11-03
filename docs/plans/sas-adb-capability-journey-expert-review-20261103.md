# SAS ADB Capability Journey — expert review and acceptance

**Product home:** existing Windows tray-hosted SysAdminSuite Dashboard; `/dashboard/capabilities.html`. Do not create a new site, public service, or target-side agent.

**Baseline:** merged PR #553 / `main@c4f8ac612a011e522f53dbdd2f1cb6a0af8ea03d`. **Parent:** issue #554 (Admin Box runtime proof and evidence coverage). This feature is an additive read-only presentation slice; it does **not** close #554.

## Product hypothesis (P82)
The operator and an external reviewer should be able to answer **what SAS Android/ADB supports** and **how far each capability has actually been proved**, without assuming a registry row is an executable or a receipt is field success.

The selected candidate is an eight-stage operator journey in the existing capability cockpit. It references *canonical command IDs* from `harness/api/harness-command-registry.json`; it is not another execution registry, local agent, runner, or unverified live data source.

## Four independent states
1. **Registered:** exact command ID exists in current host-loaded canonical registry; never assume the map's annotation itself is registration.
2. **Host entry:** exact entrypoint file can be observed on the local host, or runtime dispatcher is not probed; file presence is **not** executable readiness.
3. **Local evidence:** safe metadata on a recognized private local receipt; “not queried” and “no matching survey receipt” remain different. Timestamp and typed state are historical artifacts, not active-process confirmation.
4. **Field outcome:** NOT VERIFIED in the current endpoint; require independently bound target/session/real-world acceptance from an authorized proof owner. A typed `ADB_DEVICE_READY` receipt is not permission to mutate, deployment proof or field acceptance.

UI must fail closed on API/registry failure; no fabricated demonstration data, host identity, credential/serial/MAC/IP exposure, target connections, command execution or firmware mutation.

## Current reference workflow
The eight stages bind host readiness, USB/ADB transport, read-only inventory, version-domain classification, baseline/recovery, exact-target TCP/IP with revert, view-only display, and capability program orchestration. They describe *possibilities and gates*, not an instruction to run them in sequence. Reader physical attachment, Windows enumeration, ADB authorization, inventory, remote view and field acceptance are separate facts. Vendor-console registration and repeated exhausted menu discovery are not newly required gates.

Source roles:
- `docs/HH_CC_READER_ADB_ADMIN_BOX_WORKFLOW.md` — authoritative administered workflow and transport/authority constraints.
- `docs/HH_CC_READER_KIOSK4_MENU_CAPABILITY_MAP.md` — exhausted routes and privacy-safe historical field interpretation.
- `src/SysAdminSuite.DashboardHost/DashboardCapabilitySnapshot.cs` — local read-only evidence projection and proof ceiling.
- `harness/api/harness-command-registry.json` — exact command identities.
- Private Upstream Intelligence Library START HERE and its original master (research/provenance only, **not** implementation or asset license authorization).

## Product/design engineering critique checklist
The candidate stays in the dashboard's established dark surface rather than introducing arbitrary branding. Each stage has a scannable numeral, short job-to-be-done, four independently named facts and drill-through to the canonical command. The view uses text-node rendering, keyboard-operable Inspect buttons, an ARIA-labeled ordered list, a live status explanation, responsive two-column metrics and a single-column small-screen fallback.

Review against these independently measurable gates:
- **Comprehension:** a reviewer can distinguish command registration, local file presence, local receipt and actual field outcome without a verbal explanation.
- **Findability:** a reviewer can locate `hh-cc-reader-adb-probe` and navigate to its raw registered command detail in one Inspect action, without losing the capability map.
- **Error honesty:** if host API/registry fails, the ADB map must clear rather than display old or demo data.
- **Safety:** zero device requests, zero browser-side command dispatch, zero remote management, zero private host/reader identifiers in page text or bundled static assets.
- **Accessibility:** headings, keyboard inspection, focus styling, mobile overflow, readable labels, reduced-motion compatibility, status announcements.
- **Release:** mandatory launcher and the existing field-release ZIP must still serve the cockpit and its only required JS; no new standalone dashboard.
- **Proof:** only Windows/CI outcomes can be claimed until a real Admin Box 1 browser session and private evidence readback are observed.

## Trifecta convergence
- **P07 — repository execution:** deliver the bounded UI and automated contract, inspect PR/checks, integrate only after required gates.
- **P82 — prototype/measure/refine:** compare before/after operator discovery: previous cockpit required searching the 53-command list; new journey exposes 8 annotated stages mapped to 10 current canonical references. Measure 0 unknown-command IDs, preserved filter path and fail-closed feedback. Continue critique against mobile and keyboard interaction without adopting unlicensed assets.
- **P08 — actual runtime proof:** on independently verified Admin Box 1, launch `Open-SasCapabilityCockpit.cmd`; record actual browser route, API count, navigation through Inspect, keyboard/focus, responsive behavior, error-state behavior and protected old dashboard navigation. Preserve the private observation on host only. No live success claimed before these steps run.

## Review request (not a claim of completed review)
Ask product design and accessibility engineers to critique information hierarchy, stage density, labels, affordances and proof-language comprehension; ask security/Windows host engineers to inspect the non-execution boundary and packaging. Apply review outcomes to this existing page/host, not a second product. No reviewer, human signoff, live process or field outcome has been observed merely by opening this document.

**Operational successor:** GitHub issue #554; local runtime acceptance is the next decisive gate after repository checks.
