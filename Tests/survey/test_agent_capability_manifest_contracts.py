#!/usr/bin/env python3
"""Contracts for the machine-readable SysAdminSuite agent capability manifest."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "harness" / "api" / "agent-capability-manifest.json"
SCHEMA = ROOT / "schemas" / "harness" / "agent-capability-manifest.schema.json"
CAPABILITY_CATALOG = ROOT / ".claude" / "capabilities" / "README.md"
AI_LAYER_DOC = ROOT / "docs" / "AI_LAYER.md"
CODEBASE_MAP = ROOT / "CODEBASE_MAP.md"
WORKFLOW = ROOT / ".github" / "workflows" / "agent-instruction-contracts.yml"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"
HARNESS_API = ROOT / "harness" / "api" / "sas-harness-api.json"

REQUIRED_CAPABILITY_IDS = {
    "repository-evidence",
    "proof-and-checkpointing",
    "language-runtime-selection",
    "mutation-and-evidence-boundaries",
    "field-command-design",
}
REQUIRED_SKILL_IDS = {
    "repository-sprint",
    "language-runtime",
    "field-workflow",
    "scoped-validation",
    "live-data-guard",
    "survey-low-noise",
}
ID_PATTERN = re.compile(r"^[a-z][a-z0-9-]*$")
VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
CAPABILITY_LINK = re.compile(r"\(\.\./\.\./capabilities/([A-Za-z0-9._-]+\.md)\)")


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def repo_path(value: str) -> Path:
    assert value and not value.startswith("/"), f"path must be repository-relative: {value!r}"
    assert not re.match(r"^[A-Za-z]:[\\/]", value), f"absolute Windows path is forbidden: {value}"
    parts = Path(value).parts
    assert ".." not in parts, f"parent traversal is forbidden: {value}"
    return ROOT / value


def assert_unique_ids(items: list[dict], item_type: str) -> set[str]:
    ids = [item["id"] for item in items]
    assert len(ids) == len(set(ids)), f"duplicate {item_type} IDs: {ids}"
    for item_id in ids:
        assert ID_PATTERN.fullmatch(item_id), f"invalid {item_type} ID: {item_id}"
    return set(ids)


def assert_metadata_paths_exist(item: dict) -> None:
    assert repo_path(item["path"]).is_file(), f"missing declared item path: {item['path']}"
    for field in ("authority_paths", "validators"):
        values = item[field]
        assert values and len(values) == len(set(values)), f"{item['id']} has invalid {field}"
        for value in values:
            assert repo_path(value).exists(), f"{item['id']} references missing {field}: {value}"


def assert_common_metadata(item: dict) -> None:
    assert len(item["summary"]) >= 20, f"summary too short: {item['id']}"
    assert item["lanes"] and len(item["lanes"]) == len(set(item["lanes"]))
    for lane in item["lanes"]:
        assert ID_PATTERN.fullmatch(lane), f"invalid lane {lane!r} for {item['id']}"
    assert item["default_network_activity"] is False, item["id"]
    assert item["default_target_mutation"] is False, item["id"]
    assert item["network_activity_mode"] in {"none", "control-plane", "gated-target"}, item["id"]
    assert item["target_mutation_mode"] in {"none", "repository", "gated-target"}, item["id"]
    assert_metadata_paths_exist(item)


def test_manifest_and_schema_define_fail_closed_contract() -> None:
    manifest = load_json(MANIFEST)
    schema = load_json(SCHEMA)

    assert manifest["schema_version"] == "sas-agent-capability-manifest/v1"
    assert manifest["schema_path"] == "schemas/harness/agent-capability-manifest.schema.json"
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == manifest["schema_path"]
    assert schema["additionalProperties"] is False

    required_top = {"schema_version", "schema_path", "authority", "posture", "capabilities", "skills"}
    assert required_top <= set(schema["required"])
    for item_name in ("capability", "skill"):
        item_schema = schema["$defs"][item_name]
        assert item_schema["additionalProperties"] is False
        assert {"id", "path", "summary", "lanes", "validators"} <= set(item_schema["required"])

    posture = manifest["posture"]
    assert posture == {
        "progressive_disclosure_required": True,
        "default_network_activity": False,
        "default_target_mutation": False,
        "tracked_runtime_evidence_allowed": False,
    }

    authority = manifest["authority"]
    for value in authority.values():
        assert repo_path(value).exists(), f"manifest authority path missing: {value}"


def test_capability_entries_are_complete_and_atomic() -> None:
    manifest = load_json(MANIFEST)
    capabilities = manifest["capabilities"]
    ids = assert_unique_ids(capabilities, "capability")
    assert ids == REQUIRED_CAPABILITY_IDS

    for capability in capabilities:
        assert VERSION_PATTERN.fullmatch(capability["version"]), capability["id"]
        assert capability["path"] == f".claude/capabilities/{capability['id']}.md"
        assert_common_metadata(capability)


def test_skill_dependencies_match_markdown_exactly() -> None:
    manifest = load_json(MANIFEST)
    capabilities = {item["id"]: item for item in manifest["capabilities"]}
    skills = manifest["skills"]
    ids = assert_unique_ids(skills, "skill")
    assert ids == REQUIRED_SKILL_IDS

    referenced_capabilities: set[str] = set()
    for skill in skills:
        assert skill["path"] == f".claude/skills/{skill['id']}/SKILL.md"
        assert_common_metadata(skill)
        capability_ids = skill["capability_ids"]
        assert capability_ids and len(capability_ids) == len(set(capability_ids))
        assert set(capability_ids) <= set(capabilities), f"{skill['id']} references an unknown capability"

        markdown = read(repo_path(skill["path"]))
        linked_ids = {Path(filename).stem for filename in CAPABILITY_LINK.findall(markdown)}
        assert linked_ids == set(capability_ids), (
            f"{skill['id']} manifest dependencies differ from Markdown: "
            f"manifest={sorted(capability_ids)} markdown={sorted(linked_ids)}"
        )
        referenced_capabilities.update(capability_ids)

    assert referenced_capabilities == REQUIRED_CAPABILITY_IDS, (
        "orphan capabilities in machine-readable manifest: "
        + ", ".join(sorted(REQUIRED_CAPABILITY_IDS - referenced_capabilities))
    )


def test_manifest_is_discoverable_and_wired_into_validation() -> None:
    required_path = "harness/api/agent-capability-manifest.json"
    schema_path = "schemas/harness/agent-capability-manifest.schema.json"
    test_path = "Tests/survey/test_agent_capability_manifest_contracts.py"

    for doc in (CAPABILITY_CATALOG, AI_LAYER_DOC, CODEBASE_MAP):
        text = read(doc)
        assert required_path in text, f"{doc.relative_to(ROOT)} does not name the manifest"

    assert schema_path in read(AI_LAYER_DOC)
    assert test_path in read(WORKFLOW)
    assert f"python3 {test_path}" in read(RUNNER)

    api = load_json(HARNESS_API)
    operations = {item["id"]: item for item in api["operations"]}
    operation = operations["agent_capability.catalog.read"]
    assert operation["mode"] == "local_read"
    assert operation["network_activity"] is False
    assert operation["target_mutation"] is False
    assert required_path in operation["inputs"]
    assert schema_path in operation["inputs"]
    assert "No_second_run_context" in operation["guardrails"]


def main() -> None:
    tests = [
        test_manifest_and_schema_define_fail_closed_contract,
        test_capability_entries_are_complete_and_atomic,
        test_skill_dependencies_match_markdown_exactly,
        test_manifest_is_discoverable_and_wired_into_validation,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} agent capability manifest contracts")


if __name__ == "__main__":
    main()
