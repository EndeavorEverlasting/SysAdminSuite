# Printer Mapping Use-Case Status

## WORKING / PROVEN

**Northwell Health — organization default**

SysAdminSuite has a tracked, proven Northwell printer-mapping use case:
`northwell.shared-printer.organization-default`.

The use-case registry points to the existing Northwell runbook, launcher, engine, and evidence policy. Real requested document output observed after that canonical workflow is runtime acceptance for that Northwell use case only.

The harness now makes the boundary explicit: **Northwell behavior does not transfer** to another organization or hospital merely because the technology looks similar.

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

- Northwell product mapping remains unchanged and registered as its own use case.
- Organization/site context is now required before a printer implementation is selected.
- Cross-organization inheritance is forbidden.
- Health & Hospitals is represented separately without fake product authority.
- Runtime acceptance is scoped to the same registered use case and organization/site context.
- Hooks and CI run the focused use-case validator.

## What is missing

- Health & Hospitals mapping standards have not yet been discovered.
- No hospital-specific site override is registered yet.
- No Health & Hospitals product launcher or engine should exist until the field requirements justify one.

## Validation

```text
python harness/validators/validate-printer-mapping-use-cases.py
python Tests/survey/test_printer_mapping_use_case_contracts.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

The focused authority is `harness/validators/validate-printer-mapping-use-cases.py`.

## Proof ceiling

This report and its validators prove repository/harness isolation and routing contracts only. They do not prove Health & Hospitals printer behavior, any site-specific standard, target reachability, mapping success, or physical output.
