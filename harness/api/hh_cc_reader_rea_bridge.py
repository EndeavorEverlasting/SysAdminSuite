#!/usr/bin/env python3
"""Optional, offline REA bridge for an *already acquired* H&H CC-reader artifact.

This program NEVER contacts a reader or performs firmware updates. It evaluates
the existing SysAdminSuite portability authority before inspecting a local
artifact. REA is caller-installed; tool absence is a typed outcome, not a
request to download or bypass payment-terminal protections.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import secrets
import hashlib
import json
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from harness.api.hh_cc_reader_firmware_source_portability import evaluate_portability

SCHEMA = "sas-hh-cc-reader-rea-bridge/v1"
ALLOWED_SOURCES = frozenset({
    "AUTHORIZED_VENDOR_OR_PROVIDER", "AUTHORIZED_DEVICE_EXPORT", "SYNTHETIC_FIXTURE",
})
FIRMWARE_CLASSES = frozenset({
    "VENDOR_SIGNED_FULL_OTA", "VENDOR_SIGNED_INCREMENTAL_OTA",
    "ANDROID_AB_PAYLOAD", "VENDOR_UPDATER_CACHE",
    "GENERIC_SYSTEM_PARTITION_IMAGE",
})
MAX_INPUT = 128 * 1024 * 1024
HASH = re.compile(r"^[0-9a-fA-F]{64}$")


def _result(state: str, portability: dict[str, Any], **extra: Any) -> dict[str, Any]:
    return {
        "schema": SCHEMA,
        "state": state,
        "artifact_class": portability["artifact_class"],
        "portability_result": portability["result"],
        "mutation_authorized": False,
        "reader_contacted": False,
        "firmware_extracted_from_reader": False,
        "version_domain": "VERSION_DOMAIN_UNRESOLVED",
        "deployment_ready": False,
        **extra,
    }


def assess(manifest: dict[str, Any], *, host_os: str | None = None,
           host_arch: str | None = None) -> dict[str, Any]:
    """Preflight without REA execution or device contact.

    Return only analyzed artifact metadata and typed next action. Absolute
    artifact paths appear only in the private command receipt, never Git.
    """
    if not isinstance(manifest, dict) or not isinstance(manifest.get("artifact"), dict):
        raise ValueError("manifest.artifact must be an object")
    artifact = manifest["artifact"]
    portability = evaluate_portability(artifact)
    klass = portability["artifact_class"]
    exclusions = portability["device_unique_exclusion"]
    if portability["result"] == "POLICY_REJECTED":
        return _result("UNTRUSTED_ACQUISITION_REJECTED", portability)
    if not exclusions["clone_candidate_admitted"] or klass in {
        "SECURITY_OR_PAYMENT_STATE", "DEVICE_SPECIFIC_PARTITION",
    }:
        return _result("SENSITIVE_OR_DEVICE_UNIQUE_ARTIFACT_REJECTED", portability)
    if klass not in FIRMWARE_CLASSES | {"APK_OR_SPLIT_APK"}:
        return _result("NOT_A_LOCAL_ANALYZABLE_IMAGE", portability,
                       next_action="Acquire a legitimate local file through the established provider or authorized export route.")
    if manifest.get("source_authority") not in ALLOWED_SOURCES:
        return _result("SOURCE_AUTHORITY_REQUIRED", portability,
                       next_action="Obtain a reviewed vendor/provider or authorized read-only export provenance record.")
    raw_path = manifest.get("artifact_path")
    if not raw_path:
        return _result("ARTIFACT_NOT_ACQUIRED", portability,
                       next_action="Continue #543 provider/TMS source discovery or an already authorized accessible ADB export; no repeated OTG/PAXSTORE signup.")
    path = Path(str(raw_path)).expanduser()
    if not path.is_absolute() or path.is_symlink() or path.resolve(strict=False).is_relative_to(ROOT):
        return _result("INVALID_ARTIFACT_PATH", portability)
    if not path.is_file():
        return _result("ARTIFACT_NOT_ACQUIRED", portability,
                       next_action="Acquire and stage the actual artifact in private local storage.")
    if path.stat().st_size > MAX_INPUT or path.stat().st_size == 0:
        return _result("UNSUPPORTED_INPUT_SIZE", portability, input_size=path.stat().st_size,
                       max_supported_bytes=MAX_INPUT)
    osname = (host_os or platform.system()).lower()
    arch = (host_arch or platform.machine()).lower()
    if klass in FIRMWARE_CLASSES and (osname != "linux" or arch not in {"x86_64", "amd64"}):
        return _result("FIRMWARE_ANALYSIS_REQUIRES_LINUX_X64", portability,
                       next_action="Use a qualified Linux x64 analysis host/VM with separately supplied Binwalk 3.1.x, Unblob 26.6.x and REA.")
    expected = manifest.get("expected_sha256")
    if expected is not None and (not isinstance(expected, str) or not HASH.fullmatch(expected)):
        return _result("INVALID_EXPECTED_SHA256", portability)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    observed = digest.hexdigest()
    if expected and expected.lower() != observed:
        return _result("SOURCE_DIGEST_MISMATCH", portability, sha256=observed,
                       sha256_proves="artifact_identity_not_signature")
    subcommand = "inspect-android-package" if klass == "APK_OR_SPLIT_APK" else "inspect-firmware-regions"
    return _result("ANALYSIS_READY_NOT_EXECUTED", portability,
                   source_authority=manifest["source_authority"], sha256=observed,
                   sha256_proves="artifact_identity_not_signature",
                   verified_vendor_signature=False,
                   analysis_host={"os": osname, "architecture": arch},
                   input_size=path.stat().st_size,
                   rea_argv=["rea", subcommand, str(path)],
                   next_action="Optional read-only local analysis. Preserve original digest, REA evidence and extraction gaps; then independently prove version domain, supplier signature, package cohort and restore path.")


def invoke(preflight: dict[str, Any], *, extraction_dir: str | None = None,
           evidence_dir: Path | None = None) -> dict[str, Any]:
    """Execute ONLY an allowlisted REA local-analysis verb. Never run ADB here."""
    if preflight["state"] != "ANALYSIS_READY_NOT_EXECUTED":
        return preflight
    argv = list(preflight["rea_argv"])
    if extraction_dir is not None:
        if preflight["artifact_class"] == "APK_OR_SPLIT_APK":
            return {**preflight, "state": "EXTRACTION_NOT_SUPPORTED_FOR_APK"}
        dest = Path(extraction_dir).expanduser()
        if not dest.is_absolute() or dest.exists() or not dest.parent.is_dir():
            return {**preflight, "state": "INVALID_EXTRACTION_DESTINATION"}
        if dest.resolve(strict=False).is_relative_to(ROOT):
            return {**preflight, "state": "PUBLIC_REPOSITORY_OUTPUT_FORBIDDEN"}
        argv = ["rea", "extract-firmware", argv[2], str(dest)]
    binary = shutil.which("rea")
    if not binary:
        return {**preflight, "state": "REA_NOT_INSTALLED_OR_NOT_ON_PATH"}
    argv[0] = binary
    try:
        proc = subprocess.run(argv, timeout=130, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, check=False)
    except subprocess.TimeoutExpired:
        return {**preflight, "state": "REA_TIMED_OUT"}
    except OSError:
        return {**preflight, "state": "REA_EXECUTION_UNAVAILABLE"}
    stdout = proc.stdout[: 1024 * 1024]
    stderr = proc.stderr[: 1024 * 1024]
    evidence: dict[str, Any] = {}
    if evidence_dir is not None:
        if not evidence_dir.is_dir() or evidence_dir.resolve().is_relative_to(ROOT):
            return {**preflight, "state": "INVALID_PRIVATE_EVIDENCE_DIRECTORY"}
        stem = f"rea-{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{secrets.token_hex(5)}"
        stdout_path, stderr_path = evidence_dir / f"{stem}.stdout.bin", evidence_dir / f"{stem}.stderr.bin"
        # The captured output can contain private vendor/package paths; never publish it.
        stdout_path.write_bytes(stdout)
        stderr_path.write_bytes(stderr)
        evidence = {"rea_stdout_evidence": str(stdout_path), "rea_stderr_evidence": str(stderr_path)}
    return {**preflight, **evidence,
            "state": "REA_FINISHED_ANALYSIS_UNVERIFIED" if proc.returncode == 0 else "REA_FAILED",
            "rea_exit_code": proc.returncode,
            "rea_stdout_sha256": hashlib.sha256(stdout).hexdigest(),
            "rea_stderr_sha256": hashlib.sha256(stderr).hexdigest(),
            "rea_stdout_captured_bytes": len(stdout),
            "rea_stderr_captured_bytes": len(stderr),
            "rea_output_truncated": len(proc.stdout) > len(stdout) or len(proc.stderr) > len(stderr),
            "next_action": "Review retained REA evidence privately, classify the exact version domain and source-signature/cross-device applicability. This is not a firmware deployment approval."}


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only REA artifact gate for H&H CC Reader Suite")
    parser.add_argument("--input", required=True, help="Private local JSON descriptor")
    parser.add_argument("--output", required=True, help="Private absolute JSON receipt (never public Git)")
    parser.add_argument("--invoke", action="store_true", help="Execute allowlisted local REA inspection")
    parser.add_argument("--extract-output", help="Fresh private output directory; requires --invoke")
    args = parser.parse_args()
    dest = Path(args.output).expanduser()
    if dest.is_dir():
        dest = dest / f"rea-{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{secrets.token_hex(5)}.json"
    if not dest.is_absolute() or dest.resolve(strict=False).is_relative_to(ROOT) or not dest.parent.is_dir():
        parser.error("--output must be an absolute path in an existing private directory outside repository")
    if args.extract_output and not args.invoke:
        parser.error("--extract-output requires --invoke")
    manifest = json.loads(Path(args.input).read_text(encoding="utf-8-sig"))
    receipt = assess(manifest)
    if args.invoke:
        receipt = invoke(receipt, extraction_dir=args.extract_output, evidence_dir=dest.parent)
    with dest.open("x", encoding="utf-8") as output:
        output.write(json.dumps(receipt, indent=2) + "\n")
    print(f"STATE={receipt['state']}")
    print(f"RECEIPT={dest}")
    return 0 if receipt["state"] in {"ANALYSIS_READY_NOT_EXECUTED", "REA_FINISHED_ANALYSIS_UNVERIFIED"} else 2


if __name__ == "__main__":
    raise SystemExit(main())
