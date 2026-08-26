#!/usr/bin/env python3
"""Dependency-free canonical path contract validator for SysAdminSuite."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/canonical-path-registry.json"
SCHEMA = ROOT / "schemas/harness/canonical-path-registry.schema.json"
WORKFLOW = ROOT / "harness/workflows/canonical-path-resolution.yaml"
FRESH = ROOT / "harness/workflows/fresh-agent-intake.yaml"
FRESHNESS = ROOT / "harness/workflows/repository-freshness-before-launch.yaml"
ROUTE = ROOT / "harness/workflows/operator-execution-route.yaml"
SKILL = ROOT / "harness/skills/canonical-path-resolution/SKILL.md"
MAP = ROOT / "harness/maps/CANONICAL_PATH_MAP.md"
REPORT = ROOT / "harness/reports/CANONICAL_PATH_STATUS.md"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/canonical-path-contracts.yml"

REQUIRED_TRACKED = (
    REGISTRY,
    SCHEMA,
    WORKFLOW,
    FRESH,
    FRESHNESS,
    ROUTE,
    SKILL,
    MAP,
    REPORT,
    PRE_COMMIT,
    PRE_PUSH,
    CI,
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing canonical path component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def require_exact_keys(value: dict, required: set[str], label: str) -> None:
    assert isinstance(value, dict), f"{label} must be an object"
    actual = set(value)
    missing = required - actual
    extra = actual - required
    assert not missing, f"{label} missing required fields: {sorted(missing)}"
    assert not extra, f"{label} contains undeclared fields: {sorted(extra)}"


def require_string(value: object, label: str, minimum: int = 1) -> str:
    assert isinstance(value, str), f"{label} must be a string"
    assert len(value.strip()) >= minimum, f"{label} must contain at least {minimum} non-whitespace characters"
    return value


def validate_path_record(record: dict, label: str) -> None:
    allowed = {"template", "mutable", "purpose", "authority", "currentness"}
    required = {"template", "mutable", "purpose"}
    assert isinstance(record, dict), f"{label} must be an object"
    assert required <= set(record), f"{label} missing required fields: {sorted(required - set(record))}"
    assert set(record) <= allowed, f"{label} contains undeclared fields: {sorted(set(record) - allowed)}"
    require_string(record["template"], f"{label}.template", 2)
    assert isinstance(record["mutable"], bool), f"{label}.mutable must be boolean"
    require_string(record["purpose"], f"{label}.purpose", 8)
    if "authority" in record:
        require_string(record["authority"], f"{label}.authority", 3)
    if "currentness" in record:
        require_string(record["currentness"], f"{label}.currentness", 8)


def validate_schema_equivalent(registry: dict, schema: dict) -> None:
    """Enforce the published schema shape without requiring third-party jsonschema."""
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"] == "sas-canonical-path-registry/v1"
    assert schema["properties"]["repository"]["const"] == "EndeavorEverlasting/SysAdminSuite"

    top_required = {
        "schema_version",
        "repository",
        "default_profile",
        "policy",
        "proof_states",
        "profiles",
        "consumers",
        "operator_command_safety",
        "proof_ceiling",
    }
    assert set(schema["required"]) == top_required, "schema top-level required fields drifted"
    require_exact_keys(registry, top_required, "canonical path registry")
    assert registry["schema_version"] == "sas-canonical-path-registry/v1"
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    require_string(registry["default_profile"], "default_profile")
    require_string(registry["proof_ceiling"], "proof_ceiling", 24)

    policy_required = {
        "remote_main_contains_sha_is_not_workstation_deployment_proof",
        "canonical_development_checkout_must_be_unique",
        "second_mutable_clone_is_forbidden",
        "preserve_unique_or_dirty_work",
        "parallel_writers_use_isolated_worktrees",
        "ephemeral_acquisition_checkout_never_becomes_canonical_by_existence",
        "production_use_path_requires_independent_currentness_proof",
        "operator_entrypoint_requires_independent_observation_proof",
    }
    require_exact_keys(registry["policy"], policy_required, "policy")
    for key in policy_required:
        assert registry["policy"][key] is True, f"canonical path policy must fail closed: {key}"

    proofs = registry["proof_states"]
    assert isinstance(proofs, list) and len(proofs) >= 4, "proof_states must contain at least four records"
    for index, proof in enumerate(proofs):
        require_exact_keys(proof, {"id", "proves", "does_not_prove"}, f"proof_states[{index}]")
        require_string(proof["id"], f"proof_states[{index}].id")
        require_string(proof["proves"], f"proof_states[{index}].proves", 12)
        require_string(proof["does_not_prove"], f"proof_states[{index}].does_not_prove", 12)

    profiles = registry["profiles"]
    assert isinstance(profiles, list) and len(profiles) >= 2, "profiles must contain at least two records"
    profile_required = {
        "id",
        "platform",
        "purpose",
        "canonical_development_checkout",
        "production_use_path",
        "temporary_worktree_root",
        "ephemeral_acquisition_patterns",
        "real_operator_entrypoint",
    }
    for index, profile in enumerate(profiles):
        label = f"profiles[{index}]"
        require_exact_keys(profile, profile_required, label)
        require_string(profile["id"], f"{label}.id")
        assert profile["platform"] in {"windows", "linux", "macos", "cross-platform"}
        require_string(profile["purpose"], f"{label}.purpose", 8)
        validate_path_record(profile["canonical_development_checkout"], f"{label}.canonical_development_checkout")
        validate_path_record(profile["temporary_worktree_root"], f"{label}.temporary_worktree_root")

        production = profile["production_use_path"]
        assert isinstance(production, dict), f"{label}.production_use_path must be an object"
        assert isinstance(production.get("applicable"), bool), f"{label}.production_use_path.applicable must be boolean"
        if production["applicable"]:
            require_exact_keys(production, {"applicable", "template", "mutable", "purpose", "currentness"}, f"{label}.production_use_path")
            require_string(production["template"], f"{label}.production_use_path.template", 2)
            assert isinstance(production["mutable"], bool)
            require_string(production["purpose"], f"{label}.production_use_path.purpose", 8)
            require_string(production["currentness"], f"{label}.production_use_path.currentness", 8)
        else:
            require_exact_keys(production, {"applicable", "reason"}, f"{label}.production_use_path")
            require_string(production["reason"], f"{label}.production_use_path.reason", 8)

        patterns = profile["ephemeral_acquisition_patterns"]
        assert isinstance(patterns, list) and patterns, f"{label}.ephemeral_acquisition_patterns must be non-empty"
        for pattern_index, pattern in enumerate(patterns):
            require_string(pattern, f"{label}.ephemeral_acquisition_patterns[{pattern_index}]", 3)
        entrypoint = profile["real_operator_entrypoint"]
        assert isinstance(entrypoint, dict) and len(entrypoint) >= 2, f"{label}.real_operator_entrypoint must contain at least two fields"
        for key, value in entrypoint.items():
            require_string(key, f"{label}.real_operator_entrypoint key")
            require_string(value, f"{label}.real_operator_entrypoint.{key}")

    consumers = registry["consumers"]
    assert isinstance(consumers, list) and len(consumers) >= 3, "consumers must contain at least three paths"
    for index, consumer in enumerate(consumers):
        require_string(consumer, f"consumers[{index}]", 3)

    safety = registry["operator_command_safety"]
    require_exact_keys(safety, {"powershell_if_else_must_be_one_paste_block", "reason"}, "operator_command_safety")
    assert safety["powershell_if_else_must_be_one_paste_block"] is True
    require_string(safety["reason"], "operator_command_safety.reason", 16)


def main() -> int:
    registry = load(REGISTRY)
    schema = load(SCHEMA)
    validate_schema_equivalent(registry, schema)

    proof_ids = [item["id"] for item in registry["proof_states"]]
    expected_proofs = {
        "remote_default_contains_sha",
        "canonical_development_checkout_current",
        "production_use_path_current",
        "operator_entrypoint_observes_current",
    }
    assert set(proof_ids) == expected_proofs
    assert len(proof_ids) == len(set(proof_ids))

    profiles = {item["id"]: item for item in registry["profiles"]}
    assert {"windows-development", "windows-admin-box"} <= set(profiles)
    assert registry["default_profile"] in profiles
    for profile in profiles.values():
        assert profile["canonical_development_checkout"]["template"] == "%USERPROFILE%\\Desktop\\Dev\\SysAdminSuite"
        assert profile["temporary_worktree_root"]["template"] == "%LOCALAPPDATA%\\SysAdminSuite\\worktrees"
        assert profile["canonical_development_checkout"]["template"] != profile["temporary_worktree_root"]["template"]
        assert any("closeout-entry-*" in item for item in profile["ephemeral_acquisition_patterns"])

    admin = profiles["windows-admin-box"]
    assert admin["production_use_path"]["applicable"] is True
    assert admin["production_use_path"]["template"] == "C:\\SASAL"
    assert admin["real_operator_entrypoint"]["authority"] == "harness/api/operator-execution-route-registry.json"
    assert admin["real_operator_entrypoint"]["production_runtime_entrypoint"] == "C:\\SASAL\\Bootstrap-SysAdminSuiteAutoLogon.cmd"
    development = profiles["windows-development"]
    assert development["production_use_path"]["applicable"] is False

    consumers = set(registry["consumers"])
    for expected in (
        "harness/workflows/fresh-agent-intake.yaml",
        "harness/workflows/repository-freshness-before-launch.yaml",
        "harness/workflows/operator-execution-route.yaml",
        "harness/skills/canonical-path-resolution/SKILL.md",
        "harness/maps/CANONICAL_PATH_MAP.md",
        "harness/reports/CANONICAL_PATH_STATUS.md",
    ):
        assert expected in consumers
        assert (ROOT / expected).is_file(), f"canonical path consumer missing: {expected}"

    workflow = read(WORKFLOW)
    for marker in (
        "workflow_id: canonical-path-resolution",
        "ephemeral acquisition checkout never becomes canonical",
        "remote_default_contains_sha",
        "canonical_development_checkout_current",
        "production_use_path_current",
        "operator_entrypoint_observes_current",
        "one paste block",
    ):
        assert marker in workflow, f"canonical path workflow missing: {marker}"

    fresh = read(FRESH)
    freshness = read(FRESHNESS)
    route = read(ROUTE)
    for text, marker in (
        (fresh, "harness/api/canonical-path-registry.json"),
        (fresh, "harness/workflows/canonical-path-resolution.yaml"),
        (freshness, "harness/api/canonical-path-registry.json"),
        (route, "harness/api/canonical-path-registry.json"),
    ):
        assert marker in text, f"canonical path consumer not wired: {marker}"

    skill = read(SKILL)
    for marker in (
        "entire construct in one copy/paste block",
        "second submission attempts to invoke a command named `else`",
        "remote default contains SHA",
        "production/use path current",
    ):
        assert marker in skill, f"canonical path skill missing: {marker}"

    map_text = read(MAP)
    report = read(REPORT)
    for marker in (
        "%USERPROFILE%\\Desktop\\Dev\\SysAdminSuite",
        "%LOCALAPPDATA%\\SysAdminSuite\\worktrees",
        "C:\\SASAL",
        "closeout-entry-*",
        "standalone `else`",
    ):
        assert marker in map_text, f"canonical path map missing: {marker}"
    for marker in (
        "one machine-readable path owner",
        "four independent proof states",
        "standalone later `else`",
        "PASS: canonical path harness contracts",
    ):
        assert marker in report, f"canonical path report missing: {marker}"

    pre_commit = read(PRE_COMMIT)
    assert "validate-canonical-path-contracts.py" in pre_commit
    assert "test_canonical_path_harness_completeness.py" in pre_commit
    pre_push = read(PRE_PUSH)
    assert "has_canonical_path=0" in pre_push
    assert "git worktree add --detach --quiet \"$wt\" \"$commit\"" in pre_push
    assert "python3 harness/validators/validate-canonical-path-contracts.py" in pre_push
    assert "python3 Tests/survey/test_canonical_path_harness_completeness.py" in pre_push
    prefix = pre_push.split("validate_pushed_tip()", 1)[0]
    assert "validate-canonical-path-contracts.py" not in prefix, "pre-push must not validate canonical paths from the mutable live worktree"
    assert "test_canonical_path_harness_completeness.py" not in prefix, "pre-push must not validate canonical completeness from the mutable live worktree"

    ci = read(CI)
    for marker in (
        "Canonical Path Contracts",
        "validate-canonical-path-contracts.py",
        "test_canonical_path_harness_completeness.py",
        "test_operational_harness_completeness_contracts.py",
        "git diff --check",
    ):
        assert marker in ci, f"canonical path CI missing: {marker}"

    combined = "\n".join(read(path) for path in (REGISTRY, WORKFLOW, SKILL, MAP, REPORT)).lower()
    for forbidden in ("pa_rperez26", "wpj075", "nslijhs.net"):
        assert forbidden not in combined, f"machine/live-target literal leaked into canonical path harness: {forbidden}"

    for path in REQUIRED_TRACKED:
        assert tracked(path), f"canonical path component is not tracked: {path.relative_to(ROOT)}"

    print("PASS: canonical path harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
