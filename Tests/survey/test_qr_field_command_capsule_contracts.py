#!/usr/bin/env python3
"""Static and behavior contracts for the QR field command capsule launcher and profiles."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts" / "sas_qr_run.sh"
DOC = ROOT / "docs" / "QR_FIELD_COMMAND_CAPSULE.md"
PROFILES_DIR = ROOT / "profiles"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path}"
    return path.read_text(encoding="utf-8")


def test_surfaces_exist() -> None:
    assert LAUNCHER.is_file(), f"missing launcher: {LAUNCHER}"
    assert DOC.is_file(), f"missing doc: {DOC}"
    assert PROFILES_DIR.is_dir(), f"missing profiles dir: {PROFILES_DIR}"


def test_launcher_shell_syntax() -> None:
    # Use bash -n to validate shell script syntax using relative path
    res = subprocess.run(["bash", "-n", "scripts/sas_qr_run.sh"], capture_output=True, text=True)
    assert res.returncode == 0, f"sas_qr_run.sh has syntax errors: {res.stderr}"


def test_profiles_conform_to_contract() -> None:
    profiles = list(PROFILES_DIR.glob("*.profile"))
    assert len(profiles) > 0, "No profiles found to validate"

    for profile_path in profiles:
        content = read(profile_path)

        # Helper to parse key-value pairs
        data = {}
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                data[key.strip()] = val.strip()

        profile_id = profile_path.stem
        assert data.get("profile_id") == profile_id, f"profile_id mismatch in {profile_path.name}"
        assert data.get("mutation_allowed") == "false", f"mutation_allowed must be false in {profile_path.name}"
        assert data.get("runner") in {"python3", "bash", "pwsh"}, f"unknown runner in {profile_path.name}"

        script_path = ROOT / data.get("script", "")
        assert script_path.is_file(), f"script declared in {profile_path.name} not found: {script_path}"

        contracts = data.get("output_contract", "").split(",")
        assert len(contracts) > 0, f"missing output_contract in {profile_path.name}"
        for contract in contracts:
            assert contract in {
                "resolved_targets_csv", "review_csv", "optional_dashboard",
                "manifest_json", "validation_json", "rejections_csv"
            }, f"unknown output contract '{contract}' in {profile_path.name}"


def test_dry_run_delegation() -> None:
    res = subprocess.run(
        ["bash", "scripts/sas_qr_run.sh", "--profile", "neuron-hostname-survey", "--dry-run"],
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0
    assert "Profile: neuron-hostname-survey" in res.stdout
    assert "Lane: python3 survey/sas-match-neurons-from-nmap.py" in res.stdout
    assert "DRY RUN: approved survey lane was not executed" in res.stdout


def test_invalid_profile_rejection() -> None:
    bad1 = PROFILES_DIR / "bad1.profile"
    bad2 = PROFILES_DIR / "bad2.profile"
    bad3 = PROFILES_DIR / "bad3.profile"

    try:
        # 1. Unsafe mutation_allowed
        bad1.write_text(
            "profile_id=bad1\nrunner=python3\nscript=survey/sas-match-neurons-from-nmap.py\nmutation_allowed=true\noutput_contract=resolved_targets_csv\n",
            encoding="utf-8",
        )
        res = subprocess.run(
            ["bash", "scripts/sas_qr_run.sh", "--profile", "bad1", "--dry-run"],
            capture_output=True,
            text=True,
        )
        assert res.returncode != 0
        assert "Field capsules must be non-mutating" in res.stderr or "Unsafe mutation posture" in res.stderr

        # 2. Unknown runner
        bad2.write_text(
            "profile_id=bad2\nrunner=node\nscript=survey/sas-match-neurons-from-nmap.py\nmutation_allowed=false\noutput_contract=resolved_targets_csv\n",
            encoding="utf-8",
        )
        res = subprocess.run(
            ["bash", "scripts/sas_qr_run.sh", "--profile", "bad2", "--dry-run"],
            capture_output=True,
            text=True,
        )
        assert res.returncode != 0
        assert "Unknown runner" in res.stderr

        # 3. Unknown output contract
        bad3.write_text(
            "profile_id=bad3\nrunner=python3\nscript=survey/sas-match-neurons-from-nmap.py\nmutation_allowed=false\noutput_contract=super_secret_payload\n",
            encoding="utf-8",
        )
        res = subprocess.run(
            ["bash", "scripts/sas_qr_run.sh", "--profile", "bad3", "--dry-run"],
            capture_output=True,
            text=True,
        )
        assert res.returncode != 0
        assert "Unknown artifact contract" in res.stderr
    finally:
        for p in (bad1, bad2, bad3):
            if p.exists():
                p.unlink()


def test_unsafe_argument_injection_rejection() -> None:
    res = subprocess.run(
        ["bash", "scripts/sas_qr_run.sh", "--profile", "neuron-hostname-survey", "--dry-run", "--", "--manifest", "a.csv; rm -rf /"],
        capture_output=True,
        text=True,
    )
    assert res.returncode != 0
    assert "Unsafe shell characters detected in arguments" in res.stderr


def main() -> None:
    tests = [
        test_surfaces_exist,
        test_launcher_shell_syntax,
        test_profiles_conform_to_contract,
        test_dry_run_delegation,
        test_invalid_profile_rejection,
        test_unsafe_argument_injection_rejection,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} QR field command capsule contracts")


if __name__ == "__main__":
    main()
