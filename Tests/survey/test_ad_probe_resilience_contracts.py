#!/usr/bin/env python3
"""Offline/static contracts for Active Directory probe resilience.

These tests do not contact Active Directory, DNS, or target hosts. They guard the
public doctrine and the live helper's offline safety shape so live validation can
be performed later from an authorized domain runtime without broadening scope.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "AD_PROBE_RESILIENCE.md"
LIVE_HELPER = ROOT / "survey" / "sas-ad-identity-export.ps1"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"

REQUIRED_STATES = [
    "AD_CONFIRMED",
    "AD_OBJECT_FOUND_DNS_FOUND",
    "AD_OBJECT_FOUND_DNS_MISSING",
    "AD_OBJECT_FOUND_DNS_MISMATCH",
    "AD_OBJECT_FOUND_STALE",
    "AD_OBJECT_FOUND_DISABLED",
    "AD_OBJECT_FOUND_WRONG_OU",
    "AD_DUPLICATE_CANDIDATES",
    "AD_NOT_FOUND",
    "AD_QUERY_BLOCKED",
    "DOMAIN_CONTEXT_UNKNOWN",
    "DOMAIN_CONTROLLER_UNREACHABLE",
    "PERMISSION_BLOCKED",
    "IMPORTED_STATIC_EVIDENCE",
    "NOT_AD_VERIFIED",
    "NEEDS_OPERATOR_REVIEW",
]


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_doctrine_and_live_helper_share_ad_state_taxonomy():
    doc = read(DOC)
    helper = read(LIVE_HELPER)
    for state in REQUIRED_STATES:
        assert state in doc, f"AD doctrine missing state {state}"
        assert state in helper, f"live AD helper missing state {state}"


def test_live_helper_uses_shared_target_intake_module():
    helper = read(LIVE_HELPER)
    required_fragments = [
        "scripts/SasTargetIntake.psm1",
        "Import-Module $targetIntakeModule -Force",
        "Get-SasRepoRoot -StartPath $PSCommandPath",
        "Assert-SasApprovedInputPath -Path $Manifest",
        "-Role 'AD identity manifest'",
        "-AllowStaging -AllowGenerated",
        "Assert-SasApprovedOutputPath -Path $Output",
        "-Role 'AD identity output CSV'",
    ]
    for fragment in required_fragments:
        assert fragment in helper, f"live AD helper missing shared target-intake fragment: {fragment}"


def test_live_helper_remains_read_only_and_operator_scoped():
    helper = read(LIVE_HELPER)
    banned_patterns = [
        r"\bSet-AD\w+\b",
        r"\bNew-AD\w+\b",
        r"\bRemove-AD\w+\b",
        r"\bDisable-AD\w+\b",
        r"\bEnable-AD\w+\b",
        r"\bAdd-AD\w+\b",
        r"\bMove-AD\w+\b",
        r"\bInvoke-Command\b",
        r"\bEnter-PSSession\b",
        r"\bStart-Process\b",
        r"\b" + "audit" + r"pol\b",
        r"\b" + "wev" + r"tutil\s+cl\b",
        r"\b" + "Clear-" + r"Event" + r"Log\b",
    ]
    for pattern in banned_patterns:
        assert not re.search(pattern, helper, flags=re.IGNORECASE), f"unsafe operation pattern present: {pattern}"
    assert re.search(r"\[Parameter\(Mandatory\s*=\s*\$true\)\]", helper)
    assert "[string]$Manifest" in helper
    assert "Export-Csv" in helper


def test_live_helper_uses_resilient_bounded_lookup_shape():
    helper = read(LIVE_HELPER)
    required_fragments = [
        "function Get-DomainProbeState",
        "function Get-ADComputerCandidates",
        "function Resolve-AdDnsState",
        "function Write-AdProbeStateSummary",
        "AD PROBE STATE SUMMARY:",
        "DOMAIN_CONTEXT_UNKNOWN",
        "DOMAIN_CONTROLLER_UNREACHABLE",
        "PERMISSION_BLOCKED",
        "AD_DUPLICATE_CANDIDATES",
    ]
    for fragment in required_fragments:
        assert fragment in helper, f"missing resilience fragment: {fragment}"

    forbidden_wildcards = [
        "(name=*$safe*)",
        "(dNSHostName=*$safe*)",
        "(description=*$safe*)",
        "name=*$",
        "dNSHostName=*$",
        "description=*$",
    ]
    for fragment in forbidden_wildcards:
        assert fragment not in helper, f"broad wildcard LDAP lookup reintroduced: {fragment}"


def test_offline_runner_wires_ad_probe_contract():
    runner = read(RUNNER)
    assert "test_ad_probe_resilience_contracts.py" in runner


if __name__ == "__main__":
    test_doctrine_and_live_helper_share_ad_state_taxonomy()
    test_live_helper_uses_shared_target_intake_module()
    test_live_helper_remains_read_only_and_operator_scoped()
    test_live_helper_uses_resilient_bounded_lookup_shape()
    test_offline_runner_wires_ad_probe_contract()
