# Printer Mapping Use-Case Status

## WORKING / PROVEN

**Northwell Health — organization default**

SysAdminSuite has a tracked, proven Northwell printer-mapping use case:
`northwell.shared-printer.organization-default`.

The registered runtime authority remains the Northwell runbook, system-wide runtime launcher, canonical engine, and evidence policy. Routine technician distribution now adds `Map-NorthwellPrinter.cmd` as a thin one-click front door into the same trusted `sas printer` / bootstrap path; it does not introduce another mapping implementation.

### Current field checkpoint

On **August 20, 2026**, the current-main Northwell quick workflow was observed on an approved `DomainAuthenticated` wired connection completing both:

- SYSTEM-wide requested printer registration proof in HKLM; and
- immediate active-user printer materialization proof.

This is live mapping/materialization evidence for the current Northwell use case. It is intentionally narrower than physical print acceptance: a real requested document must still be separately observed printing before claiming document-output runtime acceptance.

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
- The current quick path has live SYSTEM/HKLM + active-user materialization evidence on a protected wired route.
- `Map-NorthwellPrinter.cmd` gives non-technical technicians a one-click route into the same canonical workflow.
- The universal installer distributes that CMD beside `sas.cmd` instead of requiring a technician checkout.
- Recent proven PCs/printers reduce repeated typing without becoming authoritative cache state.
- Organization/site context is required before a printer implementation is selected.
- Cross-organization inheritance is forbidden.
- Health & Hospitals is represented separately without fake product authority.
- Runtime acceptance remains scoped to the same registered use case and organization/site context.
- Hooks and CI run the focused use-case validator.

## What is missing

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

Repository/harness validation proves isolation, routing, thin-launcher delegation, installer distribution, and tutorial contracts. The supplied August 20 field evidence additionally proves the current Northwell quick path reached SYSTEM-wide HKLM registration and immediate active-user materialization on that approved protected wired path. It does not prove Health & Hospitals behavior, site-specific standards, every network path, or physical document output.
