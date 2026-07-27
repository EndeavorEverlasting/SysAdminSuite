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
OUTCOMES = ROOT / "harness/api/harness-outcome-registry.json"
OUTCOME_SCHEMA = ROOT / "schemas/harness/harness-outcome-registry.schema.json"
WORKFLOW = ROOT / "harness/workflows/operational-harness-maintenance.yaml"
OUTCOME_WORKFLOW = ROOT / "harness/workflows/outcome-driven-execution.yaml"
PUBLISH_WORKFLOW = ROOT / "harness/workflows/operational-harness-publish.yaml"
OUTCOME_SKILL = ROOT / "harness/skills/outcome-driven-execution/SKILL.md"
OUTCOME_VALIDATOR = ROOT / "harness/validators/validate-outcome-contracts.py"
STATUS = ROOT / "docs/HARNESS_STATUS.md"
MAP = ROOT / "CODEBASE_MAP.md"
ATTRIBUTES = ROOT / ".gitattributes"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/harness-infrastructure.yml"
TEXT_VALIDATOR = ROOT / "scripts/check-repo-text-policy.py"
DIGEST_FIXTURE = "Tests/Fixtures/autologon-result-inspector/deployment-success/artifacts/autologon_proof_source_evidence.json"


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
    assert {"maintenance-workflow", "publish-workflow", "outcome-driven-workflow", "outcome-registry", "outcome-validator"} <= set(ids)
    required_kinds = {
        "codebase_map",
        "workflow",
        "artifact_registry",
        "validator_registry",
        "command_registry",
        "outcome_registry",
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
        "harness/api/harness-outcome-registry.json",
        "harness/skills/outcome-driven-execution/SKILL.md",
        "validate-outcome-contracts.py",
        "test_operational_harness_completeness_contracts.py",
        "check-repo-text-policy.py --cached",
        "stop at the first failed proof boundary",
        "emit the exact operator-approved publish command",
        "route remote push and PR actions to operational-harness-publish",
        "provide one exact next command only when a real external or unproven gate remains",
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


def test_outcome_driven_execution_floor() -> None:
    registry = load(OUTCOMES)
    schema = load(OUTCOME_SCHEMA)
    workflow = read(OUTCOME_WORKFLOW)
    skill = read(OUTCOME_SKILL)
    validator = read(OUTCOME_VALIDATOR)

    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == "sas-harness-outcome-registry/v1"
    assert registry["schema_version"] == "sas-harness-outcome-registry/v1"
    assert registry["policy"]["validation_is_admission_not_completion"] is True
    assert registry["policy"]["dry_run_must_emit_artifact"] is True
    for forbidden in (
        "tests_passed_only",
        "status_reported_only",
        "command_printed_only",
        "wait_for_next_chat",
        "operator_repeats_agent_work",
    ):
        assert forbidden in registry["policy"]["forbidden_terminal_outcomes"]

    command_ids = [item["command_id"] for item in registry["contracts"]]
    assert len(command_ids) == len(set(command_ids))
    clinical_core = next(item for item in registry["contracts"] if item["command_id"] == "cybernet-core-deploy")
    assert clinical_core["success_outcome"] == "product_deployed"
    assert clinical_core["success_artifact_id"] == "cybernet-clinical-core-deployment-summary"
    full_deploy = next(item for item in registry["contracts"] if item["command_id"] == "cybernet-software-deploy")
    assert full_deploy["success_outcome"] == "product_deployed"
    assert full_deploy["success_artifact_id"] == "cybernet-software-deployment-result"
    autologon = next(item for item in registry["contracts"] if item["command_id"] == "autologon-remote")
    assert autologon["success_outcome"] == "product_deployed"
    assert autologon["success_artifact_id"] == "autologon-s4u-deployment-result"

    for marker in (
        "workflow_id: outcome-driven-execution",
        "validators and dry runs as admission gates, not as the requested deliverable",
        "follow the registered continuation in the same agent turn",
        "do not ask the operator to rerun a command the agent can safely execute itself",
        "blocked_with_actionable_gate",
    ):
        assert marker in workflow
    for marker in (
        "## Forbidden stopping patterns",
        "Do not hand a safe executable continuation back to the operator",
        "tests passed",
        "send me the logs",
        "wait for CI",
    ):
        assert marker in skill
    for marker in (
        "every canonical command must have exactly one outcome contract",
        "admission command must emit a registered artifact",
        "deploy-plan lacks deploy continuation",
        "PASS: outcome-driven harness contracts",
    ):
        assert marker in validator

    for path in (OUTCOMES, OUTCOME_SCHEMA, OUTCOME_WORKFLOW, OUTCOME_SKILL, OUTCOME_VALIDATOR):
        assert_tracked(path.relative_to(ROOT).as_posix())


def test_artifact_registry_names_locations_generators_and_privacy() -> None:
    registry = load(ARTIFACTS)
    assert registry["schema_version"] == "sas-harness-artifact-registry/v1"
    artifacts = registry["artifacts"]
    ids = [item["id"] for item in artifacts]
    assert len(ids) == len(set(ids))
    assert {
        "operational-harness-manifest",
        "harness-outcome-registry",
        "harness-status-report",
        "harness-completeness-result",
        "harness-outcome-validation-result",
        "repository-text-policy-result",
        "offline-survey-floor-result",
        "cybernet-client-configuration-summary",
        "cybernet-clinical-core-deployment-summary",
        "cybernet-software-deployment-result",
        "autologon-s4u-pilot-result",
        "autologon-s4u-deployment-result",
        "autologon-technician-runtime-proof",
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
    handoff = next(item for item in artifacts if item["id"] == "operator-handoff")
    assert handoff["parser_facing"] is False
    assert handoff["consumption"] == "clean local pipe and direct human review"


def test_repository_text_policy_is_explicit_and_git_visible() -> None:
    attributes = read(ATTRIBUTES)
    assert "* text=auto" not in attributes
    for marker in (
        "*.cmd text",
        "*.bat text",
        "Run-CybernetComPortQrPack.cmd -text",
        "Run-FieldHotfixesGui.cmd -text",
        "Start-CybernetSurveyTutorial.cmd -text",
        "survey/sas-reg-query.cmd -text",
        "*.sh text eol=lf",
        "*.fixture text eol=lf",
        f"{DIGEST_FIXTURE} text eol=lf",
        "*.jsonl text",
        "*.pcap binary",
        "Canonical LF storage for changed text blobs is enforced by scripts/check-repo-text-policy.py",
    ):
        assert marker in attributes, f"line-ending policy missing: {marker}"
    for forbidden in ("*.cmd text eol=crlf", "*.bat text eol=crlf"):
        assert forbidden not in attributes, f"checkout rewriting is forbidden: {forbidden}"

    generic_cmd = git("check-attr", "text", "eol", "--", "Future-Harness-Launcher.cmd")
    assert generic_cmd.returncode == 0
    assert "text: set" in generic_cmd.stdout
    assert "eol: unspecified" in generic_cmd.stdout

    legacy_cmd = git("check-attr", "text", "eol", "--", "Start-CybernetSurveyTutorial.cmd")
    assert legacy_cmd.returncode == 0
    assert "text: unset" in legacy_cmd.stdout
    assert "eol: unspecified" in legacy_cmd.stdout

    sh_attr = git("check-attr", "text", "eol", "--", "tests/survey/run_offline_survey_tests.sh")
    assert sh_attr.returncode == 0
    assert "eol: lf" in sh_attr.stdout
    digest_attr = git("check-attr", "text", "eol", "--", DIGEST_FIXTURE)
    assert digest_attr.returncode == 0
    assert "text: set" in digest_attr.stdout
    assert "eol: lf" in digest_attr.stdout
    ps_attr = git("check-attr", "text", "eol", "--", "tools/New-SasSprintCapsule.ps1")
    assert ps_attr.returncode == 0
    assert "text: unspecified" in ps_attr.stdout
    assert "eol: unspecified" in ps_attr.stdout
    json_attr = git("check-attr", "text", "eol", "--", "Config/cybernet-naabu-profiles.json")
    assert json_attr.returncode == 0
    assert "text: unspecified" in json_attr.stdout
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
        "validate-harness-registries.py",
        "validate-outcome-contracts.py",
        "test_operational_harness_completeness_contracts.py",
        "check-repo-text-policy.py --cached",
        "git diff --cached --name-only",
    ):
        assert marker in pre_commit, f"pre-commit missing: {marker}"
    for marker in (
        "validate-harness-registries.py",
        "validate-outcome-contracts.py",
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
        "harness-outcome-registry.json",
        "harness-outcome-registry.schema.json",
        "validate-outcome-contracts.py",
        "test_operational_harness_completeness_contracts.py",
        "test_local_harness_contracts.py",
        "check-repo-text-policy.py --range",
        "git diff --check",
        "bash -n .githooks/pre-commit .githooks/pre-push",
        "windows-sprint-capsule",
        "Prove checkout is clean",
        "Prove validator leaves a clean worktree",
        "SprintCapsule.Tests.ps1",
        "Capture full Pester diagnostic",
        "operational-harness-full-pester-summary",
    ):
        assert marker in ci, f"harness CI missing: {marker}"

    codebase_map = read(MAP)
    for marker in (
        "## Operational harness infrastructure",
        "harness/api/operational-harness-manifest.json",
        "harness/api/harness-artifact-registry.json",
        "harness/api/harness-outcome-registry.json",
        "harness/workflows/operational-harness-maintenance.yaml",
        "harness/workflows/outcome-driven-execution.yaml",
        "scripts/check-repo-text-policy.py",
        "docs/HARNESS_STATUS.md",
    ):
        assert marker in codebase_map, f"codebase map missing: {marker}"

    status = read(STATUS)
    for heading in (
        "## Current state",
        "## Working",
        "## Outcome-driven execution",
        "## Repaired boundary",
        "## Known gaps and proof limits",
        "## Operator validation",
        "## Expected result",
    ):
        assert heading in status
    assert "operational-harness-publish.yaml" in status
    assert "PASS: operational harness completeness" in status
    assert "tests passed" in status.lower()
    assert "same-turn" in status.lower()


def main() -> int:
    test_manifest_and_schema_floor()
    test_workflows_separate_local_maintenance_from_remote_publication()
    test_outcome_driven_execution_floor()
    test_artifact_registry_names_locations_generators_and_privacy()
    test_repository_text_policy_is_explicit_and_git_visible()
    test_hooks_ci_map_and_operator_report_are_wired()
    print("PASS: operational harness completeness")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
