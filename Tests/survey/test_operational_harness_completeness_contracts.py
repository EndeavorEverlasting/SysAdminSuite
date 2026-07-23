#!/usr/bin/env python3
"""Dependency-free completeness contracts for the operational repository harness."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
SCHEMA = ROOT / "schemas/harness/operational-harness-manifest.schema.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"
WORKFLOW = ROOT / "harness/workflows/operational-harness-maintenance.yaml"
PUBLISH_WORKFLOW = ROOT / "harness/workflows/operational-harness-publish.yaml"
STATUS = ROOT / "docs/HARNESS_STATUS.md"
MAP = ROOT / "CODEBASE_MAP.md"
ATTRIBUTES = ROOT / ".gitattributes"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/harness-infrastructure.yml"
TEXT_VALIDATOR = ROOT / "scripts/check-repo-text-policy.py"


def read(path: Path) -> str:
    assert path.is_file(), f"missing harness component: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(ROOT), *args],
        text=True,
        capture_output=True,
        check=False,
    )


def assert_tracked(path: str) -> None:
    result = git("ls-files", "--error-unmatch", path)
    assert result.returncode == 0, f"harness component is not tracked: {path}"


def test_manifest_and_schema_floor() -> None:
    manifest = load(MANIFEST)
    schema = load(SCHEMA)
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == "sas-operational-harness-manifest/v1"
    assert manifest["schema_version"] == "sas-operational-harness-manifest/v1"
    assert manifest["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert manifest["default_workflow"] == "harness/workflows/operational-harness-maintenance.yaml"
    assert len(manifest["validation_commands"]) >= 4
    assert "no product behavior" in manifest["proof_ceiling"].lower()

    components = manifest["components"]
    ids = [item["id"] for item in components]
    assert len(ids) == len(set(ids)), "duplicate operational harness component id"
    assert {"maintenance-workflow", "publish-workflow"} <= set(ids)
    required_kinds = {
        "codebase_map",
        "workflow",
        "artifact_registry",
        "validator",
        "hook",
        "hook_installer",
        "skill",
        "operator_report",
        "handoff",
        "run_context",
        "schema",
        "text_policy",
        "ci",
    }
    assert required_kinds <= {item["kind"] for item in components}

    for component in components:
        assert component["purpose"].strip()
        assert component["validation"].strip()
        path = component["path"]
        if component["required"]:
            assert (ROOT / path).is_file(), f"required harness component missing: {path}"
        if component["tracked"]:
            assert_tracked(path)

    assert_tracked(MANIFEST.relative_to(ROOT).as_posix())
    assert_tracked(SCHEMA.relative_to(ROOT).as_posix())


def test_workflows_separate_local_maintenance_from_remote_publication() -> None:
    text = read(WORKFLOW)
    markers = (
        "workflow_id: operational-harness-maintenance",
        "network_activity: false",
        "target_mutation: false",
        "- id: inspect",
        "- id: route",
        "- id: implement",
        "- id: validate",
        "- id: failure",
        "- id: commit",
        "- id: handoff",
    )
    positions = [text.index(marker) for marker in markers]
    assert positions == sorted(positions)
    for marker in (
        "read AGENTS.md without modifying it",
        "read CODEBASE_MAP.md",
        "test_operational_harness_completeness_contracts.py",
        "check-repo-text-policy.py --cached",
        "stop at the first failed proof boundary",
        "emit the exact operator-approved publish command",
        "route remote push and PR actions to operational-harness-publish",
        "provide one exact next command",
        "tools/New-SasSprintCapsule.ps1",
    ):
        assert marker in text, f"workflow missing: {marker}"
    for forbidden in ("push the isolated branch", "open or update one pull request"):
        assert forbidden not in text, f"local workflow overclaims network activity: {forbidden}"

    publish = read(PUBLISH_WORKFLOW)
    for marker in (
        "workflow_id: operational-harness-publish",
        "mode: operator_execute",
        "network_activity: true",
        "target_network_activity: false",
        "operator_approval_required: true",
        "configured_git_remote",
        "repository_pull_request_api",
        "- id: verify",
        "- id: push",
        "- id: pull_request",
        "- id: handoff",
        "force push",
        "no product target, deployment, application, or live-runtime proof",
    ):
        assert marker in publish, f"publish workflow missing: {marker}"


def test_artifact_registry_names_locations_generators_and_privacy() -> None:
    registry = load(ARTIFACTS)
    assert registry["schema_version"] == "sas-harness-artifact-registry/v1"
    artifacts = registry["artifacts"]
    ids = [item["id"] for item in artifacts]
    assert len(ids) == len(set(ids))
    assert {
        "operational-harness-manifest",
        "harness-status-report",
        "harness-completeness-result",
        "repository-text-policy-result",
        "local-harness-proof",
        "run-artifact-registry",
        "operator-handoff",
        "sprint-capsule",
    } <= set(ids)
    for item in artifacts:
        for field in ("path", "generator", "format", "tracked", "contains_live_data", "purpose"):
            assert field in item, f"artifact {item['id']} missing {field}"
        if item["contains_live_data"] is True or item["contains_live_data"] == "workflow-dependent":
            assert item["tracked"] is False, f"live-data artifact cannot be tracked: {item['id']}"


def test_repository_text_policy_is_explicit_and_git_visible() -> None:
    attributes = read(ATTRIBUTES)
    for marker in (
        "* text=auto",
        "*.cmd text eol=crlf",
        "*.bat text eol=crlf",
        "*.sh text eol=lf",
        "*.fixture text eol=lf",
        "*.jsonl text",
        "*.pcap binary",
    ):
        assert marker in attributes, f"line-ending policy missing: {marker}"

    cmd_attr = git("check-attr", "text", "eol", "--", "Start-CybernetSurveyTutorial.cmd")
    assert cmd_attr.returncode == 0
    assert "text: set" in cmd_attr.stdout
    assert "eol: crlf" in cmd_attr.stdout
    sh_attr = git("check-attr", "text", "eol", "--", "tests/survey/run_offline_survey_tests.sh")
    assert sh_attr.returncode == 0
    assert "eol: lf" in sh_attr.stdout
    ps_attr = git("check-attr", "text", "eol", "--", "tools/New-SasSprintCapsule.ps1")
    assert ps_attr.returncode == 0
    assert "text: auto" in ps_attr.stdout
    assert "eol: unspecified" in ps_attr.stdout
    json_attr = git("check-attr", "text", "eol", "--", "Config/cybernet-naabu-profiles.json")
    assert json_attr.returncode == 0
    assert "text: auto" in json_attr.stdout
    assert "eol: unspecified" in json_attr.stdout
    jsonl_attr = git("check-attr", "text", "eol", "--", "survey/output/example/events.jsonl")
    assert jsonl_attr.returncode == 0
    assert "text: set" in jsonl_attr.stdout
    assert "eol: unspecified" in jsonl_attr.stdout

    validator = read(TEXT_VALIDATOR)
    for marker in (
        "reads bytes from the Git index or commit object",
        '".jsonl"',
        "--cached",
        "--commit",
        "--range",
        "contains CR/CRLF bytes in the Git blob",
        "trailing space or tab",
    ):
        assert marker in validator, f"text validator missing: {marker}"


def test_hooks_ci_map_and_operator_report_are_wired() -> None:
    pre_commit = read(PRE_COMMIT)
    pre_push = read(PRE_PUSH)
    for marker in (
        "test_operational_harness_completeness_contracts.py",
        "check-repo-text-policy.py --cached",
        "git diff --cached --name-only",
    ):
        assert marker in pre_commit, f"pre-commit missing: {marker}"
    for marker in (
        "run_offline_survey_tests.sh",
        "test_operational_harness_completeness_contracts.py",
        "check-repo-text-policy.py --commit",
        "remote_name=",
        "remote_sha}..${local_sha}",
        "[[ \"$local_sha\" =~ ^0+$ ]] && continue",
        "refs/remotes/${remote_name}/",
    ):
        assert marker in pre_push, f"pre-push missing: {marker}"
    assert "--not --remotes" not in pre_push

    ci = read(CI)
    for marker in (
        "Operational Harness Infrastructure",
        "test_operational_harness_completeness_contracts.py",
        "test_local_harness_contracts.py",
        "check-repo-text-policy.py --range",
        "git diff --check",
        "bash -n .githooks/pre-commit .githooks/pre-push",
    ):
        assert marker in ci, f"harness CI missing: {marker}"

    codebase_map = read(MAP)
    for marker in (
        "## Operational harness infrastructure",
        "harness/api/operational-harness-manifest.json",
        "harness/api/harness-artifact-registry.json",
        "harness/workflows/operational-harness-maintenance.yaml",
        "harness/workflows/operational-harness-publish.yaml",
        "scripts/check-repo-text-policy.py",
        "docs/HARNESS_STATUS.md",
    ):
        assert marker in codebase_map, f"codebase map missing: {marker}"

    status = read(STATUS)
    for heading in (
        "## Current state",
        "## Working",
        "## Repaired boundary",
        "## Known gaps and proof limits",
        "## Operator validation",
        "## Expected result",
    ):
        assert heading in status
    assert "operational-harness-publish.yaml" in status
    assert "PASS: operational harness completeness" in status


def main() -> int:
    test_manifest_and_schema_floor()
    test_workflows_separate_local_maintenance_from_remote_publication()
    test_artifact_registry_names_locations_generators_and_privacy()
    test_repository_text_policy_is_explicit_and_git_visible()
    test_hooks_ci_map_and_operator_report_are_wired()
    print("PASS: operational harness completeness")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
