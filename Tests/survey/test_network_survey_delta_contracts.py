#!/usr/bin/env python3
"""Static contracts for the network survey delta planner and technician launcher."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLANNER = ROOT / "survey" / "sas-delta-preflight-plan.ps1"
NORMALIZER = ROOT / "scripts" / "SasSurveyArtifactNormalizer.psm1"
MODULE = ROOT / "scripts" / "SasDeltaEvidenceCache.psm1"
PLAN_ROWS = ROOT / "scripts" / "Invoke-SasDeltaPreflightPlanRows.ps1"
ARTIFACT_WRITER = ROOT / "scripts" / "Write-SasDeltaPreflightArtifacts.ps1"
LAUNCHER = ROOT / "scripts" / "Start-SasNetworkSurveyDelta.ps1"
CMD = ROOT / "Run-NetworkSurveyDelta.cmd"
DOC = ROOT / "docs" / "NETWORK_SURVEY_DELTA_LAUNCHER.md"
WORKFLOW = ROOT / ".github" / "workflows" / "network-survey-delta-contracts.yml"
FIXTURES = (
    ROOT / "survey" / "fixtures" / "delta_preflight_requested.sample.csv",
    ROOT / "survey" / "fixtures" / "delta_preflight_evidence_previous.sample.csv",
    ROOT / "survey" / "fixtures" / "delta_preflight_evidence_latest.sample.csv",
)


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path}"
    return path.read_text(encoding="utf-8")


def test_surfaces_exist() -> None:
    for path in (PLANNER, NORMALIZER, MODULE, PLAN_ROWS, ARTIFACT_WRITER, LAUNCHER, CMD, DOC, WORKFLOW, *FIXTURES):
        assert path.exists(), f"missing network survey delta surface: {path}"


def test_planner_writes_required_contract_artifacts() -> None:
    text = read(PLANNER) + "\n" + read(PLAN_ROWS) + "\n" + read(ARTIFACT_WRITER)
    for fragment in (
        "artifact_intake_manifest.json",
        "normalized_artifacts",
        "delta_preflight_plan.csv",
        "skipped_recent_evidence.csv",
        "review_required.csv",
        "delta_summary.json",
        "survey_observation_delta.csv",
        "to_probe_targets.txt",
        "network_activity_performed = $false",
        "target_mutation_performed = $false",
        "EvidenceStrengthTier",
        "StrongestEvidencePath",
        "SerialIdentityConfirmed",
        "ProbeWorthiness",
        "PreferredNextHandoff",
        "PROBE_REQUIRED_OPERATOR_FORCED",
        "PROBE_REQUIRED_STALE_EVIDENCE",
        "SKIP_RECENTLY_SILENT_WITHIN_COOLDOWN",
        "REVIEW_REQUIRED_SERIAL_ONLY",
    ):
        assert fragment in text, f"planner missing contract fragment: {fragment}"
    assert "PROBE_REQUIRD_STALE_EVIDENCE" not in text


def test_planner_contains_no_network_execution_primitives() -> None:
    text = "\n".join(read(path) for path in (PLANNER, NORMALIZER, PLAN_ROWS, ARTIFACT_WRITER, MODULE))
    forbidden = (
        "Test-NetConnection",
        "Test-Connection -ComputerName",
        "Resolve-DnsName -Name",
        "Start-BitsTransfer",
        "Invoke-Command -ComputerName",
        "naabu -",
        "nmap ",
    )
    for fragment in forbidden:
        assert fragment not in text, f"packet-free planner contains network primitive: {fragment}"


def test_cmd_is_zero_argument_double_click_entrypoint() -> None:
    text = read(CMD)
    assert 'if not "%~1"==""' in text
    assert "Start-SasNetworkSurveyDelta.ps1" in text
    assert "-Action Menu" in text
    assert "exit /b 2" in text


def test_launcher_enforces_confirmation_and_probe_cap() -> None:
    text = read(LAUNCHER)
    for fragment in (
        "Type SURVEY to continue",
        "five-attempt low-noise cap",
        "time_diverse_repeat_from_technician_launcher",
        "Invoke-DeltaPlan",
        "sas-network-preflight.ps1",
        "Survey and automatic delta comparison completed",
        "Dynamic path rewriting/path rehydration is unsupported",
    ):
        assert fragment in text, f"launcher missing safety/UX fragment: {fragment}"


def test_fixture_data_is_synthetic() -> None:
    combined = "\n".join(read(path) for path in FIXTURES)
    for serial in ("SN1001", "SN1002", "SN1003", "SN1004", "SN1005"):
        assert serial in combined
    assert "CYB001" in combined
    assert "northwell" not in combined.lower()


def test_documentation_labels_unsupported_continuation_behavior() -> None:
    text = read(DOC)
    assert "Dynamic path rewriting" in text
    assert "unsupported" in text.lower()
    assert "Run-NetworkSurveyDelta.cmd" in text
    assert "five" in text.lower() and "attempt" in text.lower()
    assert "canonical denominator" in text.lower()


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} network survey delta contracts")
