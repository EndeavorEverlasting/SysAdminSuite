from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "tools/production-install-proof/ingest_production_install_proof.py"
WRAPPER = ROOT / "scripts/Import-SasProductionInstallProof.ps1"
RECEIPT_SCHEMA = ROOT / "schemas/harness/production-install-proof-receipt.schema.json"
ROUTING_SCHEMA = ROOT / "schemas/harness/production-install-proof-routing.schema.json"
ROUTING = ROOT / "harness/api/production-install-proof-routing.json"
OPERATION = ROOT / "harness/api/production-install-proof-skill.json"
WORKFLOW = ROOT / "harness/workflows/production-install-proof-ingest.yaml"
LIVE_SHAPED_FIXTURE = ROOT / "Tests/Fixtures/production-install-proof/resume-matcher-live-accepted.fixture.json"
FIXTURE_MODE = ROOT / "Tests/Fixtures/production-install-proof/fixture-mode-rejected.fixture.json"
DOC = ROOT / "docs/PRODUCTION_INSTALL_PROOF_HARNESS.md"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def run_engine(evidence: Path, output: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(ENGINE),
            "--evidence",
            str(evidence),
            "--output-dir",
            str(output),
            "--validation-date",
            "2026-07-18",
            *extra,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class ProductionInstallProofContracts(unittest.TestCase):
    def test_contract_fixture_emits_contract_only_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "out"
            result = run_engine(LIVE_SHAPED_FIXTURE, output, "--contract-fixture")
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            receipt = load_json(output / "production_install_proof_receipt.json")
            self.assertEqual(receipt["outcome"], "contract-only")
            self.assertEqual(receipt["source"]["source_pr"], 222)
            self.assertEqual(receipt["proof"]["proof_level"], "sanitized_fixture_contract")
            self.assertFalse(receipt["proof"]["production_install_accepted"])
            self.assertTrue(receipt["event"]["contract_fixture"])
            self.assertFalse(receipt["source"]["source_evidence_copied_to_output"])
            self.assertNotIn(str(LIVE_SHAPED_FIXTURE), json.dumps(receipt))
            self.assertNotIn("operator-local-application-root", json.dumps(receipt))

            try:
                import jsonschema  # type: ignore
            except ImportError:
                jsonschema = None
            if jsonschema:
                jsonschema.Draft202012Validator(load_json(RECEIPT_SCHEMA), format_checker=jsonschema.FormatChecker()).validate(receipt)

    def test_live_shaped_evidence_requires_operator_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "out"
            result = run_engine(LIVE_SHAPED_FIXTURE, output)
            self.assertEqual(result.returncode, 2, result.stderr or result.stdout)
            receipt = load_json(output / "production_install_proof_receipt.json")
            self.assertEqual(receipt["outcome"], "blocked")
            self.assertIn("operator-confirmation-missing", receipt["reason_codes"])
            self.assertFalse(receipt["proof"]["production_install_accepted"])

    def test_fixture_mode_can_never_become_live_proof(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "out"
            result = run_engine(FIXTURE_MODE, output, "--operator-confirmed")
            self.assertEqual(result.returncode, 2, result.stderr or result.stdout)
            receipt = load_json(output / "production_install_proof_receipt.json")
            self.assertEqual(receipt["outcome"], "blocked")
            self.assertIn("fixture-mode-evidence", receipt["reason_codes"])

    def test_pr_212_is_rejected_for_resume_matcher_runtime_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "out"
            result = run_engine(LIVE_SHAPED_FIXTURE, output, "--source-pr", "212", "--operator-confirmed")
            self.assertEqual(result.returncode, 1)
            self.assertIn("expected #222", result.stderr)
            self.assertFalse((output / "production_install_proof_receipt.json").exists())

    def test_missing_machine_proof_blocks_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tampered = root / "tampered.json"
            payload = load_json(LIVE_SHAPED_FIXTURE)
            payload["proof"]["frontend_health_observed"] = False
            tampered.write_text(json.dumps(payload), encoding="utf-8")
            result = run_engine(tampered, root / "out", "--operator-confirmed")
            self.assertEqual(result.returncode, 2)
            receipt = load_json(root / "out/production_install_proof_receipt.json")
            self.assertIn("frontend-health-observed-false", receipt["reason_codes"])

    def test_manifests_route_one_nonexecuting_ingest_operation(self) -> None:
        operation = load_json(OPERATION)
        routing = load_json(ROUTING)
        schema = load_json(ROUTING_SCHEMA)
        self.assertEqual(operation["source_runtime_authority"]["pull_request"], 222)
        self.assertEqual(operation["operation"]["id"], "software_install.production_proof_ingest")
        self.assertEqual(routing["operation"], operation["operation"]["id"])
        self.assertFalse(operation["operation"]["network_activity"])
        self.assertFalse(operation["operation"]["target_mutation"])
        self.assertFalse(operation["operation"]["package_execution"])
        self.assertEqual(routing["additive_guard"], "live-data-guard")
        self.assertFalse(schema["additionalProperties"])
        workflow_text = WORKFLOW.read_text(encoding="utf-8")
        for marker in (
            "operation: software_install.production_proof_ingest",
            "entrypoint: scripts/Import-SasProductionInstallProof.ps1",
            "no package or application execution",
            "source evidence is hashed in place and never copied",
        ):
            self.assertIn(marker, workflow_text)

    def test_wrapper_uses_canonical_context_without_copying_evidence(self) -> None:
        text = WRAPPER.read_text(encoding="utf-8")
        for marker in (
            "Import-Module $runContextModule",
            "New-SasRunContext",
            "Register-SasArtifact",
            "production-install-proof-ingest",
            "-LiveData:$true",
        ):
            self.assertIn(marker, text)
        for forbidden in ("Copy-Item", "Start-Process", "Invoke-WebRequest", "Invoke-RestMethod"):
            self.assertNotIn(forbidden, text)

    def test_engine_has_no_network_or_process_execution_surface(self) -> None:
        text = ENGINE.read_text(encoding="utf-8")
        for forbidden in (
            "import socket",
            "import requests",
            "import urllib",
            "import subprocess",
            "os.system",
            "Popen(",
            "run(",
        ):
            self.assertNotIn(forbidden, text)
        for marker in (
            "source_evidence_copied_to_output\": False",
            "fixture-mode-evidence",
            "operator-confirmation-missing",
            "SUPPORTED_SOURCE_PR = 222",
        ):
            self.assertIn(marker, text)

    def test_docs_record_authority_and_proof_ceiling(self) -> None:
        text = DOC.read_text(encoding="utf-8")
        self.assertIn("PR #222", text)
        self.assertIn("PR #212", text)
        self.assertIn("July 18, 2026", text)
        self.assertIn("does not authorize another installation", text)
        self.assertIn("raw evidence remains operator-local", text)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ProductionInstallProofContracts)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print(f"production install proof contracts: {result.testsRun} run, {len(result.failures)} failed, {len(result.errors)} errors")
    raise SystemExit(0 if result.wasSuccessful() else 1)
