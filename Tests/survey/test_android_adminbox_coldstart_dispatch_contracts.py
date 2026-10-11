#!/usr/bin/env python3
"""Contract: Admin Box Android cold-start precedes provider/field readiness.

Static repository validation only. Never interpreted as installation, agent dispatch,
SAS runtime qualification, emulator boot, or physical-device evidence.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATHS = {
    "plan": ROOT / "docs/plans/android-adminbox1-coldstart-bootstrap-p04-20261010.plan.md",
    "handoff": ROOT / "docs/handoff/android-adminbox1-bootstrap-opencode-20261010.md",
    "downstream_plan": ROOT / "docs/plans/android-suite-closeout-p04-20261010.plan.md",
    "downstream_handoff": ROOT / "docs/handoff/android-suite-closeout-agent-20261010.md",
    "dispatch": ROOT / "docs/plans/android-suite-closeout-dispatch.provisional.json",
}


def test_mandatory_bootstrap_and_host_boundary():
    text = {name: path.read_text(encoding="utf-8") for name, path in PATHS.items() if name != "dispatch"}
    for name in ("plan", "handoff"):
        for term in ("Admin Box 1", "OpenCode", "Android CLI", "SDK", "PTop", "DTop",
                     "QUALIFICATION_AUTHORITY_REQUIRED", "adminbox_reference",
                     "--expected-commit", "B1-CONTRACT", "B2-SOURCE", "B3-TESTS",
                     "B4-INTEGRATE", "B5-LIVE-APPLY", "Apply", "Verify"):
            assert term in text[name], (name, term)
    for name in ("downstream_plan", "downstream_handoff"):
        assert "docs/plans/android-adminbox1-coldstart-bootstrap-p04-20261010.plan.md" in text[name]
        assert "docs/handoff/android-adminbox1-bootstrap-opencode-20261010.md" in text[name]
        assert "PTop-only" in text[name], name
    assert "do not" in text["plan"].lower()
    assert "developer" in text["handoff"].lower()
    assert "qualified" in text["plan"].lower()


def test_execution_dependency_graph_and_no_fake_runtime_proof():
    doc = json.loads(PATHS["dispatch"].read_text(encoding="utf-8"))
    assert doc["coordinator"]["expected_machine"] == "Admin Box 1"
    assert doc["coordinator"]["node_role"] == "adminbox_reference"
    assert doc["source_plan"] == "docs/plans/android-adminbox1-coldstart-bootstrap-p04-20261010.plan.md"
    assert doc["handoff"] == "docs/handoff/android-adminbox1-bootstrap-opencode-20261010.md"
    assert doc["observed_parallelism"] is False
    assert doc["expected_parallel_width"] >= 3
    lanes = doc["lanes"]
    ids = [lane["lane_id"] for lane in lanes]
    assert len(ids) == len(set(ids)), "Duplicate dispatch lane"
    required = {"W0-INTAKE", "B1-CONTRACT", "B2-SOURCE", "B3-TESTS",
                "B4-INTEGRATE", "B5-LIVE-APPLY", "W1-ABOX", "W1-AUTH",
                "W1-PTOP", "W2-CONVERGE"}
    assert required.issubset(ids)
    by_id = {lane["lane_id"]: lane for lane in lanes}
    assert set(by_id["B4-INTEGRATE"]["dependencies"]) == {"B1-CONTRACT", "B2-SOURCE", "B3-TESTS"}
    assert "B4-INTEGRATE" in by_id["B5-LIVE-APPLY"]["dependencies"]
    assert "B5-LIVE-APPLY" in by_id["W1-ABOX"]["dependencies"]
    assert "B5-LIVE-APPLY" in by_id["W1-AUTH"]["dependencies"]
    for lane in lanes:
        assert lane["execution_environment"] == "LOCAL_AGENT_RUNTIME"
        assert lane["launch_action"] and lane["expected_artifact"]
        assert lane["selected_adapter"] and lane["owned_mutation_surfaces"]
        assert all(dep in by_id and dep != lane["lane_id"] for dep in lane["dependencies"])
    visiting, visited = set(), set()
    def check_dag(node):
        if node in visited:
            return
        assert node not in visiting, "Cyclic P04 lane graph"
        visiting.add(node)
        for dep in by_id[node]["dependencies"]:
            check_dag(dep)
        visiting.remove(node)
        visited.add(node)
    for name in ids:
        check_dag(name)
    for name in ("W1-ABOX", "W2-CONVERGE"):
        assert "--expected-commit" in by_id[name]["launch_action"]
    assert "not observed" in doc["proof_ceiling"].lower() or "no live agent" in doc["proof_ceiling"].lower()


def main():
    test_mandatory_bootstrap_and_host_boundary()
    test_execution_dependency_graph_and_no_fake_runtime_proof()
    print("PASS: Admin Box 1 cold-start P04 plan/dispatch contracts (NOT runtime proof)")


if __name__ == "__main__":
    main()
