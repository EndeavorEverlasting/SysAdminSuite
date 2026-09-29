import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOVERNANCE = ROOT / "AGENTS.md"
STYLE = ROOT / "docs" / "OPERATOR_COMMUNICATION_STYLE.md"
HANDOFF = ROOT / "docs" / "HH_KIOSK_DELIVERY_COORDINATION_HANDOFF.md"
SEMANTICS = ROOT / "harness" / "api" / "operator-communication-semantics.json"
SCHEMA = ROOT / "schemas" / "harness" / "operator-communication-semantics.schema.json"
VALIDATOR = ROOT / "harness" / "validators" / "validate-operator-communication-semantics.py"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize(value: str) -> str:
    return " ".join(value.casefold().split())


def test_operator_style_contract_captures_confirmed_preferences() -> None:
    text = STYLE.read_text(encoding="utf-8")

    required = [
        "concise, direct, professional language",
        "Directive versus request",
        "Do not use em dashes",
        'Avoid the phrase "locked in"',
        "confirmed facts separated from open dependencies",
        "Plan to be onsite",
        "Commitment boundary principle",
        "COMMITMENT_STRENGTH <= EVIDENCE_STRENGTH AND OPERATOR_CONTROL",
        "assemble on-site during delivery",
    ]

    for marker in required:
        assert marker in text, f"missing operator prose contract marker: {marker}"


def test_hh_handoff_uses_operator_style_contract() -> None:
    text = HANDOFF.read_text(encoding="utf-8")

    assert "docs/OPERATOR_COMMUNICATION_STYLE.md" in text
    assert "Internal team install directive template" in text
    assert "Plan to be onsite [DATE] for the install." in text
    assert "\u2014" not in text
    assert "locked in" not in text.lower()


def test_commitment_semantics_schema_governance_and_validator_wiring() -> None:
    semantics = load_json(SEMANTICS)
    schema = load_json(SCHEMA)
    governance = GOVERNANCE.read_text(encoding="utf-8")

    assert semantics["schema_version"] == "sas-operator-communication-semantics/v1"
    assert semantics["schema_path"] == schema["$id"]
    assert semantics["validator_path"] == "harness/validators/validate-operator-communication-semantics.py"
    assert schema["additionalProperties"] is False
    assert semantics["commitment_boundary"]["formula"] == (
        "COMMITMENT_STRENGTH <= EVIDENCE_STRENGTH AND OPERATOR_CONTROL"
    )

    classes = semantics["commitment_boundary"]["classes"]
    assert classes["confirmed_fact"]["external_mode"] == "allowed"
    assert classes["expected_outcome"]["external_mode"] == "allowed_with_uncertainty"
    assert classes["internal_target"]["external_mode"] == "not_as_commitment"
    assert classes["contingency_buffer"]["external_mode"] == "omit_unless_relevant"
    assert classes["external_commitment"]["external_mode"] == "gated"
    assert set(classes["external_commitment"]["requires"]) == {
        "evidence_support",
        "sufficient_operational_control",
        "explicit_operator_intent",
    }

    loading = governance.split("## Required loading sequence", 1)[1].split(
        "## Agent operating principles", 1
    )[0]
    assert "docs/OPERATOR_COMMUNICATION_STYLE.md" in loading
    assert "harness/api/operator-communication-semantics.json" in loading
    assert "**Commitment boundary:**" in governance
    assert "harness/validators/validate-operator-communication-semantics.py" in governance

    completed = subprocess.run(
        [sys.executable, str(VALIDATOR)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr


def test_all_regression_contracts_are_semantically_consistent() -> None:
    cases = load_json(SEMANTICS)["regressions"]
    ids = [case["id"] for case in cases]
    assert len(ids) == len(set(ids)), "regression ids must be unique"

    for case in cases:
        allowed = {normalize(item) for item in case["client_allowed"]}
        forbidden = {normalize(item) for item in case["client_forbidden"]}
        assert allowed.isdisjoint(forbidden), (
            f'{case["id"]}: allowed and forbidden wording must be disjoint'
        )
        internal_target = normalize(case["facts"]["internal_technician_target"])
        assert all(internal_target not in item for item in allowed), (
            f'{case["id"]}: internal target leaked into allowed client wording'
        )


def test_internal_delivery_buffer_never_becomes_client_promise() -> None:
    case = next(
        item
        for item in load_json(SEMANTICS)["regressions"]
        if item["id"] == "south-brooklyn-delivery-buffer"
    )

    assert case["facts"]["delivery_window"] == "11:30 AM to 12:00 PM"
    assert case["facts"]["internal_technician_target"] == "11:00 AM"

    allowed = " ".join(case["client_allowed"]).lower()
    forbidden = " ".join(case["client_forbidden"]).lower()

    assert "11:00 am" not in allowed
    assert "assemble on-site during delivery" in allowed
    assert "11:00 am" in forbidden
    assert "ahead of the delivery" in forbidden


def main() -> int:
    test_operator_style_contract_captures_confirmed_preferences()
    test_hh_handoff_uses_operator_style_contract()
    test_commitment_semantics_schema_governance_and_validator_wiring()
    test_all_regression_contracts_are_semantically_consistent()
    test_internal_delivery_buffer_never_becomes_client_promise()
    print("[PASS] Operator communication style and commitment-boundary semantics are enforced")
    print("[PASS] Every registered regression is checked for semantic contradictions")
    print("[PASS] Internal delivery buffers cannot become stronger client commitments")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
