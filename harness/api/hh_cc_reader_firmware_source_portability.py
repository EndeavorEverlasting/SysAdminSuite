"""Firmware source/provenance + reader-to-reader portability proof tree.

Does not reject reader-derived firmware reuse generically.
Does not preapprove it. Classifies artifact, provenance, portability,
device-unique exclusions, and supported apply mechanisms.
SHA256 proves artifact identity, not trust.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

SCHEMA = "sas-hh-cc-reader-firmware-source-portability/v1"

ARTIFACT_CLASSES = frozenset(
    {
        "VENDOR_MARKETPLACE_OBJECT",
        "VENDOR_SIGNED_FULL_OTA",
        "VENDOR_SIGNED_INCREMENTAL_OTA",
        "ANDROID_AB_PAYLOAD",
        "VENDOR_UPDATER_CACHE",
        "APK_OR_SPLIT_APK",
        "GENERIC_SYSTEM_PARTITION_IMAGE",
        "DEVICE_SPECIFIC_PARTITION",
        "SECURITY_OR_PAYMENT_STATE",
        "UNKNOWN_ARTIFACT",
    }
)

PORTABILITY_RESULTS = frozenset(
    {
        "PROVEN_REUSABLE_SIGNED_ARTIFACT",
        "PROVEN_REUSABLE_FOR_SOURCE_BUILD_COHORT",
        "PROVEN_VENDOR_OBJECT_ONLY",
        "PROVEN_NOT_PORTABLE",
        "INCONCLUSIVE_TRANSPORT_REQUIRED",
        "INCONCLUSIVE_PRIVILEGE_REQUIRED",
        "AUTHORITY_GATE",
        "POLICY_REJECTED",
        "UNKNOWN",
    }
)

DEVICE_UNIQUE_MARKERS = frozenset(
    {
        "userdata",
        "merchant_credentials",
        "merchant_configuration",
        "terminal_identity",
        "imei",
        "device_identity",
        "payment_secrets",
        "keys",
        "secure_element_state",
        "tee_rki",
        "pan",
        "track_data",
        "pin_data",
        "device_specific_provisioning",
    }
)

UNTRUSTED_ACQUISITION = frozenset(
    {
        "torrent",
        "public_mirror",
        "unverified_web",
        "anonymous_download",
    }
)


def classify_artifact(descriptor: dict[str, Any]) -> str:
    explicit = descriptor.get("artifact_class")
    if isinstance(explicit, str) and explicit in ARTIFACT_CLASSES:
        return explicit
    kind = str(descriptor.get("kind") or descriptor.get("type") or "").lower()
    path = str(descriptor.get("path") or descriptor.get("name") or "").lower()
    if descriptor.get("security_or_payment_state") or any(
        m in kind or m in path for m in ("userdata", "tee", "rki", "secure_element", "payment")
    ):
        return "SECURITY_OR_PAYMENT_STATE"
    if "payload.bin" in path or descriptor.get("ab_payload") or kind == "ab_payload":
        return "ANDROID_AB_PAYLOAD"
    if descriptor.get("incremental") or "incremental" in kind:
        if descriptor.get("vendor_signed"):
            return "VENDOR_SIGNED_INCREMENTAL_OTA"
    if descriptor.get("vendor_signed") and (
        descriptor.get("full_ota") or kind in {"full_ota", "ota_zip"} or path.endswith(".zip")
    ):
        return "VENDOR_SIGNED_FULL_OTA"
    if descriptor.get("marketplace_object") or kind in {"fmname", "marketplace"}:
        return "VENDOR_MARKETPLACE_OBJECT"
    if descriptor.get("updater_cache") or "cache" in kind:
        return "VENDOR_UPDATER_CACHE"
    if path.endswith(".apk") or kind in {"apk", "split_apk"}:
        return "APK_OR_SPLIT_APK"
    if descriptor.get("device_specific_partition"):
        return "DEVICE_SPECIFIC_PARTITION"
    if descriptor.get("raw_partition") or kind in {"partition", "system_image"}:
        return "GENERIC_SYSTEM_PARTITION_IMAGE"
    return "UNKNOWN_ARTIFACT"


def extract_provenance(descriptor: dict[str, Any]) -> dict[str, Any]:
    return {
        "source_control_plane": descriptor.get("source_control_plane"),
        "source_reader_model": descriptor.get("source_reader_model") or descriptor.get("model"),
        "source_sku": descriptor.get("source_sku"),
        "source_android_build": descriptor.get("source_android_build"),
        "source_paydroid_build": descriptor.get("source_paydroid_build"),
        "firmware_package_name": descriptor.get("firmware_package_name")
        or descriptor.get("fm_name")
        or descriptor.get("name"),
        "signature_manifest_disposition": descriptor.get("signature_manifest_disposition")
        or ("VENDOR_SIGNED" if descriptor.get("vendor_signed") else "UNKNOWN"),
        "sha256": descriptor.get("sha256"),
        "sha256_proves": "artifact_identity_not_trust",
        "ota_metadata": descriptor.get("ota_metadata") or {},
        "original_path_or_source": descriptor.get("path") or descriptor.get("source"),
        "acquisition_method": descriptor.get("acquisition_method"),
    }


def device_unique_exclusions(descriptor: dict[str, Any]) -> dict[str, Any]:
    claimed = set(descriptor.get("included_state") or [])
    excluded = sorted(DEVICE_UNIQUE_MARKERS)
    illegal = sorted(claimed & DEVICE_UNIQUE_MARKERS)
    return {
        "excluded_from_clone_candidate": excluded,
        "illegal_inclusions_present": illegal,
        "clone_candidate_admitted": len(illegal) == 0
        and classify_artifact(descriptor)
        not in {"SECURITY_OR_PAYMENT_STATE", "DEVICE_SPECIFIC_PARTITION"},
    }


def classify_apply_mechanism(descriptor: dict[str, Any], artifact_class: str) -> str:
    explicit = descriptor.get("apply_mechanism")
    if isinstance(explicit, str) and explicit:
        return explicit
    if artifact_class == "VENDOR_MARKETPLACE_OBJECT":
        return "PAXSTORE_VENDOR_OTA"
    if artifact_class in {"VENDOR_SIGNED_FULL_OTA", "VENDOR_SIGNED_INCREMENTAL_OTA"}:
        return descriptor.get("preferred_apply") or "VENDOR_UPDATER_OR_RECOVERY"
    if artifact_class == "ANDROID_AB_PAYLOAD":
        return "UPDATE_ENGINE_PAYLOAD"
    if artifact_class == "APK_OR_SPLIT_APK":
        return "PACKAGE_INSTALLER_NOT_FIRMWARE"
    if artifact_class in {"SECURITY_OR_PAYMENT_STATE", "DEVICE_SPECIFIC_PARTITION"}:
        return "NO_SUPPORTED_CLONE_MECHANISM"
    return "NO_CURRENTLY_SUPPORTED_MECHANISM"


def evaluate_portability(descriptor: dict[str, Any]) -> dict[str, Any]:
    artifact_class = classify_artifact(descriptor)
    provenance = extract_provenance(descriptor)
    exclusions = device_unique_exclusions(descriptor)
    apply_mechanism = classify_apply_mechanism(descriptor, artifact_class)
    acquisition = str(descriptor.get("acquisition_method") or "").lower()

    ota_meta = provenance.get("ota_metadata") or {}
    incremental = artifact_class == "VENDOR_SIGNED_INCREMENTAL_OTA" or bool(
        descriptor.get("incremental")
    )
    required_source_build = ota_meta.get("pre_build") or descriptor.get("required_source_build")
    target_build = descriptor.get("target_build") or ota_meta.get("post_build")
    source_build_match = None
    if incremental and required_source_build:
        actual = descriptor.get("target_current_build")
        source_build_match = bool(actual and actual == required_source_build)

    portability = {
        "full_vs_incremental": "incremental" if incremental else "full",
        "required_source_build": required_source_build,
        "source_build_match": source_build_match,
        "pre_device_binding": ota_meta.get("pre_device"),
        "pre_build_fingerprint_binding": ota_meta.get("pre_build") or ota_meta.get("pre_fingerprint"),
        "post_build": target_build or ota_meta.get("post_build"),
        "target_model_sku": descriptor.get("target_model") or descriptor.get("target_sku"),
        "android_paydroid_compatibility": descriptor.get("android_paydroid_compatibility"),
        "ab_mechanism": artifact_class == "ANDROID_AB_PAYLOAD" or bool(descriptor.get("ab_payload")),
        "rollback_avb_constraints": descriptor.get("rollback_avb_constraints"),
        "eligible_fleet_cohort": descriptor.get("eligible_fleet_cohort") or "UNDETERMINED",
        "all_a80_assumed_compatible": False,
        "all_a80_assumed_incompatible": False,
    }

    result = "UNKNOWN"
    reasons: list[str] = []

    if acquisition in UNTRUSTED_ACQUISITION:
        result = "POLICY_REJECTED"
        reasons.append("untrusted_acquisition_not_production_safe_despite_hash")
    elif artifact_class == "SECURITY_OR_PAYMENT_STATE" or not exclusions["clone_candidate_admitted"]:
        result = "PROVEN_NOT_PORTABLE"
        reasons.append("device_unique_or_security_state_excluded")
    elif artifact_class == "DEVICE_SPECIFIC_PARTITION":
        result = "PROVEN_NOT_PORTABLE"
        reasons.append("device_specific_partition")
    elif artifact_class == "GENERIC_SYSTEM_PARTITION_IMAGE":
        result = "AUTHORITY_GATE"
        reasons.append("raw_partition_not_automatically_admitted")
    elif artifact_class == "VENDOR_MARKETPLACE_OBJECT":
        result = "PROVEN_VENDOR_OBJECT_ONLY"
        reasons.append("marketplace_object_identity_only")
    elif artifact_class == "VENDOR_SIGNED_INCREMENTAL_OTA":
        if source_build_match is True:
            result = "PROVEN_REUSABLE_FOR_SOURCE_BUILD_COHORT"
            reasons.append("incremental_source_build_match")
        elif source_build_match is False:
            result = "PROVEN_NOT_PORTABLE"
            reasons.append("incremental_source_build_mismatch")
        else:
            result = "INCONCLUSIVE_TRANSPORT_REQUIRED"
            reasons.append("incremental_needs_source_build_observation")
    elif artifact_class == "VENDOR_SIGNED_FULL_OTA":
        if descriptor.get("vendor_signed"):
            result = "PROVEN_REUSABLE_SIGNED_ARTIFACT"
            reasons.append("vendor_signed_full_ota")
        else:
            result = "UNKNOWN"
            reasons.append("full_ota_signature_unproved")
    elif artifact_class == "ANDROID_AB_PAYLOAD":
        result = "INCONCLUSIVE_PRIVILEGE_REQUIRED"
        reasons.append("ab_payload_requires_update_engine_privilege_and_compat_proof")
    elif artifact_class == "APK_OR_SPLIT_APK":
        result = "PROVEN_NOT_PORTABLE"
        reasons.append("apk_is_not_device_firmware_image")
    elif descriptor.get("transport_required"):
        result = "INCONCLUSIVE_TRANSPORT_REQUIRED"
        reasons.append("capable_transport_not_yet_available")
    elif descriptor.get("privilege_required"):
        result = "INCONCLUSIVE_PRIVILEGE_REQUIRED"
        reasons.append("privilege_not_available")

    # Never emit a generic "cloning unsafe" token
    assert "cloning unsafe" not in " ".join(reasons)

    return {
        "schema": SCHEMA,
        "artifact": "firmware-source-portability-evaluation",
        "artifact_class": artifact_class,
        "provenance": provenance,
        "portability": portability,
        "device_unique_exclusion": exclusions,
        "supported_apply_mechanism": apply_mechanism,
        "result": result,
        "reasons": reasons,
        "mutation_performed": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Classify firmware source/portability proof tree")
    parser.add_argument("--input", required=True, help="Artifact descriptor JSON")
    parser.add_argument("--output", default=None)
    args = parser.parse_args(argv)
    descriptor = json.loads(Path(args.input).read_text(encoding="utf-8-sig"))
    result = evaluate_portability(descriptor)
    text = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"RECEIPT={args.output}", file=sys.stderr)
    else:
        out_dir = ROOT / "survey" / "output" / "hh-cc-reader"
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / "hh-cc-reader-firmware-portability.json"
        path.write_text(text, encoding="utf-8")
        print(f"RECEIPT={path}", file=sys.stderr)
    print(text, end="")
    return 0 if result.get("result") in PORTABILITY_RESULTS else 2


if __name__ == "__main__":
    raise SystemExit(main())
