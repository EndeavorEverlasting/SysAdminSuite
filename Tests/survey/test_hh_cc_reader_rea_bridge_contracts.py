#!/usr/bin/env python3
"""Dependency-free, offline proof for the optional REA artifact bridge."""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api import hh_cc_reader_rea_bridge as bridge


def fixture(path: str | None, kind: str = "VENDOR_SIGNED_FULL_OTA") -> dict:
    return {"artifact_path": path, "source_authority": "AUTHORIZED_VENDOR_OR_PROVIDER",
            "artifact": {"artifact_class": kind, "name": "synthetic-artifact.bin",
                         "source_control_plane": "authorized_vendor",
                         "acquisition_method": "authorized_vendor_distribution",
                         "vendor_signed": kind.startswith("VENDOR_SIGNED")}}


def with_artifact(fn) -> None:
    with tempfile.TemporaryDirectory() as directory:
        file = Path(directory) / "synthetic-fw.bin"
        file.write_bytes(b"synthetic fixture; no production reader bytes")
        fn(file)


def test_absent_source_is_typed_and_does_not_reopen_exhausted_paths() -> None:
    state = bridge.assess(fixture(None), host_os="Linux", host_arch="x86_64")
    assert state["state"] == "ARTIFACT_NOT_ACQUIRED"
    assert "OTG" in state["next_action"] and "PAXSTORE signup" in state["next_action"]
    assert state["firmware_extracted_from_reader"] is False


def test_source_authority_is_independent() -> None:
    data = fixture(None)
    data["source_authority"] = "unconfirmed_public"
    assert bridge.assess(data)["state"] == "SOURCE_AUTHORITY_REQUIRED"


def test_untrusted_origin_rejected_even_with_hash() -> None:
    data = fixture(None)
    data["artifact"]["acquisition_method"] = "torrent"
    data["artifact"]["sha256"] = "f" * 64
    assert bridge.assess(data)["state"] == "UNTRUSTED_ACQUISITION_REJECTED"


def test_payment_state_forbidden() -> None:
    data = fixture(None)
    data["artifact"]["included_state"] = ["merchant_credentials", "payment_secrets"]
    assert bridge.assess(data)["state"] == "SENSITIVE_OR_DEVICE_UNIQUE_ARTIFACT_REJECTED"


def test_apk_not_device_firmware_and_windows_analysis_possible() -> None:
    def check(path: Path) -> None:
        receipt = bridge.assess(fixture(str(path), "APK_OR_SPLIT_APK"), host_os="Windows", host_arch="AMD64")
        assert receipt["state"] == "ANALYSIS_READY_NOT_EXECUTED"
        assert receipt["rea_argv"][1] == "inspect-android-package"
        assert receipt["portability_result"] == "PROVEN_NOT_PORTABLE"
        assert receipt["deployment_ready"] is False
    with_artifact(check)


def test_windows_firmware_analysis_routes_to_linux_x64() -> None:
    def check(path: Path) -> None:
        receipt = bridge.assess(fixture(str(path)), host_os="Windows", host_arch="AMD64")
        assert receipt["state"] == "FIRMWARE_ANALYSIS_REQUIRES_LINUX_X64"
        assert "rea_argv" not in receipt
    with_artifact(check)


