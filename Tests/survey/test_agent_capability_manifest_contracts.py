#!/usr/bin/env python3
"""Executable contracts for the machine-readable SysAdminSuite agent capability manifest."""
from __future__ import annotations
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "harness/api/agent-capability-manifest.json"
SCHEMA = ROOT / "schemas/harness/agent-capability-manifest.schema.json"
AGENTS = ROOT / "AGENTS.md"
CLAUDE = ROOT / "CLAUDE.md"
CAPABILITY_CATALOG = ROOT / ".claude/capabilities/README.md"
AI_LAYER_DOC = ROOT / "docs/AI_LAYER.md"
CODEBASE_MAP = ROOT / "CODEBASE_MAP.md"
WORKFLOW = ROOT / ".github/workflows/agent-instruction-contracts.yml"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
HARNESS_API = ROOT / "harness/api/sas-harness-api.json"
ID_PATTERN = re.compile(r"^[a-z][a-z0-9-]*$")
VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
CAPABILITY_LINK = re.compile(r"\(\.\./\.\./capabilities/([A-Za-z0-9._-]+\.md)\)")
SKILL_LINK = re.compile(r"\.claude/skills/([a-z][a-z0-9-]*)/SKILL\.md")


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load_json(path: Path):
    return json.loads(read(path))


def repo_path(value: str) -> Path:
    assert value and not value.startswith("/"), f"path must be repository-relative: {value!r}"
    assert not re.match(r"^[A-Za-z]:[\\/]", value), f"absolute Windows path is forbidden: {value}"
    assert ".." not in Path(value).parts, f"parent traversal is forbidden: {value}"
    return ROOT / value


def item_ids(items, kind: str) -> set[str]:
    ids = [item["id"] for item in items]
    assert len(ids) == len(set(ids)), f"duplicate {kind} IDs: {ids}"
    assert all(ID_PATTERN.fullmatch(item_id) for item_id in ids), f"invalid {kind} ID"
    return set(ids)


def assert_common(item: dict) -> None:
    assert 20 <= len(item["summary"]) <= 240
    assert item["lanes"] and len(item["lanes"]) == len(set(item["lanes"]))
    assert all(ID_PATTERN.fullmatch(lane) for lane in item["lanes"])
    assert item["default_network_activity"] is False
    assert item["default_target_mutation"] is False
    assert item["network_activity_mode"] in {"none", "control-plane", "gated-target"}
    assert item["target_mutation_mode"] in {"none", "repository", "gated-target"}
    assert repo_path(item["path"]).is_file(), f"missing declared item path: {item['path']}"
    for field in ("authority_paths", "validators"):
        values = item[field]
        assert values and len(values) == len(set(values)), f"{item['id']} has invalid {field}"
        for value in values:
            assert repo_path(value).exists(), f"{item['id']} references missing {field}: {value}"


def test_manifest_and_schema_define_fail_closed_contract() -> None:
    manifest, schema = load_json(MANIFEST), load_json(SCHEMA)
    assert manifest["schema_version"] == "sas-agent-capability-manifest/v1"
    assert manifest["schema_path"] == "schemas/harness/agent-capability-manifest.schema.json"
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == manifest["schema_path"]
    assert schema["additionalProperties"] is False
    assert manifest["posture"] == {
        "progressive_disclosure_required": True,
        "end_to_end_default_required": True,
        "unit_tests_sufficient_for_merge": False,
        "default_network_activity": False,
        "default_target_mutation": False,
        "tracked_runtime_evidence_allowed": False,
    }
    for value in manifest["authority"].values():
        assert repo_path(value).exists(), f"manifest authority path missing: {value}"


def test_manifest_covers_every_repo_skill_and_capability() -> None:
    manifest = load_json(MANIFEST)
    manifest_skills = item_ids(manifest["skills"], "skill")
    manifest_caps = item_ids(manifest["capabilities"], "capability")
    disk_skills = {path.parent.name for path in (ROOT / ".claude/skills").glob("*/SKILL.md")}
    disk_caps = {path.stem for path in (ROOT / ".claude/capabilities").glob("*.md") if path.name != "README.md"}
    assert manifest_skills == disk_skills, f"skill manifest drift: manifest={sorted(manifest_skills)} disk={sorted(disk_skills)}"
    assert manifest_caps == disk_caps, f"capability manifest drift: manifest={sorted(manifest_caps)} disk={sorted(disk_caps)}"


def test_capability_entries_are_complete_and_atomic() -> None:
    for cap in load_json(MANIFEST)["capabilities"]:
        assert VERSION_PATTERN.fullmatch(cap["version"])
        assert cap["path"] == f'.claude/capabilities/{cap["id"]}.md'
        assert_common(cap)


def test_skill_dependencies_match_markdown_exactly() -> None:
    manifest = load_json(MANIFEST)
    capabilities = {item["id"] for item in manifest["capabilities"]}
    referenced: set[str] = set()
    for skill in manifest["skills"]:
        assert skill["path"] == f'.claude/skills/{skill["id"]}/SKILL.md'
        assert_common(skill)
        ids = skill["capability_ids"]
        assert ids and len(ids) == len(set(ids)) and set(ids) <= capabilities
        linked = {Path(filename).stem for filename in CAPABILITY_LINK.findall(read(repo_path(skill["path"])))}
        assert linked == set(ids), f'{skill["id"]} manifest dependencies differ from Markdown: manifest={ids}, markdown={sorted(linked)}'
        referenced.update(ids)
    assert referenced == capabilities, f"orphan capabilities: {sorted(capabilities - referenced)}"


def test_human_routers_and_validators_cover_manifest() -> None:
    manifest = load_json(MANIFEST)
    agent_routes = set(SKILL_LINK.findall(read(AGENTS)))
    claude_routes = set(SKILL_LINK.findall(read(CLAUDE)))
    skill_ids = {item["id"] for item in manifest["skills"]}
    assert agent_routes == skill_ids, f"AGENTS router drift: {sorted(agent_routes ^ skill_ids)}"
    assert claude_routes == skill_ids, f"CLAUDE router drift: {sorted(claude_routes ^ skill_ids)}"
    for path in (CAPABILITY_CATALOG, AI_LAYER_DOC, CODEBASE_MAP):
        assert "harness/api/agent-capability-manifest.json" in read(path)
    assert "Tests/survey/test_agent_capability_manifest_contracts.py" in read(WORKFLOW)
    assert "python3 Tests/survey/test_agent_capability_manifest_contracts.py" in read(RUNNER)
    operation = {item["id"]: item for item in load_json(HARNESS_API)["operations"]}["agent_capability.catalog.read"]
    assert operation["mode"] == "local_read" and operation["network_activity"] is False and operation["target_mutation"] is False
    assert "No_second_run_context" in operation["guardrails"]


def test_schema_validation_when_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load_json(MANIFEST), load_json(SCHEMA))


def main() -> None:
    tests = [test_manifest_and_schema_define_fail_closed_contract, test_manifest_covers_every_repo_skill_and_capability, test_capability_entries_are_complete_and_atomic, test_skill_dependencies_match_markdown_exactly, test_human_routers_and_validators_cover_manifest, test_schema_validation_when_available]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} agent capability manifest contracts")


if __name__ == "__main__":
    main()
