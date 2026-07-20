#!/usr/bin/env python3
"""Contracts for the progressive-disclosure SysAdminSuite agent instruction architecture."""
from __future__ import annotations
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AGENTS = ROOT / "AGENTS.md"
CLAUDE = ROOT / "CLAUDE.md"
MANIFEST = ROOT / "harness/api/agent-capability-manifest.json"
CAPABILITY_ROOT = ROOT / ".claude/capabilities"
E2E_SKILL = ROOT / ".claude/skills/end-to-end-validation/SKILL.md"
WORKFLOW = ROOT / ".github/workflows/agent-instruction-contracts.yml"
FORBIDDEN_ROOT_DETAILS = {"naabu -list", "get-netadapter", "new-netipaddress", "ip addr", "journalctl"}
FORBIDDEN_CONTRADICTIONS = {"powershell is deprecated", "powershell is dead code", "legacy/reference tooling"}
E2E_ROUTED_DETAILS = {
    "end-to-end proof is the default merge and release target",
    "unit tests, parser checks, and narrow contracts are fast diagnostics",
    "green static contract",
    "mark e2e `not_applicable`",
    "run the applicable e2e journey through the real repo-owned entrypoint",
    "run broader regression checks only after",
    "do not claim merge or release readiness",
}
CAPABILITY_LINK = re.compile(r"\(\.\./\.\./capabilities/([A-Za-z0-9._-]+\.md)\)")


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def manifest() -> dict:
    return json.loads(read(MANIFEST))


def test_agents_is_compact_router() -> None:
    text = read(AGENTS)
    assert len(text.splitlines()) <= 120
    assert "## Skill router" in text and "Progressive disclosure is a repository requirement" in text
    assert ".claude/skills/end-to-end-validation/SKILL.md" in text
    lowered = text.lower()
    for detail in FORBIDDEN_ROOT_DETAILS | E2E_ROUTED_DETAILS:
        assert detail not in lowered, f"root instruction contains routed detail: {detail}"
    for skill in manifest()["skills"]:
        assert skill["path"] in text, f"AGENTS.md does not route to {skill['path']}"


def test_e2e_procedure_is_owned_by_project_skill() -> None:
    text = read(E2E_SKILL).lower()
    for detail in E2E_ROUTED_DETAILS:
        assert detail in text, f"E2E project skill is missing extracted instruction: {detail}"


def test_every_skill_composes_declared_capabilities() -> None:
    data = manifest()
    capability_ids = {item["id"] for item in data["capabilities"]}
    referenced: set[str] = set()
    for skill in data["skills"]:
        text = read(ROOT / skill["path"])
        assert "## Capability dependencies" in text
        linked = {Path(name).stem for name in CAPABILITY_LINK.findall(text)}
        assert linked == set(skill["capability_ids"]), f"dependency drift in {skill['id']}"
        referenced.update(linked)
    assert referenced == capability_ids, f"orphan capabilities: {sorted(capability_ids - referenced)}"


def test_capabilities_are_atomic_and_catalogued() -> None:
    catalog = read(CAPABILITY_ROOT / "README.md")
    for capability in manifest()["capabilities"]:
        path = ROOT / capability["path"]
        text = read(path)
        assert "## Contract" in text, f"capability missing contract section: {path.name}"
        assert "## Used by" in text, f"capability missing used-by section: {path.name}"
        assert path.name in catalog, f"capability missing from catalog: {path.name}"
        assert len(text.splitlines()) <= 80, f"capability is too broad and should be factored again: {path.name}"


def test_instruction_sources_do_not_reintroduce_language_conflict() -> None:
    data = manifest()
    paths = [AGENTS, CLAUDE]
    paths.extend(ROOT / item["path"] for item in data["skills"])
    paths.extend(ROOT / item["path"] for item in data["capabilities"])
    combined = "\n".join(read(path) for path in paths).lower()
    for phrase in FORBIDDEN_CONTRADICTIONS:
        assert phrase not in combined, f"contradictory PowerShell instruction remains: {phrase}"
    language = read(CAPABILITY_ROOT / "language-runtime-selection.md")
    assert "Bash-first on Windows" in language
    assert "PowerShell files are active production-relevant tooling" in language
    assert "Windows-native operations" in language


def test_claude_front_door_uses_progressive_disclosure() -> None:
    text = read(CLAUDE)
    assert "Do not preload" in text and ".claude/capabilities/README.md" in text
    assert "Load only the selected `SKILL.md` files" in text
    for skill in manifest()["skills"]:
        assert skill["path"] in text


def test_ci_runs_manifest_routing_and_handoff_contracts() -> None:
    text = read(WORKFLOW)
    assert "ubuntu-latest" in text and "windows-latest" in text
    for path in (
        "Tests/survey/test_agent_instruction_factoring_contracts.py",
        "Tests/survey/test_agent_capability_manifest_contracts.py",
        "Tests/survey/test_agent_routing_manifest_contracts.py",
        "Tests/survey/test_agent_sprint_capsule_contracts.py",
    ):
        assert f"python3 {path}" in text
    assert "tools\\validate-ai-layer.ps1" in text
    assert "SprintCapsule.Tests.ps1" in text


def main() -> None:
    tests = [
        test_agents_is_compact_router,
        test_e2e_procedure_is_owned_by_project_skill,
        test_every_skill_composes_declared_capabilities,
        test_capabilities_are_atomic_and_catalogued,
        test_instruction_sources_do_not_reintroduce_language_conflict,
        test_claude_front_door_uses_progressive_disclosure,
        test_ci_runs_manifest_routing_and_handoff_contracts,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} agent instruction factoring contracts")


if __name__ == "__main__":
    main()
