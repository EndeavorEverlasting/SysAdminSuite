#!/usr/bin/env python3
"""Contracts for the technician-facing software deployment tutorial."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TUTORIAL = ROOT / "docs" / "tutorials" / "SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md"
START_HERE = ROOT / "START-HERE-SysAdminSuite.md"
DOC_INDEX = ROOT / "docs" / "launch-and-doc-index.md"
E2E_SCRIPT = ROOT / "scripts" / "Invoke-SasSoftwareInstallE2E.ps1"
INSTALL_SCRIPT = ROOT / "scripts" / "Invoke-SasSoftwareInstall.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_tutorial_is_discoverable() -> None:
    relative = "docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md"
    assert relative in read(START_HERE)
    assert relative in read(DOC_INDEX)
    assert "Where is the software deployment tutorial?" in read(START_HERE)


def test_tutorial_matches_real_entrypoints() -> None:
    tutorial = read(TUTORIAL)
    assert "scripts\\Invoke-SasSoftwareInstallE2E.ps1" in tutorial
    assert ".\\scripts\\Invoke-SasSoftwareInstall.ps1" in tutorial
    assert "docs/SOFTWARE_INSTALL_E2E.md" in tutorial
    assert "docs/SOFTWARE_INSTALL_HARNESS.md" in tutorial
    assert E2E_SCRIPT.is_file()
    assert INSTALL_SCRIPT.is_file()


def test_dry_run_is_first_and_explicitly_non_live() -> None:
    tutorial = read(TUTORIAL)
    dry_run = tutorial.index("# Phase 1: Run the safe executable dry run")
    pilot = tutorial.index("# Phase 2: Prepare one real pilot deployment")
    assert dry_run < pilot
    for fragment in [
        "It does not contact a real package share or workstation.",
        "fixture-software-install-executable-e2e",
        "Delta: 3 added / 0 changed / 0 removed",
        "dummy-installed.txt",
        "real_operator_wrapper_executed = true",
        "real_installer_executable_executed = true",
        "live_target_e2e = false",
        "Do not add them to git.",
    ]:
        assert fragment in tutorial, f"tutorial missing dry-run contract: {fragment}"


def test_pilot_remains_bounded_and_confirmation_enabled() -> None:
    tutorial = read(TUTORIAL)
    for fragment in [
        "one approved package and one authorized target",
        "Keep the first live run to one workstation.",
        "-WhatIf",
        "-AllowTargetMutation",
        "Do not add `-Confirm:$false` during the first real pilot.",
        "Read the confirmation prompt carefully.",
        "UncDirect` first",
        "CopyThenInstall",
    ]:
        assert fragment in tutorial, f"tutorial missing pilot guard: {fragment}"

    pilot_section = tutorial.split("# Phase 4: Execute one approved pilot", 1)[1]
    pilot_section = pilot_section.split("# Phase 5:", 1)[0]
    assert "-Confirm:$false" in pilot_section  # present only in the explicit prohibition
    executable_commands = re.findall(r"```powershell\n(.*?)```", pilot_section, re.DOTALL)
    assert executable_commands, "pilot section must contain an executable PowerShell example"
    assert all("-Confirm:$false" not in command for command in executable_commands)


def test_tutorial_requires_evidence_and_observed_behavior() -> None:
    tutorial = read(TUTORIAL)
    for fragment in [
        "software_install_events.jsonl",
        "software_install_summary.json",
        "operator_handoff.txt",
        "completed_count = 1",
        "failed_count = 0",
        "cleanup_failure_count = 0",
        "repo_artifact_remaining_count = 0",
        "Record actual observed behavior separately from installer exit-code proof.",
        "A process launch or exit code alone is not full deployment proof.",
    ]:
        assert fragment in tutorial, f"tutorial missing evidence contract: {fragment}"


def test_stop_and_expand_gates_are_present() -> None:
    tutorial = read(TUTORIAL)
    assert "## Expand only when" in tutorial
    assert "## Stop and escalate when" in tutorial
    for fragment in [
        "package hash, signature, version, or arguments are uncertain",
        "cleanup fails or target staging remains",
        "endpoint security blocks or quarantines the package",
        "evidence is incomplete or contradictory",
        "Do not hide failures, clear logs, or delete operating-system audit records.",
    ]:
        assert fragment in tutorial, f"tutorial missing stop condition: {fragment}"


def test_tutorial_uses_placeholders_not_operational_targets() -> None:
    tutorial = read(TUTORIAL)
    assert "<AUTHORIZED-HOST>" in tutorial
    assert "<APPROVED-PACKAGE-NAME>" in tutorial
    forbidden = [
        r"DefaultPassword\s*=",
        r"-Credential\b",
        r"ConvertTo-SecureString",
        r"Invoke-Command\s+-ComputerName",
        r"Enter-PSSession",
        r"git\s+add\s+survey/output",
    ]
    for pattern in forbidden:
        assert not re.search(pattern, tutorial, re.IGNORECASE), (
            f"tutorial contains forbidden operational pattern: {pattern}"
        )


def main() -> None:
    tests = [
        test_tutorial_is_discoverable,
        test_tutorial_matches_real_entrypoints,
        test_dry_run_is_first_and_explicitly_non_live,
        test_pilot_remains_bounded_and_confirmation_enabled,
        test_tutorial_requires_evidence_and_observed_behavior,
        test_stop_and_expand_gates_are_present,
        test_tutorial_uses_placeholders_not_operational_targets,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} software deployment tutorial contracts")


if __name__ == "__main__":
    main()
