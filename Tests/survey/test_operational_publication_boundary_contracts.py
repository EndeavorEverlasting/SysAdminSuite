#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "harness" / "api" / "operational-publication-boundary.v1.json"
VALIDATOR = ROOT / "harness" / "validators" / "validate-operational-publication-boundary.py"


def _load_validator():
    spec = importlib.util.spec_from_file_location("publication_boundary_validator", VALIDATOR)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class OperationalPublicationBoundaryContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
        cls.validator = _load_validator()

    def test_current_contract_passes(self) -> None:
        self.assertEqual([], self.validator.validate_contract(self.payload))

    def test_downstream_cannot_become_upstream_dependency(self) -> None:
        candidate = copy.deepcopy(self.payload)
        candidate["principles"]["downstream_visibility_must_not_be_upstream_availability_dependency"] = False
        self.assertIn(
            "principles.downstream_visibility_must_not_be_upstream_availability_dependency",
            self.validator.validate_contract(candidate),
        )

    def test_filename_cannot_be_logical_identity(self) -> None:
        candidate = copy.deepcopy(self.payload)
        candidate["artifact_identity"]["filename_is_not_identity"] = False
        self.assertIn(
            "artifact_identity.filename_is_not_identity",
            self.validator.validate_contract(candidate),
        )

    def test_publication_lifecycle_is_ordered(self) -> None:
        candidate = copy.deepcopy(self.payload)
        candidate["publication_lifecycle"] = list(reversed(candidate["publication_lifecycle"]))
        self.assertIn("publication_lifecycle", self.validator.validate_contract(candidate))

    def test_reverse_sync_defaults_disabled(self) -> None:
        candidate = copy.deepcopy(self.payload)
        candidate["principles"]["reverse_sync_default"] = "ENABLED"
        self.assertIn(
            "principles.reverse_sync_default",
            self.validator.validate_contract(candidate),
        )


if __name__ == "__main__":
    unittest.main()
