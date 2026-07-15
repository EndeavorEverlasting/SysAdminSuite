#!/usr/bin/env python3
"""Dependency-free contracts for the developer-workstation inventory."""
from __future__ import annotations

import copy
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "schemas/harness/developer-workstation-inventory.schema.json"
PROFILE_SCHEMA = ROOT / "schemas/harness/developer-workstation-profile.schema.json"
PROFILE_SAMPLE = ROOT / "Config/developer-workstation-profile.sample.json"
DOC = ROOT / "docs/DEVELOPER_WORKSTATION_INVENTORY.md"
MAP = ROOT / "CODEBASE_MAP.md"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
RENDERER = ROOT / "scripts/Render-SasWorkstationInventoryEnglish.py"
WIN_SCRIPT = ROOT / "scripts/Get-SasDeveloperWorkstationInventory.ps1"
LINUX_SCRIPT = ROOT / "scripts/get-sas-developer-workstation-inventory.sh"
FIXTURE_DIR = ROOT / "Tests/Fixtures/workstation-inventory"

FIXTURES = {
    "windows-native": FIXTURE_DIR / "windows-native.fixture.json",
    "linux-native": FIXTURE_DIR / "linux-native.fixture.json",
    "wsl": FIXTURE_DIR / "wsl.fixture.json",
    "missing-tools": FIXTURE_DIR / "missing-tools.fixture.json",
    "malformed-output": FIXTURE_DIR / "malformed-output.fixture.json",
    "unsupported-platform": FIXTURE_DIR / "unsupported-platform.fixture.json",
}


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def _import_renderer():
    spec = importlib.util.spec_from_file_location("renderer", str(RENDERER))
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def validate_status(value: str) -> None:
    assert value in ("PASS", "SKIP", "FAIL"), f"invalid status: {value}"


def validate_inventory_shape(inventory: dict) -> None:
    assert isinstance(inventory, dict), "inventory must be an object"
    for field in [
        "schema_version", "generated_at", "detected_platform",
        "execution_environment", "checks", "selected_profile",
        "eligible_profiles", "proof_ceiling",
    ]:
        assert field in inventory, f"missing required field: {field}"

    assert inventory["schema_version"] == "sas-developer-workstation-inventory/v1"
    assert inventory["detected_platform"] in ("windows", "linux", "unsupported")
    assert inventory["execution_environment"] in ("native", "wsl", "unknown")

    checks = inventory["checks"]
    for ck in ["wezterm", "shell", "multiplexer", "repository", "agent_commands", "agent_switchboard"]:
        assert ck in checks, f"missing required check: {ck}"

    for tk in ["wezterm", "shell", "multiplexer", "agent_switchboard"]:
        tool = checks[tk]
        validate_status(tool["status"])
        assert "reason" in tool and len(tool["reason"]) > 0

    repo = checks["repository"]
    validate_status(repo["status"])
    if repo.get("relative_path") is not None:
        rp = repo["relative_path"]
        assert not rp.startswith("/"), "relative_path must not be absolute"
        assert not re.match(r"^[A-Za-z]:", rp), "relative_path must not contain drive letter"
        assert "Users/" not in rp
        assert "home/" not in rp

    agents = checks["agent_commands"]
    assert isinstance(agents, list)
    ids = [a["agent_id"] for a in agents]
    assert len(ids) == len(set(ids)), f"duplicate agent_ids: {ids}"
    for agent in agents:
        validate_status(agent["status"])

    if "wsl" in checks:
        validate_status(checks["wsl"]["status"])

    if inventory["selected_profile"] is not None:
        assert inventory["selected_profile"] in inventory["eligible_profiles"]

    assert isinstance(inventory["proof_ceiling"], str) and len(inventory["proof_ceiling"]) > 0


# --- Contract tests ---

def test_schema_exists_and_is_fail_closed() -> None:
    schema = load(SCHEMA)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == "schemas/harness/developer-workstation-inventory.schema.json"
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {
        "schema_version", "generated_at", "detected_platform",
        "execution_environment", "checks", "selected_profile",
        "eligible_profiles", "proof_ceiling",
    }


def test_schema_version_is_v1_const() -> None:
    schema = load(SCHEMA)
    assert schema["properties"]["schema_version"]["const"] == "sas-developer-workstation-inventory/v1"


def test_platform_is_bimodal_with_unsupported_fallback() -> None:
    schema = load(SCHEMA)
    platforms = set(schema["properties"]["detected_platform"]["enum"])
    assert platforms == {"windows", "linux", "unsupported"}


