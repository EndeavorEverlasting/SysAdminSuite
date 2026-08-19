# Printer Mapping Use-Case Map

This map keeps printer mapping readable for a fresh agent. **Printer mapping is not one generic SysAdminSuite behavior.** The implementation is selected only after organization and site context are resolved through `harness/api/printer-mapping-use-case-registry.json`.

## Selection order

1. Exact **site override** for the organization + hospital/site.
2. Registered organization default.
3. `BLOCK_FOR_DISCOVERY`.

Cross-organization inheritance is forbidden. Site inheritance is never implicit.

## Current use cases

| Use case | Organization/site | Status | Product authority |
|---|---|---|---|
| `northwell.shared-printer.organization-default` | Northwell Health / organization default | `proven` | `START-HERE-NORTHWELL-PRINTER-MAPPING.md` → `Map-NorthwellPrinter-SystemWide.cmd` → `mapping/Invoke-NorthwellPrinterMapping.ps1` |
| `health-and-hospitals.shared-printer.discovery` | Health & Hospitals / organization default | `discovery_required` | **no product launcher is registered** |

Northwell Health is the learned implementation. Its mapping scope, identity, queue form, `/ga` behavior, HKLM registration proof, and runtime acceptance rules stay inside that use case.

Health & Hospitals is intentionally separate. Until its standards are observed and tracked, no Northwell assumption is executable authority there.

## Key harness directories

- `harness/api/` — machine-readable use-case and general harness registries.
- `harness/workflows/` — deterministic selection and handoff sequences.
- `harness/skills/` — repeatable harness procedures.
- `harness/validators/` — fail-closed registry and wiring checks.
- `harness/maps/` — concise navigation maps such as this one.
- `harness/reports/` — English operator state.
- `schemas/harness/` — JSON Schema contracts.
- `Tests/survey/` — dependency-free harness contract tests.
- `.githooks/` — local commit/push gates.
- `.github/workflows/` — CI validation.

## Product versus harness boundary

The use-case registry chooses an implementation; it does not implement printer mapping.

For Northwell, product behavior remains in:
- `START-HERE-NORTHWELL-PRINTER-MAPPING.md`
- `Map-NorthwellPrinter-SystemWide.cmd`
- `mapping/Start-NorthwellPrinterMapping.ps1`
- `mapping/Invoke-NorthwellPrinterMapping.ps1`
- `mapping/Modules/NorthwellPrinterMapping.Core.psm1`

The harness must not rewrite those files merely to onboard another organization.

## Adding another organization

1. Add an organization-default registry record with status `discovery_required`.
2. Capture that organization's real requirements without borrowing another organization's mechanism.
3. Only after the standards and product path exist, promote the record to `proven`.
4. Add the product workflow/launcher/engine/evidence policy and the exact assumptions/proof fields.
5. Run the focused validator and the product workflow's own validators.

## Adding a newly acquired or independently operated hospital

Create a `site_override`. The site record outranks its organization's default. Reuse from the organization default is allowed only through explicit same-organization `parent_use_case_id` plus named `inherited_fields`.

## Build / test / validation commands

```text
python harness/validators/validate-printer-mapping-use-cases.py
python Tests/survey/test_printer_mapping_use_case_contracts.py
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
bash tests/survey/run_offline_survey_tests.sh
git diff --check
```

The dedicated CI authority is `.github/workflows/printer-mapping-use-case-contracts.yml`.

## Proof boundary

A green harness proves use-case isolation, file wiring, and deterministic selection. It does not prove Health & Hospitals behavior before discovery, and it does not turn one successful Northwell print into proof for another organization or hospital.
