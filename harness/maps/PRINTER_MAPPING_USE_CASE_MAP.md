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
| `northwell.shared-printer.organization-default` | Northwell Health / organization default | `proven` | `START-HERE-NORTHWELL-PRINTER-MAPPING.md` → Northwell technician CMDs → `mapping/Invoke-NorthwellPrinterMapping.ps1` |
| `health-and-hospitals.shared-printer.discovery` | Health & Hospitals / organization default | `discovery_required` | **no product launcher is registered** |

Northwell's SYSTEM identity, `/ga`, shared-queue form, HKLM proof, and runtime acceptance rules stay inside Northwell. Health & Hospitals remains separate until its own standards are observed and tracked.

## Northwell technician entrypoints

After selecting the Northwell use case:

```text
Map-NorthwellPrinter-SystemWide.cmd
Edit-NorthwellPrinter-Defaults.cmd
Edit-NorthwellPrinter-Batch.cmd
Map-NorthwellPrinters-Batch.cmd
```

- Quick CMD: ad-hoc one/many computers × one/many queues.
- Defaults editor: maintains one approved **local gitignored** server/queue pair; never maps.
- Batch editor: maintains local gitignored CSV assignments; never maps.
- Batch mapper: validates, resolves, displays the plan, requires `MAP`, then delegates rows to the canonical engine.

Batch rule: **one row = every queue in that row maps to every computer in that row**. Multiple values inside a cell use semicolons.

Tracked examples contain only synthetic placeholders. Live server/queue values belong in `Config\northwell-printer-defaults.local.json` or the local batch CSV, both ignored by Git.

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

For Northwell, product behavior is owned by:

- `START-HERE-NORTHWELL-PRINTER-MAPPING.md`
- `Map-NorthwellPrinter-SystemWide.cmd`
- `Edit-NorthwellPrinter-Defaults.cmd`
- `Edit-NorthwellPrinter-Batch.cmd`
- `Map-NorthwellPrinters-Batch.cmd`
- `mapping/Start-NorthwellPrinterMapping.ps1`
- `mapping/Start-NorthwellPrinterBatch.ps1`
- `mapping/Invoke-NorthwellPrinterMapping.ps1`
- `mapping/Modules/NorthwellPrinterMapping.Core.psm1`
- synthetic examples under `mapping/Examples/`

Batch is orchestration only; the canonical engine remains the single Northwell mapping implementation.

## Validation

```text
python harness/validators/validate-printer-mapping-use-cases.py
python Tests/survey/test_printer_mapping_use_case_contracts.py
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

Northwell product gate:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester\NorthwellPrinterMapping.Tests.ps1
```

A green harness proves use-case isolation and deterministic selection. Product CI proves launcher/batch contracts. Neither turns Northwell behavior into Health & Hospitals authority.
