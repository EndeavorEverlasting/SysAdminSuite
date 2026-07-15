#!/usr/bin/env python3
"""Contracts for read-only execution-domain workstation inventory."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "schemas/harness/developer-workstation-inventory.schema.json"
LIFECYCLE_SCHEMA = ROOT / "schemas/harness/developer-workstation-lifecycle-result.schema.json"
FIXTURES = ROOT / "Tests/Fixtures/workstation-inventory"
PS = ROOT / "scripts/Get-SasDeveloperWorkstationInventory.ps1"
BASH = ROOT / "scripts/get-sas-developer-workstation-inventory.sh"
RENDERER = ROOT / "scripts/Render-SasWorkstationInventoryEnglish.py"
DOC = ROOT / "docs/DEVELOPER_WORKSTATION_INVENTORY.md"
WORKFLOW = ROOT / ".github/workflows/developer-workstation-inventory.yml"

SCENARIOS = {
    "no-wsl", "docker-only-wsl", "wsl-stops", "keepalive-healthy", "keepalive-stale",
    "tmux-session-healthy", "windows-bridge-only", "wsl-native-agent", "invalid-font", "cli-gui-mismatch",
}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def validate_shape(data: dict) -> None:
    assert data["schema_version"] == "sas-developer-workstation-inventory/v2"
    assert data["host_platform"] in {"windows", "linux", "unsupported"}
    assert data["detected_context"] in {"windows-native", "windows-wsl", "linux-native", "unknown"}
    assert {item["id"] for item in data["domains"]} <= {"windows-native", "windows-wsl", "linux-native"}
    for domain in data["domains"]:
        assert len(domain["agents"]) == 3
        assert {agent["agent_id"] for agent in domain["agents"]} == {"opencode", "agy", "goose"}
        for agent in domain["agents"]:
            assert agent["interactive_smoke"] == {"attempted": False, "status": "not-attempted"}
            if agent["resolution_kind"] in {"alias", "function"}:
                assert agent["command_path_class"] == "alias-only"
    assert data["proof_ceiling"].startswith("Read-only inventory proves detected state only")
    assert not re.search(r"Cheex|[A-Za-z]:\\\\Users|/home/[^<]", json.dumps(data))


def validate_jsonschema(data: dict, schema_path: Path) -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(data, load(schema_path))


def test_schema_models_domains_terminal_service_and_agents() -> None:
    schema = load(SCHEMA)
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"].endswith("/v2")
    assert set(schema["$defs"]["domain"]["properties"]["id"]["enum"]) == {
        "windows-native", "windows-wsl", "linux-native"
    }
    assert set(schema["$defs"]["agent"]["properties"]["resolution_kind"]["enum"]) == {
        "executable", "wrapper", "function", "alias", "missing"
    }
    required = set(schema["properties"]["workspace_service"]["required"])
    assert required == {"keepalive", "pid_file", "shortcut", "start_script", "stop_script"}
    assert "wezterm_cli" in schema["properties"]["terminal"]["required"]
    assert "wezterm_gui" in schema["properties"]["terminal"]["required"]


def test_scenario_fixtures_cover_required_failures() -> None:
    files = sorted(FIXTURES.glob("*.fixture.json"))
    assert {path.name.removesuffix(".fixture.json") for path in files} == SCENARIOS
    for path in files:
        fixture = load(path)
        assert fixture["schema_version"] == "sas-workstation-inventory-fixture/v2"
        assert fixture["scenario"] in SCENARIOS
        assert "Cheex" not in path.read_text(encoding="utf-8")


def test_bash_fixture_collector_emits_typed_inventory_and_lifecycle() -> None:
    if not shutil.which("bash"):
        return
    for scenario in sorted(SCENARIOS):
        if os.name == "nt":
            completed = subprocess.run(
                ["bash", "scripts/get-sas-developer-workstation-inventory.sh", "--fixture", scenario],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )
            inventory = json.loads(completed.stdout)
            validate_shape(inventory); validate_jsonschema(inventory, SCHEMA)
            continue
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "inventory.json"; lifecycle_path = Path(temp) / "lifecycle.json"
            subprocess.run(["bash", str(BASH), "--fixture", scenario, "--output", str(output), "--lifecycle-output", str(lifecycle_path)], cwd=ROOT, check=True, capture_output=True, text=True)
            inventory, lifecycle = load(output), load(lifecycle_path)
        validate_shape(inventory); validate_jsonschema(inventory, SCHEMA); validate_jsonschema(lifecycle, LIFECYCLE_SCHEMA)
        assert lifecycle["operation"] == "inventory"
        assert all(value is False for value in lifecycle["proof"].values())


def test_powershell_fixture_collector_when_available() -> None:
    pwsh = shutil.which("pwsh") or shutil.which("powershell")
    if not pwsh:
        return
    for scenario in sorted(SCENARIOS):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "inventory.json"; lifecycle = Path(temp) / "lifecycle.json"
            subprocess.run([pwsh, "-NoProfile", "-File", str(PS), "-Fixture", scenario, "-OutputPath", str(output), "-LifecycleOutputPath", str(lifecycle)], cwd=ROOT, check=True, capture_output=True, text=True)
            inventory, result = load(output), load(lifecycle)
        validate_shape(inventory); validate_jsonschema(inventory, SCHEMA); validate_jsonschema(result, LIFECYCLE_SCHEMA)


def test_collectors_are_read_only_and_do_not_authenticate() -> None:
    text = PS.read_text(encoding="utf-8") + BASH.read_text(encoding="utf-8")
    forbidden = ["Start-Process", "wsl --install", "wsl --shutdown", "--unregister", "apt install", "sudo ", "oauth", "login --"]
    for fragment in forbidden:
        assert fragment not in text
    assert "interactive_smoke" in text and "not-attempted" in text
    assert "docker-desktop" in text
    assert "wezterm-gui" in text
    assert "alias-only" in text


def test_docs_renderer_workflow_and_runner_are_wired() -> None:
    for path in (RENDERER, DOC, WORKFLOW):
        assert path.is_file()
    docs = DOC.read_text(encoding="utf-8")
    for phrase in ("windows-native", "windows-wsl", "linux-native", "read-only", "persistence"):
        assert phrase in docs
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "test_developer_workstation_inventory_contracts.py" in workflow
    runner = (ROOT / "tests/survey/run_offline_survey_tests.sh").read_text(encoding="utf-8")
    assert "python3 Tests/survey/test_developer_workstation_inventory_contracts.py" in runner


def main() -> None:
    tests = [
        test_schema_models_domains_terminal_service_and_agents,
        test_scenario_fixtures_cover_required_failures,
        test_bash_fixture_collector_emits_typed_inventory_and_lifecycle,
        test_powershell_fixture_collector_when_available,
        test_collectors_are_read_only_and_do_not_authenticate,
        test_docs_renderer_workflow_and_runner_are_wired,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} execution-domain inventory contracts across {len(SCENARIOS)} scenarios")


if __name__ == "__main__":
    main()
