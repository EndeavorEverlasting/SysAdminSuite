#!/usr/bin/env python3
"""Validate operator communication semantics, including cross-field rules."""
from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SEMANTICS = ROOT / "harness" / "api" / "operator-communication-semantics.json"
SCHEMA = ROOT / "schemas" / "harness" / "operator-communication-semantics.schema.json"

GATE_KEYS = {
    "evidence_support",
    "sufficient_operational_control",
    "explicit_operator_intent",
}
INTERNAL_CLASSES = {"internal_target", "contingency_buffer"}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize(value: str) -> str:
    return " ".join(value.casefold().split())


def validate_document(semantics: dict, schema: dict) -> None:
    Draft202012Validator.check_schema(schema)
    Draft202012Validator(schema).validate(semantics)

    seen_ids: set[str] = set()
    for case in semantics["regressions"]:
        case_id = case["id"]
        if case_id in seen_ids:
            raise ValueError(f"duplicate regression id: {case_id}")
        seen_ids.add(case_id)

        if case["fixture_scope"] != "synthetic_provider_neutral":
            raise ValueError(f"{case_id}: fixture must be synthetic/provider-neutral")
        if not case_id.startswith("synthetic-"):
            raise ValueError(f"{case_id}: synthetic fixture id must start with synthetic-")

        fact_keys: set[str] = set()
        internal_values: set[str] = set()
        for fact in case["facts"]:
            key = fact["key"]
            if key in fact_keys:
                raise ValueError(f"{case_id}: duplicate fact key: {key}")
            fact_keys.add(key)
            if fact["classification"] in INTERNAL_CLASSES:
                internal_values.add(normalize(fact["value"]))

        allowed = {normalize(item["text"]) for item in case["client_allowed"]}
        forbidden = {normalize(item) for item in case["client_forbidden"]}
        overlap = allowed & forbidden
        if overlap:
            raise ValueError(
                f"{case_id}: client_allowed and client_forbidden overlap: "
                + ", ".join(sorted(overlap))
            )

        for item in case["client_allowed"]:
            text = normalize(item["text"])
            leaked = sorted(value for value in internal_values if value in text)
            if leaked:
                raise ValueError(
                    f"{case_id}: internal planning value leaked into client_allowed: "
                    + ", ".join(leaked)
                )
            if item["statement_class"] == "external_commitment":
                gate = item.get("gate", {})
                if set(gate) != GATE_KEYS:
                    raise ValueError(
                        f"{case_id}: external commitment gate is incomplete"
                    )
                if not all(gate[key] is True for key in GATE_KEYS):
                    raise ValueError(
                        f"{case_id}: external commitment is not fully gated"
                    )

    if not seen_ids:
        raise ValueError("at least one communication regression is required")


def validate() -> None:
    validate_document(load_json(SEMANTICS), load_json(SCHEMA))


def main() -> int:
    validate()
    print("[PASS] Operator communication semantics schema and relational rules")
    print("[PASS] Fixtures are synthetic/provider-neutral and facts are extensible typed records")
    print("[PASS] All regressions keep internal planning values out of client-safe wording")
    print("[PASS] Every external commitment requires all three commitment gates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
