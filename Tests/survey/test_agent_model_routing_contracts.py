#!/usr/bin/env python3
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
POLICY = ROOT / "Config" / "agent-model-routing-policy.sample.json"
SCRIPT = ROOT / "scripts" / "Invoke-SasAgentModelRoute.ps1"
DOC = ROOT / "docs" / "AGENT_MODEL_ROUTING.md"


def main() -> None:
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    assert policy["schema_version"] == "sas-agent-model-routing/v1"
    assert policy["authority"] == "AgentSwitchboard"
    assert policy["selection_order"] == ["opencode-limited-free", "free", "paid"]
    assert policy["allow_paid_fallback"] is True
    assert policy["guards"]["automatic_authentication"] is False
    assert policy["guards"]["automatic_post_mutation_fallback"] is False
    assert policy["guards"]["require_gnhf_compatibility_proof"] is True

    pricing = policy["deepseek_pricing"]
    assert pricing["mode"] == "flat"
    assert pricing["windows_utc"] == []
    assert pricing["official_source"] == "https://api-docs.deepseek.com/quick_start/pricing/"
    assert pricing["operator_override_required_for_time_windows"] is True

    script = SCRIPT.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    assert "Start-AutoRoutedGnhfSprint.ps1" in script
    assert "Target repository must be clean" in script
    assert "-ListRoutes" in script
    assert "AgentSwitchboard" in doc
    assert "OpenCode" in doc and "limited-time" in doc
    assert "DeepSeek" in doc and "flat" in doc.lower()

    combined = script + "\n" + doc + "\n" + POLICY.read_text(encoding="utf-8")
    forbidden = [r"sk-[A-Za-z0-9]", r"api[_-]?key\s*[:=]\s*['\"][^'\"]+", r"git\s+push", r"--push\b"]
    for pattern in forbidden:
        assert re.search(pattern, combined, flags=re.IGNORECASE) is None, pattern

    print("PASS: SysAdminSuite AgentSwitchboard model routing contracts")


if __name__ == "__main__":
    main()
