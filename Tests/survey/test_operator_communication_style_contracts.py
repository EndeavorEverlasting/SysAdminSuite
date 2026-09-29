import copy
import importlib.util
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
        "provider-neutral synthetic fixtures",
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

    assert semantics["schema_version"] == "sas-operator-communication-semantics/v2"
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
        assert case["fixture_scope"] == "synthetic_provider_neutral"
        assert case["id"].startswith("synthetic-")

        fact_keys = [fact["key"] for fact in case["facts"]]
        assert len(fact_keys) == len(set(fact_keys)), (
            f'{case["id"]}: fact keys must be unique'
        )

        internal_values = {
            normalize(fact["value"])
            for fact in case["facts"]
            if fact["classification"] in {"internal_target", "contingency_buffer"}
        }
        allowed = {normalize(item["text"]) for item in case["client_allowed"]}
        forbidden = {normalize(item) for item in case["client_forbidden"]}
        assert allowed.isdisjoint(forbidden), (
            f'{case["id"]}: allowed and forbidden wording must be disjoint'
        )
        for item in case["client_allowed"]:
            normalized_text = normalize(item["text"])
            assert all(value not in normalized_text for value in internal_values), (
                f'{case["id"]}: internal planning value leaked into client wording'
            )
            if item["statement_class"] == "external_commitment":
                assert item["gate"] == {
                    "evidence_support": True,
                    "sufficient_operational_control": True,
                    "explicit_operator_intent": True,
                }


def load_validator_module():
    spec = importlib.util.spec_from_file_location(
        "operator_communication_semantics_validator",
        VALIDATOR,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load operator communication validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_runtime_validator_survives_python_optimization_and_rejects_bad_data() -> None:
    source = VALIDATOR.read_text(encoding="utf-8")
    assert "assert " not in source

    optimized = subprocess.run(
        [sys.executable, "-O", str(VALIDATOR)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert optimized.returncode == 0, optimized.stdout + optimized.stderr

    semantics = load_json(SEMANTICS)
    schema = load_json(SCHEMA)
    invalid = copy.deepcopy(semantics)
    case = invalid["regressions"][0]
    case["client_allowed"][0]["text"] = case["client_forbidden"][0]

    validator = load_validator_module()
    try:
        validator.validate_document(invalid, schema)
    except ValueError as exc:
        assert "overlap" in str(exc)
    else:
        raise AssertionError("validator accepted contradictory allowed/forbidden wording")


def test_synthetic_delivery_buffer_preserves_the_behavior_not_live_details() -> None:
    case = next(
        item
        for item in load_json(SEMANTICS)["regressions"]
        if item["id"] == "synthetic-delivery-buffer"
    )

    expected = next(
        fact for fact in case["facts"]
        if fact["classification"] == "expected_outcome"
    )
    internal = next(
        fact for fact in case["facts"]
        if fact["classification"] == "internal_target"
    )
    assert expected["key"] == "delivery_window"
    assert internal["key"] == "technician_arrival_target"

    external_commitment = next(
        item for item in case["client_allowed"]
        if item["statement_class"] == "external_commitment"
    )
    assert external_commitment["text"] == (
        "Our technicians will assemble on-site during delivery."
    )
    assert all(external_commitment["gate"].values())

    allowed_text = " ".join(item["text"] for item in case["client_allowed"]).lower()
    forbidden_text = " ".join(case["client_forbidden"]).lower()
    assert internal["value"].lower() not in allowed_text
    assert internal["value"].lower() in forbidden_text
    assert "ahead of the delivery" in forbidden_text


def main() -> int:
    test_operator_style_contract_captures_confirmed_preferences()
    test_hh_handoff_uses_operator_style_contract()
    test_commitment_semantics_schema_governance_and_validator_wiring()
    test_all_regression_contracts_are_semantically_consistent()
    test_runtime_validator_survives_python_optimization_and_rejects_bad_data()
    test_synthetic_delivery_buffer_preserves_the_behavior_not_live_details()
    print("[PASS] Operator communication style and commitment-boundary semantics are enforced")
    print("[PASS] Every registered regression is synthetic, typed, and semantically checked")
    print("[PASS] Runtime validation remains active under Python optimization and rejects contradictions")
    print("[PASS] External attendance promises are gated; internal buffers remain internal")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
