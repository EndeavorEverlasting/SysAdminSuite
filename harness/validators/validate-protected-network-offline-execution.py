#!/usr/bin/env python3
"""Validate the Internet-preparation -> protected-offline execution contract."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "harness/contracts/protected-network-offline-execution.v1.json"
GOVERNANCE = ROOT / "AGENTS.md"
GUEST_DOC = ROOT / "docs/GUEST_SYNC_TO_PROTECTED_DEPLOYMENT.md"
SCAN_PLAN = ROOT / "docs/SCANSNAP_PROVEN_DEPLOYMENT_FACTORY_PLAN.md"
SCAN_HANDOFF = ROOT / "docs/handoff/SCANSNAP_ONE_PASS_CURSOR_HANDOFF.md"
INTAKE = ROOT / "harness/workflows/fresh-agent-intake.yaml"
CI = ROOT / ".github/workflows/harness-contracts.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    for path in (CONTRACT, GOVERNANCE, GUEST_DOC, SCAN_PLAN, SCAN_HANDOFF, INTAKE, CI):
        assert tracked(path), f"component not tracked: {path.relative_to(ROOT)}"

    contract = json.loads(read(CONTRACT))
    assert contract["schema_version"] == "sas-protected-offline-execution/v1"
    assert contract["prompt_provenance"]["P00"]["name"] == "Governance Doctrine Installer"
    assert contract["prompt_provenance"]["P01"]["name"] == "Harness Infrastructure Builder"

    prep = contract["phases"]["internet_preparation"]
    protected = contract["phases"]["protected_execution"]
    doctrine = contract["doctrine"]

    assert prep["network_intent"] == "InternetSync"
    assert prep["target_contact_allowed"] is False
    assert "sealed_runtime" in prep["required_outputs"]
    assert "offline_failure_continuation_logic" in prep["required_outputs"]

    assert protected["network_intent"] == "ProtectedNorthwell"
    assert protected["agent_runtime_may_be_required"] is False
    assert protected["public_internet_may_be_required"] is False
    assert protected["git_network_io_allowed"] is False
    assert protected["public_web_lookup_allowed"] is False
    assert protected["cloud_agent_provider_required"] is False
    assert protected["execution_must_be_self_contained"] is True
    assert protected["required_runtime_transport"] == "LOCAL_FILESYSTEM_ONLY"

    for marker in (
        "package_payload_available_locally",
        "target_resolution_available_offline",
        "deployment_engine_available_offline",
        "failure_classification_available_offline",
        "same_transaction_continuation_available_offline",
        "evidence_written_locally",
        "operator_recovery_available_offline",
    ):
        assert marker in protected["required_properties"], marker

    assert doctrine["agent_prepares_but_does_not_own_protected_runtime"] is True
    assert doctrine["protected_network_must_assume_public_services_unavailable"] is True
    assert doctrine["protected_execution_cannot_depend_on_chat_continuity"] is True
    assert doctrine["failure_is_a_local_continuation_state_not_a_chat_handoff"] is True

    governance = read(GOVERNANCE)
    for marker in (
        "Protected-network offline autonomy",
        "the agent may be unavailable after the network switch",
        "C:\\SASAL",
        "same-transaction failure continuation",
    ):
        assert marker in governance, f"governance missing: {marker}"

    guest = read(GUEST_DOC)
    for marker in (
        "Agent availability boundary",
        "assume the agent and public Internet are unavailable",
        "Do not switch to protected Northwell until the sealed runtime contains every package, script, validator, continuation path, and operator front door required",
    ):
        assert marker in guest, f"runbook missing: {marker}"

    for text, owner in ((read(SCAN_PLAN), "ScanSnap plan"), (read(SCAN_HANDOFF), "ScanSnap handoff")):
        for marker in (
            "P00",
            "P01",
            "protected execution is agent-independent",
            "offline/sealed deployment transaction",
            "no public Internet dependency",
        ):
            assert marker in text, f"{owner} missing: {marker}"

    intake = read(INTAKE)
    assert "harness/contracts/protected-network-offline-execution.v1.json" in intake
    assert "python harness/validators/validate-protected-network-offline-execution.py" in intake

    ci = read(CI)
    assert "harness/validators/validate-protected-network-offline-execution.py" in ci
    assert "harness/contracts/protected-network-offline-execution.v1.json" in ci

    print("PASS: P00 governance requires agent-independent protected execution")
    print("PASS: P01 harness separates Internet preparation from protected execution")
    print("PASS: ScanSnap must be sealed and self-contained before the network switch")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
