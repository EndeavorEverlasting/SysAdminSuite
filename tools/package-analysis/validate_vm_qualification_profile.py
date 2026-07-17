#!/usr/bin/env python3
"""Fail-closed validation for package-specific disposable-VM qualification profiles."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

LOCAL_PATH = re.compile(r"(?i)(?:[A-Za-z]:[\\/]|/(?:home|Users|mnt/c)/|%USERPROFILE%|\$HOME)")
REPO_PATH = re.compile(r"^(?!/)(?!~)(?![A-Za-z]:[\\/])(?!.*\\)(?!.*(?:^|/)\.\.(?:/|$)).+")
SENSITIVE_NAMES = ("pass" + "word", "to" + "ken", "se" + "cret")


class ProfileError(ValueError):
    """Raised when a qualification profile cannot safely authorize VM entry."""


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ProfileError(f"profile_missing:{path}") from exc
    except json.JSONDecodeError as exc:
        raise ProfileError(f"profile_malformed:{exc.msg}") from exc
    if not isinstance(value, dict):
        raise ProfileError("profile_root_must_be_object")
    return value


def walk_strings(value: Any):
    if isinstance(value, dict):
        for item in value.values():
            yield from walk_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk_strings(item)
    elif isinstance(value, str):
        yield value


def require_keys(value: dict[str, Any], expected: set[str], name: str) -> None:
    actual = set(value)
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing:
        raise ProfileError(f"{name}_missing_keys:{','.join(missing)}")
    if extra:
        raise ProfileError(f"{name}_unknown_keys:{','.join(extra)}")


def require_repo_reference(value: str | None, name: str, *, nullable: bool = False) -> None:
    if value is None and nullable:
        return
    if not isinstance(value, str) or not REPO_PATH.fullmatch(value):
        raise ProfileError(f"{name}_must_be_canonical_repo_reference")


def validate(profile: dict[str, Any]) -> str:
    require_keys(profile, {
        "schema_version", "schema_path", "profile_id", "package_family", "package_selector",
        "prerequisite_evidence", "trust_policy", "guest", "execution_contract",
        "acceptance", "rollback", "evidence", "decision", "proof_ceiling",
    }, "profile")
    if profile["schema_version"] != "sas-package-vm-qualification-profile/v1":
        raise ProfileError("schema_version_unsupported")
    if profile["schema_path"] != "schemas/harness/package-vm-qualification-profile.schema.json":
        raise ProfileError("schema_path_mismatch")
    if profile["proof_ceiling"] != "qualification_profile_only_no_vm_or_package_execution":
        raise ProfileError("proof_ceiling_mismatch")

    for value in walk_strings(profile):
        if LOCAL_PATH.search(value):
            raise ProfileError("machine_local_value")
        if any(re.search(rf"(?i){name}\s*[:=]", value) for name in SENSITIVE_NAMES):
            raise ProfileError("sensitive_assignment_value")

    selector = profile["package_selector"]
    require_keys(selector, {"source_sha256", "static_result_reference", "semantic_result_reference", "trust_result_reference"}, "package_selector")
    if not re.fullmatch(r"[A-Fa-f0-9]{64}", selector["source_sha256"]):
        raise ProfileError("source_sha256_invalid")
    require_repo_reference(selector["static_result_reference"], "static_result_reference")
    require_repo_reference(selector["semantic_result_reference"], "semantic_result_reference", nullable=True)
    require_repo_reference(selector["trust_result_reference"], "trust_result_reference", nullable=True)

    prerequisite = profile["prerequisite_evidence"]
    require_keys(prerequisite, {
        "static_analysis_complete", "semantic_analysis_complete", "offline_trust_complete",
        "online_revocation_required_before_pilot", "strong_name_required_if_managed",
        "full_msi_decode_required_if_msi", "exact_sapien_payload_required_if_detected",
    }, "prerequisite_evidence")
    for key in ("online_revocation_required_before_pilot", "strong_name_required_if_managed", "full_msi_decode_required_if_msi", "exact_sapien_payload_required_if_detected"):
        if prerequisite[key] is not True:
            raise ProfileError(f"{key}_must_be_true")

    trust = profile["trust_policy"]
    require_keys(trust, {"package_family_policy_required", "policy_status", "policy_reference"}, "trust_policy")
    if trust["package_family_policy_required"] is not True:
        raise ProfileError("package_family_policy_must_be_required")
    if trust["policy_status"] == "approved":
        require_repo_reference(trust["policy_reference"], "policy_reference")
    elif trust["policy_reference"] is not None:
        raise ProfileError("unapproved_policy_reference_must_be_null")

    guest = profile["guest"]
    require_keys(guest, {
        "provider", "os_family", "architecture", "network_mode", "snapshot_strategy",
        "host_execution_forbidden", "one_package_per_snapshot", "autologon_allowed",
        "shared_clipboard_allowed", "shared_folders_allowed",
    }, "guest")
    for key in ("host_execution_forbidden", "one_package_per_snapshot"):
        if guest[key] is not True:
            raise ProfileError(f"{key}_must_be_true")
    for key in ("autologon_allowed", "shared_clipboard_allowed", "shared_folders_allowed"):
        if guest[key] is not False:
            raise ProfileError(f"{key}_must_be_false")
    if guest["network_mode"] not in {"disconnected", "isolated_allowlist"}:
        raise ProfileError("network_mode_unsafe")

    execution = profile["execution_contract"]
    require_keys(execution, {"installer_type", "supported_arguments_source", "supported_arguments", "reboot_expected", "execution_authorized", "authorization_reference"}, "execution_contract")
    if execution["execution_authorized"]:
        if execution["supported_arguments_source"] == "missing":
            raise ProfileError("authorized_execution_requires_supported_arguments")
        if not isinstance(execution["authorization_reference"], str):
            raise ProfileError("authorized_execution_requires_reference")
    elif execution["authorization_reference"] is not None:
        raise ProfileError("unauthorized_execution_reference_must_be_null")

    acceptance = profile["acceptance"]
    require_keys(acceptance, {"criteria_status", "required_checks"}, "acceptance")
    rollback = profile["rollback"]
    require_keys(rollback, {"mode", "required", "verification_checks"}, "rollback")
    if rollback["required"] is not True:
        raise ProfileError("rollback_or_destroy_must_be_required")
    if set(rollback["verification_checks"]) != {"guest_reverted_or_destroyed", "package_absent_from_host", "host_postflight_clean"}:
        raise ProfileError("rollback_verification_incomplete")

    evidence = profile["evidence"]
    require_keys(evidence, {"output_root_policy", "required_artifacts"}, "evidence")
    if evidence["output_root_policy"] != "gitignored_operator_local":
        raise ProfileError("evidence_must_be_gitignored_operator_local")

    decision = profile["decision"]
    require_keys(decision, {"status", "blockers", "vm_started", "package_executed"}, "decision")
    if decision["vm_started"] is not False or decision["package_executed"] is not False:
        raise ProfileError("profile_cannot_claim_runtime_execution")
    blockers = set(decision["blockers"])
    if len(blockers) != len(decision["blockers"]):
        raise ProfileError("decision_blockers_must_be_unique")

    if profile["package_family"] == "allscripts" and trust["policy_status"] != "approved":
        if not ({"trust_policy_missing", "trust_policy_not_approved"} & blockers):
            raise ProfileError("allscripts_unapproved_policy_must_block")
        if decision["status"] != "blocked":
            raise ProfileError("allscripts_unapproved_policy_cannot_be_ready")

    ready = (
        prerequisite["static_analysis_complete"] and prerequisite["semantic_analysis_complete"] and
        prerequisite["offline_trust_complete"] and trust["policy_status"] == "approved" and
        guest["provider"] != "unselected" and execution["execution_authorized"] and
        acceptance["criteria_status"] == "approved" and not blockers
    )
    if decision["status"] == "ready_for_authorized_vm_run" and not ready:
        raise ProfileError("ready_status_without_complete_gates")
    if decision["status"] == "completed":
        raise ProfileError("completed_status_requires_separate_runtime_result_contract")
    return decision["status"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, type=Path)
    args = parser.parse_args()
    try:
        status = validate(load_json(args.profile))
    except ProfileError as exc:
        print(f"[FAIL] package VM qualification profile - {exc}", file=sys.stderr)
        return 1
    print(f"[PASS] package VM qualification profile - status={status}; no VM or package execution performed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
