# Printer Mapping Use-Case Routing Skill

## Trigger

Use this skill for **every printer-mapping request before selecting an implementation**. Organization and site are part of printer-mapping identity. A printer workflow that is proven at one organization or hospital is not a generic Windows printer recipe.

This is a harness-routing skill. It does not change printer product code, contact a target, map a printer, or authorize a mapping mechanism.

## Required inputs

- organization or health-system context
- site/hospital context when known or operationally relevant
- requested printer-mapping action
- existing evidence, if the request is a continuation

## Canonical authorities

1. `harness/api/printer-mapping-use-case-registry.json`
2. `schemas/harness/printer-mapping-use-case-registry.schema.json`
3. `harness/workflows/printer-mapping-use-case-routing.yaml`
4. `harness/maps/PRINTER_MAPPING_USE_CASE_MAP.md`
5. `.claude/skills/field-workflow/SKILL.md` only after a proven use case has been selected

## Selection procedure

1. Resolve the organization explicitly. Never infer it from technical similarity.
2. Resolve the hospital/site when supplied, newly acquired, independently operated, or otherwise known to differ.
3. Select an **Exact site override** first when one is registered.
4. Otherwise select the registered organization default.
5. If no authorized use case exists, or an independently operated site has no override, fail closed to `BLOCK_FOR_DISCOVERY`.
6. Load product workflow/launcher/engine assumptions only from the selected `use_case_id`.

No cross-organization inheritance is allowed. Site inheritance is never implicit. If a site override intentionally reuses part of its organization's default later, it must name its parent and the exact inherited fields in the registry.

## Current use cases

### Northwell Health

`northwell.shared-printer.organization-default` is `proven`.

Its registered product authority is the existing Northwell workflow. The known system-wide `/ga`, SYSTEM, hostname/UNC, HKLM registration, no-direct-IP, and runtime-acceptance rules belong to that use case.

**Northwell rules are not portable defaults.**

### Health & Hospitals

`health-and-hospitals.shared-printer.discovery` is `discovery_required`.

No product launcher, engine, mapping mechanism, mapping scope, queue convention, print-server convention, or proof policy is authorized yet. The next Health & Hospitals field session should learn those facts and then update the registry and create a separately validated product workflow if appropriate.

Do not route a Health & Hospitals request to the Northwell launcher merely because both environments use Windows or hospital printers.

## Newly acquired or independently operated hospitals

A hospital that follows standards different from its parent health system gets a separate `site_override` use case. Do not silently inherit the parent organization's mapping rules.

A site override must identify:
- organization and site;
- its status;
- its product workflow when proven;
- any explicit same-organization parent and exact inherited fields, if reuse is intentional;
- its own proof and discovery boundaries.

## Failure handling

Treat these as blocking routing defects:
- organization unknown;
- site ambiguity matters to standards;
- registered status is `discovery_required`;
- a product path is present on a discovery-only record;
- cross-organization parentage;
- implicit site inheritance;
- proof from one use case is offered as proof for another.

Do not resolve these defects by guessing or by choosing the most similar existing workflow.

## Validation

Run:

```text
python harness/validators/validate-printer-mapping-use-cases.py
python Tests/survey/test_printer_mapping_use_case_contracts.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

When the product workflow for a proven use case is changed, also run that use case's product validators.

## Expected outputs

- one selected registered `use_case_id`, or a fail-closed discovery classification;
- exact product authority only for `proven` cases;
- organization/site-scoped proof interpretation;
- a discovery checklist for unlearned environments;
- a clean handoff that never implies one organization's behavior applies elsewhere.

## Proof ceiling

Static harness proof that printer workflows are isolated and selected deterministically by registered organization/site context. This skill cannot prove an organization's real printer standards or that a printer actually mapped or printed.
