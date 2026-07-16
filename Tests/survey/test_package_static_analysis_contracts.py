#!/usr/bin/env python3
"""Executable contracts for the static package analyzer and skill wiring."""
from __future__ import annotations

import json
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANALYZER = ROOT / "tools/package-analysis/analyze_package.py"
SCHEMA = ROOT / "schemas/harness/package-static-analysis-result.schema.json"
SKILL = ROOT / ".claude/skills/package-static-analysis/SKILL.md"
HARNESS = ROOT / "harness/api/package-static-analysis-skill.json"
DOC = ROOT / "docs/PACKAGE_STATIC_ANALYSIS.md"
PS_WRAPPER = ROOT / "scripts/Invoke-SasPackageStaticAnalysis.ps1"
BASH_WRAPPER = ROOT / "scripts/invoke-sas-package-static-analysis.sh"
WORKFLOW = ROOT / ".github/workflows/package-static-analysis.yml"
AGENTS = ROOT / "AGENTS.md"
CLAUDE = ROOT / "CLAUDE.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def write_fake_pe(path: Path) -> None:
    data = bytearray(1024)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", data, 0x84, 0x8664, 1, 0, 0, 0, 0xF0, 0x0022)
    struct.pack_into("<H", data, 0x98, 0x20B)
    struct.pack_into("<H", data, 0x98 + 68, 3)
    data.extend(b"\nSet-ItemProperty Start-Service gpupdate /force https://private.invalid/path\n")
    path.write_bytes(data)


def test_files_and_contract_text_exist() -> None:
    for path in (ANALYZER, SCHEMA, SKILL, HARNESS, DOC, PS_WRAPPER, BASH_WRAPPER, WORKFLOW, AGENTS, CLAUDE):
        read(path)
    skill = read(SKILL)
    assert "## Capability dependencies" in skill
    assert "../../capabilities/mutation-and-evidence-boundaries.md" in skill
    assert "never execute" in skill.lower()
    assert "offline" in skill.lower()
    route = ".claude/skills/package-static-analysis/SKILL.md"
    assert route in read(AGENTS)
    assert route in read(CLAUDE)


def test_harness_contract_is_fail_closed() -> None:
    contract = json.loads(read(HARNESS))
    assert contract["schema_version"] == "sas-package-static-analysis-skill/v1"
    assert contract["skill_path"] == ".claude/skills/package-static-analysis/SKILL.md"
    operation = contract["operation"]
    assert operation["mode"] == "local_read"
    assert operation["network_activity"] is False
    assert operation["target_mutation"] is False
    assert operation["package_execution"] is False
    assert operation["archive_payload_extraction"] is False
    assert "raw_strings_not_emitted" in operation["guardrails"]


def test_analyzer_executes_against_sanitized_fixture() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fixture = root / "fixture"
        output = root / "output"
        fixture.mkdir()
        write_fake_pe(fixture / "setup.exe")
        (fixture / "install.cmd").write_text(
            "reg add HKLM\\Software\\Fixture\nsc.exe create Fixture\nshutdown.exe /r\n"
            "set TOKEN=do-not-emit\n\\\\private.invalid\\software\\fixture.msi\n",
            encoding="utf-8",
        )
        with zipfile.ZipFile(fixture / "bundle.zip", "w") as archive:
            archive.writestr("nested/setup.msi", b"fixture")
            archive.writestr("scripts/install.ps1", b"Start-Process setup.exe")
        completed = subprocess.run(
            [
                sys.executable,
                str(ANALYZER),
                "--input",
                str(fixture),
                "--output-dir",
                str(output),
                "--max-content-bytes",
                "1048576",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        assert completed.returncode == 0, completed.stderr
        result = json.loads((output / "package_analysis.json").read_text(encoding="utf-8"))
        matrix = (output / "package_analysis.txt").read_text(encoding="utf-8")
        assert result["schema_version"] == "sas-package-static-analysis/v1"
        assert result["summary"]["analyzed_files"] == 3
        assert result["proof"] == {
            "proof_level": "static_only",
            "file_execution_performed": False,
            "archive_payload_extracted": False,
            "network_activity_performed": False,
            "target_mutation_performed": False,
            "host_mutation_performed": False,
            "signature_trust_validated": False,
            "runtime_behavior_validated": False,
        }
        files = {item["file_name"]: item for item in result["files"]}
        assert files["setup.exe"]["pe"]["valid_pe_header"] is True
        assert files["setup.exe"]["pe"]["machine"] == "x64"
        assert files["bundle.zip"]["archive"]["payload_extracted"] is False
        assert ".msi" in files["bundle.zip"]["archive"]["nested_installer_extensions"]
        assert {"registry_changes", "services", "reboot", "secret_like_material"} <= set(
            files["install.cmd"]["content_scan"]["indicators"]
        )
        serialized = json.dumps(result)
        assert "do-not-emit" not in serialized
        assert "private.invalid" not in serialized
        assert "PACKAGE STATIC ANALYSIS" in matrix
        assert "no package code executed" in matrix


def test_schema_and_safety_declarations() -> None:
    schema = json.loads(read(SCHEMA))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["additionalProperties"] is False
    proof = schema["properties"]["proof"]["properties"]
    for field in (
        "file_execution_performed",
        "archive_payload_extracted",
        "network_activity_performed",
        "target_mutation_performed",
        "host_mutation_performed",
        "signature_trust_validated",
        "runtime_behavior_validated",
    ):
        assert proof[field]["const"] is False
    analyzer = read(ANALYZER)
    forbidden = ("subprocess.run([str(path)", "os.startfile", "shell=True", "requests.", "urllib.request.urlopen")
    for fragment in forbidden:
        assert fragment not in analyzer
    ps = read(PS_WRAPPER)
    assert "--no-index" in ps and "--find-links" in ps
    assert "Invoke-WebRequest" not in ps and "Start-Process" not in ps


def main() -> None:
    tests = [
        test_files_and_contract_text_exist,
        test_harness_contract_is_fail_closed,
        test_analyzer_executes_against_sanitized_fixture,
        test_schema_and_safety_declarations,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} package static analysis contract groups")


if __name__ == "__main__":
    main()