def test_all_valid_fixtures_pass_schema_validation() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    schema = load(SCHEMA)
    for name, path in FIXTURES.items():
        if name == "malformed-output":
            continue
        fixture = load(path)
        try:
            jsonschema.validate(fixture, schema)
        except jsonschema.ValidationError as e:
            raise AssertionError(f"fixture '{name}' failed: {e.message}")


def test_malformed_fixture_rejected_by_schema() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    schema = load(SCHEMA)
    fixture = load(FIXTURES["malformed-output"])
    try:
        jsonschema.validate(fixture, schema)
    except jsonschema.ValidationError:
        pass
    else:
        raise AssertionError("malformed-output fixture was not rejected by schema")


def test_windows_native_fixture() -> None:
    inv = load(FIXTURES["windows-native"])
    validate_inventory_shape(inv)
    assert inv["detected_platform"] == "windows"
    assert inv["execution_environment"] == "native"
    assert inv["checks"]["multiplexer"]["status"] == "SKIP"
    assert inv["selected_profile"] == "windows-native"
    assert inv["checks"]["wsl"]["status"] == "PASS"


def test_linux_native_fixture() -> None:
    inv = load(FIXTURES["linux-native"])
    validate_inventory_shape(inv)
    assert inv["detected_platform"] == "linux"
    assert inv["checks"]["multiplexer"]["status"] == "PASS"
    assert inv["selected_profile"] == "linux-native"
    assert inv["checks"]["wsl"]["status"] == "SKIP"


def test_wsl_fixture() -> None:
    inv = load(FIXTURES["wsl"])
    validate_inventory_shape(inv)
    assert inv["execution_environment"] == "wsl"
    assert inv["selected_profile"] == "wsl-tmux"


def test_missing_tools_fixture() -> None:
    inv = load(FIXTURES["missing-tools"])
    validate_inventory_shape(inv)
    assert inv["selected_profile"] is None
    assert inv["eligible_profiles"] == []
    assert inv["checks"]["wezterm"]["status"] == "FAIL"
    assert inv["checks"]["shell"]["status"] == "FAIL"


def test_unsupported_platform_fixture() -> None:
    inv = load(FIXTURES["unsupported-platform"])
    validate_inventory_shape(inv)
    assert inv["detected_platform"] == "unsupported"
    assert inv["selected_profile"] is None
    for tk in ["wezterm", "shell", "multiplexer"]:
        assert inv["checks"][tk]["status"] == "SKIP"


def test_all_fixtures_have_proof_ceiling() -> None:
    for name, path in FIXTURES.items():
        if name == "malformed-output":
            continue
        inv = load(path)
        assert "Presence is not successful launch" in inv["proof_ceiling"]


def test_no_fixture_contains_machine_local_paths() -> None:
    forbidden = [r"Cheex", r"token", r"secret", r"password", r"api_key", r"credential"]
    for name, path in FIXTURES.items():
        if name == "malformed-output":
            continue
        text = read(path)
        for pat in forbidden:
            assert not re.search(pat, text, re.IGNORECASE), f"fixture '{name}' contains: {pat}"


def test_english_renderer_produces_output_for_all_fixtures() -> None:
    mod = _import_renderer()
    for name, path in FIXTURES.items():
        if name == "malformed-output":
            continue
        inv = load(path)
        output = mod.render_inventory_summary(inv)
        assert "Developer Workstation Inventory" in output
        assert "Platform:" in output
        assert "Proof Ceiling:" in output


def test_english_renderer_shows_agent_commands() -> None:
    mod = _import_renderer()
    inv = load(FIXTURES["windows-native"])
    output = mod.render_inventory_summary(inv)
    assert "Agent Commands:" in output
    assert "[PASS] opencode:" in output
    assert "[FAIL] agy:" in output
    assert "[PASS] goose:" in output


def test_collector_scripts_exist() -> None:
    assert WIN_SCRIPT.is_file()
    assert LINUX_SCRIPT.is_file()


def test_windows_collector_has_fixture_mode() -> None:
    text = read(WIN_SCRIPT)
    assert "FixtureMode" in text
    assert "sas-developer-workstation-inventory/v1" in text
    assert "Get-EnglishSummary" in text


def test_linux_collector_has_fixture_mode() -> None:
    text = read(LINUX_SCRIPT)
    assert "FIXTURE_MODE" in text
    assert "sas-developer-workstation-inventory/v1" in text


