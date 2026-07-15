#!/usr/bin/env python3
"""Contracts for the version-pinned external AgentSwitchboard adapter."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "scripts/Invoke-SasAgentSwitchboard.py"


def request(path: Path, platform="windows", domain="windows-wsl", agents=None, bridge=False) -> None:
    value = {"schema_version":"agentswitchboard-invocation/v2","platform":platform,"execution_domain":domain,
             "requested_agents":agents or ["opencode","agy","goose"],"operation":"inventory","install_missing_only":True,
             "native_preference":True,"bridge_permission":bridge,"posture":"fixture","fixture_scenario":"native"}
    if domain == "windows-wsl": value["distro"] = "Ubuntu"
    path.write_text(json.dumps(value), encoding="utf-8")


def run(args):
    return subprocess.run([sys.executable, str(ADAPTER), *args], cwd=ROOT, capture_output=True, text=True, timeout=20)


def test_versions_and_structured_process_boundary() -> None:
    text = ADAPTER.read_text(encoding="utf-8")
    assert 'REQUEST_VERSION = "agentswitchboard-invocation/v2"' in text
    assert 'RESULT_VERSION = "agentswitchboard-result/v2"' in text
    assert "subprocess.run(" in text and "timeout=args.timeout_seconds" in text
    assert "shell=True" not in text and "Invoke-Expression" not in text


def test_valid_native_and_bridge_fixtures() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp); req=root/"request.json"; out=root/"result.json"
        request(req)
        result=run(["--request",str(req),"--output",str(out),"--fixture-result","native"])
        assert result.returncode==0, result.stderr
        assert json.loads(out.read_text())["agents"]["opencode"]["selected_backend"]=="native"
        request(req,bridge=True)
        result=run(["--request",str(req),"--output",str(out),"--fixture-result","bridge"])
        assert result.returncode==0 and json.loads(out.read_text())["agents"]["goose"]["selected_backend"]=="bridge"


def test_domain_and_bridge_truth_fail_closed() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp); req=root/"request.json"; out=root/"result.json"
        request(req, platform="linux", domain="linux-native")
        mismatch=run(["--request",str(req),"--output",str(out),"--fixture-result","native"])
        assert mismatch.returncode==4 and "execution-domain mismatch" in mismatch.stderr
        request(req, bridge=False)
        bridge=run(["--request",str(req),"--output",str(out),"--fixture-result","bridge"])
        assert bridge.returncode==4


def test_authentication_required_is_data_not_automation() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp); req=root/"request.json"; out=root/"result.json"
        request(req,platform="linux",domain="linux-native",agents=["opencode"])
        result=run(["--request",str(req),"--output",str(out),"--fixture-result","authentication-required"])
        assert result.returncode==0
        row=json.loads(out.read_text())["agents"]["opencode"]
        assert row["authentication_readiness"]=="required" and row["action_required"] is True
        assert "oauth" not in ADAPTER.read_text(encoding="utf-8").lower()


def test_malformed_and_timeout_are_bounded() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp); req=root/"request.json"; out=root/"result.json"; request(req)
        malformed=run(["--request",str(req),"--output",str(out),"--fixture-result","malformed"])
        assert malformed.returncode==4 and not out.exists()
        timeout=run(["--request",str(req),"--output",str(out),"--simulate-timeout"])
        assert timeout.returncode==124 and "timed out" in timeout.stderr


if __name__=="__main__":
    tests=[value for name,value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:test()
    print(f"PASS: {len(tests)} AgentSwitchboard adapter contract groups")
