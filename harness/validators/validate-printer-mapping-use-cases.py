#!/usr/bin/env python3
"""Validate organization/site isolation for printer-mapping use cases."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

try:
    import jsonschema  # type: ignore
except ImportError:  # Local hooks stay dependency-free; CI installs jsonschema.
    jsonschema = None

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/printer-mapping-use-case-registry.json"
SCHEMA = ROOT / "schemas/harness/printer-mapping-use-case-registry.schema.json"
WORKFLOW = ROOT / "harness/workflows/printer-mapping-use-case-routing.yaml"
SKILL = ROOT / "harness/skills/printer-mapping-use-case-routing/SKILL.md"
MAP = ROOT / "harness/maps/PRINTER_MAPPING_USE_CASE_MAP.md"
REPORT = ROOT / "harness/reports/PRINTER_MAPPING_USE_CASES.md"
FIELD_SKILL = ROOT / ".claude/skills/field-workflow/SKILL.md"
FRESH_AGENT = ROOT / "harness/workflows/fresh-agent-intake.yaml"
AGENT_ROUTING = ROOT / "harness/api/agent-routing-manifest.json"
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
VALIDATOR_REGISTRY = ROOT / "harness/api/harness-validator-registry.json"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/printer-mapping-use-case-contracts.yml"
TEST = ROOT / "Tests/survey/test_printer_mapping_use_case_contracts.py"

REQUIRED_COMPONENT_IDS = {
    "printer-mapping-use-case-registry",
    "printer-mapping-use-case-registry-schema",
    "printer-mapping-use-case-workflow",
    "printer-mapping-use-case-skill",
    "printer-mapping-use-case-map",
    "printer-mapping-use-case-report",
    "printer-mapping-use-case-validator",
    "printer-mapping-use-case-contracts",
    "printer-mapping-use-case-ci",
}
ROOT_KEYS = {"schema_version", "repository", "selection_policy", "status_definitions", "use_cases"}
POLICY_KEYS = {
    "context_fields", "site_override_precedence", "organization_default_allowed",
    "unknown_organization_action", "unknown_site_action", "cross_organization_inheritance",
    "implicit_site_inheritance", "runtime_acceptance_scope", "rule",
}
STATUS_DEFINITION_KEYS = {"proven", "discovery_required", "unsupported", "deprecated"}
USE_CASE_KEYS = {
    "id", "organization_id", "organization_name", "scope_type", "site_id", "site_name",
    "status", "parent_use_case_id", "inherited_fields", "product_workflow", "product_launcher",
    "product_engine", "evidence_policy", "agent_skill", "assumptions", "proof",
    "discovery_requirements",
}
ALLOWED_SCOPE_TYPES = {"organization_default", "site_override"}
ALLOWED_STATUSES = {"proven", "discovery_required", "unsupported", "deprecated"}


def read(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"missing printer-mapping harness surface: {path.relative_to(ROOT).as_posix()}")
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def assert_exact_keys(value: dict, expected: set[str], label: str) -> None:
    actual = set(value)
    missing = expected - actual
    unknown = actual - expected
    assert not missing, f"{label} missing required keys: {sorted(missing)}"
    assert not unknown, f"{label} contains unknown keys: {sorted(unknown)}"


def assert_string(value: object, label: str, *, nullable: bool = False) -> None:
    if nullable and value is None:
        return
    assert isinstance(value, str) and value.strip(), f"{label} must be a non-empty string"


def validate_dependency_free_shape(data: dict) -> None:
    """Mirror authority-critical schema rules for bare-Python local hooks."""
    assert isinstance(data, dict), "printer-mapping registry root must be an object"
    assert_exact_keys(data, ROOT_KEYS, "printer-mapping registry")
    assert data["schema_version"] == "sas-printer-mapping-use-case-registry/v1"
    assert data["repository"] == "EndeavorEverlasting/SysAdminSuite"

    policy = data["selection_policy"]
    assert isinstance(policy, dict), "selection_policy must be an object"
    assert_exact_keys(policy, POLICY_KEYS, "selection_policy")
    assert policy["context_fields"] == ["organization_id", "site_id"]
    for field in (
        "site_override_precedence", "organization_default_allowed",
        "cross_organization_inheritance", "implicit_site_inheritance",
    ):
        assert isinstance(policy[field], bool), f"selection_policy.{field} must be boolean"
    assert policy["site_override_precedence"] is True
    assert policy["organization_default_allowed"] is True
    assert policy["cross_organization_inheritance"] is False
    assert policy["implicit_site_inheritance"] is False
    assert policy["unknown_organization_action"] == "BLOCK_FOR_DISCOVERY"
    assert policy["unknown_site_action"] == "USE_REGISTERED_ORGANIZATION_DEFAULT_OR_BLOCK"
    assert_string(policy["runtime_acceptance_scope"], "selection_policy.runtime_acceptance_scope")
    assert_string(policy["rule"], "selection_policy.rule")

    status_definitions = data["status_definitions"]
    assert isinstance(status_definitions, dict), "status_definitions must be an object"
    assert_exact_keys(status_definitions, STATUS_DEFINITION_KEYS, "status_definitions")
    for key, value in status_definitions.items():
        assert_string(value, f"status_definitions.{key}")

    use_cases = data["use_cases"]
    assert isinstance(use_cases, list) and len(use_cases) >= 2, "use_cases must contain at least two records"
    for index, item in enumerate(use_cases):
        label = f"use_cases[{index}]"
        assert isinstance(item, dict), f"{label} must be an object"
        assert_exact_keys(item, USE_CASE_KEYS, label)
        for field in ("id", "organization_id", "organization_name", "agent_skill"):
            assert_string(item[field], f"{label}.{field}")
        assert item["scope_type"] in ALLOWED_SCOPE_TYPES, f"{label}.scope_type is unsupported: {item['scope_type']!r}"
        assert item["status"] in ALLOWED_STATUSES, f"{label}.status is unsupported: {item['status']!r}"
        assert_string(item["site_id"], f"{label}.site_id", nullable=True)
        assert_string(item["site_name"], f"{label}.site_name", nullable=True)
        assert_string(item["parent_use_case_id"], f"{label}.parent_use_case_id", nullable=True)
        for field in ("product_workflow", "product_launcher", "product_engine", "evidence_policy"):
            assert_string(item[field], f"{label}.{field}", nullable=True)
        assert isinstance(item["inherited_fields"], list), f"{label}.inherited_fields must be an array"
        assert len(item["inherited_fields"]) == len(set(item["inherited_fields"])), f"{label}.inherited_fields must be unique"
        assert all(isinstance(value, str) and value.strip() for value in item["inherited_fields"]), f"{label}.inherited_fields must contain strings"
        assert isinstance(item["discovery_requirements"], list), f"{label}.discovery_requirements must be an array"
        assert len(item["discovery_requirements"]) == len(set(item["discovery_requirements"])), f"{label}.discovery_requirements must be unique"
        assert all(isinstance(value, str) and value.strip() for value in item["discovery_requirements"]), f"{label}.discovery_requirements must contain strings"
        assert item["assumptions"] is None or isinstance(item["assumptions"], dict), f"{label}.assumptions must be object or null"
        assert item["proof"] is None or isinstance(item["proof"], dict), f"{label}.proof must be object or null"

        if item["scope_type"] == "organization_default":
            assert item["site_id"] is None and item["site_name"] is None, f"{label} organization default cannot name a site"
            assert item["parent_use_case_id"] is None, f"{label} organization default cannot inherit"
            assert item["inherited_fields"] == [], f"{label} organization default cannot inherit fields"
        else:
            assert_string(item["site_id"], f"{label}.site_id")
            assert_string(item["site_name"], f"{label}.site_name")

        if item["status"] == "proven":
            for field in ("product_workflow", "product_launcher", "product_engine", "evidence_policy"):
                assert_string(item[field], f"{label}.{field}")
            assert isinstance(item["assumptions"], dict), f"{label}.assumptions must be an object when proven"
            assert isinstance(item["proof"], dict), f"{label}.proof must be an object when proven"
            assert item["discovery_requirements"] == [], f"{label} proven record cannot retain discovery requirements"
        elif item["status"] == "discovery_required":
            for field in ("product_workflow", "product_launcher", "product_engine", "evidence_policy", "assumptions", "proof"):
                assert item[field] is None, f"{label}.{field} must be null while discovery_required"
            assert item["discovery_requirements"], f"{label} discovery_required record must name discovery requirements"


def assert_tracked(path: Path) -> None:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"printer-mapping harness surface is not tracked: {path.relative_to(ROOT).as_posix()}")


def main() -> None:
    data = load(REGISTRY)
    schema = load(SCHEMA)
    validate_dependency_free_shape(data)
    assert schema["properties"]["schema_version"]["const"] == data["schema_version"]
    if jsonschema is not None:
        jsonschema.Draft202012Validator(schema).validate(data)
        print("PASS: declared Draft 2020-12 printer registry schema")
    else:
        print("PASS: dependency-free printer registry shape (jsonschema unavailable locally)")

    policy = data["selection_policy"]
    assert "same use_case_id" in policy["runtime_acceptance_scope"]

    use_cases = data["use_cases"]
    ids = [item["id"] for item in use_cases]
    assert len(ids) == len(set(ids)), "duplicate printer-mapping use_case_id"
    by_id = {item["id"]: item for item in use_cases}

    org_defaults: set[str] = set()
    site_keys: set[tuple[str, str]] = set()
    for item in use_cases:
        if item["scope_type"] == "organization_default":
            assert item["organization_id"] not in org_defaults, f"duplicate organization default: {item['organization_id']}"
            org_defaults.add(item["organization_id"])
        else:
            key = (item["organization_id"], item["site_id"])
            assert key not in site_keys, f"duplicate site override: {key}"
            site_keys.add(key)

        parent_id = item["parent_use_case_id"]
        if parent_id is not None:
            assert parent_id in by_id, f"unknown parent use case: {parent_id}"
            parent = by_id[parent_id]
            assert parent["organization_id"] == item["organization_id"], "cross-organization inheritance is forbidden"
            assert item["scope_type"] == "site_override"
            assert item["inherited_fields"], "site inheritance must name exact inherited fields"

        if item["status"] == "proven":
            for field in ("product_workflow", "product_launcher", "product_engine", "evidence_policy", "agent_skill"):
                value = item[field]
                assert (ROOT / value).is_file(), f"proven use case path missing: {value}"

    northwell = by_id["northwell.shared-printer.organization-default"]
    assert northwell["organization_id"] == "northwell-health"
    assert northwell["status"] == "proven"
    assert northwell["product_workflow"] == "START-HERE-NORTHWELL-PRINTER-MAPPING.md"
    assert northwell["product_launcher"] == "Map-NorthwellPrinter-SystemWide.cmd"
    assert northwell["product_engine"] == "mapping/Invoke-NorthwellPrinterMapping.ps1"
    assert northwell["evidence_policy"] == "harness/api/northwell-printer-mapping-evidence-policy.json"
    assumptions = northwell["assumptions"]
    assert assumptions["mapping_scope"] == "system-wide/per-computer"
    assert assumptions["execution_identity"] == "SYSTEM"
    assert assumptions["mapping_mechanism"] == "PrintUIEntry /ga"
    assert assumptions["direct_ip_mapping"] is False
    assert assumptions["per_user_fallback"] is False
    assert assumptions["guess_print_server"] is False
    assert northwell["proof"]["lower_ranked_telemetry_cannot_override_runtime_acceptance"] is True

    h_and_h = by_id["health-and-hospitals.shared-printer.discovery"]
    assert h_and_h["organization_id"] == "health-and-hospitals"
    assert h_and_h["status"] == "discovery_required"
    assert h_and_h["parent_use_case_id"] is None
    assert h_and_h["inherited_fields"] == []
    assert any("site-specific exceptions" in value for value in h_and_h["discovery_requirements"])

    markers = {
        WORKFLOW: (
            "workflow_id: printer-mapping-use-case-routing",
            "exact site override",
            "registered organization default",
            "BLOCK_FOR_DISCOVERY",
            "do not copy Northwell assumptions",
            "discovery_required",
            "same use_case_id",
        ),
        SKILL: (
            "# Printer Mapping Use-Case Routing Skill",
            "Organization and site are part of printer-mapping identity",
            "Exact site override",
            "Health & Hospitals",
            "Northwell rules are not portable defaults",
            "discovery_required",
        ),
        MAP: (
            "# Printer Mapping Use-Case Map",
            "Northwell Health",
            "Health & Hospitals",
            "site override",
            "Map-NorthwellPrinter-SystemWide.cmd",
            "no product launcher is registered",
        ),
        REPORT: (
            "# Printer Mapping Use-Case Status",
            "WORKING / PROVEN",
            "DISCOVERY REQUIRED",
            "Northwell behavior does not transfer",
            "Newly acquired or independently operated hospitals",
            "validate-printer-mapping-use-cases.py",
        ),
        FIELD_SKILL: (
            "## Printer mapping context gate",
            "printer-mapping-use-case-registry.json",
            "Northwell rules are not portable defaults",
            "Health & Hospitals",
            "discovery_required",
            "site_override",
        ),
        FRESH_AGENT: (
            "printer-mapping-use-case-registry.json",
            "printer-mapping-use-case-routing/SKILL.md",
            "do not copy Northwell assumptions",
            "validate-printer-mapping-use-cases.py",
        ),
    }
    for path, required in markers.items():
        text = read(path)
        for marker in required:
            assert marker in text, f"{path.relative_to(ROOT)} missing marker: {marker}"

    routing = load(AGENT_ROUTING)
    field_route = next(item for item in routing["triggers"] if item["target"] == "field-workflow")
    normalized_signals = {signal.lower() for signal in field_route["deterministic_task_signals"]}
    for signal in ("map a printer", "printer mapping", "add a printer", "northwell printer mapping", "health & hospitals printer mapping"):
        assert signal in normalized_signals, f"field-workflow route missing printer signal: {signal}"
    assert "Tests/survey/test_printer_mapping_use_case_contracts.py" in field_route["validators"]
    assert any("organization/site" in item for item in field_route["guardrails"])
    assert any("Northwell" in item for item in field_route["guardrails"])

    manifest = load(MANIFEST)
    component_ids = {item["id"] for item in manifest["components"]}
    missing_components = REQUIRED_COMPONENT_IDS.difference(component_ids)
    assert not missing_components, f"operational manifest missing printer components: {sorted(missing_components)}"
    assert "python harness/validators/validate-printer-mapping-use-cases.py" in manifest["validation_commands"]

    validator_registry = load(VALIDATOR_REGISTRY)
    focused = next(item for item in validator_registry["validators"] if item["id"] == "printer-mapping-use-case-contracts")
    assert focused["blocking"] is True
    assert focused["command"] == "python harness/validators/validate-printer-mapping-use-cases.py"
    assert "harness/api/agent-routing-manifest.json" in focused["scope"]
    assert "harness/api/operational-harness-manifest.json" in focused["scope"]

    for hook in (PRE_COMMIT, PRE_PUSH):
        assert "validate-printer-mapping-use-cases.py" in read(hook), f"{hook.name} does not run printer use-case validator"

    ci_text = read(CI)
    for marker in (
        "printer-mapping-use-case-registry.json",
        "printer-mapping-use-case-registry.schema.json",
        "agent-routing-manifest.json",
        "operational-harness-manifest.json",
        "harness-validator-registry.json",
        "validate-printer-mapping-use-cases.py",
        "test_printer_mapping_use_case_contracts.py",
        "test_agent_routing_manifest_contracts.py",
        "test_operational_harness_completeness_contracts.py",
        "git diff --check",
    ):
        assert marker in ci_text, f"printer use-case CI missing: {marker}"

    tracked = (
        REGISTRY, SCHEMA, WORKFLOW, SKILL, MAP, REPORT, FIELD_SKILL, FRESH_AGENT,
        AGENT_ROUTING, MANIFEST, VALIDATOR_REGISTRY, PRE_COMMIT, PRE_PUSH, CI, TEST,
    )
    for path in tracked:
        assert_tracked(path)

    print(f"PASS: {len(use_cases)} printer-mapping use cases explicitly registered")
    print("PASS: exact site override > registered organization default > discovery block")
    print("PASS: Northwell proven behavior is isolated from Health & Hospitals discovery")
    print("PASS: generic printer requests reach field-workflow and compose the use-case gate")
    print("PASS: printer-mapping surfaces are registered centrally and enforced by hooks and CI")


if __name__ == "__main__":
    main()