def test_windows_collector_is_read_only() -> None:
    text = read(WIN_SCRIPT)
    for cmd in ["Install-Module", "winget install", "choco install", "Set-Content", "Remove-Item", "New-Service"]:
        assert cmd not in text, f"Windows collector contains mutation: {cmd}"


def test_linux_collector_is_read_only() -> None:
    text = read(LINUX_SCRIPT)
    for cmd in ["apt install", "apt-get install", "yum install", "pip install", "sudo rm", "rm -rf"]:
        assert cmd not in text, f"Linux collector contains mutation: {cmd}"


def test_profile_schema_execution_profiles_compatible() -> None:
    ps = load(PROFILE_SCHEMA)
    ep = ps["$defs"]["executionProfile"]
    assert "platform" in ep["properties"]
    assert "environment" in ep["properties"]
    assert "shell" in ep["properties"]
    assert "multiplexer" in ep["properties"]


def test_inventory_platform_covers_profile_platforms() -> None:
    ps = load(PROFILE_SCHEMA)
    is_ = load(SCHEMA)
    profile_platforms = set(ps["$defs"]["executionProfile"]["properties"]["platform"]["enum"])
    inv_platforms = set(is_["properties"]["detected_platform"]["enum"])
    assert profile_platforms.issubset(inv_platforms)


def test_doc_references_schema_and_scripts() -> None:
    assert DOC.is_file()
    doc = read(DOC)
    assert "developer-workstation-inventory.schema.json" in doc
    assert "Get-SasDeveloperWorkstationInventory" in doc
    assert "get-sas-developer-workstation-inventory" in doc
    assert "Render-SasWorkstationInventoryEnglish" in doc


def test_codebase_map_references_inventory_files() -> None:
    map_text = read(MAP)
    assert "DEVELOPER_WORKSTATION_INVENTORY" in map_text
    assert "developer-workstation-inventory" in map_text


def test_offline_runner_registers_inventory_test() -> None:
    runner = read(RUNNER)
    assert "test_developer_workstation_inventory_contracts.py" in runner


def test_negative_selected_profile_always_eligible() -> None:
    for name, path in FIXTURES.items():
        if name == "malformed-output":
            continue
        inv = load(path)
        if inv["selected_profile"] is not None:
            assert inv["selected_profile"] in inv["eligible_profiles"]


def test_negative_all_statuses_valid() -> None:
    for name, path in FIXTURES.items():
        if name == "malformed-output":
            continue
        inv = load(path)
        for tk in ["wezterm", "shell", "multiplexer", "agent_switchboard"]:
            validate_status(inv["checks"][tk]["status"])
        validate_status(inv["checks"]["repository"]["status"])
        for agent in inv["checks"]["agent_commands"]:
            validate_status(agent["status"])


def test_negative_supported_fixtures_have_supported_platform() -> None:
    for name, path in FIXTURES.items():
        if name in ("malformed-output", "unsupported-platform"):
            continue
        inv = load(path)
        assert inv["detected_platform"] in ("windows", "linux")


def main() -> None:
    tests = [
        test_schema_exists_and_is_fail_closed,
        test_schema_version_is_v1_const,
        test_platform_is_bimodal_with_unsupported_fallback,
        test_all_valid_fixtures_pass_schema_validation,
        test_malformed_fixture_rejected_by_schema,
        test_windows_native_fixture,
        test_linux_native_fixture,
        test_wsl_fixture,
        test_missing_tools_fixture,
        test_unsupported_platform_fixture,
        test_all_fixtures_have_proof_ceiling,
        test_no_fixture_contains_machine_local_paths,
        test_english_renderer_produces_output_for_all_fixtures,
        test_english_renderer_shows_agent_commands,
        test_collector_scripts_exist,
        test_windows_collector_has_fixture_mode,
        test_linux_collector_has_fixture_mode,
        test_windows_collector_is_read_only,
        test_linux_collector_is_read_only,
        test_profile_schema_execution_profiles_compatible,
        test_inventory_platform_covers_profile_platforms,
        test_doc_references_schema_and_scripts,
        test_codebase_map_references_inventory_files,
        test_offline_runner_registers_inventory_test,
        test_negative_selected_profile_always_eligible,
        test_negative_all_statuses_valid,
        test_negative_supported_fixtures_have_supported_platform,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation inventory contracts")


if __name__ == "__main__":
    main()
