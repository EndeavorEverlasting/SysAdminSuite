#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]

MAP = ROOT / "harness/maps/controller-network-mode-map.md"
WORKFLOW = ROOT / "harness/workflows/controller-network-mode-serialization.yaml"
REGISTRY = ROOT / "harness/api/controller-network-mode-artifact-registry.json"
SCHEMA = ROOT / "schemas/harness/controller-network-mode-artifact-registry.schema.json"
SKILL = ROOT / "harness/skills/controller-network-mode-serialization/SKILL.md"
REPORT = ROOT / "harness/reports/CONTROLLER_NETWORK_MODE_STATUS.md"
COMPLETENESS = ROOT / "Tests/survey/test_controller_network_mode_harness_completeness.py"
CI = ROOT / ".github/workflows/controller-network-mode-harness.yml"
FRESH_INTAKE = ROOT / "harness/workflows/fresh-agent-intake.yaml"
REPO_SKILL = ROOT / ".claude/skills/repository-sprint/SKILL.md"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"

VPN_HELPER = ROOT / "scripts/Enable-SasNorthwellVpnNetworkGuard.ps1"
FIELD_DEPLOY = ROOT / "scripts/Invoke-SasAutoLogonFieldDeployment.ps1"
ONSITE = ROOT / "scripts/Invoke-SasAutoLogonOnsite.ps1"

