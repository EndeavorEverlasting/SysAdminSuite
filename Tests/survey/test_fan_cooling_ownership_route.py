#!/usr/bin/env python3
"""Synthetic regression tests for semantic ownership of fan diagnostics and shopping."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "harness/api/fan-cooling-task-ownership.v1.json"
RESOLVER = ROOT / "harness/api/sas_fan_cooling_route.py"


def load_resolver():
    spec = importlib.util.spec_from_file_location("sas_fan_cooling_route", RESOLVER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class FanCoolingOwnershipTests(unittest.TestCase):
    def test_machine_contract_and_synthetic_routing(self):
        manifest = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema_version"], "sas-fan-cooling-ownership/v1")
        self.assertEqual(manifest["authority"]["diagnostics"], "SysAdminSuite")
        self.assertEqual(manifest["authority"]["shopping"], "external-shopping-owners")
        self.assertIn("FamilyRecipes", manifest["authority"]["shopping_owner_resolution"]["general_purchase_status"])
        self.assertIn("PantryPoint", manifest["authority"]["shopping_owner_resolution"]["household_sufficiency_semantics"])
        self.assertTrue(manifest["mixed_intent"]["shopping_never_waits_for_unrelated_software_diagnostics"])
        self.assertTrue(manifest["safety"]["protect_cpu_fan"])
        resolve = load_resolver().classify
        for case in manifest["synthetic_cases"]:
            with self.subTest(text=case["text"]):
                result = resolve(case["text"], manifest)
                self.assertEqual(result["route"], case["expect"])
                self.assertFalse(result["diagnostics_blocks_shopping"])
                self.assertFalse(result["runtime_observed"])

    def test_routing_and_discoverability(self):
        routing = json.loads((ROOT / "harness/api/agent-routing-manifest.json").read_text(encoding="utf-8"))
        field = next(x for x in routing["triggers"] if x["target"] == "field-workflow")
        self.assertIn("Fan Control diagnostics", field["deterministic_task_signals"])
        self.assertIn("Fan Control window missing", field["deterministic_task_signals"])
        for path in ("AGENTS.md", "CODEBASE_MAP.md", ".claude/skills/field-workflow/SKILL.md"):
            self.assertIn("fan-cooling-task-ownership.v1.json", (ROOT / path).read_text(encoding="utf-8"))
        self.assertTrue((ROOT / "docs/field/FAN-CONTROL-DIAGNOSTICS.md").is_file())

    def test_no_private_machine_or_purchasing_details(self):
        text = CONTRACT.read_text(encoding="utf-8")
        self.assertNotIn("DatPhanFailed", text)
        self.assertNotIn("docs.google.com/document/d/", text)
        self.assertNotIn("Amazon.com/dp/", text)
        self.assertNotIn("$10.38", text)


if __name__ == "__main__":
    unittest.main()
