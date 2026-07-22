#!/usr/bin/env python3
"""Dependency-free contracts for Cybernet operator documentation and help."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GUIDE = ROOT / "docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md"
TROUBLESHOOTING = ROOT / "docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md"
START_HERE = ROOT / "START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md"
DOC_INDEX = ROOT / "docs/launch-and-doc-index.md"
HARDWARE_README = ROOT / "Hardware/Cybernet/README.md"
LAUNCHER = ROOT / "Run-CybernetClientConfiguration.cmd"
ORCHESTRATOR = ROOT / "Hardware/Cybernet/Invoke-CybernetClientConfiguration.ps1"
COMMON = ROOT / "Hardware/Cybernet/CybernetHardware.Common.psm1"
TARGET_INTAKE = ROOT / "scripts/SasTargetIntake.psm1"
DISPLAY_RESTORE = ROOT / "Hardware/Cybernet/Enable-PrivacyButton.ps1"
DISPLAY_CONTROLLER = ROOT / "scripts/Invoke-SasCybernetDisplayButtonControl.ps1"
PROFILE = ROOT / "Config/cybernet-client-preferences.json"
PACKAGE_CATALOG = ROOT / "configs/software-packages/windows-native-package-sets.json"

OWNED_DOCS = (GUIDE, TROUBLESHOOTING, START_HERE, DOC_INDEX, HARDWARE_README)


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_docs_are_discoverable_from_every_operator_entrypoint() -> None:
    troubleshooting_name = TROUBLESHOOTING.name
    guide_name = GUIDE.name
    for path in (START_HERE, DOC_INDEX, HARDWARE_README, LAUNCHER):
        text = read(path)
        assert guide_name in text, f"{path.relative_to(ROOT)} does not link the complete guide"
        assert troubleshooting_name in text, f"{path.relative_to(ROOT)} does not link troubleshooting"


def test_guide_matches_current_modes_statuses_and_artifacts() -> None:
    guide = read(GUIDE)
    orchestrator = read(ORCHESTRATOR)
    launcher = read(LAUNCHER)

    for mode in ("Plan", "Apply", "Validate"):
        marker = f"Run-CybernetClientConfiguration.cmd {mode}"
        assert marker in guide
        assert f'-Mode {mode}' in launcher

    for status in (
        "PLAN_READY",
        "APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED",
        "HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED",
        "ACTION_REQUIRED",
        "FIXTURE_PASS",
    ):
        assert status in guide
        assert status in orchestrator

    for artifact in (
        "cybernet_client_configuration_summary.json",
        "operator_handoff.txt",
        "technician_software_acceptance.txt",
        "approved-software.console.log",
        "bash/apps/output/",
    ):
        assert artifact in guide

    for boundary in (
        "The combined workflow never changes COM mappings remotely",
        "The combined workflow does not reboot the target",
        "There is no one-command rollback for the complete client profile",
        "does **not** mean application behavior",
        "Fixture and CI proof",
    ):
        assert boundary in guide


def test_documented_package_order_is_generated_from_current_catalog() -> None:
    guide = read(GUIDE)
    profile = load(PROFILE)
    catalog = load(PACKAGE_CATALOG)
    package_set = next(
        item for item in catalog["package_sets"]
        if item["id"] == profile["software"]["package_set_id"]
    )
    names = {item["id"]: item["display_name"] for item in catalog["packages"]}
    ordered_names = [names[package_id] for package_id in package_set["package_ids"]]

    positions = [guide.index(name) for name in ordered_names]
    assert positions == sorted(positions), "guide package order differs from the approved catalog"
    assert package_set["package_ids"][-1] == "autologon"
    assert "AutoLogon must remain last" in guide


def test_windows_controller_and_target_boundaries_are_explicit() -> None:
    guide = read(GUIDE)
    for marker in (
        "Windows admin workstation or approved admin VM",
        "Git Bash on the Windows controller",
        "Browser dashboard",
        "Cybernet target machine",
        "Linux or macOS",
        "browser tutorial does not apply Cybernet",
        "Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'",
    ):
        assert marker in guide


def test_csv_batch_documentation_matches_target_resolver() -> None:
    guide = read(GUIDE)
    common = read(COMMON)
    intake = read(TARGET_INTAKE)

    for root in ("targets/local/", "logs/targets/", "survey/input/"):
        assert root in guide
    for header in ("ComputerName", "HostName", "Hostname", "Target"):
        assert header in guide
        assert header in common
    for implementation_root in ("targets/local", "logs/targets", "survey/input"):
        assert implementation_root in intake

    assert r"-TargetsCsv '.\targets\local\cybernet-approved-batch.csv'" in guide
    assert "deduplicated case-insensitively" in guide
    assert "hard maximum is 25" in guide


def test_troubleshooting_covers_safe_failure_and_retry_behavior() -> None:
    text = read(TROUBLESHOOTING)
    for marker in (
        "stop and preserve evidence",
        "Do not rerun Apply immediately",
        "hardware-apply",
        "approved-software-install",
        "hardware-post-software-validation",
        "COM_AUTOFIX_ELIGIBLE_LOCAL_ONLY",
        "COM_PORT_REVIEW_REQUIRED",
        "Apply requires -AllowTargetMutation",
        "Git Bash is missing",
        "Cleanup uncertainty",
        "Safe retry sequence",
        "Do not add them to Git",
    ):
        assert marker.lower() in text.lower(), marker

    for forbidden_workaround in (
        "use PsExec instead",
        "disable the firewall",
        "-Confirm:$false",
        "--no-teardown as a field workaround",
    ):
        assert forbidden_workaround not in text


def test_display_restore_documentation_matches_exact_manifest_contract() -> None:
    troubleshooting = read(TROUBLESHOOTING)
    restore = read(DISPLAY_RESTORE)
    controller = read(DISPLAY_CONTROLLER)

    for marker in (
        "Enable-PrivacyButton.ps1",
        "cybernet_display_button_restore_manifest.json",
        "-RestoreManifest '<EXACT-RESTORE-MANIFEST-PATH>'",
        "-WhatIf",
        "-AllowTargetMutation",
        "refuses to invent a factory value",
    ):
        assert marker.lower() in troubleshooting.lower(), marker

    assert "requires -RestoreManifest" in restore
    assert "cybernet_display_button_restore_manifest.json" in controller
    assert "best-effort rollback" in controller


def test_launcher_help_is_operator_complete_and_one_target_only() -> None:
    launcher = read(LAUNCHER)
    for marker in (
        'if /I "%~1"=="Help" goto help_ok',
        "Usage:",
        "PLAN_READY",
        "APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED",
        "HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED",
        "cybernet_client_configuration_summary.json",
        "technician_software_acceptance.txt",
        'if not "%~3"==""',
        "never reboots a target or repairs COM ports remotely",
    ):
        assert marker in launcher
    assert "-ExecutionPolicy Bypass" not in launcher


def test_relative_markdown_links_resolve() -> None:
    link_pattern = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
    for path in OWNED_DOCS:
        for raw_target in link_pattern.findall(read(path)):
            target = raw_target.split("#", 1)[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            resolved = (path.parent / target).resolve()
            assert resolved.is_file(), (
                f"broken relative link in {path.relative_to(ROOT)}: {raw_target}"
            )


def test_docs_exclude_private_or_machine_specific_values() -> None:
    combined = "\n".join(read(path) for path in OWNED_DOCS)
    package_catalog = load(PACKAGE_CATALOG)
    private_share = str(package_catalog.get("software_share_root", "")).strip()

    forbidden = (
        r"C:\\Users\\Cheex",
        r"CHEEX-DESKTOP",
        r"rperez26@",
        r"rperez@",
        r"password\s*=",
    )
    for pattern in forbidden:
        assert not re.search(pattern, combined, re.IGNORECASE), pattern
    if private_share:
        assert private_share not in combined, "private software-share root leaked into operator docs"


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Cybernet operator documentation contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
