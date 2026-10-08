# Cursor / local Windows agent handoff — Agilant HQ local TCP printer field certification

## EXECUTE THE REMAINING FIELD GATE. DO NOT REPLAN THE ARCHITECTURE.

Repo: EndeavorEverlasting/SysAdminSuite
PR: #518
Lane: one-click local Windows printer mapper field acceptance
Branch for local evidence: canonical refreshed main AFTER PR merge; if not merged, independently check out the PR head without altering unrelated local work.
Owned scope: operator-approved Agilant HQ local TCP mapping and its evidence; focused defects/regressions discovered during certification.
Forbidden: Northwell shared-queue engine, Health & Hospitals printer assumptions, DHCP or firewall administration, unsanctioned network transitions, broad network scans, cached-IP-only mapping, printer firmware changes, credential disclosure.
Physical proof requirement: actual Windows test page observed exiting the intended copier when sent from the new SysAdminSuite app.

## Before execution

1. Read AGENTS.md and the field-workflow skill; reconcile repository HEAD/PR provider truth, status, local installer freshness, field-release documentation and printer registry.
2. Confirm current operator is at **Agilant HQ** and workstation is on the **approved main network**, not Guest, Northwell, or another organization. Capture observed Wi-Fi SSID and actual workstation source IP before any printer action; do not assume the name of the SSID.
3. Confirm the copier model and currently displayed Wi-Fi IPv4 from the copier itself. Do not assume an earlier remembered address or infer DHCP change solely from failed TCP/9100.
4. Inspect the existing local Windows queue, driver, port, and any saved profile using read-only methods before mutation. The October 8 manual Windows test page is evidence for the mechanism, **not** proof the new app works.

## App / release prerequisites

- Build/inspect the app field-release ZIP using the canonical packaging script.
- Assert it contains Map-AgilantHqPrinter.cmd, GUI/Start-LocalTcpPrinterGui.ps1, mapping/Invoke-LocalTcpPrinter.ps1, the dashboard host, and runbook. Avoid trusting source-checkout-only files.
- Use a clean installed/portable app location. Do not run a stale user PATH shim or mutate C:\SASAL without its separate authority.
- Start the site-specific .cmd. Observe that the native GUI opens after normal UAC elevation; no copied PowerShell commands required.
- Save the printer profile privately only when the operator requests. Never commit hostname, printer IP, profile, screenshots, or local receipt to Git.

## Acceptance ladder

A. **Read-only:** Before clicking Map, verify no queue/port changed during preview. The preflight receipt must show current hostname resolution, panel comparison, actual TCP source IP, connected SSID if available, chosen address, driver, and existing port.

B. **Already-working queue:** With the manual queue installed using a legacy IP port, assert preflight classifies READY_TO_ADOPT or READY_TO_ADOPT_STALE; never silently overwrite. Explicitly check adoption, site confirmation, physical panel IP confirmation, and preview again.

C. **Apply:** Click Map / Repair. Read back Get-Printer, Get-PrinterPort, exact driver, destination and expected port; output MAPPED_NOW/ALREADY_MAPPED only after postcondition. Do not set default printer.

D. **Test:** Use the GUI Send test page button. Observe physical output on the correct device and answer the app's Yes/No attestation truthfully. Preserve both the engine receipt and distinct physical-observation receipt, redacted for any external report.

E. **Repeat:** Re-run preview/map with unchanged input; expect ALREADY_MAPPED (idempotent). Open saved profile; assert last IP does NOT autopopulate physical panel field or auto-check the confirmation checkbox.

F. **Address-change emulation (isolated, not on a live printer without explicit approval):** Use an isolated Windows test environment or mock seams to simulate changed DNS and stale managed/legacy port; verify block on DNS_PANEL_MISMATCH, no silent cached-IP reuse, explicit panel-IP override only, adoption safety and correct rollback. Do not deliberately disrupt the real HQ printer's DHCP lease.

G. **Negative paths:** Driver missing, wrong SSID when an approved expected SSID is set, TCP/9100 unavailable, mismatched device-panel IP, unmanaged non-TCP queue, ambiguous DNS, wrong org/site, canceled UAC, failed postcondition, and partial rollback must all fail closed with typed receipts and no false success.

## Proof and report

- Run focused Python contract, registry validator, existing printer use-case test, Windows PowerShell parser, changed-surface Pester and release-packaging smoke test. Fix failed gates and rerun; do not rename a skipped check as passed.
- Report every gate as designed / implemented / locally validated / integration validated / merged / app packaged / workstation deployed / physically verified.
- Preserve sanitised evidence path/receipt references and current Git SHA/branch/PR, status, and any skipped tests.
- If the operator cannot access the copier/device, STOP at **physical certification pending** with exact next action and durable handoff. Never claim production verification.

## Product boundary

Northwell printer mapping stays SYSTEM plus shared UNC / PrintUIEntry /ga; this Agilant HQ workflow is local TCP/RAW/9100 with exact driver, current device-panel binding, explicit legacy adoption, and private per-run receipts. H&H remains discovery-only. Cross-organization inheritance is a release-blocking defect.
