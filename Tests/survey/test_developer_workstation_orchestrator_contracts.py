#!/usr/bin/env python3
"""One-command fixture contracts for the workstation orchestrator."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
CORE=ROOT/"scripts/Invoke-SasDeveloperWorkstation.py"
SCENARIOS=ROOT/"Tests/Fixtures/developer-workstation-orchestrator/scenarios.json"
RESULT_SCHEMA=ROOT/"schemas/harness/developer-workstation-orchestrator-result.schema.json"
HAS_PWSH=bool(shutil.which("pwsh"))


def invoke(scenario,mode,root,allow=False,launch=False):
    command=[sys.executable,str(CORE),"--fixture-scenario",scenario,"--mode",mode,"--output-root",str(root),"--timeout-seconds","10"]
    if allow:command.append("--allow-target-mutation")
    if launch:command.append("--launch-gui")
    completed=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=40)
    result=json.loads((root/"orchestrator-result.json").read_text(encoding="utf-8"))
    try:
        import jsonschema
    except ImportError:pass
    else:jsonschema.Draft202012Validator(json.loads(RESULT_SCHEMA.read_text())).validate(result)
    return completed,result


def test_modes_entrypoints_and_default() -> None:
    text=CORE.read_text(encoding="utf-8")
    for mode in ("Inventory","Plan","Apply","Start","Status","Stop","Repair","Validate","Rollback"):assert f'"{mode}"' in text
    assert 'default="Inventory"' in text
    for path in (ROOT/"scripts/Invoke-SasDeveloperWorkstation.ps1",ROOT/"scripts/invoke-sas-developer-workstation.sh",ROOT/"Developer-Workstation.cmd"):assert path.is_file()


def test_explicit_apply_gate() -> None:
    with tempfile.TemporaryDirectory() as temp:
        completed,result=invoke("success","Apply",Path(temp))
        assert completed.returncode==0 and result["outcome"]=="ACTION_REQUIRED"
        assert [item["name"] for item in result["steps"]]==["mutation-gate"]


def test_windows_and_linux_composed_success() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp)
        for scenario in ("success","success-linux"):
            if scenario=="success" and not HAS_PWSH:continue
            completed,result=invoke(scenario,"Apply",root/scenario,allow=True,launch=True)
            assert completed.returncode==0,completed.stderr
            assert result["outcome"]=="PASS"
            names=[item["name"] for item in result["steps"]]
            assert names[:2]==["inventory","plan"] and "apply" in names and "start" in names and "status" in names and "agent-readiness" in names
            assert (root/scenario/"artifact-registry.json").is_file() and (root/scenario/"english-summary.txt").is_file()
            assert result["proof"]=={"fixture":True,"live_runtime":False,"behavior_observed":False,"persistence_observed":False,"operator_accepted":False}


def test_required_failure_matrix_classifies_honestly() -> None:
    modes={"partial":"Plan","stale-keepalive":"Status","missing-tmux":"Plan","malformed-lua":"Apply","bridge-only":"Plan","authentication-required":"Plan","nested-tmux":"Start","timeout":"Plan","rollback":"Rollback","unsupported-platform":"Plan"}
    expected={item["id"]:item["expected"] for item in json.loads(SCENARIOS.read_text())["scenarios"]}
    platforms={item["id"]:item["platform"] for item in json.loads(SCENARIOS.read_text())["scenarios"]}
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp)
        for scenario,mode in modes.items():
            if platforms[scenario]=="windows" and not HAS_PWSH:continue
            completed,result=invoke(scenario,mode,root/scenario,allow=mode in {"Apply","Rollback"})
            assert result["outcome"]==expected[scenario],f"{scenario}: {result}"
            if expected[scenario]=="FAIL":assert completed.returncode==1
            else:assert completed.returncode==0


def test_artifact_chain_and_english_classifications() -> None:
    if not HAS_PWSH:return
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp); _,result=invoke("bridge-only","Plan",root)
        registry=json.loads((root/"artifact-registry.json").read_text())
        assert registry["path_class"]=="temporary-fixture" and registry["run_id"]==result["run_id"]
        assert {item["role"] for item in registry["artifacts"]}>={"inventory","plan","agentswitchboard-result","english-summary"}
        english=(root/"english-summary.txt").read_text()
        assert "DEVELOPER WORKSTATION [Windows PowerShell]" in english and "Overall: PARTIAL" in english
        assert all(label in CORE.read_text() or label in (ROOT/"scripts/Render-SasDeveloperWorkstationEnglish.py").read_text() for label in ("PASS","SKIP","FAIL","ACTION_REQUIRED"))


def test_no_fixture_runtime_claims_or_home_paths() -> None:
    combined=CORE.read_text()+SCENARIOS.read_text()
    assert "Cheex" not in combined and "C:\\Users" not in combined
    assert '"live_runtime": False' in combined and '"persistence_observed": False' in combined
    assert "shell=True" not in combined and "automatic authentication" not in combined.lower()


if __name__=="__main__":
    tests=[value for name,value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:test()
    print(f"PASS: {len(tests)} developer workstation orchestrator contract groups")
