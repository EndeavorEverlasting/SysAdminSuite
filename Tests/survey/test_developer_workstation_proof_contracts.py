#!/usr/bin/env python3
"""Contracts for the 22-journey persistent-workstation fixture E2E."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
PROOF_SCHEMA=ROOT/"schemas/harness/developer-workstation-proof.schema.json"
CATALOG=ROOT/"harness/e2e/e2e-profiles.json"
RUNNER=ROOT/"scripts/Invoke-SasWorkstationE2E.py"
WORKFLOW=ROOT/".github/workflows/developer-workstation-e2e-proof.yml"
REPORT=ROOT/"docs/DEVELOPER_WORKSTATION_E2E_PROOF_MERGE_READINESS.md"


def load(path):return json.loads(path.read_text(encoding="utf-8-sig"))


def runner_module():
    spec=importlib.util.spec_from_file_location("sas_workstation_e2e",RUNNER);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


def test_proof_schema_locks_fixture_ceiling() -> None:
    schema=load(PROOF_SCHEMA);assert schema["$id"]=="schemas/harness/developer-workstation-proof.schema.json"
    assert schema["properties"]["schema_version"]["const"]=="sas-developer-workstation-proof/v2"
    proof=schema["properties"]["proof"]["properties"]
    assert proof["fixture"]["const"] is True
    for name in ("live_runtime","behavior_observed","persistence_observed","agent_interaction_observed","operator_accepted"):assert proof[name]["const"] is False


def test_profile_has_exact_required_22_journeys() -> None:
    catalog=load(CATALOG);profiles={item["id"]:item for item in catalog["profiles"]};profile=profiles["developer-workstation-persistent-e2e-v2"]
    module=runner_module();assert len(profile["journey_ids"])==22
    assert set(profile["journey_ids"])==set(module.JOURNEYS)


def test_catalog_journeys_use_fixture_only_python_runner() -> None:
    catalog=load(CATALOG);journeys={item["id"]:item for item in catalog["journeys"]};ids={item for item in next(p for p in catalog["profiles"] if p["id"]=="developer-workstation-persistent-e2e-v2")["journey_ids"]}
    for journey_id in ids:
        item=journeys[journey_id]
        assert item["script"]=="scripts/Invoke-SasWorkstationE2E.py"
        assert item["network_scope"]=="none" and item["target_mutation"] is False and item["required"] is True


def test_public_entrypoint_and_idempotent_proof_execute() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp)
        for journey in ("workstation-native-linux-success","workstation-unsupported-mac-v2"):
            completed=subprocess.run([sys.executable,str(RUNNER),"--journey-id",journey,"--output-root",str(root/journey)],cwd=ROOT,capture_output=True,text=True,timeout=60)
            assert completed.returncode==0,completed.stderr
            proof=load(root/journey/"proof.json")
            assert proof["status"]=="PASS" and proof["artifacts_validated"] and proof["idempotent_rerun"]
            assert proof["public_entrypoint"]=="scripts/Invoke-SasDeveloperWorkstation.py"
            try:import jsonschema
            except ImportError:pass
            else:jsonschema.Draft202012Validator(load(PROOF_SCHEMA)).validate(proof)


def test_persistence_is_only_simulated() -> None:
    text=RUNNER.read_text(encoding="utf-8")
    assert 'state["gui_launched"]=False' in text
    assert '"persistence_observed":False' in text
    assert "wsl --terminate" not in text.lower() and "provider" not in text.lower()
    assert "Fixture GUI ownership was removed" in text


def test_windows_and_linux_ci_are_platform_bounded() -> None:
    workflow=WORKFLOW.read_text(encoding="utf-8")
    assert "windows-latest" in workflow and "ubuntu-latest" in workflow
    assert "--platform-filter windows" in workflow and "--platform-filter linux" in workflow
    assert "developer-workstation-persistent-e2e-v2" in workflow


def test_merge_readiness_report_is_honest() -> None:
    report=REPORT.read_text(encoding="utf-8")
    assert "22 / 22" in report and "fixture" in report.lower()
    assert "not live persistence" in report.lower()
    assert "native Linux desktop" in report
    assert "operator acceptance" in report.lower()
    assert "100% complete and merge-ready" not in report


if __name__=="__main__":
    tests=[value for name,value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:test()
    print(f"PASS: {len(tests)} developer workstation proof contract groups")
