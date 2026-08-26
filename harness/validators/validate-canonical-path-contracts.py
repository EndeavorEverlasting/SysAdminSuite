#!/usr/bin/env python3
"""Dependency-free canonical path contract validator for SysAdminSuite."""
from __future__ import annotations

import json
import re
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
ONE_COMMAND = ROOT / "scripts/validate-sysadmin-harness.ps1"
ONE_COMMAND_CI = ROOT / ".github/workflows/one-command-harness-proof.yml"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/canonical-path-contracts.yml"

PROFILE_PARAMETERS = ["os", "user", "onedrive_enabled", "desktop_dev_root"]
PLATFORMS = {"windows", "linux", "macos", "cross-platform"}
REQUIRED_TRACKED = (
    REGISTRY, SCHEMA, WORKFLOW, FRESH, FRESHNESS, ROUTE, SKILL, MAP, REPORT,
    ONE_COMMAND, ONE_COMMAND_CI, PRE_COMMIT, PRE_PUSH, CI,
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing canonical path component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True, capture_output=True, check=False,
    )
    return result.returncode == 0


def exact_keys(value: object, required: set[str], label: str, optional: set[str] | None = None) -> dict:
    assert isinstance(value, dict), f"{label} must be an object"
    optional = optional or set()
    actual = set(value)
    assert required <= actual, f"{label} missing: {sorted(required - actual)}"
    assert actual <= required | optional, f"{label} undeclared: {sorted(actual - required - optional)}"
    return value


def string(value: object, label: str, minimum: int = 1) -> str:
    assert isinstance(value, str) and len(value.strip()) >= minimum, f"{label} must be a non-empty string"
    return value


def validate_path_record(record: object, label: str) -> dict:
    item = exact_keys(
        record,
        {"template", "mutable", "purpose"},
        label,
        {"authority", "currentness"},
    )
    string(item["template"], f"{label}.template", 2)
    assert isinstance(item["mutable"], bool), f"{label}.mutable must be boolean"
    string(item["purpose"], f"{label}.purpose", 8)
    if "authority" in item:
        string(item["authority"], f"{label}.authority", 3)
    if "currentness" in item:
        string(item["currentness"], f"{label}.currentness", 8)
    return item


def validate_profile_parameters(registry: dict) -> None:
    contract = exact_keys(
        registry["profile_parameters"],
        {"required", "resolution_order", "fields", "composition"},
        "profile_parameters",
    )
    assert contract["required"] == PROFILE_PARAMETERS
    assert isinstance(contract["resolution_order"], list) and len(contract["resolution_order"]) >= 3
    fields = exact_keys(contract["fields"], set(PROFILE_PARAMETERS), "profile_parameters.fields")
    expected_types = {"os": "enum", "user": "string", "onedrive_enabled": "boolean", "desktop_dev_root": "path"}
    for name, expected_type in expected_types.items():
        field = exact_keys(fields[name], {"type", "source", "purpose"}, f"profile_parameters.fields.{name}", {"allowed"})
        assert field["type"] == expected_type
        string(field["source"], f"{name}.source", 8)
        string(field["purpose"], f"{name}.purpose", 8)
    assert fields["os"]["allowed"] == ["windows", "linux", "macos"]
    composition = exact_keys(contract["composition"], {"canonical_development_checkout", "identity"}, "profile_parameters.composition")
    assert "{desktop_dev_root}" in composition["canonical_development_checkout"]
    for token in ("{os}", "{user}", "{onedrive_enabled}", "{desktop_dev_root}"):
        assert token in composition["identity"], f"profile identity missing {token}"


