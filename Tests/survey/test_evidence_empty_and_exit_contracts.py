#!/usr/bin/env python3
"""Regression contracts for empty evidence discovery and sas exit propagation."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "scripts" / "Show-SasOperatorEvidence.ps1"
INSTALLER = ROOT / "scripts" / "Install-SasPortableLauncher.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_empty_generic_evidence_lists_are_valid_inputs() -> None:
    text = read(EVIDENCE)
    compact = "".join(text.split())
    marker = "[Parameter(Mandatory=$true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$List"
    assert marker in compact
    assert "NO MATCHING EVIDENCE FOUND" in text
    assert "exit 23" in text


def test_installed_sas_shim_preserves_child_exit_code_across_endlocal() -> None:
    text = read(INSTALLER)
    assert 'set "SAS_EXIT=!ERRORLEVEL!"' in text
    assert "for %%# in (!SAS_EXIT!) do endlocal & exit /b %%#" in text
    assert "endlocal & exit /b %SAS_EXIT%" not in text


if __name__ == "__main__":
    test_empty_generic_evidence_lists_are_valid_inputs()
    test_installed_sas_shim_preserves_child_exit_code_across_endlocal()
    print("PASS: evidence empty-list and sas exit propagation contracts (2 groups)")
