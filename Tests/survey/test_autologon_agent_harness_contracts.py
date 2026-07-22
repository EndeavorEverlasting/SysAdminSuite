#!/usr/bin/env python3
"""Contracts for deterministic AutoLogon routing without prompt-owned application logic."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / ".claude/skills/autologon-deployment/SKILL.md"
CAPABILITY_MANIFEST = ROOT / "harness/api/agent-capability-manifest.json"
ROUTING_MANIFEST = ROOT / "harness/api/agent-routing-manifest.json"
WORKFLOW = ROOT / "harness/workflows/autologon-proof-contract-floor.yaml"
ADMIN_CAPABILITY = ROOT / ".claude/capabilities/autologon-deployment-orchestration.md"
RUNTIME_CAPABILITY = ROOT / ".claude/capabilities/autologon-runtime-proof.md"

PLAN_SIGNALS = {"plan AutoLogon", "AutoLogon deployment plan"}
ADMIN_SIGNALS = {"deploy AutoLogon", "AutoLogon as admin", "AutoLogon pilot"}
RUNTIME_SIGNALS = {"prove AutoLogon after reboot", "AutoLogon session access", "technician runtime proof"}
CAPABILITY_IDS = {"autologon-deployment-orchestration", "autologon-runtime-proof"}


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def by_id(items: list[dict]) -> dict[str, dict]:
    return {item["id"]: item for item in items}


def normalized(value: str) -> str:
    return " ".join(value.lower().split())


def exact_targets(request: str) -> set[str]:
    request_signal = normalized(request)
    return {
        item["target"]
        for item in load(ROUTING_MANIFEST)["triggers"]
        if request_signal in {normalized(signal) for signal in item["deterministic_task_signals"]}
    }


def test_activation_signals_and_manifest_contracts() -> None:
    routing = by_id(load(ROUTING_MANIFEST)["triggers"])
    plan = routing["autologon-plan-trigger"]
    admin = routing["autologon-admin-deployment-trigger"]
    runtime = routing["autologon-runtime-proof-trigger"]
    assert set(plan["deterministic_task_signals"]) == PLAN_SIGNALS
    assert set(admin["deterministic_task_signals"]) == ADMIN_SIGNALS
    assert set(runtime["deterministic_task_signals"]) == RUNTIME_SIGNALS
    assert (plan["target_type"], plan["target"]) == ("skill", "autologon-deployment")
    assert (admin["target_type"], admin["target"]) == ("capability", "autologon-deployment-orchestration")
    assert (runtime["target_type"], runtime["target"]) == ("capability", "autologon-runtime-proof")
    for trigger in (plan, admin, runtime):
        assert trigger["required_inputs"] and trigger["outputs"] and trigger["preconditions"]
        assert trigger["guardrails"] and trigger["validators"] and trigger["owner"] and trigger["proof_ceiling"]
    assert admin["priority"] == runtime["priority"] > plan["priority"]


def test_exact_routes_separate_admin_and_runtime_authority() -> None:
    for signal in PLAN_SIGNALS:
        assert exact_targets(signal) == {"autologon-deployment"}
    for signal in ADMIN_SIGNALS:
        assert exact_targets(signal) == {"autologon-deployment-orchestration"}
    for signal in RUNTIME_SIGNALS:
        assert exact_targets(signal) == {"autologon-runtime-proof"}
    assert exact_targets("technician runtime proof") != {"autologon-deployment-orchestration"}
    assert exact_targets("deploy AutoLogon") != {"autologon-runtime-proof"}


def test_collision_ambiguity_and_negative_routing_fail_closed() -> None:
    routing = load(ROUTING_MANIFEST)
    triggers = by_id(routing["triggers"])
    admin = triggers["autologon-admin-deployment-trigger"]
    runtime = triggers["autologon-runtime-proof-trigger"]
    ambiguous = "deploy AutoLogon and prove AutoLogon after reboot"
    matching = [
        item for item in (admin, runtime)
        if any(normalized(signal) in normalized(ambiguous) for signal in item["deterministic_task_signals"])
    ]
    assert {item["target"] for item in matching} == CAPABILITY_IDS
    assert len({item["priority"] for item in matching}) == 1
    assert routing["ambiguity_rules"]["equal_priority_conflict_resolution"] == "fail_closed_to_repository_sprint"
    for negative in (
        "install an ordinary package in the disposable VM",
        "collect an AutoLogon password",
        "run AutoLogon through WinRM",
        "prove package acceptance",
    ):
        assert not (exact_targets(negative) & {"autologon-deployment", *CAPABILITY_IDS})
    package_vm = triggers["package-vm-qualification-trigger"]
    assert "AutoLogon excluded" in package_vm["guardrails"]
    assert all("autologon" not in normalized(signal) for signal in package_vm["deterministic_task_signals"])


def test_skill_routes_to_product_entrypoints_without_reimplementation() -> None:
    skill = read(SKILL)
    for path in (
        "scripts/Invoke-SasAutoLogonDeployment.ps1",
        "scripts/Invoke-SasAutoLogonSessionAccessProof.ps1",
        "scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1",
        "harness/workflows/autologon-proof-contract-floor.yaml",
    ):
        assert path in skill
    assert "Never route runtime proof through admin deployment" in skill
    assert "admin deployment result is never post-reboot runtime proof" in skill
    for implementation_detail in ("New-ScheduledTaskAction", "Register-ScheduledTask", "DefaultPassword =", "Start-Process"):
        assert implementation_detail not in skill, f"skill reimplements product behavior: {implementation_detail}"


def test_capabilities_are_atomic_registered_and_owned() -> None:
    manifest = load(CAPABILITY_MANIFEST)
    capabilities = by_id(manifest["capabilities"])
    skills = by_id(manifest["skills"])
    assert CAPABILITY_IDS <= set(capabilities)
    skill = skills["autologon-deployment"]
    assert CAPABILITY_IDS <= set(skill["capability_ids"])
    linked = {
        Path(name).stem
        for name in re.findall(r"\(\.\./\.\./capabilities/([A-Za-z0-9._-]+\.md)\)", read(SKILL))
    }
    assert linked == set(skill["capability_ids"])
    for cap_id, path in (
        ("autologon-deployment-orchestration", ADMIN_CAPABILITY),
        ("autologon-runtime-proof", RUNTIME_CAPABILITY),
    ):
        text = read(path)
        assert capabilities[cap_id]["default_network_activity"] is False
        assert capabilities[cap_id]["default_target_mutation"] is False
        assert "## Contract" in text and "## Used by" in text
        assert ".claude/skills/autologon-deployment/SKILL.md" in text


def test_frozen_operations_and_proof_separation_remain_visible() -> None:
    workflow = read(WORKFLOW)
    for operation in (
        "autologon.plan", "autologon.admin_deploy", "autologon.state_proof",
        "autologon.session_access_proof", "autologon.technician_runtime_proof",
        "autologon.proof_receipt_ingest",
    ):
        assert f"id: {operation}" in workflow
    admin = read(ADMIN_CAPABILITY)
    runtime = read(RUNTIME_CAPABILITY)
    assert "canonical Kerberos/SMB scheduled-task" in admin
    assert "does not prove reboot" in admin
    assert "actual signed-in AutoLogon session" in runtime
    assert "does not initiate either action" in runtime
    assert "Fixture results remain contract-only" in runtime


def test_discovery_and_validation_wiring() -> None:
    assert ".claude/skills/autologon-deployment/SKILL.md" in read(ROOT / "AGENTS.md")
    assert ".claude/skills/autologon-deployment/SKILL.md" in read(ROOT / "CLAUDE.md")
    assert "test_autologon_agent_harness_contracts.py" in read(ROOT / "CODEBASE_MAP.md")
    assert "python3 Tests/survey/test_autologon_agent_harness_contracts.py" in read(ROOT / "tests/survey/run_offline_survey_tests.sh")
    assert "test_autologon_agent_harness_contracts.py" in read(ROOT / ".github/workflows/agent-instruction-contracts.yml")


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon agent-harness contract groups")