def validate_registry_shape(registry: dict, schema: dict) -> None:
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"] == "sas-canonical-path-registry/v1"
    top = {
        "schema_version", "repository", "default_profile", "policy", "profile_parameters",
        "proof_states", "profiles", "consumers", "operator_command_safety", "proof_ceiling",
    }
    assert set(schema["required"]) == top
    exact_keys(registry, top, "canonical path registry")
    assert registry["schema_version"] == "sas-canonical-path-registry/v1"
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    string(registry["default_profile"], "default_profile")
    string(registry["proof_ceiling"], "proof_ceiling", 24)

    policy_keys = {
        "remote_main_contains_sha_is_not_workstation_deployment_proof",
        "canonical_development_checkout_must_be_unique",
        "second_mutable_clone_is_forbidden",
        "preserve_unique_or_dirty_work",
        "parallel_writers_use_isolated_worktrees",
        "ephemeral_acquisition_checkout_never_becomes_canonical_by_existence",
        "production_use_path_requires_independent_currentness_proof",
        "operator_entrypoint_requires_independent_observation_proof",
        "profile_parameters_are_independent",
        "onedrive_toggle_does_not_choose_desktop_location",
        "desktop_dev_root_is_authoritative",
        "user_identity_is_runtime_data_not_tracked_fixture",
    }
    policy = exact_keys(registry["policy"], policy_keys, "policy")
    assert all(policy[key] is True for key in policy_keys)
    validate_profile_parameters(registry)

    proofs = registry["proof_states"]
    assert isinstance(proofs, list) and len(proofs) == 4
    proof_ids = []
    for index, proof in enumerate(proofs):
        item = exact_keys(proof, {"id", "proves", "does_not_prove"}, f"proof_states[{index}]")
        proof_ids.append(string(item["id"], f"proof_states[{index}].id"))
        string(item["proves"], f"proof_states[{index}].proves", 12)
        string(item["does_not_prove"], f"proof_states[{index}].does_not_prove", 12)
    assert set(proof_ids) == {
        "remote_default_contains_sha", "canonical_development_checkout_current",
        "production_use_path_current", "operator_entrypoint_observes_current",
    }

    profiles = registry["profiles"]
    assert isinstance(profiles, list) and len(profiles) >= 4
    ids: set[str] = set()
    for index, profile in enumerate(profiles):
        item = exact_keys(
            profile,
            {"id", "platform", "purpose", "required_profile_parameters", "canonical_development_checkout",
             "production_use_path", "temporary_worktree_root", "ephemeral_acquisition_patterns", "real_operator_entrypoint"},
            f"profiles[{index}]",
        )
        profile_id = string(item["id"], f"profiles[{index}].id")
        assert re.fullmatch(r"[a-z0-9][a-z0-9-]+", profile_id)
        assert profile_id not in ids
        ids.add(profile_id)
        assert item["platform"] in PLATFORMS
        assert item["required_profile_parameters"] == PROFILE_PARAMETERS
        dev = validate_path_record(item["canonical_development_checkout"], f"profiles[{index}].canonical_development_checkout")
        assert "{desktop_dev_root}" in dev["template"]
        temp = validate_path_record(item["temporary_worktree_root"], f"profiles[{index}].temporary_worktree_root")
        assert dev["template"] != temp["template"]
        production = item["production_use_path"]
        assert isinstance(production, dict) and isinstance(production.get("applicable"), bool)
        if production["applicable"]:
            exact_keys(production, {"applicable", "template", "mutable", "purpose", "currentness"}, f"profiles[{index}].production_use_path")
        else:
            exact_keys(production, {"applicable", "reason"}, f"profiles[{index}].production_use_path")
        patterns = item["ephemeral_acquisition_patterns"]
        assert isinstance(patterns, list) and patterns
        entrypoint = item["real_operator_entrypoint"]
        assert isinstance(entrypoint, dict) and len(entrypoint) >= 2

    assert {"windows-development", "windows-admin-box", "linux-development", "macos-development"} <= ids
    assert registry["default_profile"] in ids


