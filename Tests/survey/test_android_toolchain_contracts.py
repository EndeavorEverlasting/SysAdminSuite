#!/usr/bin/env python3
"""Bounded synthetic prerequisite and diagnostic propagation tests; no host proof."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE_ROOT = Path(os.environ.get("SAS_ANDROID_TOOLCHAIN_ENGINE_ROOT", str(ROOT)))
FIXTURES = ROOT / "Tests/Fixtures/android-toolchain"
SCRIPT = ENGINE_ROOT / "scripts/Invoke-SasAndroidToolchain.ps1"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def invoke(fixture, operation=None, role=None):
    shell = shutil.which("pwsh")
    assert shell, "PowerShell 7 required for executable fixture gate"
    expectation = load(fixture)["test_expectation"]
    with tempfile.TemporaryDirectory(prefix="sas-android-fixture-") as output:
        command = [shell, "-NoProfile", "-File", str(SCRIPT), "-FixturePath", str(fixture),
                   "-Operation", operation or expectation["operation"], "-NodeRole",
                   role or expectation["node_role"], "-OutputRoot", output]
        process = subprocess.run(command, capture_output=True, text=True, timeout=60)
        receipts = list(Path(output).glob("receipt-*.json"))
        assert len(receipts) == 1, (process.returncode, process.stdout, process.stderr)
        return process.returncode, load(receipts[0])


def test_fixture_privacy_and_coverage():
    required = {"healthy", "missing-jdk", "user-local-alias", "sdk-studio-disagreement",
                "duplicate-adb", "wrong-api", "disk-failure", "network-failure",
                "interrupted-install", "license-required", "elevation-required",
                "emulator-nonboot", "source-hash-missing", "role-mismatch",
                "disconnected-target"}
    assert {p.name.removesuffix(".fixture.json") for p in FIXTURES.glob("*.json")} >= required
    for path in FIXTURES.glob("*.json"):
        data = load(path)
        assert data["synthetic"] is True
        text = path.read_text()
        assert "CheeksMcClappeth" not in text and "C:\\Users" not in text


def test_prerequisites_and_synthetic_observations():
    schema = load(ENGINE_ROOT / "schemas/harness/android-toolchain-result.schema.json")
    for fixture in sorted(FIXTURES.glob("*.fixture.json")):
        expected = load(fixture)["test_expectation"]
        code, receipt = invoke(fixture)
        assert set(expected["reasons"]) <= set(receipt["reason_codes"]), fixture.name
        assert code == (2 if expected["reasons"] else 0), (fixture.name, receipt)
        assert receipt["result"] == ("BLOCK" if expected["reasons"] else "SUCCESS")
        assert set(receipt["proof"]) <= {"FIXTURE_ONLY"}, receipt
        assert receipt["checks"] == [] and receipt["source"] is None
        try:
            import jsonschema
        except ImportError:
            pass
        else:
            jsonschema.Draft202012Validator(schema).validate(receipt)


def test_fixture_cannot_apply_or_repair():
    for operation in ("Apply", "Repair"):
        code, receipt = invoke(FIXTURES / "healthy.fixture.json", operation)
        assert code == 2
        assert "FIXTURE_MUTATION_FORBIDDEN" in receipt["reason_codes"]
        assert not receipt["checks"] and not receipt["proof"]


def test_inventory_is_not_a_runtime_claim():
    code, receipt = invoke(FIXTURES / "missing-jdk.fixture.json", "Inventory")
    assert code == 0
    assert "MISSING_STANDALONE_JDK" in receipt["reason_codes"]
    assert receipt["proof"] == ["FIXTURE_ONLY"]


def test_registry_wiring():
    def by_id(name, collection, key="id"):
        return {row[key]: row for row in load(ROOT / f"harness/api/{name}.json")[collection]}
    command = by_id("harness-command-registry", "commands")["android-toolchain"]
    assert command["source_of_truth"] == "scripts/Invoke-SasAndroidToolchain.ps1"
    artifact = by_id("harness-artifact-registry", "artifacts")["android-toolchain-result"]
    assert artifact["tracked"] is False and artifact["contains_live_data"] is True
    assert artifact["path"].startswith("survey/output/android-toolchain/")
    outcome = by_id("harness-outcome-registry", "contracts", "command_id")["android-toolchain"]
    assert outcome["success_artifact_id"] == "android-toolchain-result"
    assert outcome["failure_outcome"] == "blocked_with_actionable_gate"


if __name__ == "__main__":
    for name, function in sorted(globals().copy().items()):
        if name.startswith("test_") and callable(function):
            function()
            print(f"PASS: {name}")