def test_firmware_digest_not_signature_and_real_command_shape() -> None:
    def check(path: Path) -> None:
        data = fixture(str(path))
        data["expected_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        receipt = bridge.assess(data, host_os="Linux", host_arch="x86_64")
        assert receipt["state"] == "ANALYSIS_READY_NOT_EXECUTED"
        assert receipt["sha256"] == data["expected_sha256"]
        assert receipt["sha256_proves"] == "artifact_identity_not_signature"
        assert receipt["verified_vendor_signature"] is False
        assert receipt["rea_argv"][1] == "inspect-firmware-regions"
        assert receipt["mutation_authorized"] is False
    with_artifact(check)


def test_mismatched_digest_refuses_analysis() -> None:
    def check(path: Path) -> None:
        data = fixture(str(path))
        data["expected_sha256"] = "a" * 64
        assert bridge.assess(data, host_os="Linux", host_arch="x86_64")["state"] == "SOURCE_DIGEST_MISMATCH"
    with_artifact(check)


def test_marketplace_metadata_without_image_is_not_analyzable() -> None:
    data = fixture(None, "VENDOR_MARKETPLACE_OBJECT")
    assert bridge.assess(data)["state"] == "NOT_A_LOCAL_ANALYZABLE_IMAGE"


def test_rea_missing_is_typed() -> None:
    def check(path: Path) -> None:
        ready = bridge.assess(fixture(str(path)), host_os="Linux", host_arch="x86_64")
        with mock.patch.object(bridge.shutil, "which", return_value=None):
            assert bridge.invoke(ready)["state"] == "REA_NOT_INSTALLED_OR_NOT_ON_PATH"
    with_artifact(check)


def test_read_only_rea_invocation_keeps_mutation_false() -> None:
    def check(path: Path) -> None:
        ready = bridge.assess(fixture(str(path)), host_os="Linux", host_arch="x86_64")
        fake = SimpleNamespace(returncode=0, stdout=b"fixture evidence", stderr=b"")
        with mock.patch.object(bridge.shutil, "which", return_value="/usr/bin/rea"), \
             mock.patch.object(bridge.subprocess, "run", return_value=fake) as run:
            result = bridge.invoke(ready)
        assert result["state"] == "REA_FINISHED_ANALYSIS_UNVERIFIED"
        assert result["deployment_ready"] is False
        argv = run.call_args.args[0]
        assert argv[0] == "/usr/bin/rea" and argv[1] == "inspect-firmware-regions"
        assert "adb" not in json.dumps(argv).lower()
    with_artifact(check)


def test_extract_requires_fresh_private_destination() -> None:
    def check(path: Path) -> None:
        ready = bridge.assess(fixture(str(path)), host_os="Linux", host_arch="x86_64")
        assert bridge.invoke(ready, extraction_dir=str(path.parent))["state"] == "INVALID_EXTRACTION_DESTINATION"
        fake = SimpleNamespace(returncode=0, stdout=b"extracted fixture", stderr=b"")
        with mock.patch.object(bridge.shutil, "which", return_value="/usr/bin/rea"), \
             mock.patch.object(bridge.subprocess, "run", return_value=fake) as run:
            result = bridge.invoke(ready, extraction_dir=str(path.parent / "new-private-extract"))
        assert result["state"] == "REA_FINISHED_ANALYSIS_UNVERIFIED"
        assert run.call_args.args[0][1] == "extract-firmware"
    with_artifact(check)



def test_unqualified_windows_cmd_shim_is_blocked() -> None:
    def check(path: Path) -> None:
        ready = bridge.assess(fixture(str(path), "APK_OR_SPLIT_APK"),
                              host_os="Windows", host_arch="AMD64")
        with mock.patch.object(bridge.shutil, "which",
                               return_value=r"C:\\tools\\rea.cmd"), \
             mock.patch.object(bridge.subprocess, "run") as run:
            result = bridge.invoke(ready)
        assert result["state"] == "REA_SHELL_SHIM_NOT_QUALIFIED"
        run.assert_not_called()
    with_artifact(check)

def test_malformed_string_sensitive_state_is_fail_closed() -> None:
    data = fixture(None)
    data["artifact"]["included_state"] = "merchant_credentials"
    state = bridge.assess(data, host_os="Linux", host_arch="x86_64")
    assert state["state"] == "MALFORMED_PROVENANCE_OR_SENSITIVE_STATE_REJECTED"
    assert state["deployment_ready"] is False
    assert "rea_argv" not in state


def test_malformed_vendor_signature_bool_is_fail_closed() -> None:
    data = fixture(None)
    data["artifact"]["vendor_signed"] = "false"
    state = bridge.assess(data)
    assert state["state"] == "MALFORMED_PROVENANCE_OR_SENSITIVE_STATE_REJECTED"


def test_changed_source_is_not_analyzed_or_misattributed() -> None:
    def check(path: Path) -> None:
        ready = bridge.assess(fixture(str(path)), host_os="Linux", host_arch="x86_64")
        path.write_bytes(b"source changed after preflight")
        with mock.patch.object(bridge.shutil, "which", return_value="/usr/bin/rea"), \
             mock.patch.object(bridge.subprocess, "run") as run:
            result = bridge.invoke(ready)
        assert result["state"] == "SOURCE_CHANGED_SINCE_PREFLIGHT"
        assert result["deployment_ready"] is False
        run.assert_not_called()
    with_artifact(check)


def test_rea_invoked_against_digest_locked_snapshot_not_source() -> None:
    def check(path: Path) -> None:
        ready = bridge.assess(fixture(str(path)), host_os="Linux", host_arch="x86_64")
        fake = SimpleNamespace(returncode=0, stdout=b"fixture", stderr=b"")
        with mock.patch.object(bridge.shutil, "which", return_value="/usr/bin/rea"), \
             mock.patch.object(bridge.subprocess, "run", return_value=fake) as run:
            result = bridge.invoke(ready)
        assert result["state"] == "REA_FINISHED_ANALYSIS_UNVERIFIED"
        snapshot = Path(run.call_args.args[0][2])
        assert snapshot != path and snapshot.name.endswith(".bin")
        assert snapshot.parent.name.startswith("sas-rea-snapshot-")
        assert not snapshot.exists()  # scrubbed after process completes
    with_artifact(check)


def test_existing_receipt_refused_before_invocation() -> None:
    with tempfile.TemporaryDirectory() as directory:
        base = Path(directory)
        file = base / "candidate.bin"
        file.write_bytes(b"synthetic")
        manifest = base / "manifest.json"
        manifest.write_text(json.dumps(fixture(str(file))), encoding="utf-8")
        output = base / "existing.json"
        output.write_text('{"keep":"original"}', encoding="utf-8")
        with mock.patch.object(sys, "argv", [
            "bridge.py", "--input", str(manifest), "--output", str(output),
            "--invoke",
        ]), mock.patch.object(bridge, "invoke") as invoke:
            try:
                bridge.main()
            except FileExistsError:
                pass
            else:
                raise AssertionError("Existing receipt must fail before REA")
        invoke.assert_not_called()
        assert json.loads(output.read_text()) == {"keep": "original"}


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failures = 0
    for test in tests:
        try:
            test()
            print("PASS", test.__name__)
        except Exception as exc:
            failures += 1
            print("FAIL", test.__name__, repr(exc))
    raise SystemExit(1 if failures else 0)
