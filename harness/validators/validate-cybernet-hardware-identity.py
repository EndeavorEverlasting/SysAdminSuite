#!/usr/bin/env python3
"""Validate the Cybernet hardware-identity harness and its anti-misclassification contract."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

try:
    import jsonschema  # type: ignore
except ImportError:
    jsonschema = None

ROOT = Path(__file__).resolve().parents[2]

REGISTRY = ROOT / "harness/api/cybernet-hardware-identity-artifact-registry.json"
SCHEMA = ROOT / "schemas/harness/cybernet-hardware-identity-artifact-registry.schema.json"
MAP = ROOT / "harness/maps/CYBERNET_HARDWARE_IDENTITY_MAP.md"
WORKFLOW = ROOT / "harness/workflows/cybernet-hardware-identity-discovery.yaml"
SKILL = ROOT / "harness/skills/cybernet-hardware-identity/SKILL.md"
REPORT = ROOT / "harness/reports/CYBERNET_HARDWARE_IDENTITY_STATUS.md"
TEST = ROOT / "Tests/survey/test_cybernet_hardware_identity_harness_completeness.py"
CI = ROOT / ".github/workflows/cybernet-hardware-identity-harness.yml"
HARNESS_README = ROOT / "harness/README.md"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"

NETWORK_PREFLIGHT = ROOT / "survey/sas-network-preflight.ps1"
BASH_NETWORK_PREFLIGHT = ROOT / "bash/transport/sas-network-preflight.sh"
WORKSTATION_IDENTITY = ROOT / "bash/transport/sas-workstation-identity.sh"
WMI_IDENTITY = ROOT / "bash/transport/sas-wmi-identity.sh"
LOCAL_MODEL_INFO = ROOT / "QRTasks/Get-ModelInfo.ps1"
CYBERNET_PROFILE = ROOT / "Config/cybernet-client-preferences.json"
GOVERNANCE = ROOT / "AGENTS.md"

COMPONENTS = (
    REGISTRY, SCHEMA, MAP, WORKFLOW, SKILL, REPORT, TEST, CI,
    HARNESS_README, PRE_COMMIT, PRE_PUSH,
)

RUNTIME_TRUTH = (
    NETWORK_PREFLIGHT, BASH_NETWORK_PREFLIGHT, WORKSTATION_IDENTITY,
    WMI_IDENTITY, LOCAL_MODEL_INFO, CYBERNET_PROFILE, GOVERNANCE,
)


def read(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"missing Cybernet hardware-identity surface: {path.relative_to(ROOT).as_posix()}")
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def assert_tracked(path: Path) -> None:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"Cybernet hardware-identity surface is not tracked: {path.relative_to(ROOT).as_posix()}")


def require_markers(path: Path, markers: tuple[str, ...]) -> None:
    text = read(path)
    for marker in markers:
        assert marker in text, f"{path.relative_to(ROOT)} missing marker: {marker}"


def main() -> None:
    for path in COMPONENTS + RUNTIME_TRUTH:
        read(path)
    for path in COMPONENTS:
        assert_tracked(path)

    data = load(REGISTRY)
    schema = load(SCHEMA)
    assert data["schema_version"] == "sas-cybernet-hardware-identity-artifact-registry/v1"
    assert data["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["properties"]["schema_version"]["const"] == data["schema_version"]
    if jsonschema is not None:
        jsonschema.Draft202012Validator(schema).validate(data)
        print("PASS: declared Draft 2020-12 Cybernet hardware-identity registry schema")
    else:
        print("PASS: dependency-free Cybernet hardware-identity registry shape (jsonschema unavailable locally)")

    policy = data["identity_policy"]
    assert policy["confirmation_requires"] == [
        "observed_serial", "observed_model", "approved_hardware_reference_match"
    ]
    for signal in (
        "hostname_convention", "software_footprint", "software_absence",
        "active_directory_object", "dns_resolution", "icmp_reachability",
        "open_tcp_port", "subnet_or_site_inference",
    ):
        assert signal in policy["non_authoritative_signals"], f"missing non-authoritative signal: {signal}"
    assert policy["software_absence_disqualifies"] is False
    assert policy["hostname_convention_confirms"] is False
    assert policy["reachability_confirms"] is False
    assert policy["missing_model_action"] == "IDENTITY_INCOMPLETE"
    assert policy["missing_serial_action"] == "IDENTITY_INCOMPLETE"
    assert policy["conflicting_identity_action"] == "BLOCK_PROFILE_SELECTION"
    assert policy["confirmed_non_cybernet_action"] == "KEEP_AS_KNOWN_DEVICE_EXCLUDE_FROM_CYBERNET_TARGETS"

    artifacts = data["artifact_types"]
    ids = [item["id"] for item in artifacts]
    assert len(ids) == len(set(ids)), "duplicate Cybernet hardware-identity artifact id"
    by_id = {item["id"]: item for item in artifacts}
    assert by_id["candidate-network-preflight"]["identity_fields"] == {"serial": False, "model": False}
    assert by_id["workstation-identity"]["identity_fields"] == {"serial": True, "model": False}
    assert by_id["local-model-identity"]["identity_fields"] == {"serial": True, "model": True}
    assert by_id["cybernet-hardware-decision"]["tracking"] == "untracked"
    assert by_id["cybernet-hardware-identity-status"]["tracking"] == "tracked"

    workstation = read(WORKSTATION_IDENTITY)
    assert "ObservedSerial" in workstation
    assert "ObservedModel" not in workstation, "validator assumptions changed: workstation identity now emits model"
    wmi = read(WMI_IDENTITY)
    assert "ObservedSerial" in wmi
    assert "ObservedModel" not in wmi, "validator assumptions changed: WMI identity now emits model"
    local_model = read(LOCAL_MODEL_INFO)
    for marker in ("Manufacturer", "Model", "BIOSSerial", "Win32_ComputerSystem", "Win32_BIOS"):
        assert marker in local_model, f"local model identity source missing marker: {marker}"

    profile = load(CYBERNET_PROFILE)
    assert profile["profile_id"] == "cybernet-clinical-workstation-default"
    assert profile["software"]["package_count"] == 6
    assert profile["software"]["autologon_must_be_last"] is True

    governance = read(GOVERNANCE)
    assert "Establish the equipment profile before configuration or package selection." in governance
    assert "Unknown, ambiguous, conflicting, or unsupported profile evidence fails closed to read-only review." in governance

    require_markers(MAP, (
        "# Cybernet Hardware Identity Map",
        "Serial + model",
        "Software footprint is not identity",
        "hostname convention",
        "IDENTITY_INCOMPLETE",
        "CONFIRMED_NON_CYBERNET",
        "CONFIRMED_CYBERNET",
    ))
    require_markers(WORKFLOW, (
        "workflow_id: cybernet-hardware-identity-discovery",
        "target_mutation: false",
        "software footprint is non-authoritative",
        "require observed serial and observed model",
        "IDENTITY_INCOMPLETE",
        "CONFIRMED_NON_CYBERNET",
        "CONFIRMED_CYBERNET",
        "load Config/cybernet-client-preferences.json only after CONFIRMED_CYBERNET",
    ))
    require_markers(SKILL, (
        "# Cybernet Hardware Identity Skill",
        "Software presence or absence never confirms or disqualifies a Cybernet",
        "Serial and model are both required",
        "approved hardware reference",
        "CONFIRMED_CYBERNET",
        "KEEP_AS_KNOWN_DEVICE_EXCLUDE_FROM_CYBERNET_TARGETS",
    ))
    require_markers(REPORT, (
        "# Cybernet Hardware Identity Status",
        "WORKING",
        "KNOWN GAP",
        "software footprint",
        "serial but not model",
        "QRTasks/Get-ModelInfo.ps1",
        "Proof ceiling",
    ))
    require_markers(HARNESS_README, (
        "Cybernet hardware identity",
        "cybernet-hardware-identity-discovery.yaml",
        "validate-cybernet-hardware-identity.py",
        "Software footprint, hostname convention, AD presence, and reachability are candidate signals",
    ))
    require_markers(PRE_COMMIT, ("validate-cybernet-hardware-identity.py",))
    require_markers(PRE_PUSH, (
        "validate-cybernet-hardware-identity.py",
        "test_cybernet_hardware_identity_harness_completeness.py",
    ))
    require_markers(CI, (
        "name: Cybernet hardware identity harness",
        "validate-cybernet-hardware-identity.py",
        "test_cybernet_hardware_identity_harness_completeness.py",
        "git diff --check",
    ))

    for path in (MAP, WORKFLOW, SKILL, REPORT, REGISTRY):
        text = read(path)
        assert not re.search(r"\bW[A-Z]{2}\d{3}OPR\d+\b", text), (
            f"live-looking target hostname must not be committed in {path.relative_to(ROOT)}"
        )

    print("PASS: Cybernet hardware identity requires serial + model + approved reference")
    print("PASS: hostname/software/AD/network signals remain candidate-only")
    print("PASS: current serial-only remote adapters cannot overclaim CONFIRMED_CYBERNET")
    print("PASS: Cybernet hardware-identity map/workflow/registry/skill/report/hooks/CI are wired")


if __name__ == "__main__":
    main()
