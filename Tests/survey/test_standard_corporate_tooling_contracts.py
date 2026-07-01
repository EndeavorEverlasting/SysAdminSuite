#!/usr/bin/env python3
"""Static contracts for the standard corporate survey tooling lane."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "STANDARD_CORPORATE_SURVEY_TOOLING.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_standard_tooling_doc_names_both_lanes_and_boundary():
    text = read(DOC)
    required = [
        "Use standard corporate tools first when they can answer the question with lower operational complexity.",
        "Use edge tools only when the standard lane cannot answer the question",
        "CMD, PowerShell, DNS, ARP",
        "Naabu, Nmap, and the Go packet-expenditure lane remain useful",
        "This is authorized, scoped, low-noise survey discipline.",
        "It is not stealth, evasion, log suppression, or hiding activity.",
    ]
    for fragment in required:
        assert fragment in text, f"missing standard/edge lane boundary: {fragment}"


def test_target_reduction_statuses_are_preserved():
    text = read(DOC)
    required_statuses = [
        "ConfirmedReached",
        "RetryCandidate",
        "ReviewRequired",
        "DeferredSubnetCandidate",
        "OutOfScope",
    ]
    for status in required_statuses:
        assert status in text, f"missing target reduction status: {status}"

    required_semantics = [
        "NoPing`, `NoTcp`, and DNS failures are not proof that a device is gone.",
        "Reachability is not serial proof.",
        "Candidate discovery is not identity proof.",
    ]
    for fragment in required_semantics:
        assert fragment in text, f"missing reduction/identity warning: {fragment}"


def test_location_subnet_schema_is_documented():
    text = read(DOC)
    fields = [
        "Site",
        "Location",
        "Building",
        "Floor",
        "SubnetCIDR",
        "Gateway",
        "SourceEvidence",
        "LastVerified",
        "SurveyAllowed",
        "Confidence",
        "Notes",
    ]
    for field in fields:
        assert field in text, f"missing location/subnet map field: {field}"

    assert "Commit only redacted examples, schema, and tests." in text


def test_standard_cmd_and_powershell_tooling_is_named():
    text = read(DOC)
    commands = [
        "ping -n 1 -w 750 HOSTNAME",
        "nslookup HOSTNAME",
        "arp -a",
        "tracert -d -h 3 HOSTNAME",
        "Resolve-DnsName -Name HOSTNAME -ErrorAction SilentlyContinue",
        "Test-Connection -ComputerName HOSTNAME -Count 1 -Quiet",
        "Test-NetConnection -ComputerName HOSTNAME -Port 445",
        "Get-NetNeighbor -AddressFamily IPv4",
    ]
    for command in commands:
        assert command in text, f"missing standard tooling command: {command}"


def test_targeted_subnet_signature_search_is_bounded():
    text = read(DOC)
    required = [
        "Do not run blind subnet sweeps from CMD.",
        "Do not turn a location subnet into a full `/24` sweep by default.",
        "The subnet is tied to a known location through the location/subnet map.",
        "SurveyAllowed` is `yes`",
        "The search is bounded by documented Cybernet signatures.",
        "Known Cybernet hostname or naming pattern from approved manifests.",
        "Known MAC vendor/OUI evidence",
        "The command does not broaden beyond the approved subnet, approved location, or approved target class.",
    ]
    for fragment in required:
        assert fragment in text, f"missing subnet boundary: {fragment}"


def test_next_artifacts_are_plan_only_and_local_first():
    text = read(DOC)
    artifacts = [
        "survey/input/target_reduction/<run_id>/prior_probe_results.csv",
        "survey/output/target_reduction/<run_id>/reduced_targets.csv",
        "survey/output/target_reduction/<run_id>/retry_candidates.csv",
        "survey/output/target_reduction/<run_id>/review_required.csv",
        "survey/output/target_reduction/<run_id>/location_subnet_candidates.csv",
        "survey/output/target_reduction/<run_id>/target_reduction_summary.json",
    ]
    for artifact in artifacts:
        assert artifact in text, f"missing target reduction artifact: {artifact}"

    assert "The first version can be plan-only and local-only. It should not probe." in text


if __name__ == "__main__":
    test_standard_tooling_doc_names_both_lanes_and_boundary()
    test_target_reduction_statuses_are_preserved()
    test_location_subnet_schema_is_documented()
    test_standard_cmd_and_powershell_tooling_is_named()
    test_targeted_subnet_signature_search_is_bounded()
    test_next_artifacts_are_plan_only_and_local_first()
