#!/usr/bin/env python3
"""Contracts for the canonical persistent developer-workstation documentation."""
from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TUTORIAL = ROOT / "docs/tutorials/DEVELOPER_WORKSTATION.md"
REPORT = ROOT / "docs/DEVELOPER_WORKSTATION_CONVERGENCE_REPORT.md"
README = ROOT / "README.md"
START_HERE = ROOT / "START-HERE-SysAdminSuite.md"
CODEBASE_MAP = ROOT / "CODEBASE_MAP.md"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
WORKFLOW = ROOT / ".github/workflows/developer-workstation-documentation.yml"
DOCUMENTS = (TUTORIAL, REPORT, README, START_HERE, CODEBASE_MAP)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def test_canonical_documents_exist_and_are_discoverable() -> None:
    for path in DOCUMENTS:
        assert path.is_file(), path
    tutorial_path = "docs/tutorials/DEVELOPER_WORKSTATION.md"
    report_path = "docs/DEVELOPER_WORKSTATION_CONVERGENCE_REPORT.md"
    for path in (README, START_HERE, CODEBASE_MAP):
        text = read(path)
        assert tutorial_path in text
        assert report_path in text


def test_architecture_is_consistent_and_stale_v2_guidance_is_absent() -> None:
    for path in (TUTORIAL, REPORT, README, START_HERE):
        text = read(path)
        assert "WezTerm" in text and "tmux `dev`" in text
        assert "PowerShell" in text and "fallback" in text.lower()
        assert "macOS" in text and "unsupported" in text.lower()
    current_entrypoints = read(README) + read(TUTORIAL) + read(CODEBASE_MAP)
    assert "scripts/Invoke-SasDeveloperWorkstation.ps1" in current_entrypoints
    assert "scripts/invoke-sas-developer-workstation.sh" in current_entrypoints
    assert "-Mode Inventory" in read(README)
    assert "-Operation Inventory" not in read(README)
    assert "-ProfilePath" not in read(README)
    stale_surfaces = read(README) + read(START_HERE) + read(CODEBASE_MAP)
    for stale in (
        "WSL is optional",
        "optional WSL",
        "12-journey",
        "canonical v2 profile",
        "Invoke-SasWezTermWindowsNativeProfile.ps1",
        "configs/linux-native/",
    ):
        assert stale not in stale_surfaces, stale


def test_tutorial_labels_every_code_block_with_its_destination() -> None:
    lines = read(TUTORIAL).splitlines()
    inside_fence = False
    opening_fences = 0
    for index, line in enumerate(lines):
        if not line.startswith("```"):
            continue
        if inside_fence:
            inside_fence = False
            continue
        inside_fence = True
        opening_fences += 1
        prior = next((item.strip() for item in reversed(lines[:index]) if item.strip()), "")
        assert prior.startswith(("Terminal:", "File content:")), (index + 1, prior)
    assert not inside_fence
    assert opening_fences >= 10


def test_tutorial_covers_daily_use_agents_recovery_and_proof_ceilings() -> None:
    text = read(TUTORIAL)
    for required in (
        "WezTerm tmux",
        "nested tmux",
        "Lua is not a PowerShell or Bash command",
        "opencode",
        "agy",
        "goose",
        "Stop",
        "Repair",
        "Rollback",
        "fixture proof",
        "live-runtime proof",
        "operator acceptance",
        "WSL is not native-Linux proof",
    ):
        assert required.lower() in text.lower(), required
    assert "it terminates tmux `dev`" in text
    assert "--allow-target-mutation" in text


def test_local_markdown_links_and_named_entrypoints_resolve() -> None:
    link_pattern = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
    for document in DOCUMENTS:
        for raw_target in link_pattern.findall(read(document)):
            target = raw_target.strip().strip("<>").split("#", 1)[0]
            if not target or "://" in target or target.startswith(("mailto:", "#")):
                continue
            resolved = (document.parent / target).resolve()
            assert resolved.exists(), f"{document.relative_to(ROOT)} -> {target}"
    for relative in (
        "Config/developer-workstation-profile.sample.json",
        "scripts/Invoke-SasDeveloperWorkstation.ps1",
        "scripts/invoke-sas-developer-workstation.sh",
        "scripts/Invoke-SasWorkstationE2E.py",
        "scripts/Invoke-SasWindowsWorkstationLiveProof.ps1",
        "Config/wezterm-windows-tmux.lua.template",
        "Config/wezterm-linux-tmux.lua.template",
    ):
        assert (ROOT / relative).is_file(), relative


def test_convergence_report_preserves_exact_evidence_boundaries() -> None:
    text = read(REPORT)
    for number in range(199, 217):
        if number in (200, 211, 213):
            continue
        assert f"#{number}" in text
    assert "#217" in text
    for required in (
        "22 passed / 0 skipped / 0 failed",
        "Windows live runtime",
        "Native Linux live runtime",
        "Blocked",
        "authentication_observed=false",
        "provider_response_observed=false",
        "operator_accepted=false",
        "canonical-wrapper-help-command-only",
        "microsoft-standard-WSL2",
        "Stop and live Rollback were not executed",
    ):
        assert required.lower() in text.lower(), required
    assert "100% complete" not in text


def test_documentation_contract_is_registered_in_offline_and_ci_gates() -> None:
    assert "test_developer_workstation_documentation_contracts.py" in read(RUNNER)
    workflow = read(WORKFLOW)
    assert "ubuntu-latest" in workflow and "windows-latest" in workflow
    assert "test_developer_workstation_documentation_contracts.py" in workflow
    for document in DOCUMENTS:
        assert str(document.relative_to(ROOT)).replace("\\", "/") in workflow


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation documentation contract groups")
