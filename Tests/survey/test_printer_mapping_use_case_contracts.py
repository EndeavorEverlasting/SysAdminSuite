#!/usr/bin/env python3
"""Focused contracts for printer-mapping organization/site use-case isolation."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/printer-mapping-use-case-registry.json"


def load() -> dict:
    return json.loads(REGISTRY.read_text(encoding="utf-8"))


def cases() -> dict[str, dict]:
    return {item["id"]: item for item in load()["use_cases"]}


def test_selection_policy_requires_explicit_context_and_no_cross_org_inheritance() -> None:
    policy = load()["selection_policy"]
    assert policy["context_fields"] == ["organization_id", "site_id"]
    assert policy["site_override_precedence"] is True
    assert policy["cross_organization_inheritance"] is False
    assert policy["implicit_site_inheritance"] is False
    assert policy["unknown_organization_action"] == "BLOCK_FOR_DISCOVERY"


def test_northwell_and_health_and_hospitals_are_distinct_use_cases() -> None:
    data = cases()
    northwell = data["northwell.shared-printer.organization-default"]
    h_and_h = data["health-and-hospitals.shared-printer.discovery"]
    assert northwell["organization_id"] != h_and_h["organization_id"]
    assert northwell["status"] == "proven"
    assert h_and_h["status"] == "discovery_required"


def test_northwell_assumptions_cannot_become_generic_fallback() -> None:
    northwell = cases()["northwell.shared-printer.organization-default"]
    assert northwell["product_launcher"] == "Map-NorthwellPrinter-SystemWide.cmd"
    assert northwell["assumptions"]["mapping_mechanism"] == "PrintUIEntry /ga"
    assert northwell["assumptions"]["mapping_scope"] == "system-wide/per-computer"
    policy = load()["selection_policy"]
    assert policy["unknown_organization_action"] == "BLOCK_FOR_DISCOVERY"
    assert policy["rule"].startswith("Printer mapping behavior is organization/site-specific")


def test_health_and_hospitals_advertises_no_fake_product_authority() -> None:
    h_and_h = cases()["health-and-hospitals.shared-printer.discovery"]
    for field in ("product_workflow", "product_launcher", "product_engine", "evidence_policy", "assumptions", "proof"):
        assert h_and_h[field] is None
    assert len(h_and_h["discovery_requirements"]) >= 8
    assert any("independently operated hospitals" in item for item in h_and_h["discovery_requirements"])


def test_focused_validator_passes() -> None:
    result = subprocess.run(
        [sys.executable, str(ROOT / "harness/validators/validate-printer-mapping-use-cases.py")],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "PASS: Northwell proven behavior is isolated from Health & Hospitals discovery" in result.stdout


def main() -> None:
    tests = [
        test_selection_policy_requires_explicit_context_and_no_cross_org_inheritance,
        test_northwell_and_health_and_hospitals_are_distinct_use_cases,
        test_northwell_assumptions_cannot_become_generic_fallback,
        test_health_and_hospitals_advertises_no_fake_product_authority,
        test_focused_validator_passes,
    ]
    for fn in tests:
        fn()
        print(f"PASS: {fn.__name__}")
    print(f"PASS: {len(tests)} printer-mapping use-case contract groups")


if __name__ == "__main__":
    main()
