#!/usr/bin/env python3
"""Executable contracts for the package semantic sidecar and harness requirements."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEMANTIC = ROOT / "tools/package-analysis/enrich_package_semantics.py"
SCHEMA = ROOT / "schemas/harness/package-semantic-analysis-result.schema.json"
MANIFEST = ROOT / "harness/api/package-semantic-analysis-skill.json"
DOC = ROOT / "docs/PACKAGE_SEMANTIC_ANALYSIS.md"
PS_WRAPPER = ROOT / "scripts/Invoke-SasPackageSemanticAnalysis.ps1"
BASH_WRAPPER = ROOT / "scripts/invoke-sas-package-semantic-analysis.sh"
WORKFLOW = ROOT / ".github/workflows/package-static-analysis.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_module():
    spec = importlib.util.spec_from_file_location("semantic", SEMANTIC)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_fake_managed_sapien_pe(path: Path) -> None:
    data = bytearray(0x1200)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    optional_offset = 0x98
    optional_size = 0xE0
    struct.pack_into("<HHIIIHH", data, 0x84, 0x014C, 1, 0, 0, 0, optional_size, 0x0102)
    struct.pack_into("<H", data, optional_offset, 0x10B)
    struct.pack_into("<I", data, optional_offset + 60, 0x200)
    struct.pack_into("<I", data, optional_offset + 92, 16)
    struct.pack_into("<II", data, optional_offset + 96 + 14 * 8, 0x2000, 72)
    section_offset = optional_offset + optional_size
    data[section_offset:section_offset + 8] = b".text\0\0\0"
    struct.pack_into("<IIII", data, section_offset + 8, 0x1000, 0x2000, 0x1000, 0x200)
    struct.pack_into("<IHH", data, 0x200, 72, 2, 5)
    struct.pack_into("<II", data, 0x208, 0x2100, 0x100)
    struct.pack_into("<II", data, 0x210, 0x00000009, 0x06000001)
    struct.pack_into("<II", data, 0x218, 0x2200, 0x20)
    struct.pack_into("<II", data, 0x220, 0x2240, 0x80)
    struct.pack_into("<II", data, 0x230, 0x22C0, 0x20)
    data[0x300:0x304] = b"BSJB"
    struct.pack_into("<HHI", data, 0x304, 1, 1, 0)
    version = b"v4.0.30319\0\0"
    struct.pack_into("<I", data, 0x30C, len(version))
    data[0x310:0x310 + len(version)] = version
    marker = b"SAPIEN Technologies Inc.\0PowerShell Script Packager\0System.Management.Automation\0"
    data[0x700:0x700 + len(marker)] = marker
    path.write_bytes(data)


def base_record(path: Path, relative: str, magic_type: str, indicators: list[str], archive=None) -> dict:
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
            "indicators": indicators,
            "endpoint_fingerprints": [],
            "raw_strings_emitted": False,
        },
        "pe": None,
        "compound_file": None,
        "archive": archive,
    }


def write_base_result(path: Path, files: list[dict], schema="sas-package-static-analysis/v1") -> None:
    result = {
        "schema_version": schema,
        "analyzer_version": "0.1.0",
        "generated_at": "2026-07-16T00:00:00Z",
        "input": {"kind": "directory", "display_name": "fixture", "absolute_path_emitted": False, "total_bytes": sum(item["size_bytes"] for item in files)},
        "limits": {"max_files": 100, "max_total_bytes": 1000000, "max_content_bytes_per_file": 1000000, "archive_payload_extraction_allowed": False, "symlink_following_allowed": False},
        "tools": {"python_version": "3.12", "platform": "fixture", "pefile_available": False, "olefile_available": False},
        "proof": {"proof_level": "static_only", "file_execution_performed": False, "archive_payload_extracted": False, "network_activity_performed": False, "target_mutation_performed": False, "host_mutation_performed": False, "signature_trust_validated": False, "runtime_behavior_validated": False},
        "summary": {"discovered_files": len(files), "analyzed_files": len(files), "skipped_files": 0, "error_count": 0, "file_classes": {"installer": len(files)}, "indicator_counts": {}},
        "files": files,
        "skipped": [],
        "errors": [],
    }
    path.write_text(json.dumps(result), encoding="utf-8")


def test_required_surfaces_and_manifest() -> None:
    for path in (SEMANTIC, SCHEMA, MANIFEST, DOC, PS_WRAPPER, BASH_WRAPPER, WORKFLOW):
        read(path)
    manifest = json.loads(read(MANIFEST))
    assert manifest["schema_version"] == "sas-package-semantic-analysis-skill/v1"
    operation = manifest["operation"]
    assert operation["mode"] == "local_transform"
    assert operation["network_activity"] is False
    assert operation["target_mutation"] is False
    assert operation["package_execution"] is False
    assert "source_hash_reverification_required" in operation["guardrails"]


def test_semantic_sidecar_and_harness_requirements() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fixture = root / "fixture"
        output = root / "output"
        fixture.mkdir()
        managed = fixture / "managed-host.exe"
        write_fake_managed_sapien_pe(managed)
        msi = fixture / "application.msi"
        msi.write_bytes(bytes.fromhex("d0cf11e0a1b11ae1") + b"\0" * 64 + b"CustomAction ServiceInstall Registry Property")
        transform = fixture / "application.mst"
        transform.write_bytes(bytes.fromhex("d0cf11e0a1b11ae1") + b"\0" * 64 + b"Feature Property")
        files = [
            base_record(managed, managed.name, "pe", ["process_execution", "registry_changes"]),
            base_record(msi, msi.name, "ole_cfb", ["services", "registry_changes", "reboot"]),
            base_record(transform, transform.name, "ole_cfb", []),
        ]
        base = root / "package_analysis.json"
        write_base_result(base, files)
        completed = subprocess.run([sys.executable, str(SEMANTIC), "--input", str(fixture), "--base-result", str(base), "--output-dir", str(output)], cwd=ROOT, text=True, capture_output=True, check=False)
        assert completed.returncode == 0, completed.stderr
        result = json.loads((output / "package_semantic_analysis.json").read_text(encoding="utf-8"))
        english = (output / "package_semantic_analysis.txt").read_text(encoding="utf-8")
        assert result["schema_version"] == "sas-package-semantic-analysis/v1"
        assert result["summary"]["files_enriched"] == 3
        assert result["base_result"]["hash_verified_source_files"] == 3
        assert all(item["hash_verified"] is True for item in result["files"])
        by_name = {item["relative_path"]: item for item in result["files"]}
        managed_semantic = by_name[managed.name]["semantic_analysis"]
        assert managed_semantic["managed_dotnet"]["metadata_version"] == "v4.0.30319"
        assert managed_semantic["managed_dotnet"]["strong_name_signature_present"] is True
        assert {"managed_dotnet", "sapien_powershell_host", "powershell_host_material"} <= set(managed_semantic["packaging_signals"])
        assert "may_host_embedded_powershell" in {item["id"] for item in managed_semantic["behavior_inferences"]}
        msi_semantic = by_name[msi.name]["semantic_analysis"]["msi_semantics"]
        assert msi_semantic["custom_action_signal_present"] is True
        assert msi_semantic["service_signal_present"] is True
        assert msi_semantic["registry_signal_present"] is True
        requirements = result["harness_requirements"]
        assert "bind_msi_and_mst_hashes_as_one_identity" in requirements["preflight"]
        assert "enable_verbose_msi_logging" in requirements["logging"]
        assert "verify_service_start_type_and_stability" in requirements["runtime_acceptance"]
        assert "classify_msi_exit_codes_3010_and_1641" in requirements["reboot"]
        assert "retain_preinstall_snapshot_until_post_reboot_passes" in requirements["rollback"]
        assert "autologon_excluded_from_application_vm_lane" in requirements["environment"]
        assert result["proof"]["semantic_inferences_runtime_confirmed"] is False
        assert "every behavior inference requires VM or runtime confirmation" in english
        try:
            import jsonschema
        except ImportError:
            pass
        else:
            jsonschema.validate(result, json.loads(read(SCHEMA)))


def test_hash_mismatch_fails_with_evidence() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fixture = root / "fixture"
        output = root / "output"
        fixture.mkdir()
        package = fixture / "package.exe"
        write_fake_managed_sapien_pe(package)
        base = root / "package_analysis.json"
        write_base_result(base, [base_record(package, package.name, "pe", [])])
        package.write_bytes(package.read_bytes() + b"changed")
        completed = subprocess.run([sys.executable, str(SEMANTIC), "--input", str(fixture), "--base-result", str(base), "--output-dir", str(output)], cwd=ROOT, text=True, capture_output=True, check=False)
        assert completed.returncode == 1
        result = json.loads((output / "package_semantic_analysis.json").read_text(encoding="utf-8"))
        assert result["summary"]["files_enriched"] == 0
        assert result["errors"][0]["message"] == "hash_mismatch_since_base_analysis"


def test_fail_closed_base_and_sanitized_msi_classifier() -> None:
    module = load_module()
    signals = module.classify_msi_markers("CustomAction ServiceInstall Registry private-secret-value")
    assert signals == ["custom_action", "registry", "service_install"]
    assert "private-secret" not in json.dumps(signals)
    bad = {"schema_version": "unknown", "input": {"absolute_path_emitted": False}, "proof": {field: False for field in module.BASE_PROOF_FALSE_FIELDS}}
    try:
        module.validate_base_result(bad)
    except ValueError as exc:
        assert "unsupported base schema" in str(exc)
    else:
        raise AssertionError("unsupported base schema did not fail closed")


def test_dangerous_inferences_generate_controls() -> None:
    module = load_module()
    files = [{
        "semantic_analysis": {
            "packaging_signals": [],
            "behavior_inferences": [
                {"id": "may_modify_accounts_or_credential_provider"},
                {"id": "may_delete_files_broadly"},
                {"id": "may_remove_own_files"},
                {"id": "may_refresh_or_modify_group_policy"},
            ],
        }
    }]
    requirements = module.derive_harness_requirements(files)
    assert "capture_local_accounts_and_credential_providers" in requirements["preflight"]
    assert "capture_protected_file_tree_baseline" in requirements["preflight"]
    assert "verify_no_unapproved_file_deletion" in requirements["runtime_acceptance"]
    assert "restore_snapshot_on_unbounded_file_change" in requirements["rollback"]
    assert "preserve_requested_application_during_cleanup" in requirements["rollback"]
    assert "capture_group_policy_refresh_result" in requirements["logging"]


def test_symlink_substitution_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fixture = root / "fixture"
        output = root / "output"
        fixture.mkdir()
        real = fixture / "real.exe"
        write_fake_managed_sapien_pe(real)
        link = fixture / "package.exe"
        try:
            link.symlink_to(real.name)
        except (OSError, NotImplementedError):
            return
        base = root / "package_analysis.json"
        record = base_record(real, link.name, "pe", [])
        write_base_result(base, [record])
        completed = subprocess.run([sys.executable, str(SEMANTIC), "--input", str(fixture), "--base-result", str(base), "--output-dir", str(output)], cwd=ROOT, text=True, capture_output=True, check=False)
        assert completed.returncode == 1
        result = json.loads((output / "package_semantic_analysis.json").read_text(encoding="utf-8"))
        assert result["summary"]["files_enriched"] == 0
        assert result["errors"][0]["message"] == "symlink_not_followed"


def test_safety_contracts() -> None:
    schema = json.loads(read(SCHEMA))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["additionalProperties"] is False
    proof = schema["properties"]["proof"]["properties"]
    for field in ("file_execution_performed", "archive_payload_extracted", "network_activity_performed", "target_mutation_performed", "host_mutation_performed", "signature_trust_validated", "runtime_behavior_validated", "semantic_inferences_runtime_confirmed"):
        assert proof[field]["const"] is False
    source = read(SEMANTIC)
    for forbidden in ("subprocess.run([str(path)", "os.startfile", "shell=True", "requests.", "urllib.request.urlopen", "extractall("):
        assert forbidden not in source
    ps = read(PS_WRAPPER)
    assert "Start-Process" not in ps and "Invoke-WebRequest" not in ps
    assert "Invoke-SasPackageStaticAnalysis.ps1" in ps


def main() -> None:
    tests = {
        "surfaces": test_required_surfaces_and_manifest,
        "semantic": test_semantic_sidecar_and_harness_requirements,
        "hash_mismatch": test_hash_mismatch_fails_with_evidence,
        "fail_closed": test_fail_closed_base_and_sanitized_msi_classifier,
        "dangerous_controls": test_dangerous_inferences_generate_controls,
        "symlink": test_symlink_substitution_fails_closed,
        "safety": test_safety_contracts,
    }
    selected = sys.argv[1:] or list(tests)
    for name in selected:
        assert name in tests, f"unknown test group: {name}"
        print(f"RUN: {name}")
        tests[name]()
        print(f"PASS: {name}")
    print(f"PASS: {len(selected)} package semantic analysis contract groups")


if __name__ == "__main__":
    main()
