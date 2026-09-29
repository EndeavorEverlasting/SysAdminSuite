#!/usr/bin/env python3
"""Validate operator communication semantics, including cross-field rules."""
from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SEMANTICS = ROOT / "harness" / "api" / "operator-communication-semantics.json"
SCHEMA = ROOT / "schemas" / "harness" / "operator-communication-semantics.schema.json"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize(value: str) -> str:
    return " ".join(value.casefold().split())


def validate() -> None:
    semantics = load_json(SEMANTICS)
    schema = load_json(SCHEMA)

    Draft202012Validator.check_schema(schema)
    Draft202012Validator(schema).validate(semantics)

    seen_ids: set[str] = set()
    for case in semantics["regressions"]:
        case_id = case["id"]
        assert case_id not in seen_ids, f"duplicate regression id: {case_id}"
        seen_ids.add(case_id)

        allowed = {normalize(item) for item in case["client_allowed"]}
        forbidden = {normalize(item) for item in case["client_forbidden"]}
        overlap = allowed & forbidden
        assert not overlap, (
            f"{case_id}: client_allowed and client_forbidden overlap: "
            + ", ".join(sorted(overlap))
        )

        internal_target = normalize(case["facts"]["internal_technician_target"])
        assert all(internal_target not in item for item in allowed), (
            f"{case_id}: internal target leaked into client_allowed"
        )

    assert seen_ids, "at least one communication regression is required"


def main() -> int:
    validate()
    print("[PASS] Operator communication semantics schema and relational rules")
    print("[PASS] All regression contracts are unique, noncontradictory, and keep internal targets out of client-safe wording")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
