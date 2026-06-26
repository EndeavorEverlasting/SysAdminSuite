#!/usr/bin/env python3
"""Offline contract tests for the AD probe resilience and ambiguity doctrine.

These tests are network-free and domain-free. They validate the doctrine
artifacts (rule, canonical doc, synthetic fixture) rather than executing a live
AD query. Live AD validation requires an authorized domain runtime and is
classified as blocked-by-runtime-access; see docs/AD_PROBE_RESILIENCE.md.

The tests prove:
- the required AD state taxonomy is fully documented and fully exercised by the
  synthetic fixture (ambiguous states are classified, not silently dropped),
- the documented fallback ladder and AD PROBE STATE SUMMARY template exist,
- the synthetic fixture contains no obvious live/private values (no committed
  live evidence, no credentials/tokens).
"""
from __future__ import annotations

import csv
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DOC = REPO_ROOT / "docs" / "AD_PROBE_RESILIENCE.md"
RULE = REPO_ROOT / ".cursor" / "rules" / "ad-probe-resilience.mdc"
FIXTURE = REPO_ROOT / "survey" / "fixtures" / "ad_probe_states.sample.csv"

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

REQUIRED_SUMMARY_FIELDS = [
    "Query mode used:",
    "Fallback mode used:",
    "Domain context:",
    "Domain controller status:",
    "Permission status:",
    "Input target count:",
    "AD objects found:",
    "DNS enriched:",
    "Stale objects:",
    "Disabled objects:",
    "Duplicate candidates:",
    "Not found:",
    "Blocked / unknown:",
    "Needs operator review:",
    "Local ignored log path:",
    "Evidence committed:",
]

REQUIRED_LADDER_TERMS = [
    "RSAT",
    "LDAP",
    "Domain",
    "DNS enrichment",
    "manifest fallback",
    "No-AD fallback",
]


def _read(path: Path) -> str:
    assert path.exists(), f"Missing required artifact: {path}"
    return path.read_text(encoding="utf-8")


def test_doc_and_rule_exist() -> None:
    assert DOC.exists(), "docs/AD_PROBE_RESILIENCE.md must exist"
    assert RULE.exists(), ".cursor/rules/ad-probe-resilience.mdc must exist"
    rule_text = _read(RULE)
    assert "alwaysApply: true" in rule_text, "Rule must be always-applied"
    assert "docs/AD_PROBE_RESILIENCE.md" in rule_text, "Rule must cite canonical doc"


def test_doc_documents_every_required_state() -> None:
    doc = _read(DOC)
    missing = [s for s in REQUIRED_STATES if s not in doc]
    assert not missing, f"Doc missing required AD states: {missing}"


def test_doc_documents_fallback_ladder_and_summary() -> None:
    doc = _read(DOC)
    missing_terms = [t for t in REQUIRED_LADDER_TERMS if t not in doc]
    assert not missing_terms, f"Doc missing fallback ladder terms: {missing_terms}"
    assert "AD PROBE STATE SUMMARY:" in doc, "Doc must include the state summary template"
    missing_fields = [f for f in REQUIRED_SUMMARY_FIELDS if f not in doc]
    assert not missing_fields, f"Doc missing summary fields: {missing_fields}"


def test_doc_states_live_validation_is_blocked_by_runtime() -> None:
    doc = _read(DOC)
    assert "blocked by runtime access" in doc, (
        "Doc must classify live AD validation as blocked by runtime access, "
        "not pretend a domain run occurred"
    )
    assert "sas-ad-identity-export.ps1" in doc, (
        "Doc must name the exact operator command/file for future authorized validation"
    )


def test_fixture_exercises_every_required_state() -> None:
    with FIXTURE.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    assert rows, "Fixture must contain rows"
    assert "ADState" in rows[0], "Fixture must have an ADState column"
    seen = {row["ADState"].strip() for row in rows}
    missing = [s for s in REQUIRED_STATES if s not in seen]
    assert not missing, f"Fixture does not exercise states: {missing}"
    unknown = [s for s in seen if s not in REQUIRED_STATES]
    assert not unknown, f"Fixture has undocumented states: {unknown}"


def test_fixture_uses_only_synthetic_identifiers() -> None:
    """Guard against committing live evidence, credentials, or tokens."""
    text = _read(FIXTURE)
    with FIXTURE.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))

    for row in rows:
        target = row["Target"].strip()
        assert re.fullmatch(r"(CYBTEST|WNH000TEST)\d+", target), (
            f"Non-synthetic target identifier in fixture: {target!r}"
        )

    # DNS hostnames must stay inside the synthetic sample domain.
    for row in rows:
        dns = row.get("DNSHostName", "").strip()
        if dns:
            for name in re.split(r"[;\s]+", dns):
                if name:
                    assert name.endswith(".sample.local"), (
                        f"Non-synthetic DNS name in fixture: {name!r}"
                    )

    lowered = text.lower()
    forbidden = ["password", "secret", "token", "apikey", "api_key", "bearer", "northwell"]
    hits = [needle for needle in forbidden if needle in lowered]
    assert not hits, f"Fixture appears to contain sensitive values: {hits}"


if __name__ == "__main__":
    test_doc_and_rule_exist()
    test_doc_documents_every_required_state()
    test_doc_documents_fallback_ladder_and_summary()
    test_doc_states_live_validation_is_blocked_by_runtime()
    test_fixture_exercises_every_required_state()
    test_fixture_uses_only_synthetic_identifiers()
    print("offline AD probe resilience contract tests passed")
