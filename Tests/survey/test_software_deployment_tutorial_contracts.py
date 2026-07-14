#!/usr/bin/env python3
"""Contracts for the browser-first software deployment tutorial."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TUTORIAL = ROOT / "docs" / "tutorials" / "SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md"
START_HERE = ROOT / "START-HERE-SysAdminSuite.md"
DOC_INDEX = ROOT / "docs" / "launch-and-doc-index.md"
DASHBOARD_UI = ROOT / "dashboard" / "js" / "software-deployment-tutorial.js"
DASHBOARD_LOADER = ROOT / "dashboard" / "js" / "launch-repo-setup-tutorial.js"
DASHBOARD_RUNTIME = ROOT / "dashboard" / "test_software_deployment_tutorial.js"
DASHBOARD_WORKFLOW = ROOT / ".github" / "workflows" / "dashboard-smoke.yml"
E2E_SCRIPT = ROOT / "scripts" / "Invoke-SasSoftwareInstallE2E.ps1"
INSTALL_SCRIPT = ROOT / "scripts" / "Invoke-SasSoftwareInstall.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_web_interface_is_canonical_and_discoverable() -> None:
    start = read(START_HERE)
    index = read(DOC_INDEX)
    assert "web interface is the canonical technician tutorial" in start
    assert "Start Software Deployment" in start
    assert "?tutorial=software-deployment" in start
    assert "Supporting written runbook" in start
    assert "docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md" in start
    assert "SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md" in index


def test_dashboard_loader_and_primary_card_exist() -> None:
    loader = read(DASHBOARD_LOADER)
    ui = read(DASHBOARD_UI)
    assert "software-deployment-tutorial.js" in loader
    assert "Primary deployment interface" in ui
    assert "Start Software Deployment" in ui
    assert "Jump to Safe Dry Run" in ui
    assert "hero-open-deployment" in ui
    assert "software-deployment" in ui
    assert "software-install" in ui


def test_dashboard_matches_real_entrypoints() -> None:
    ui = read(DASHBOARD_UI)
    tutorial = read(TUTORIAL)
    for fragment in [
        "Invoke-SasSoftwareInstallE2E.ps1",
        "Invoke-SasSoftwareInstall.ps1",
    ]:
        assert fragment in ui
        assert fragment in tutorial
    assert E2E_SCRIPT.is_file()
    assert INSTALL_SCRIPT.is_file()


def test_dry_run_is_first_and_explicitly_non_live() -> None:
    tutorial = read(TUTORIAL)
    ui = read(DASHBOARD_UI)
    dry_run = tutorial.index("# Phase 1: Run the safe executable dry run")
    pilot = tutorial.index("# Phase 2: Prepare one real pilot deployment")
    assert dry_run < pilot
    for fragment in [
        "fixture-software-install-executable-e2e",
        "real_operator_wrapper_executed",
        "real_installer_executable_executed",
        "3 / 0 / 0",
        "does not contact a package share or workstation",
    ]:
        assert fragment.lower() in ui.lower(), f"dashboard missing dry-run contract: {fragment}"
    assert "live_target_e2e = false" in tutorial
    assert "Do not add them to git." in tutorial


def test_pilot_remains_one_target_and_confirmation_enabled() -> None:
    tutorial = read(TUTORIAL)
    ui = read(DASHBOARD_UI)
    for fragment in [
        "The first live pilot stays limited to one workstation.",
        "Use one hostname or FQDN only",
        "-WhatIf",
        "-AllowTargetMutation",
        "Confirmation remains enabled",
        "Do not bypass the confirmation prompt",
        "UncDirect",
        "CopyThenInstall",
    ]:
        assert fragment in ui, f"dashboard missing pilot guard: {fragment}"

    pilot_section = tutorial.split("# Phase 4: Execute one approved pilot", 1)[1]
    pilot_section = pilot_section.split("# Phase 5:", 1)[0]
    executable_commands = re.findall(r"```powershell\n(.*?)```", pilot_section, re.DOTALL)
    assert executable_commands
    assert all("-Confirm:$false" not in command for command in executable_commands)


def test_dashboard_requires_evidence_and_observed_behavior() -> None:
    ui = read(DASHBOARD_UI)
    for fragment in [
        "software_install_events.jsonl",
        "software_install_summary.json",
        "operator_handoff.txt",
        "completed_count = 1",
        "failed_count = 0",
        "cleanup_failure_count = 0",
        "repo_artifact_remaining_count = 0",
        "A process launch or exit code alone is not deployment proof.",
        "intended behavior were actually observed",
    ]:
        assert fragment in ui, f"dashboard missing evidence contract: {fragment}"


def test_dashboard_has_stop_and_expand_gates() -> None:
    ui = read(DASHBOARD_UI)
    assert "Expand only when" in ui
    assert "Stop when" in ui
    for fragment in [
        "Package evidence or arguments are uncertain",
        "Security blocks or unexpected interaction occurs",
        "Version, behavior, cleanup, or evidence is wrong",
        "Results are incomplete or contradictory",
    ]:
        assert fragment in ui, f"dashboard missing decision gate: {fragment}"


def test_command_builder_stays_placeholder_free_and_safe() -> None:
    ui = read(DASHBOARD_UI)
    runtime = read(DASHBOARD_RUNTIME)
    for fragment in [
        "validatePilot",
        "buildWhatIfCommand",
        "buildPilotCommand",
        "one hostname or FQDN",
        "parent traversal",
    ]:
        assert fragment in ui
    assert "-Confirm:$false" not in ui
    assert "assert(!whatIf.command.includes('-Confirm:$false'))" in runtime
    assert "assert(!pilot.command.includes('-Confirm:$false'))" in runtime
    assert "HOST1,HOST2" in runtime
    assert "unsafe path accepted" in runtime
    forbidden = [
        r"DefaultPassword\s*=",
        r"-Credential\b",
        r"ConvertTo-SecureString",
        r"Enter-PSSession",
        r"git\s+add\s+survey/output",
    ]
    for pattern in forbidden:
        assert not re.search(pattern, ui, re.IGNORECASE), (
            f"dashboard tutorial contains forbidden pattern: {pattern}"
        )


def test_dashboard_ci_executes_browser_contracts() -> None:
    workflow = read(DASHBOARD_WORKFLOW)
    for fragment in [
        "node --check dashboard/js/software-deployment-tutorial.js",
        "node dashboard/test_software_deployment_tutorial.js",
        "test_dashboard_software_deployment_tutorial_contracts.sh",
    ]:
        assert fragment in workflow, f"dashboard workflow missing: {fragment}"


def main() -> None:
    tests = [
        test_web_interface_is_canonical_and_discoverable,
        test_dashboard_loader_and_primary_card_exist,
        test_dashboard_matches_real_entrypoints,
        test_dry_run_is_first_and_explicitly_non_live,
        test_pilot_remains_one_target_and_confirmation_enabled,
        test_dashboard_requires_evidence_and_observed_behavior,
        test_dashboard_has_stop_and_expand_gates,
        test_command_builder_stays_placeholder_free_and_safe,
        test_dashboard_ci_executes_browser_contracts,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} browser-first software deployment tutorial contracts")


if __name__ == "__main__":
    main()