REQUIRED_ARTIFACT_IDS = {
    "controller-network-mode-map",
    "controller-network-mode-workflow",
    "controller-network-mode-skill",
    "controller-network-mode-status",
    "controller-repo-certification",
    "controller-network-posture-evidence",
    "controller-network-mode-validation-result",
    "controller-network-mode-completeness-result",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def read(path: Path) -> str:
    if not path.is_file():
        fail(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def require_tokens(label: str, text: str, tokens: list[str]) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        fail(f"{label} missing tokens: {missing}")


def validate_registry() -> None:
    registry = json.loads(read(REGISTRY))
    schema = json.loads(read(SCHEMA))

    if registry.get("schema_version") != "sas-controller-network-mode-artifact-registry/v1":
        fail("registry schema_version mismatch")
    if registry.get("repository") != "EndeavorEverlasting/SysAdminSuite":
        fail("registry repository mismatch")
    if registry.get("schema") != "schemas/harness/controller-network-mode-artifact-registry.schema.json":
        fail("registry schema path mismatch")

    expected_top = {"schema_version", "repository", "schema", "naming", "artifacts"}
    if set(registry) != expected_top:
        fail("registry top-level keys must exactly match schema contract")

    naming = registry.get("naming")
    expected_naming = {"tracked_report", "runtime_certification", "network_evidence"}
    if not isinstance(naming, dict) or set(naming) != expected_naming:
        fail("registry naming contract mismatch")
    for key, value in naming.items():
        if not isinstance(value, str) or not value.strip():
            fail(f"registry naming.{key} must be a non-empty string")

    artifacts = registry.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        fail("registry artifacts must be a non-empty array")
    ids: list[str] = []
    required_keys = {"id", "kind", "path", "generator", "tracked", "purpose"}
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict) or set(artifact) != required_keys:
            fail(f"artifact[{index}] keys do not match strict schema")
        for key in ("id", "kind", "path", "generator", "purpose"):
            if not isinstance(artifact[key], str) or not artifact[key].strip():
                fail(f"artifact[{index}].{key} must be a non-empty string")
        if not isinstance(artifact["tracked"], bool):
            fail(f"artifact[{index}].tracked must be boolean")
        ids.append(artifact["id"])
    if len(ids) != len(set(ids)):
        fail("artifact ids must be unique")
    if set(ids) != REQUIRED_ARTIFACT_IDS:
        fail(f"artifact ids mismatch: {set(ids) ^ REQUIRED_ARTIFACT_IDS}")

    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        fail("schema must declare Draft 2020-12")
    if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
        fail("schema root must be a strict object")
    artifact_schema = schema["properties"]["artifacts"]["items"]
    if artifact_schema.get("additionalProperties") is not False:
        fail("artifact schema must reject additional properties")
    if artifact_schema["properties"]["tracked"].get("type") != "boolean":
        fail("artifact tracked schema must require boolean")


def validate_phase_contract() -> None:
    workflow = read(WORKFLOW)
    require_tokens("workflow", workflow, [
        "OFF_NETWORK_REPOSITORY_PREP",
        "TRANSITION_TO_PROTECTED_NETWORK",
        "PROTECTED_NETWORK_DEPLOYMENT",
        "remote_git_off_network_only",
        "no_git_after_transition",
        "controller-repo-certification.json",
        "PRODUCT_RUNTIME_GIT_DEPENDENCY",
        "CERTIFICATION_ARTIFACT_INVALID",
        "NETWORK_POSTURE_UNPROVEN",
        "scripts/Enable-SasNorthwellVpnNetworkGuard.ps1 -ConfirmVpnPosture",
        "scripts/Confirm-SasNorthwellNetwork.ps1 -NonInteractive -NoOpenWifiSettings",
    ])
    if workflow.index("OFF_NETWORK_REPOSITORY_PREP") > workflow.index("TRANSITION_TO_PROTECTED_NETWORK"):
        fail("off-network phase must precede transition")
    if workflow.index("TRANSITION_TO_PROTECTED_NETWORK") > workflow.index("PROTECTED_NETWORK_DEPLOYMENT"):
        fail("transition must precede protected-network phase")
    protected = workflow.split("- id: PROTECTED_NETWORK_DEPLOYMENT", 1)[1]
    require_tokens("protected phase", protected, [
        "git_allowed: false",
        "read controller-repo-certification.json with filesystem APIs; do not invoke Git",
        "target_contact_allowed: only_after_network_gate",
    ])


def validate_docs() -> None:
    common = [
        "OFF_NETWORK_REPOSITORY_PREP",
        "PROTECTED_NETWORK_DEPLOYMENT",
        "no_git_after_transition",
        "PRODUCT_RUNTIME_GIT_DEPENDENCY",
        "controller-repo-certification.json",
    ]
    require_tokens("map", read(MAP), common + ["TRANSITION_TO_PROTECTED_NETWORK", "CODEBASE_MAP.md"])
    require_tokens("skill", read(SKILL), common + ["Required inputs", "Expected outputs", "Validation", "Handoff"])
    require_tokens("report", read(REPORT), common + ["Working", "Broken / blocked conditions", "Missing proof", "Operator next gate"])


def validate_product_observations() -> None:
    vpn = read(VPN_HELPER)
    require_tokens("VPN helper", vpn, [
        "ConfirmVpnPosture",
        "DomainAuthenticated",
        "SAS_VPN_NETWORK_GUARD_READY",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
    ])

    field = read(FIELD_DEPLOY)
    network_marker = "=== PROTECTED NETWORK GATE ==="
    resolution_marker = "=== CANONICAL TARGET RESOLUTION ==="
    require_tokens("field deployment", field, [network_marker, resolution_marker])
    if field.index(network_marker) > field.index(resolution_marker):
        fail("field deployment must prove protected network before target resolution")

    onsite = read(ONSITE)
    require_tokens("onsite launcher current product dependency", onsite, [
        "git -C $SourceRepoRoot rev-parse HEAD",
        "git worktree add --detach",
        "git -C $fieldRuntimeRoot status",
        "git -C $fieldRuntimeRoot checkout --detach",
    ])


def validate_routing_and_admission() -> None:
    intake = read(FRESH_INTAKE)
    require_tokens("fresh-agent intake", intake, [
        "controller-network-mode-serialization",
        "no_git_after_transition",
        "PRODUCT_RUNTIME_GIT_DEPENDENCY",
    ])
    repo_skill = read(REPO_SKILL)
    require_tokens("repository sprint skill", repo_skill, [
        "controller-network-mode-serialization.yaml",
        "Git may be unavailable after the protected-network transition",
    ])

    pre_commit = read(PRE_COMMIT)
    require_tokens("pre-commit", pre_commit, [
        "validate-controller-network-mode.py",
        "test_controller_network_mode_harness_completeness.py",
    ])
    pre_push = read(PRE_PUSH)
    require_tokens("pre-push", pre_push, [
        "validate-controller-network-mode.py",
        "test_controller_network_mode_harness_completeness.py",
    ])
    ci = read(CI)
    require_tokens("CI", ci, [
        "validate-controller-network-mode.py",
        "test_controller_network_mode_harness_completeness.py",
        "validate-prestage-bootstrap-safety.py",
        "validate-repository-freshness-contracts.py",
        "git diff --check",
    ])


def validate_runtime_artifact_tracking_boundary() -> None:
    registry = json.loads(read(REGISTRY))
    runtime = {
        item["id"]: item for item in registry["artifacts"]
        if item["id"] in {"controller-repo-certification", "controller-network-posture-evidence"}
    }
    if any(item["tracked"] for item in runtime.values()):
        fail("runtime controller/network evidence must remain untracked")
    if "controller-handoff" not in read(PRE_COMMIT):
        fail("pre-commit must reject staged controller-handoff runtime artifacts")


def main() -> int:
    groups = [
        ("component files", lambda: [read(p) for p in (MAP, WORKFLOW, REGISTRY, SCHEMA, SKILL, REPORT, COMPLETENESS, CI)]),
        ("artifact registry/schema", validate_registry),
        ("serialized phase contract", validate_phase_contract),
        ("map/skill/report", validate_docs),
        ("read-only product observations", validate_product_observations),
        ("routing/hooks/CI", validate_routing_and_admission),
        ("runtime tracking boundary", validate_runtime_artifact_tracking_boundary),
    ]
    for _, check in groups:
        check()
    print(f"PASS: controller network-mode serialization harness contracts ({len(groups)} groups)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, json.JSONDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