def main() -> int:
    registry = load(REGISTRY)
    schema = load(SCHEMA)
    validate_registry_shape(registry, schema)
    profiles = {item["id"]: item for item in registry["profiles"]}

    for profile_id in ("windows-development", "windows-admin-box"):
        profile = profiles[profile_id]
        assert profile["platform"] == "windows"
        assert profile["canonical_development_checkout"]["template"] == "{desktop_dev_root}\\SysAdminSuite"
        assert profile["temporary_worktree_root"]["template"] == "%LOCALAPPDATA%\\SysAdminSuite\\worktrees"
        assert any("closeout-entry-*" in item for item in profile["ephemeral_acquisition_patterns"])
    for profile_id, platform in (("linux-development", "linux"), ("macos-development", "macos")):
        profile = profiles[profile_id]
        assert profile["platform"] == platform
        assert profile["canonical_development_checkout"]["template"] == "{desktop_dev_root}/SysAdminSuite"
        assert profile["production_use_path"]["applicable"] is False

    admin = profiles["windows-admin-box"]
    assert admin["production_use_path"]["template"] == "C:\\SASAL"
    assert admin["real_operator_entrypoint"]["authority"] == "harness/api/operator-execution-route-registry.json"
    assert admin["real_operator_entrypoint"]["production_runtime_entrypoint"] == "C:\\SASAL\\Bootstrap-SysAdminSuiteAutoLogon.cmd"

    consumers = set(registry["consumers"])
    expected_consumers = {
        "harness/workflows/fresh-agent-intake.yaml",
        "harness/workflows/repository-freshness-before-launch.yaml",
        "harness/workflows/operator-execution-route.yaml",
        "harness/skills/canonical-path-resolution/SKILL.md",
        "harness/maps/CANONICAL_PATH_MAP.md",
        "harness/reports/CANONICAL_PATH_STATUS.md",
        "scripts/validate-sysadmin-harness.ps1",
        ".github/workflows/one-command-harness-proof.yml",
    }
    assert expected_consumers <= consumers
    for relative in expected_consumers:
        assert (ROOT / relative).is_file(), f"canonical path consumer missing: {relative}"

    workflow = read(WORKFLOW)
    for marker in (
        "workflow_id: canonical-path-resolution", "profile parameters", "onedrive_enabled", "desktop_dev_root",
        "never derive desktop_dev_root from onedrive_enabled", "ephemeral acquisition checkout never becomes canonical",
        "remote_default_contains_sha", "canonical_development_checkout_current", "production_use_path_current",
        "operator_entrypoint_observes_current", "one paste block",
    ):
        assert marker in workflow, f"canonical path workflow missing: {marker}"

    for text, marker in (
        (read(FRESH), "harness/api/canonical-path-registry.json"),
        (read(FRESH), "harness/workflows/canonical-path-resolution.yaml"),
        (read(FRESHNESS), "harness/api/canonical-path-registry.json"),
        (read(ROUTE), "harness/api/canonical-path-registry.json"),
    ):
        assert marker in text, f"canonical path consumer not wired: {marker}"

    skill = read(SKILL)
    for marker in (
        "`os`, `user`, `onedrive_enabled`, and `desktop_dev_root`",
        "OneDrive toggle never chooses the Desktop path",
        "entire construct in one copy/paste block",
        "second submission attempts to invoke a command named `else`",
        "remote default contains SHA", "production/use path current",
    ):
        assert marker in skill, f"canonical path skill missing: {marker}"

    map_text = read(MAP)
    for marker in (
        "desktop_dev_root", "onedrive_enabled", "{desktop_dev_root}\\SysAdminSuite",
        "%LOCALAPPDATA%\\SysAdminSuite\\worktrees", "C:\\SASAL", "closeout-entry-*", "standalone `else`",
    ):
        assert marker in map_text, f"canonical path map missing: {marker}"
    report = read(REPORT)
    for marker in (
        "one machine-readable path owner", "four independent user profile parameters",
        "four independent proof states", "standalone later `else`", "PASS: canonical path harness contracts",
    ):
        assert marker in report, f"canonical path report missing: {marker}"

    one_command = read(ONE_COMMAND)
    for marker in ("harness/api/canonical-path-registry.json", "onedrive_enabled", "desktop_dev_root", "canonical path profile"):
        assert marker in one_command, f"one-command harness proof missing canonical profile seam: {marker}"
    one_command_ci = read(ONE_COMMAND_CI)
    for marker in ("scripts/Invoke-SasVmDryRunHarnessProof.ps1", "harness/api/canonical-path-registry.json", "harness/validators/validate-canonical-path-contracts.py"):
        assert marker in one_command_ci, f"one-command CI missing canonical path dependency: {marker}"

    pre_commit = read(PRE_COMMIT)
    assert "validate-canonical-path-contracts.py" in pre_commit
    assert "test_canonical_path_harness_completeness.py" in pre_commit
    pre_push = read(PRE_PUSH)
    assert "has_canonical_path=0" in pre_push
    assert "git worktree add --detach --quiet \"$wt\" \"$commit\"" in pre_push
    assert "python3 harness/validators/validate-canonical-path-contracts.py" in pre_push
    assert "python3 Tests/survey/test_canonical_path_harness_completeness.py" in pre_push
    prefix = pre_push.split("validate_pushed_tip()", 1)[0]
    assert "validate-canonical-path-contracts.py" not in prefix
    assert "test_canonical_path_harness_completeness.py" not in prefix

    ci = read(CI)
    for marker in ("Canonical Path Contracts", "validate-canonical-path-contracts.py", "test_canonical_path_harness_completeness.py", "test_operational_harness_completeness_contracts.py", "git diff --check"):
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
