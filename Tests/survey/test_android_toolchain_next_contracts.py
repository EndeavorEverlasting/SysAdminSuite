#!/usr/bin/env python3
"""Contracts for read-only Android toolchain Next projection.

Synthetic/fixture only. Does not claim Admin Box install, SAS qualification,
or device contact. Inventory SUCCESS must never be treated as operational ready.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE_ROOT = Path(os.environ.get("SAS_ANDROID_TOOLCHAIN_ENGINE_ROOT", str(ROOT)))
SCRIPT = ENGINE_ROOT / "scripts/Invoke-SasAndroidToolchain.ps1"
SCHEMA = ENGINE_ROOT / "schemas/harness/android-toolchain-result.schema.json"
PROFILE = ROOT / "Config/android-adminbox-toolchain-profile.json"
FIXTURES = ROOT / "Tests/Fixtures/android-toolchain-next"
TRUSTBRIDGE_FIXTURES = ROOT / "Tests/Fixtures/android-trustbridge"
PIN_CATALOG = ROOT / "configs/android-provider/sas-platform-tools-archive-pins.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def invoke_next(fixture: Path, role: str = "adminbox_reference"):
    shell = shutil.which("pwsh")
    assert shell, "PowerShell 7 required for executable fixture gate"
    with tempfile.TemporaryDirectory(prefix="sas-android-next-") as output:
        command = [
            shell,
            "-NoProfile",
            "-File",
            str(SCRIPT),
            "-FixturePath",
            str(fixture),
            "-Operation",
            "Next",
            "-NodeRole",
            role,
            "-OutputRoot",
            output,
        ]
        process = subprocess.run(command, capture_output=True, text=True, timeout=60)
        receipts = list(Path(output).glob("receipt-*.json"))
        assert len(receipts) == 1, (process.returncode, process.stdout, process.stderr)
        packets = list((Path(output) / "approval-packets").glob("*.json")) if (Path(output) / "approval-packets").is_dir() else []
        return process.returncode, load(receipts[0]), packets, process.stdout + process.stderr


def test_schema_includes_bootstrap_and_next():
    schema = load(SCHEMA)
    assert set(schema["properties"]["operation"]["enum"]) >= {
        "Inventory",
        "Plan",
        "Apply",
        "Verify",
        "Repair",
        "Bootstrap",
        "Next",
    }
    capability = schema["properties"]["capability"]
    assert "null" in capability["type"] or capability["type"] == ["object", "null"]
    states = capability["properties"]
    assert set(states["developer_stack"]["enum"]) == {
        "VERIFIED",
        "NEEDS_INSTALL",
        "VERIFY_REQUIRED",
        "POLICY_BLOCKED",
        "UNKNOWN",
    }
    assert set(states["sas_adb"]["enum"]) == {
        "QUALIFIED",
        "NEEDS_APPROVAL",
        "NEEDS_PREPARE",
        "VERIFY_REQUIRED",
        "UNKNOWN",
    }


def test_engine_validate_set_and_next_is_readonly():
    text = SCRIPT.read_text(encoding="utf-8-sig")
    assert "'Next'" in text
    assert "ValidateSet('Inventory','Plan','Apply','Verify','Repair','Bootstrap','Next')" in text.replace(" ", "") or (
        "Bootstrap','Next'" in text
    )
    assert "if($Operation -eq 'Next')" in text
    # Next must not authorize mutation switches.
    next_block_start = text.index("if($Operation -eq 'Next')")
    next_block = text[next_block_start : text.index("if($Operation -eq 'Bootstrap')", next_block_start)]
    assert "MutationAuthorized" not in next_block
    assert "winget" not in next_block.lower()
    assert "Fetch-Installers" not in next_block
    assert "prepare" not in next_block.lower() or "approval" in next_block.lower()


def test_does_not_duplicate_trustbridge_fixture_catalog():
    assert TRUSTBRIDGE_FIXTURES.is_dir()
    assert len(list(TRUSTBRIDGE_FIXTURES.glob("*.fixture.json"))) == 19
    assert FIXTURES.is_dir()
    names = {p.name for p in FIXTURES.glob("*.fixture.json")}
    assert "missing-cli-studio-no-authority.fixture.json" in names


def test_next_fixture_projection_and_packets():
    for fixture in sorted(FIXTURES.glob("*.fixture.json")):
        expected = load(fixture)["test_expectation"]
        code, receipt, packets, terminal = invoke_next(fixture, expected["node_role"])
        assert code == 0, (fixture.name, receipt)
        assert receipt["result"] == "SUCCESS"
        assert receipt["operation"] == "Next"
        assert receipt["proof"] == ["FIXTURE_ONLY"] or "INSPECTION_COMPLETE" in receipt["proof"]
        # Fixture path forces FIXTURE_ONLY proof overwrite after Next proof — accept either contract.
        capability = receipt["capability"]
        assert capability["developer_stack"] == expected["developer_stack"], fixture.name
        assert capability["sas_adb"] == expected["sas_adb"], fixture.name
        assert capability["inspection"] == expected["inspection"]
        assert capability["operational_readiness"] == expected["operational_readiness"]
        assert capability["operational_readiness"] != "PROVEN" or (
            capability["developer_stack"] == "VERIFIED" and capability["sas_adb"] == "QUALIFIED"
        )
        action_ids = [action["action_id"] for action in receipt["actions"]]
        for action_id in expected["first_action_ids"]:
            assert action_id in action_ids, (fixture.name, action_ids)
        # Deterministic ordering: approval packet actions precede gated mutations.
        if "PREPARE_HOST_PROFILE_APPROVAL_PACKET" in action_ids and "APPLY_DEVELOPER_TOOLCHAIN" in action_ids:
            assert action_ids.index("PREPARE_HOST_PROFILE_APPROVAL_PACKET") < action_ids.index(
                "APPLY_DEVELOPER_TOOLCHAIN"
            )
        if "PREPARE_ARCHIVE_PIN_APPROVAL_PACKET" in action_ids and "BOOTSTRAP_SAS_PLATFORM_TOOLS" in action_ids:
            assert action_ids.index("PREPARE_ARCHIVE_PIN_APPROVAL_PACKET") < action_ids.index(
                "BOOTSTRAP_SAS_PLATFORM_TOOLS"
            )
        for action in receipt["actions"]:
            for key in (
                "action_id",
                "allowed_now",
                "requires_authority",
                "preconditions",
                "proof_ref",
                "command_owner",
                "why_blocked",
            ):
                assert key in action, action
        assert set(expected["reasons_subset"]) <= set(receipt["reason_codes"]), (
            fixture.name,
            receipt["reason_codes"],
        )
        assert "Developer toolchain:" in terminal
        assert "Operational readiness:" in terminal
        assert "C:\\Users" not in terminal
        try:
            import jsonschema
        except ImportError:
            pass
        else:
            jsonschema.Draft202012Validator(load(SCHEMA)).validate(receipt)
        # Incomplete authority drafts packets; resolved host + blocked pin drafts pin packet only.
        if expected["developer_stack"] == "NEEDS_INSTALL" and "ADMINBOX_PROFILE_AUTHORITY_REQUIRED" in expected[
            "reasons_subset"
        ] or "ADMINBOX_PROFILE_AUTHORITY_INVALID" in expected["reasons_subset"]:
            assert any(path.name.startswith("host-profile") for path in packets), fixture.name
        if expected["sas_adb"] == "NEEDS_APPROVAL":
            assert any(path.name.startswith("platform-tools") for path in packets), fixture.name


def test_inventory_success_is_not_operational_ready():
    fixture = FIXTURES / "missing-cli-studio-no-authority.fixture.json"
    shell = shutil.which("pwsh")
    with tempfile.TemporaryDirectory(prefix="sas-inv-vs-next-") as output:
        inv = subprocess.run(
            [
                shell,
                "-NoProfile",
                "-File",
                str(SCRIPT),
                "-FixturePath",
                str(fixture),
                "-Operation",
                "Inventory",
                "-NodeRole",
                "adminbox_reference",
                "-OutputRoot",
                output,
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        inv_receipt = load(next(Path(output).glob("receipt-*.json")))
    assert inv.returncode == 0
    assert inv_receipt["result"] == "SUCCESS"
    assert "MISSING_ANDROID_CLI" in inv_receipt["reason_codes"]
    code, next_receipt, _, _ = invoke_next(fixture)
    assert code == 0
    assert next_receipt["result"] == "SUCCESS"
    assert next_receipt["capability"]["operational_readiness"] == "NOT_YET_PROVEN"
    assert next_receipt["capability"]["developer_stack"] == "NEEDS_INSTALL"


def test_next_fixture_cannot_mutate():
    for operation in ("Apply", "Repair", "Bootstrap"):
        shell = shutil.which("pwsh")
        with tempfile.TemporaryDirectory(prefix="sas-next-mut-") as output:
            process = subprocess.run(
                [
                    shell,
                    "-NoProfile",
                    "-File",
                    str(SCRIPT),
                    "-FixturePath",
                    str(FIXTURES / "missing-cli-studio-no-authority.fixture.json"),
                    "-Operation",
                    operation,
                    "-NodeRole",
                    "adminbox_reference",
                    "-OutputRoot",
                    output,
                    "-MutationAuthorized",
                ],
                capture_output=True,
                text=True,
                timeout=60,
            )
            receipt = load(next(Path(output).glob("receipt-*.json")))
        assert process.returncode == 2
        assert "FIXTURE_MUTATION_FORBIDDEN" in receipt["reason_codes"]


def test_pin_catalog_zero_hash_still_blocked():
    catalog = load(PIN_CATALOG)
    for pin in catalog["pins"]:
        assert pin["promotion_status"] == "blocked_pending_independent_sha256_pin"
        assert pin["expected_archive_sha256"] == "0" * 64 or pin["approval_reference"].upper().startswith(
            "PENDING"
        )


def test_adminbox_profile_lists_next():
    profile = load(PROFILE)
    assert "Next" in profile["allowed_operations"]
    assert "Bootstrap" in profile["allowed_operations"]


def test_ptop_next_remains_role_isolated():
    fixture = FIXTURES / "missing-cli-studio-no-authority.fixture.json"
    # Override role expectation: ptop_lab must not silently become adminbox.
    data = load(fixture)
    data["next_projection"]["host_profile_reason"] = "PTOP_PROFILE_AUTHORITY_REQUIRED"
    with tempfile.TemporaryDirectory(prefix="sas-ptop-next-") as directory:
        path = Path(directory) / "ptop-next.fixture.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        code, receipt, _, _ = invoke_next(path, role="ptop_lab")
    assert code == 0
    assert receipt["node_role"] == "ptop_lab"
    assert receipt["capability"]["developer_stack"] == "NEEDS_INSTALL"
    assert "PREPARE_HOST_PROFILE_APPROVAL_PACKET" in [a["action_id"] for a in receipt["actions"]]


if __name__ == "__main__":
    test_schema_includes_bootstrap_and_next()
    test_engine_validate_set_and_next_is_readonly()
    test_does_not_duplicate_trustbridge_fixture_catalog()
    test_next_fixture_projection_and_packets()
    test_inventory_success_is_not_operational_ready()
    test_next_fixture_cannot_mutate()
    test_pin_catalog_zero_hash_still_blocked()
    test_adminbox_profile_lists_next()
    test_ptop_next_remains_role_isolated()
    print("android-toolchain-next-contracts: PASS")
