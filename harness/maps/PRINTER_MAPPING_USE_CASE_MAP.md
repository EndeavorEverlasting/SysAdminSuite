# Printer Mapping Use-Case Map

**Printer mapping is not one generic SysAdminSuite behavior.** Select organization/site context through `harness/api/printer-mapping-use-case-registry.json` before choosing an implementation.

## Selection order

1. Exact site override.
2. Registered organization default.
3. `BLOCK_FOR_DISCOVERY`.

Cross-organization inheritance is forbidden. Site inheritance is never implicit.

## Current use cases

| Use case | Organization/site | Status | Product authority |
|---|---|---|---|
| `northwell.shared-printer.organization-default` | Northwell Health / organization default | `proven` | `START-HERE-NORTHWELL-PRINTER-MAPPING.md` → technician front door → registered Northwell runtime launcher → canonical engine |
| `health-and-hospitals.shared-printer.discovery` | Health & Hospitals / organization default | `discovery_required` | **no product launcher is registered** |

Northwell's SYSTEM identity, `/ga`, shared-queue form, HKLM proof, and runtime acceptance rules stay inside Northwell. Health & Hospitals remains separate until its own standards are observed and tracked.

## Northwell technician entrypoints

Routine mapping now has one obvious non-technical front door:

```text
Map-NorthwellPrinter.cmd
```

Terminal equivalent:

```text
sas printer
```

The technician CMD is a thin distribution wrapper. It delegates into `sas printer` / `Bootstrap-SysAdminSuitePrinter.cmd`, which selects the trusted current runtime and ultimately invokes the registered quick runtime launcher:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

This distinction is deliberate: `Map-NorthwellPrinter.cmd` is the **human-facing entrypoint**; `Map-NorthwellPrinter-SystemWide.cmd` remains the **registered product/runtime launcher**. There is still one mapping implementation.

Related technician/advanced entrypoints:

```text
Edit-NorthwellPrinter-Defaults.cmd
Edit-NorthwellPrinter-Batch.cmd
Map-NorthwellPrinters-Batch.cmd
Manage-NorthwellPrinters.cmd
```

- Quick front door: ad-hoc one/many computers × one/many queues with recent-proven input reuse.
- Defaults editor: maintains one approved **local gitignored** server/queue pair; never maps.
- Batch editor: maintains local gitignored assignments; never maps.
- Batch mapper: validates, resolves, displays the plan, then delegates to the canonical engine.
- Management menu: advanced unmap/undo/default/batch/evidence operations.

Technician tutorial: `docs/tutorials/NORTHWELL_PRINTER_MAPPING_FOR_TECHS.md`.

Tracked examples contain only synthetic placeholders. Live server/queue values belong in local ignored state, not Git.

## Field proof checkpoint

On **August 20, 2026**, the current-main Northwell quick workflow was observed on an approved `DomainAuthenticated` wired connection producing:

- SYSTEM-wide requested queue proof in HKLM; and
- immediate active-user materialization proof.

This closes the mapping/materialization proof gap for the current Northwell use case. Physical document output is still a separate runtime-acceptance observation.

## Key harness directories

- `harness/api/` — machine-readable use-case and harness registries.
- `harness/workflows/` — deterministic selection/handoff sequences.
- `harness/skills/` — repeatable procedures.
- `harness/validators/` — fail-closed wiring checks.
- `harness/maps/` — navigation maps.
- `harness/reports/` — English operator state.
- `schemas/harness/` — JSON schemas.
- `Tests/survey/` / `Tests/Pester/` — contracts.
- `.github/workflows/` — CI validation.

## Product boundary

For Northwell, product/runtime behavior remains owned by:

- `START-HERE-NORTHWELL-PRINTER-MAPPING.md`
- `Map-NorthwellPrinter-SystemWide.cmd`
- `Bootstrap-SysAdminSuitePrinter.ps1`
- `mapping/Start-NorthwellPrinterMapping.ps1`
- `mapping/Invoke-NorthwellPrinterMapping.ps1`
- `mapping/Modules/NorthwellPrinterMapping.Core.psm1`

Distribution/usability surfaces include:

- `Map-NorthwellPrinter.cmd`
- `scripts/Install-SasUniversalFieldLauncher.ps1`
- `docs/tutorials/NORTHWELL_PRINTER_MAPPING_FOR_TECHS.md`
- `START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md`

The wrapper and tutorials may make the path easier to discover, but they may not introduce a second mapper or weaken Northwell proof/safety rules.

## Validation

```text
python harness/validators/validate-printer-mapping-use-cases.py
python Tests/survey/test_printer_mapping_use_case_contracts.py
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

Focused technician-launcher gate:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester\NorthwellPrinterTechnicianLauncher.Tests.ps1
```

A green harness proves use-case isolation and deterministic selection. Product/launcher CI proves delegation and mapping contracts. Neither turns Northwell behavior into Health & Hospitals authority.
