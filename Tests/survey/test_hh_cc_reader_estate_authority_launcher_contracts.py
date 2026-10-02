#!/usr/bin/env python3
"""Contracts for the H&H estate-authority operator evaluate launcher seam."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_estate_authority import main as evaluate_main

CMD = ROOT / "Evaluate-HHCCReaderEstateAuthority.cmd"
EVALUATOR = ROOT / "harness/api/hh_cc_reader_estate_authority.py"
FIXTURES = ROOT / "Tests/survey/fixtures/hh-cc-reader-estate-authority"
RUNBOOK = ROOT / "docs/HH_CC_READER_P5_READONLY_SESSION_RUNBOOK.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def run_cli(packet: Path, output_dir: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(EVALUATOR), str(packet), "--output-dir", str(output_dir)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )


def test_launcher_and_registries_exist() -> None:
    assert CMD.is_file()
    text = read(CMD)
    for marker in (
        "hh_cc_reader_estate_authority.py",
        "SANITIZED_PACKET_JSON",
        "No Payment Fusion",
        "exit /b %ERRORLEVEL%",
    ):
        assert marker in text, f"launcher missing marker: {marker}"
    assert "evaluate_proven_path_transition" in read(EVALUATOR)
    assert "RECEIPT_SCHEMA_VERSION" in read(EVALUATOR)
    assert 'if __name__ == "__main__"' in read(EVALUATOR)

    commands = {item["id"]: item for item in load_json(ROOT / "harness/api/harness-command-registry.json")["commands"]}
    outcomes = {
        item["command_id"]: item
        for item in load_json(ROOT / "harness/api/harness-outcome-registry.json")["contracts"]
    }
    artifacts = {
        item["id"]: item for item in load_json(ROOT / "harness/api/harness-artifact-registry.json")["artifacts"]
    }
    assert "hh-cc-reader-estate-authority-evaluate" in commands
    assert commands["hh-cc-reader-estate-authority-evaluate"]["source_of_truth"] == (
        "Evaluate-HHCCReaderEstateAuthority.cmd"
    )
    assert commands["hh-cc-reader-estate-authority-evaluate"]["network"] is False
    assert commands["hh-cc-reader-estate-authority-evaluate"]["mutation"] == "none"
    assert "hh-cc-reader-estate-authority-evaluate" in outcomes
    assert outcomes["hh-cc-reader-estate-authority-evaluate"]["success_artifact_id"] == (
        "hh-cc-reader-estate-authority-result"
    )
    assert "hh-cc-reader-estate-authority-result" in artifacts
    assert "survey/output/hh-cc-reader/hh-cc-reader-estate-authority-" in artifacts[
        "hh-cc-reader-estate-authority-result"
    ]["path"]

    runbook = read(RUNBOOK)
    assert "Evaluate-HHCCReaderEstateAuthority.cmd" in runbook
    evaluate_section = runbook.split("## Evaluate", 1)[1].split("## ", 1)[0]
    assert "Evaluate-HHCCReaderEstateAuthority.cmd" in evaluate_section
    assert "```bat" in evaluate_section
    assert "python -c \"" not in evaluate_section
    assert "python -c '" not in evaluate_section


def test_cli_positive_control_yes_promotes() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        proc = run_cli(FIXTURES / "complete-yes.json", out)
        assert proc.returncode == 0, proc.stderr
        assert "PROPOSED_DISPOSITION=PROVEN_PATH" in proc.stdout
        assert "PACKAGE_CONFLICT=False" in proc.stdout
        assert "MUTATION_AUTHORIZED=False" in proc.stdout
        assert "NEXT_GATE=P6_SEPARATE_PILOT_AUTHORIZATION" in proc.stdout
        assert "CURRENT_FIRMWARE_OBSERVED_VALUE=2.0.14.221110" in proc.stdout
        assert "EVIDENCE=" in proc.stdout
        receipts = list(out.glob("hh-cc-reader-estate-authority-*.json"))
        assert len(receipts) == 1
        receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
        assert receipt["schema_version"] == "sas-hh-cc-reader-estate-authority-result/v1"
        assert receipt["mutation"] == "NONE"
        assert receipt["proposed_disposition"] == "PROVEN_PATH"
        assert receipt["mutation_authorized"] is False
        assert receipt["current_firmware_observed_value"] == "2.0.14.221110"
        assert receipt["authority_packet_id"] == "pkt-fixture-yes"


def test_cli_package_conflict_branch() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        proc = run_cli(FIXTURES / "package-conflict-no.json", Path(tmp))
        assert proc.returncode == 0, proc.stderr
        assert "PROPOSED_DISPOSITION=PROVEN_PATH" in proc.stdout
        assert "PACKAGE_CONFLICT=True" in proc.stdout
        assert "NEXT_GATE=RESOLVE_PACKAGE_CONFLICT_BEFORE_P6" in proc.stdout
        assert "MUTATION_AUTHORIZED=False" in proc.stdout


def test_cli_unknown_package_does_not_promote() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        proc = run_cli(FIXTURES / "unknown-package.json", Path(tmp))
        assert proc.returncode == 0, proc.stderr
        assert "PROPOSED_DISPOSITION=CREDENTIAL_GATE" in proc.stdout
        assert "PROVEN_PATH" not in proc.stdout.split("PROPOSED_DISPOSITION=", 1)[1].splitlines()[0]


def test_cli_missing_firmware_value_does_not_promote() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        proc = run_cli(FIXTURES / "missing-firmware-value.json", Path(tmp))
        assert proc.returncode == 0, proc.stderr
        assert "REASON=CURRENT_FIRMWARE_VALUE_REQUIRED" in proc.stdout
        assert "PROPOSED_DISPOSITION=CREDENTIAL_GATE" in proc.stdout


def test_cli_bool_firmware_bleed_does_not_promote() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        proc = run_cli(FIXTURES / "bool-firmware-bleed.json", Path(tmp))
        assert proc.returncode == 0, proc.stderr
        assert "REASON=CURRENT_FIRMWARE_VALUE_REQUIRED" in proc.stdout
        assert "PROPOSED_DISPOSITION=CREDENTIAL_GATE" in proc.stdout


def test_cli_mutation_forbidden() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        proc = run_cli(FIXTURES / "mutation-forbidden.json", Path(tmp))
        assert proc.returncode == 0, proc.stderr
        assert "REASON=DISCOVERY_MUTATION_FORBIDDEN" in proc.stdout
        assert "PACKET_STATE=REJECTED" in proc.stdout


def test_cli_ineligible_tms() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        proc = run_cli(FIXTURES / "ineligible-tms.json", Path(tmp))
        assert proc.returncode == 0, proc.stderr
        assert "REASON=MECHANISM_INELIGIBLE" in proc.stdout
        assert "PROPOSED_DISPOSITION=NOT_APPLICABLE" in proc.stdout


def test_cli_missing_file_exits_2() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        missing = Path(tmp) / "does-not-exist.json"
        proc = run_cli(missing, Path(tmp))
        assert proc.returncode == 2
        assert "packet file not found" in proc.stderr.lower()


def test_cli_malformed_and_missing_inputs_exit_1() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        malformed = run_cli(FIXTURES / "malformed.json", out)
        assert malformed.returncode == 1
        assert "malformed" in malformed.stderr.lower() or "error" in malformed.stderr.lower()
        missing_inputs = run_cli(FIXTURES / "missing-evaluator-inputs.json", out)
        assert missing_inputs.returncode == 1
        assert "evaluator_inputs" in missing_inputs.stderr


def test_main_usage_without_args_exits_nonzero() -> None:
    # argparse writes to stderr and exits 2
    try:
        code = evaluate_main([])
    except SystemExit as exc:
        code = int(exc.code)
    assert code != 0


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for fn in tests:
        fn()
    print(f"PASS: H&H estate-authority operator launcher contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
