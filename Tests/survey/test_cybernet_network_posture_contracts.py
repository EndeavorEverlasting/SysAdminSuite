#!/usr/bin/env python3
"""Static contracts for the local-only Cybernet network posture gate."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Test-CybernetNetworkPosture.ps1"
TEST = ROOT / "Tests" / "Pester" / "CybernetNetworkPosture.Tests.ps1"
RUNBOOK = ROOT / "docs" / "WAB_TEST_READINESS.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8-sig")


def test_posture_gate_is_local_only_and_classifies_environment() -> None:
    text = read(SCRIPT)
    for fragment in [
        "SasNetworkGuard.psm1",
        "OK_NETWORK_POSTURE",
        "ENVIRONMENT_BLOCKED_GUEST_NETWORK",
        "ENVIRONMENT_BLOCKED_POLICY",
        "INCONCLUSIVE",
        "network_activity_performed = $false",
        "target_mutation_performed = $false",
        "allowed_for_target_preflight",
        "wired_guard_configured",
        "survey/output/network_posture",
        "[switch]$NoExitCode",
    ]:
        assert fragment in text, f"missing posture gate contract: {fragment}"

    for forbidden in ["Test-NetConnection", "Resolve-DnsName", "Invoke-WebRequest", "Invoke-Command", "Set-ItemProperty", "Start-Process", "nmap", "naabu"]:
        assert forbidden not in text, f"posture gate must not execute {forbidden}"


def test_posture_gate_has_fixture_backed_pester_coverage() -> None:
    text = read(TEST)
    for fragment in [
        "accepts approved Wi-Fi",
        "accepts approved wired evidence",
        "classifies an unapproved Wi-Fi segment",
        "network_activity_performed",
        "target_mutation_performed",
    ]:
        assert fragment in text


def test_wab_runbook_names_posture_before_target_preflight() -> None:
    text = read(RUNBOOK)
    assert "Test-CybernetNetworkPosture.ps1" in text
    assert "before target preflight" in text


if __name__ == "__main__":
    test_posture_gate_is_local_only_and_classifies_environment()
    test_posture_gate_has_fixture_backed_pester_coverage()
    test_wab_runbook_names_posture_before_target_preflight()
