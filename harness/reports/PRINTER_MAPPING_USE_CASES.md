# Printer Mapping Use-Case Status

## WORKING / PROVEN

**Northwell Health — organization default**

SysAdminSuite has a tracked, proven Northwell printer-mapping use case:
`northwell.shared-printer.organization-default`.

The registered runtime authority remains the Northwell runbook, system-wide runtime launcher, operator wrapper, canonical mapper/finalizer chain, and evidence policy. Routine technician distribution adds `Map-NorthwellPrinter.cmd` as a thin one-click front door into the same trusted `sas printer` / bootstrap path; it does not introduce another mapping implementation.

### Field checkpoint

On **August 20, 2026**, SysAdminSuite commit `4c5f1252aae24269ac1e0ab28ef9366ea08fd33f` was observed through `sas printer` on an approved `DomainAuthenticated` wired connection completing both:

- SYSTEM-wide requested printer registration proof in HKLM; and
- immediate active-user printer materialization proof.

This is live mapping/materialization evidence for the underlying Northwell use case on that observed protected path. It is intentionally narrower than physical print acceptance: a real requested document must still be separately observed printing before claiming document-output runtime acceptance.

Subsequent mainline printer work added a bounded per-user local admin-box trail and explicit outcomes (`MAPPED_NOW`, `ALREADY_MAPPED`, `NOT_FOUND`, `FAILED`, `READY`, `READY_NEXT_LOGON`) while preserving the same resilient mapper/finalizer authority. Repository validation proves that composition. The one-click wrapper now stamps its process-local launch identity into the local operator trail as `EntryPoint=TECHNICIAN_CMD`, so the next field run can prove that exact front door was used without changing printer transport. It still needs post-refresh field acceptance before claiming that exact wrapper was observed live.

Technician path:

```text
Map-NorthwellPrinter.cmd
```

Terminal equivalent:

```text
sas printer
```

Tutorial: `docs/tutorials/NORTHWELL_PRINTER_MAPPING_FOR_TECHS.md`.

The harness keeps the organization boundary explicit: **Northwell behavior does not transfer** to another organization or hospital merely because the technology looks similar.

## DISCOVERY REQUIRED

**Health & Hospitals — organization default**

`health-and-hospitals.shared-printer.discovery` is intentionally `discovery_required`.

There is no registered Health & Hospitals product launcher, engine, mechanism, mapping scope, queue convention, print-server authority, or runtime proof contract yet. This is not a missing-command bug. It is the correct fail-closed state until field discovery establishes the real standard.

The discovery checklist is machine-readable in `harness/api/printer-mapping-use-case-registry.json`.

## SITE-SPECIFIC USE CASES

Newly acquired or independently operated hospitals may differ from their parent organization. The harness requires an explicit `site_override` when local standards differ.

Selection is:
1. exact site override;
2. registered organization default;
3. discovery block.

No site silently inherits a different organization's rules, and no acquired hospital is assumed to follow parent standards merely from ownership.

## What is working

- Northwell system-wide mapping remains registered as its own organization-specific use case.
- Commit `4c5f1252...` has live SYSTEM/HKLM + active-user materialization evidence on an approved protected wired route.
- The current runtime operator layer adds clear `MAPPED NOW` / `ALREADY MAPPED` / `NOT FOUND` / `FAILED` / `READY` outcomes and a bounded local trail without replacing mapping authority.
- `Map-NorthwellPrinter.cmd` gives non-technical technicians a one-click route into the same canonical workflow.
- The technician CMD accepts only installer-owned sibling `sas.cmd` or sibling trusted bootstrap authority; an unqualified PATH shim is forbidden.
- The universal installer distributes that CMD beside `sas.cmd` instead of requiring a technician checkout.
- Wrapper-originated runs can be attributed from the local `latest.v1.json` record through `EntryPoint=TECHNICIAN_CMD`; direct or otherwise unmarked `sas printer` runs remain `SAS_PRINTER`.
- Recent proven PCs/printers reduce repeated typing without becoming authoritative cache state.
- Organization/site context is required before a printer implementation is selected.
- Cross-organization inheritance is forbidden.
- Health & Hospitals is represented separately without fake product authority.
- Runtime acceptance remains scoped to the same registered use case and organization/site context.
- Hooks and CI run the focused use-case validator.

## What is missing

- The new one-click `Map-NorthwellPrinter.cmd` wrapper has not yet been separately field-accepted after installation/refresh; close this gate only with a protected field run whose local latest record reports `EntryPoint=TECHNICIAN_CMD` and whose normal authoritative workflow reaches `READY` or `READY_NEXT_LOGON`.
- Physical document output is not claimed by the August 20 mapping/materialization evidence alone.
- Health & Hospitals mapping standards have not yet been discovered.
- No hospital-specific site override is registered yet.
- No Health & Hospitals product launcher or engine should exist until field requirements justify one.

## Validation

```text
python harness/validators/validate-printer-mapping-use-cases.py
python Tests/survey/test_printer_mapping_use_case_contracts.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

Technician launcher validation:

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-Pester5Suite.ps1 -TestPath Tests/Pester/NorthwellPrinterTechnicianLauncher.Tests.ps1
```

The focused harness authority remains `harness/validators/validate-printer-mapping-use-cases.py`.

## Proof ceiling

Repository/harness validation proves organization isolation, routing, operator-layer composition, thin-launcher delegation, trusted-launcher authority, installer distribution, and tutorial/governance contracts. The August 20 field evidence additionally proves commit `4c5f1252...` reached SYSTEM-wide HKLM registration and immediate active-user materialization on the observed protected wired path. It proves the technician CMD can stamp attributable local provenance, but it does not prove that CMD has itself been field-run yet, Health & Hospitals behavior, site-specific standards, every network path, or physical document output.
