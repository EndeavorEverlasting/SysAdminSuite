#!/usr/bin/env python3
"""Contracts for deterministic workstation agent routing without prompt-owned product logic."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / ".claude/skills/developer-workstation/SKILL.md"
ROUTING = ROOT / "harness/api/developer-workstation-agent-routing.json"
SCHEMA = ROOT / "schemas/harness/developer-workstation-agent-routing.schema.json"
MANIFEST = ROOT / "harness/api/agent-capability-manifest.json"
HARNESS_API = ROOT / "harness/api/sas-harness-api.json"
CAPS = {
    "workstation-inventory", "workstation-planning", "workstation-managed-configuration",
    "workstation-backend-lifecycle", "workstation-session-lifecycle",
    "workstation-agent-domain-resolution", "agentswitchboard-invocation", "workstation-rollback",
}
PHRASES = {
    "set up WezTerm and tmux", "start my coding workspace", "why did my tmux session disappear?",
    "check my agents", "repair workstation", "stop persistent workspace", "use native Linux",
    "use PowerShell fallback",
}


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_routing_schema_and_surfaces() -> None:
    routing = load(ROUTING); schema = load(SCHEMA)
    assert routing["schema_version"] == "sas-developer-workstation-agent-routing/v1"
    assert routing["schema_path"] == schema["$id"]
    assert schema["additionalProperties"] is False
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.Draft202012Validator(schema).validate(routing)


def test_triggers_are_exact_and_unique() -> None:
    triggers = load(ROUTING)["triggers"]
    phrases = [item["phrase"] for item in triggers]
    assert set(phrases) == PHRASES and len(phrases) == len(set(phrases))
    assert {item["capability_id"] for item in triggers} <= CAPS


def test_terminal_context_and_fail_closed_guards() -> None:
    routing = load(ROUTING)
    assert routing["terminal_context_labels"] == ["Windows PowerShell", "WezTerm/tmux Bash", "file content: Lua"]
    guards = routing["guards"]
    assert guards["already_inside_tmux"] == "route-to-status-or-current-session"
    assert guards["lua_content"] == "route-to-managed-file-operation"
    assert all(guards[name] is False for name in ("default_mutation", "automatic_authentication", "inject_user_home_content", "mac_supported"))


def test_skill_routes_to_real_application_entrypoints() -> None:
    skill = read(SKILL)
    assert "scripts/Invoke-SasWindowsTmuxWorkspace.ps1" in skill
    assert "scripts/invoke-sas-linux-tmux-workspace.sh" in skill
    assert "Windows PowerShell" in skill and "WezTerm/tmux Bash" in skill and "file content: Lua" in skill
    assert "already inside tmux" in skill and "never start nested tmux" in skill
    assert "never paste Lua into PowerShell or Bash" in skill
    for product_detail in ("Start-Process", "sleep infinity", "tmux new-session", "WScript.Shell"):
        assert product_detail not in skill, f"prompt layer reimplements application detail: {product_detail}"


def test_manifest_registration_is_exact() -> None:
    manifest = load(MANIFEST)
    capabilities = {item["id"]: item for item in manifest["capabilities"]}
    skills = {item["id"]: item for item in manifest["skills"]}
    assert CAPS <= set(capabilities) and "developer-workstation" in skills
    linked = {Path(name).stem for name in re.findall(r"\(\.\./\.\./capabilities/([A-Za-z0-9._-]+\.md)\)", read(SKILL))}
    assert linked == set(skills["developer-workstation"]["capability_ids"])
    for cap_id in CAPS:
        assert (ROOT / capabilities[cap_id]["path"]).is_file()


def test_harness_api_is_read_only_router() -> None:
    operation = {item["id"]: item for item in load(HARNESS_API)["operations"]}["developer_workstation.agent_route"]
    assert operation["mode"] == "local_read"
    assert operation["network_activity"] is False and operation["target_mutation"] is False
    assert "No_prompt_only_application_logic" in operation["guardrails"]
    assert "Lua_routes_to_managed_file_operation" in operation["guardrails"]


def test_capabilities_are_atomic_and_owned_by_skill() -> None:
    for cap_id in CAPS:
        text = read(ROOT / f".claude/capabilities/{cap_id}.md")
        assert "## Contract" in text and "## Used by" in text
        assert ".claude/skills/developer-workstation/SKILL.md" in text
        assert len(text.splitlines()) <= 40


def test_discovery_and_validation_wiring() -> None:
    assert ".claude/skills/developer-workstation/SKILL.md" in read(ROOT / "AGENTS.md")
    assert "developer-workstation-agent-routing.json" in read(ROOT / "CODEBASE_MAP.md")
    assert "test_developer_workstation_agent_harness_contracts.py" in read(ROOT / ".github/workflows/agent-instruction-contracts.yml")
    assert "python3 Tests/survey/test_developer_workstation_agent_harness_contracts.py" in read(ROOT / "tests/survey/run_offline_survey_tests.sh")


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation agent-harness contract groups")
