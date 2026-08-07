#!/usr/bin/env python3
"""Executable contracts for CLR strong-name verification producer and harness wiring."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERIFIER = ROOT / "tools/package-analysis/verify_dotnet_strong_name.py"
SCHEMA = ROOT / "schemas/harness/package-strong-name-verification-result.schema.json"
MANIFEST = ROOT / "harness/api/package-strong-name-verification-skill.json"
DOC = ROOT / "docs/PACKAGE_STRONG_NAME_VERIFICATION.md"
PS_WRAPPER = ROOT / "scripts/Invoke-SasPackageStrongNameVerification.ps1"
BASH_WRAPPER = ROOT / "scripts/invoke-sas-package-strong-name-verification.sh"
WORKFLOW = ROOT / ".github/workflows/package-static-analysis.yml"
CAPABILITY = ROOT / ".claude/capabilities/package-clr-strong-name-verification.md"
PACKAGE_SKILL = ROOT / ".claude/skills/package-static-analysis/SKILL.md"
HARNESS_API = ROOT / "harness/api/sas-harness-api.json"
ROUTING = ROOT / "harness/api/agent-routing-manifest.json"
CAPABILITY_MANIFEST = ROOT / "harness/api/agent-capability-manifest.json"
PACKAGE_WORKFLOW = ROOT / "harness/workflows/package-analysis.yaml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_module():
    spec = importlib.util.spec_from_file_location("strong_name", VERIFIER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def base_record(path: Path, relative: str, magic_type: str = "pe") -> dict:
    return {
        "relative_path": relative,
        "file_name": path.name,
        "extension": path.suffix.lower(),
        "file_class": "installer",
        "magic_type": magic_type,
        "size_bytes": path.stat().st_size,
        "sha256": sha(path),
        "entropy_first_mib": 0.0,
        "content_scan": {
            "status": "scanned",
            "bytes_scanned": path.stat().st_size,
            "truncated": False,
            "indicators": [],
            "endpoint_fingerprints": [],
            "raw_strings_emitted": False,
        },
        "pe": None,
        "compound_file": None,
        "archive": None,
    }


def write_base_result(path: Path, files: list[dict]) -> None:
    result = {
        "schema_version": "sas-package-static-analysis/v1",
        "analyzer_version": "0.1.0",
        "generated_at": "2026-07-17T00:00:00Z",
        "input": {
            "kind": "directory",
            "display_name": "fixture",
            "absolute_path_emitted": False,
            "total_bytes": sum(item["size_bytes"] for item in files),
        },
        "limits": {
            "max_files": 100,
            "max_total_bytes": 1000000,
            "max_content_bytes_per_file": 1000000,
            "archive_payload_extraction_allowed": False,
            "symlink_following_allowed": False,
        },
        "tools": {
            "python_version": "3.12",
            "platform": "fixture",
            "pefile_available": False,
            "olefile_available": False,
        },
        "proof": {
            "proof_level": "static_only",
            "file_execution_performed": False,
            "archive_payload_extracted": False,
            "network_activity_performed": False,
            "target_mutation_performed": False,
            "host_mutation_performed": False,
            "signature_trust_validated": False,
            "runtime_behavior_validated": False,
        },
        "summary": {
            "discovered_files": len(files),
            "analyzed_files": len(files),
            "skipped_files": 0,
            "error_count": 0,
            "file_classes": {"installer": len(files)},
            "indicator_counts": {},
        },
        "files": files,
        "skipped": [],
        "errors": [],
    }
    path.write_text(json.dumps(result), encoding="utf-8")


def test_required_surfaces_and_manifest() -> None:
    for path in (
        VERIFIER,
        SCHEMA,
        MANIFEST,
        DOC,
        PS_WRAPPER,
        BASH_WRAPPER,
        WORKFLOW,
        CAPABILITY,
        PACKAGE_SKILL,
        HARNESS_API,
        ROUTING,
        CAPABILITY_MANIFEST,
        PACKAGE_WORKFLOW,
    ):
        read(path)
    manifest = json.loads(read(MANIFEST))
    assert manifest["schema_version"] == "sas-package-strong-name-verification-skill/v1"
    operation = manifest["operation"]
    assert operation["id"] == "package_analysis.strong_name"
    assert operation["mode"] == "local_read"
    assert operation["network_activity"] is False
    assert operation["target_mutation"] is False
    assert operation["package_execution"] is False
    assert "source_hash_reverification_required" in operation["guardrails"]
    assert "authenticode_trust_is_separate_lane" in operation["guardrails"]
    assert "package-clr-strong-name-verification.md" in read(PACKAGE_SKILL)
    assert "package_analysis.strong_name" in read(HARNESS_API)
    assert "package_analysis.strong_name" in read(ROUTING)
    assert "verify_dotnet_strong_name.py" in read(WORKFLOW)
    assert "test_package_strong_name_verification_contracts.py" in read(WORKFLOW)
    assert "package_strong_name_verification.json" in read(PACKAGE_WORKFLOW)


def test_fixture_statuses_cover_owned_proof_ceiling() -> None:
    module = load_module()
    expected = {
        "signed": "verified",
        "unsigned": "unsigned",
        "delay_signed": "delay_signed",
        "tampered": "invalid",
        "malformed": "not_applicable",
        "unsupported": "unsupported",
    }
    for mode, status in expected.items():
        result = module.verify_assembly_bytes(module.build_managed_fixture(mode=mode))
        assert result["status"] == status, (mode, result)


def test_producer_emits_canonical_result_for_mixed_package() -> None:
    module = load_module()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fixture = root / "fixture"
        output = root / "output"
        fixture.mkdir()
        files = []
        for mode in ("signed", "unsigned", "delay_signed", "tampered", "unsupported"):
            path = fixture / f"{mode}.dll"
            path.write_bytes(module.build_managed_fixture(mode=mode, assembly_name=mode.title()))
            files.append(base_record(path, path.name))
        notes = fixture / "readme.txt"
        notes.write_text("not managed code\n", encoding="utf-8")
        files.append(base_record(notes, notes.name, magic_type="text"))
        base = root / "package_analysis.json"
        write_base_result(base, files)
        completed = subprocess.run(
            [
                sys.executable,
                str(VERIFIER),
                "--input",
                str(fixture),
                "--base-result",
                str(base),
                "--output-dir",
                str(output),
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        assert completed.returncode == 0, completed.stderr
        result = json.loads((output / "package_strong_name_verification.json").read_text(encoding="utf-8"))
        english = (output / "package_strong_name_verification.txt").read_text(encoding="utf-8")
        assert result["schema_version"] == "sas-package-strong-name-verification/v1"
        assert result["proof"]["proof_level"] == "clr_strong_name_integrity"
        assert result["proof"]["authenticode_trust_evaluated"] is False
        assert result["proof"]["strong_name_cryptographic_validation_performed"] is True
        assert result["summary"]["managed_assemblies"] == 5
        assert result["summary"]["verified_count"] == 1
        assert result["summary"]["unsigned_count"] == 1
        assert result["summary"]["delay_signed_count"] == 1
        assert result["summary"]["invalid_count"] == 1
        assert result["summary"]["unsupported_count"] == 1
        assert result["summary"]["not_applicable_count"] == 1
        assert result["summary"]["overall_status"] == "invalid"
        assert "Authenticode publisher trust was not evaluated" in english
        try:
            import jsonschema
        except ImportError:
            pass
        else:
            jsonschema.validate(result, json.loads(read(SCHEMA)))


def test_hash_mismatch_fails_closed() -> None:
    module = load_module()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fixture = root / "fixture"
        output = root / "output"
        fixture.mkdir()
        path = fixture / "signed.dll"
        path.write_bytes(module.build_managed_fixture(mode="signed"))
        base = root / "package_analysis.json"
        write_base_result(base, [base_record(path, path.name)])
        path.write_bytes(path.read_bytes() + b"changed")
        completed = subprocess.run(
            [
                sys.executable,
                str(VERIFIER),
                "--input",
                str(fixture),
                "--base-result",
                str(base),
                "--output-dir",
                str(output),
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        assert completed.returncode == 1
        result = json.loads((output / "package_strong_name_verification.json").read_text(encoding="utf-8"))
        assert result["summary"]["files_examined"] == 0
        assert result["errors"][0]["message"] == "hash_mismatch_since_base_analysis"


def test_schema_posture_and_docs_bound_proof_ceiling() -> None:
    schema = json.loads(read(SCHEMA))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["additionalProperties"] is False
    assert schema["properties"]["proof"]["properties"]["proof_level"]["const"] == "clr_strong_name_integrity"
    doc = read(DOC).lower()
    assert "authenticode" in doc
    assert "online revocation" in doc
    assert "does **not** prove" in doc or "does not prove" in doc
    assert "without executing" in doc


def main() -> int:
    tests = [
        test_required_surfaces_and_manifest,
        test_fixture_statuses_cover_owned_proof_ceiling,
        test_producer_emits_canonical_result_for_mixed_package,
        test_hash_mismatch_fails_closed,
        test_schema_posture_and_docs_bound_proof_ceiling,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} package strong-name verification contract groups")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
