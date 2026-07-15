#!/usr/bin/env python3
"""Dependency-free contract tests for developer-workstation inventory schema and fixtures."""
from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "schemas/harness/developer-workstation-inventory.schema.json"
FIXTURES_DIR = ROOT / "Tests/Fixtures/workstation-inventory"
DOC = ROOT / "docs/DEVELOPER_WORKSTATION_PROVISIONING.md"
MAP = ROOT / "CODEBASE_MAP.md"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def import_hyphenated_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load module from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# Load the hyphenated Python summary renderer
RenderModule = import_hyphenated_module(
    "Render_SasWorkstationInventoryEnglish",
    ROOT / "scripts/Render-SasWorkstationInventoryEnglish.py"
)
render_inventory_summary = RenderModule.render_inventory_summary


def test_schema_is_fail_closed() -> None:
    schema = load(SCHEMA)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == "schemas/harness/developer-workstation-inventory.schema.json"
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {
        "schema_version",
        "generated_at",
        "detected_platform",
        "execution_environment",
        "checks",
        "selected_profile",
        "eligible_profiles",
        "proof_ceiling",
    }

    # Assert additionalProperties is false on definitions
    for def_name, def_val in schema["$defs"].items():
        assert def_val.get("additionalProperties") is False, f"def {def_name} should have additionalProperties: false"


def test_fixtures_validate_against_schema() -> None:
    try:
        import jsonschema
    except ImportError:
        return

    schema = load(SCHEMA)
    for p in FIXTURES_DIR.glob("*.fixture.json"):
        fixture = json.loads(p.read_text(encoding="utf-8"))
        if p.name == "malformed-output.fixture.json":
            # Malformed output should fail validation
            try:
                jsonschema.validate(fixture, schema)
            except jsonschema.ValidationError:
                pass
            else:
                raise AssertionError(f"Schema accepted malformed output fixture: {p.name}")
        else:
            # All other fixtures should pass
            try:
                jsonschema.validate(fixture, schema)
            except jsonschema.ValidationError as e:
                raise AssertionError(f"Schema failed to validate valid fixture {p.name}: {e}")


def test_english_renderer_on_fixtures() -> None:
    # Test rendering each valid fixture
    for p in FIXTURES_DIR.glob("*.fixture.json"):
        if p.name == "malformed-output.fixture.json":
            continue
        fixture = json.loads(p.read_text(encoding="utf-8"))
        summary = render_inventory_summary(fixture)
        assert "Developer Workstation Inventory" in summary
        assert f"Platform: {fixture['detected_platform']}" in summary
        assert f"Environment: {fixture['execution_environment']}" in summary
        assert f"Proof Ceiling: {fixture['proof_ceiling']}" in summary


def test_fixtures_have_no_personal_leakage() -> None:
    for p in FIXTURES_DIR.glob("*.fixture.json"):
        text = p.read_text(encoding="utf-8")
        assert "Cheex" not in text, f"fixture {p.name} contains developer username 'Cheex'"
        # Check that we don't have local path directories under Users other than generic
        assert not re.search(r"Users/(?!someuser)[A-Za-z0-9_-]+", text), f"fixture {p.name} contains personal Users/ path"


def test_inventory_is_discoverable() -> None:
    # Check that codebase map contains inventory files
    codebase_map = read(MAP)
    assert "developer-workstation-inventory.schema.json" in codebase_map
    assert "get-sas-developer-workstation-inventory.sh" in codebase_map
    assert "Get-SasDeveloperWorkstationInventory.ps1" in codebase_map

    # Check that tests/survey/run_offline_survey_tests.sh runs this test
    runner_script = read(RUNNER)
    assert "test_developer_workstation_inventory_contracts.py" in runner_script


def main() -> None:
    tests = [
        test_schema_is_fail_closed,
        test_fixtures_validate_against_schema,
        test_english_renderer_on_fixtures,
        test_fixtures_have_no_personal_leakage,
        test_inventory_is_discoverable,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation inventory contracts")


if __name__ == "__main__":
    main()
