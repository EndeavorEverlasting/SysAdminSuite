#!/usr/bin/env python3
"""Contract and schema validation tests for the developer workstation E2E proof results."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROOF_SCHEMA = ROOT / "schemas/harness/developer-workstation-proof.schema.json"
E2E_PROFILES = ROOT / "harness/e2e/e2e-profiles.json"
E2E_RUNNER = ROOT / "scripts/Invoke-SasEndToEndValidation.ps1"
E2E_WORKSTATION_JOURNEY = ROOT / "scripts/Invoke-SasWorkstationE2E.ps1"
MAP = ROOT / "CODEBASE_MAP.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_proof_schema_structure() -> None:
    schema = load(PROOF_SCHEMA)
    assert schema["$id"] == "schemas/harness/developer-workstation-proof.schema.json"
    assert "schema_version" in schema["properties"]
    assert "validation_matrix" in schema["properties"]
    assert "journeys" in schema["properties"]
    assert "proof_ceiling" in schema["properties"]


def test_e2e_profiles_registration() -> None:
    catalog = load(E2E_PROFILES)
    profiles = {p["id"]: p for p in catalog["profiles"]}
    assert "developer-workstation-bimodal-e2e" in profiles
    
    ws_profile = profiles["developer-workstation-bimodal-e2e"]
    assert ws_profile["proof_class"] == "fixture-loopback-e2e"
    assert len(ws_profile["journey_ids"]) == 12


def test_runner_safety_and_proof_ceiling() -> None:
    text = read(E2E_RUNNER)
    assert "live_target_e2e=$false" in text or "live_target_e2e = $false" in text
    assert "fixture_or_loopback_e2e" in text


def test_codebase_map_registration() -> None:
    codebase_map = read(MAP)
    assert "developer-workstation-proof.schema.json" in codebase_map
    assert "Invoke-SasWorkstationE2E.ps1" in codebase_map


def main() -> None:
    tests = [
        test_proof_schema_structure,
        test_e2e_profiles_registration,
        test_runner_safety_and_proof_ceiling,
        test_codebase_map_registration,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation proof contracts")


if __name__ == "__main__":
    main()
