#!/usr/bin/env python3
"""Documentation contracts for the current Cybernet software deployment lane."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TUTORIAL = ROOT / "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md"
START = ROOT / "START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md"
REFERENCE = ROOT / "docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md"
CENTRAL_START = ROOT / "START-HERE-SysAdminSuite.md"
SCRIPT = ROOT / "bash/apps/sas-install-apps.sh"
CATALOG = ROOT / "configs/software-packages/approved-apps.json"
PACKAGE_SET_CATALOG = ROOT / "configs/software-packages/windows-native-package-sets.json"
WORKFLOW = ROOT / ".github/workflows/operational-posture.yml"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
IMPLEMENTATION_CONTRACT = ROOT / "Tests/bash/test_smb_scheduled_task_install_contracts.sh"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_navigation_and_audience() -> None:
    tutorial = read(TUTORIAL)
    start = read(START)
    reference = read(REFERENCE)
    central = read(CENTRAL_START)
    assert "authorized technicians and Windows administrators" in tutorial
    assert "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md" in start
    assert "tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md" in reference
    assert "START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md" in central
    assert "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md" in central


def test_primary_commands_match_restart_complete_field_entrypoints() -> None:
    tutorial = read(TUTORIAL)
    start = read(START)
    combined = tutorial + "\n" + start
    for marker in (
        "sas cybernet Deploy <AUTHORIZED-CYBERNET>",
        "sas autologon Remote <AUTHORIZED-CYBERNET>",
        "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED",
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "automatic_reboot_performed=true",
        "restart_offline_observed=true",
        "restart_online_observed=true",
    ):
        assert marker in combined, f"current technician route missing: {marker}"
    assert "AutoLogon **last**" in tutorial or "AutoLogon is always the final software step" in start
    assert "historical six-package LocalSystem" in tutorial


def test_generic_single_package_reference_still_matches_controller() -> None:
    tutorial = read(TUTORIAL)
    script = read(SCRIPT)
    for flag in ("--targets", "--package", "--allow-legacy", "--dry-run"):
        assert flag in tutorial, f"tutorial missing advanced controller flag {flag}"
        assert flag in script, f"entrypoint missing {flag}"
    commands = re.findall(r"```bash\n(.*?)\n```", tutorial, flags=re.DOTALL)
    deployment_commands = [command for command in commands if "bash bash/apps/sas-install-apps.sh" in command]
    assert len(deployment_commands) == 2
    assert any("--dry-run" in command for command in deployment_commands)
    assert any("--dry-run" not in command for command in deployment_commands)


def test_current_controller_boundaries_are_documented() -> None:
    tutorial = read(TUTORIAL)
    reference = read(REFERENCE)
    script = read(SCRIPT)
    combined = tutorial + "\n" + reference
    for marker in (
        "current Windows admin token",
        "enable WinRM",
        "Transport cleanup is not an uninstall",
        "does not implement a general software rollback",
        "HOST_OK",
        "technician",
        "--no-teardown",
    ):
        assert marker.lower() in combined.lower(), f"missing boundary: {marker}"
    for marker in (
        "Target count exceeds the guarded maximum of 25",
        "approved-package mode requires the Windows-native admin-share transport",
        "native_remove_run_root",
        "delete_remote_task",
    ):
        assert marker in script, f"controller boundary disappeared: {marker}"
    for forbidden in ("--smb-pass PASSWORD", "SAS_SMB_PASS=", "taskkill /im", "tmux kill-server"):
        assert forbidden.lower() not in combined.lower(), f"unsafe example present: {forbidden}"


def test_deployment_restart_and_optional_runtime_outputs_are_explained() -> None:
    combined = read(TUTORIAL) + "\n" + read(START)
    for marker in (
        "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED",
        "cybernet_software_deployment_result.json",
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "autologon_s4u_deployment_result.json",
        "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING",
        "runtime proof",
        "not a prerequisite",
    ):
        assert marker.lower() in combined.lower(), f"tutorial missing current deployment state: {marker}"
    assert "AutoLogon installation is **not deployment-complete before the restart**" in read(START)
    assert "technician is not required to run a separate fixture, transport live-cert, or runtime-proof loop" in read(TUTORIAL)


def test_bca_example_is_catalog_backed() -> None:
    catalog = json.loads(read(CATALOG))
    matches = [item for item in catalog["packages"] if item["id"] == "bca"]
    assert len(matches) == 1
    bca = matches[0]
    assert bca["display_name"] == "Epic BCA Web Shortcut 1.0"
    assert bca["installer_file"] == "EPIC_BCA_Web-Shortcut_1.0.msi"
    assert bca["default_installer_arguments"] == ["/qn", "/norestart"]
    assert bca["install_enabled"] is True
    assert "--package bca" in read(TUTORIAL)


def test_clinical_package_sets_match_autologon_last_model() -> None:
    catalog = json.loads(read(PACKAGE_SET_CATALOG))
    sets = {item["id"]: item for item in catalog["package_sets"]}
    core = sets["cybernet-clinical-core"]["package_ids"]
    full = sets["cybernet-clinical-workstation"]["package_ids"]
    assert core == [
        "allscripts-eehr-shortcut-uai-2-2",
        "epic-downtime-guide-shortcut-1-0",
        "nuance-dragon-medical-one-2025",
        "hyland-fos-epic-integration-23-1-33-1000",
        "bca",
    ]
    assert full[:-1] == core
    assert full[-1] == "autologon"
    assert sets["cybernet-autologon-only"]["package_ids"] == ["autologon"]


def test_docs_contract_is_wired_beside_the_executable_contract() -> None:
    workflow = read(WORKFLOW)
    runner = read(RUNNER)
    implementation = read(IMPLEMENTATION_CONTRACT)
    test_path = "Tests/survey/test_cybernet_software_deployment_documentation_contracts.py"
    assert test_path in workflow and test_path in runner
    assert "Tests/survey/test_technician_deployment_guidance_contracts.py" in runner
    assert "bash Tests/bash/test_smb_scheduled_task_install_contracts.sh" in workflow
    assert "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md" in workflow
    assert "configs/software-packages/windows-native-package-sets.json" in workflow
    assert "START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md" in workflow
    assert "'docs/**'" in workflow
    assert "DRY_RUN_OK" in implementation
    assert "HOST_OK" in implementation


def test_no_machine_local_or_private_runtime_evidence_is_documented() -> None:
    combined = read(TUTORIAL) + "\n" + read(START) + "\n" + read(REFERENCE)
    assert not re.search(r"(?i)C:\\Users\\[A-Za-z0-9._-]+", combined)
    assert "CYBERNET-PILOT-01" in combined
    assert "hostname intentionally omitted" not in combined.lower()


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} Cybernet software deployment documentation contract groups")
