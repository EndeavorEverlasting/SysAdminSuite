#!/usr/bin/env python3
"""Convert verified static package inventory into bounded semantic and harness evidence.

This sidecar consumes the v1 SysAdminSuite package inventory, re-verifies each local file by
SHA-256, inspects managed PE/CLR and MSI/SAPIEN packaging markers without execution, and
emits concrete preflight, logging, acceptance, reboot, rollback, and VM requirements.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

SCHEMA_VERSION = "sas-package-semantic-analysis/v1"
ANALYZER_VERSION = "0.1.0"
BASE_SCHEMA_VERSION = "sas-package-static-analysis/v1"
DEFAULT_MAX_FILES = 50000
DEFAULT_MAX_SEMANTIC_BYTES = 16 * 1024**2

CLI_FLAG_NAMES = {
    0x00000001: "il_only",
    0x00000002: "32bit_required",
    0x00000008: "strong_name_signed",
    0x00000010: "native_entrypoint",
    0x00010000: "track_debug_data",
    0x00020000: "32bit_preferred",
}
INDICATOR_INFERENCES = {
    "registry_changes": "may_modify_registry",
    "services": "may_modify_services",
    "scheduled_tasks": "may_modify_scheduled_tasks",
    "reboot": "may_require_reboot",
    "autologon": "may_configure_autologon",
    "account_changes": "may_modify_accounts_or_credential_provider",
    "firewall_changes": "may_modify_firewall",
    "broad_deletion": "may_delete_files_broadly",
    "self_removal": "may_remove_own_files",
    "process_execution": "may_launch_child_processes",
    "download_or_network": "may_contact_endpoints",
    "browser_policy": "may_modify_browser_policy",
    "driver_changes": "may_modify_drivers",
    "group_policy": "may_refresh_or_modify_group_policy",
    "encoded_powershell": "contains_encoded_powershell_marker",
    "secret_like_material": "contains_secret_like_material",
}
MSI_TABLE_MARKERS = {
    "binary": "binary",
    "customaction": "custom_action",
    "directory": "directory",
    "feature": "feature",
    "file": "file",
    "installexecutesequence": "install_execute_sequence",
    "media": "media",
    "property": "property",
    "registry": "registry",
    "servicecontrol": "service_control",
    "serviceinstall": "service_install",
    "upgrade": "upgrade",
}
BASE_PROOF_FALSE_FIELDS = (
    "file_execution_performed",
    "archive_payload_extracted",
    "network_activity_performed",
    "target_mutation_performed",
    "host_mutation_performed",
    "signature_trust_validated",
    "runtime_behavior_validated",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n", delete=False, dir=path.parent) as tmp:
        tmp.write(content)
        temp_path = Path(tmp.name)
    os.replace(temp_path, path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_bounded(path: Path, max_bytes: int) -> tuple[bytes, bool]:
    with path.open("rb") as handle:
        data = handle.read(max_bytes + 1)
    return data[:max_bytes], len(data) > max_bytes


def _read_at(handle: Any, offset: int, size: int) -> bytes:
    if offset < 0 or size < 0:
        return b""
    handle.seek(offset)
    return handle.read(size)


def _rva_to_offset(rva: int, sections: list[dict[str, int]], size_of_headers: int) -> int | None:
    if rva <= 0:
        return None
    if rva < size_of_headers:
        return rva
    for section in sections:
        span = max(section["virtual_size"], section["raw_size"])
        if section["virtual_address"] <= rva < section["virtual_address"] + span:
            return section["raw_pointer"] + rva - section["virtual_address"]
    return None


def inspect_managed_pe(path: Path) -> dict[str, Any] | None:
    try:
        with path.open("rb") as handle:
            dos = _read_at(handle, 0, 64)
            if len(dos) < 64 or dos[:2] != b"MZ":
                return None
            pe_offset = struct.unpack_from("<I", dos, 0x3C)[0]
            coff = _read_at(handle, pe_offset, 24)
            if len(coff) < 24 or coff[:4] != b"PE\0\0":
                return None
            _, section_count, _, _, _, optional_size, _ = struct.unpack_from("<HHIIIHH", coff, 4)
            optional_offset = pe_offset + 24
            optional = _read_at(handle, optional_offset, optional_size)
            if len(optional) < 2:
                return None
            magic = struct.unpack_from("<H", optional, 0)[0]
            if magic == 0x10B:
                directory_offset, count_offset = 96, 92
            elif magic == 0x20B:
                directory_offset, count_offset = 112, 108
            else:
                return None
            if len(optional) < count_offset + 4:
                return None
            directory_count = struct.unpack_from("<I", optional, count_offset)[0]
            clr_entry = directory_offset + 14 * 8
            if directory_count <= 14 or len(optional) < clr_entry + 8:
                return None
            clr_rva, clr_size = struct.unpack_from("<II", optional, clr_entry)
            if not clr_rva or not clr_size:
                return None
            size_of_headers = struct.unpack_from("<I", optional, 60)[0] if len(optional) >= 64 else 0
            sections: list[dict[str, int]] = []
            section_table = optional_offset + optional_size
            for index in range(min(section_count, 256)):
                raw = _read_at(handle, section_table + index * 40, 40)
                if len(raw) < 40:
                    break
                virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<IIII", raw, 8)
                sections.append({"virtual_size": virtual_size, "virtual_address": virtual_address, "raw_size": raw_size, "raw_pointer": raw_pointer})
            cli_offset = _rva_to_offset(clr_rva, sections, size_of_headers)
            if cli_offset is None:
                return None
            cli = _read_at(handle, cli_offset, min(max(clr_size, 72), 256))
            if len(cli) < 24:
                return None
            cb = struct.unpack_from("<I", cli, 0)[0]
            metadata_rva, metadata_size = struct.unpack_from("<II", cli, 8)
            flags, entry_point = struct.unpack_from("<II", cli, 16)
            resources_rva, resources_size = struct.unpack_from("<II", cli, 24) if len(cli) >= 32 else (0, 0)
            strong_name_rva, strong_name_size = struct.unpack_from("<II", cli, 32) if len(cli) >= 40 else (0, 0)
            vtable_rva, vtable_size = struct.unpack_from("<II", cli, 48) if len(cli) >= 56 else (0, 0)
            metadata_present = False
            metadata_version = None
            metadata_offset = _rva_to_offset(metadata_rva, sections, size_of_headers)
            if metadata_offset is not None and metadata_size > 0:
                prefix = _read_at(handle, metadata_offset, 16)
                if len(prefix) >= 16 and prefix[:4] == b"BSJB":
                    version_length = struct.unpack_from("<I", prefix, 12)[0]
                    version_raw = _read_at(handle, metadata_offset + 16, min(version_length, 128))
                    metadata_version = "".join(chr(value) if 32 <= value < 127 else " " for value in version_raw).strip(" \x00")[:120] or None
                    metadata_present = True
            return {
                "cli_header_present": cb >= 24,
                "metadata_root_present": metadata_present,
                "metadata_version": metadata_version,
                "cli_flags": [name for bit, name in CLI_FLAG_NAMES.items() if flags & bit],
                "entry_point_kind": "native_rva" if flags & 0x10 and entry_point else "managed_token" if entry_point else "none",
                "entry_point_value": entry_point or None,
                "strong_name_signature_present": bool(strong_name_rva and strong_name_size),
                "managed_resources_present": bool(resources_rva and resources_size),
                "vtable_fixups_present": bool(vtable_rva and vtable_size),
                "trust_validated": False,
                "runtime_behavior_validated": False,
            }
    except (OSError, struct.error, ValueError):
        return None


def classify_msi_markers(text: str, optional_streams: Iterable[Iterable[str]] = ()) -> list[str]:
    normalized = re.sub(r"[^a-z0-9]", "", text.lower())
    stream_text = "".join(re.sub(r"[^a-z0-9]", "", "/".join(str(part) for part in parts).lower()) for parts in optional_streams)
    combined = normalized + stream_text
    return sorted({signal for token, signal in MSI_TABLE_MARKERS.items() if token in combined})


def inspect_msi(path: Path, bounded_text: str) -> dict[str, Any] | None:
    roles = {".msi": "product_package", ".msp": "patch", ".mst": "transform"}
    role = roles.get(path.suffix.lower())
    if role is None:
        return None
    streams: list[list[str]] = []
    olefile_available = False
    stream_count = None
    try:
        import olefile  # type: ignore

        olefile_available = True
        if olefile.isOleFile(str(path)):
            with olefile.OleFileIO(str(path)) as ole:
                streams = ole.listdir(streams=True, storages=False)
            stream_count = len(streams)
    except ImportError:
        pass
    except Exception:
        streams = []
    signals = classify_msi_markers(bounded_text, streams)
    signal_set = set(signals)
    return {
        "extension_role": role,
        "optional_olefile_available": olefile_available,
        "stream_count": stream_count,
        "table_signals": signals,
        "custom_action_signal_present": "custom_action" in signal_set,
        "service_signal_present": bool({"service_control", "service_install"} & signal_set),
        "registry_signal_present": "registry" in signal_set,
        "binary_signal_present": "binary" in signal_set,
        "property_signal_present": "property" in signal_set,
        "tables_decoded": False,
        "raw_stream_names_emitted": False,
    }


def inference(item_id: str, confidence: str, basis: Iterable[str]) -> dict[str, Any]:
    return {"id": item_id, "confidence": confidence, "basis": sorted(set(basis)), "runtime_confirmed": False}


def derive_semantics(path: Path, base_record: dict[str, Any], max_bytes: int) -> dict[str, Any]:
    data, truncated = read_bounded(path, max_bytes)
    text = data.decode("latin-1", "ignore")
    lower = text.lower()
    managed = inspect_managed_pe(path) if base_record.get("magic_type") == "pe" else None
    msi = inspect_msi(path, text)
    packaging: set[str] = set()
    inferences: dict[str, dict[str, Any]] = {}
    if managed:
        packaging.add("managed_dotnet")
    if "sapien" in lower and ("powershell" in lower or "system.management.automation" in lower or "script packager" in lower):
        packaging.add("sapien_powershell_host")
        basis = ["packaging:sapien_powershell_host"]
        if managed:
            basis.append("packaging:managed_dotnet")
        inferences["may_host_embedded_powershell"] = inference("may_host_embedded_powershell", "medium", basis)
    if base_record.get("magic_type") == "pe" and ("powershell" in lower or "system.management.automation" in lower):
        packaging.add("powershell_host_material")
    for marker, signal in (("7-zip sfx", "7zip_sfx"), ("winrar sfx", "winrar_sfx"), ("nullsoft install system", "nsis"), ("inno setup", "inno_setup")):
        if marker in lower:
            packaging.add(signal)
    if msi:
        packaging.add({"product_package": "windows_installer_product", "patch": "windows_installer_patch", "transform": "windows_installer_transform"}[msi["extension_role"]])
        if msi["custom_action_signal_present"]:
            inferences["may_define_msi_custom_actions"] = inference("may_define_msi_custom_actions", "low", ["msi_table_signal:custom_action"])
    archive = base_record.get("archive") or {}
    if archive.get("nested_installer_extensions"):
        packaging.add("archive_contains_installer_metadata")
    indicators = set((base_record.get("content_scan") or {}).get("indicators") or [])
    for indicator in indicators:
        item_id = INDICATOR_INFERENCES.get(indicator)
        if item_id:
            inferences[item_id] = inference(item_id, "low", [f"indicator:{indicator}"])
    endpoint_fingerprints = (base_record.get("content_scan") or {}).get("endpoint_fingerprints") or []
    if endpoint_fingerprints and "may_contact_endpoints" not in inferences:
        inferences["may_contact_endpoints"] = inference("may_contact_endpoints", "low", ["endpoint_fingerprint_present"])
    return {
        "bytes_scanned": len(data),
        "truncated": truncated,
        "managed_dotnet": managed,
        "msi_semantics": msi,
        "packaging_signals": sorted(packaging),
        "behavior_inferences": sorted(inferences.values(), key=lambda item: item["id"]),
        "raw_strings_emitted": False,
        "runtime_confirmation_required": True,
    }


def add_requirements(target: dict[str, set[str]], category: str, *values: str) -> None:
    target[category].update(values)


def derive_harness_requirements(files: list[dict[str, Any]]) -> dict[str, list[str]]:
    req: dict[str, set[str]] = {name: set() for name in ("preflight", "logging", "runtime_acceptance", "reboot", "rollback", "environment")}
    add_requirements(req, "preflight", "verify_package_hashes", "verify_publisher_trust_separately", "capture_installed_state_baseline")
    add_requirements(req, "logging", "capture_process_exit_code", "preserve_vendor_logs", "preserve_process_timeline")
    add_requirements(req, "runtime_acceptance", "verify_expected_file_and_product_delta", "separate_installer_completion_from_application_acceptance")
    add_requirements(req, "rollback", "define_owned_state_rollback", "validate_uninstall_or_snapshot_restore")
    add_requirements(req, "environment", "disposable_windows_vm", "one_package_per_clean_snapshot", "autologon_excluded_from_application_vm_lane")
    signals = {signal for item in files for signal in item["semantic_analysis"]["packaging_signals"]}
    inference_ids = {entry["id"] for item in files for entry in item["semantic_analysis"]["behavior_inferences"]}
    if "managed_dotnet" in signals:
        add_requirements(req, "preflight", "inventory_dotnet_runtime_compatibility")
        add_requirements(req, "logging", "capture_dotnet_and_application_event_errors")
        add_requirements(req, "runtime_acceptance", "observe_managed_process_or_service_stability")
    if "sapien_powershell_host" in signals:
        add_requirements(req, "preflight", "inspect_packaged_powershell_payload_when_available")
        add_requirements(req, "logging", "capture_child_process_command_lines_redacted")
        add_requirements(req, "runtime_acceptance", "verify_embedded_script_outcome_separately")
    if any(signal.startswith("windows_installer_") for signal in signals):
        add_requirements(req, "preflight", "inventory_existing_msi_product_and_upgrade_codes")
        add_requirements(req, "logging", "enable_verbose_msi_logging")
        add_requirements(req, "reboot", "classify_msi_exit_codes_3010_and_1641")
        add_requirements(req, "rollback", "preserve_shared_prerequisites_during_msi_rollback")
    if "windows_installer_transform" in signals:
        add_requirements(req, "preflight", "bind_msi_and_mst_hashes_as_one_identity", "verify_transform_selected_features")
    mapping = {
        "may_modify_registry": ("preflight", "capture_registry_baseline", "runtime_acceptance", "verify_expected_registry_delta", "rollback", "restore_only_owned_registry_state"),
        "may_modify_services": ("preflight", "capture_service_baseline", "logging", "capture_service_control_manager_events", "runtime_acceptance", "verify_service_start_type_and_stability", "rollback", "remove_only_owned_services"),
        "may_modify_scheduled_tasks": ("preflight", "capture_scheduled_task_baseline", "runtime_acceptance", "verify_owned_task_delta", "rollback", "remove_only_owned_tasks"),
        "may_require_reboot": ("preflight", "detect_pending_reboot", "reboot", "perform_post_reboot_acceptance", "rollback", "retain_preinstall_snapshot_until_post_reboot_passes"),
        "may_modify_browser_policy": ("preflight", "backup_browser_policy", "runtime_acceptance", "verify_owned_policy_entries_and_preserve_unrelated_entries", "rollback", "restore_only_owned_policy_entries"),
        "may_modify_drivers": ("preflight", "capture_driver_inventory", "runtime_acceptance", "verify_driver_signature_device_state_and_reboot", "rollback", "restore_snapshot_for_driver_failure"),
        "may_modify_firewall": ("preflight", "capture_firewall_rule_baseline", "runtime_acceptance", "verify_owned_firewall_rule_delta", "rollback", "remove_only_owned_firewall_rules"),
        "may_contact_endpoints": ("preflight", "store_endpoints_in_ignored_configuration", "logging", "redact_endpoint_values", "runtime_acceptance", "run_connectivity_checks_only_in_authorized_environment"),
        "may_launch_child_processes": ("logging", "capture_process_tree", "runtime_acceptance", "classify_child_process_exit_and_stability"),
        "may_configure_autologon": ("environment", "physical_cybernet_final_step_only", "runtime_acceptance", "require_post_reboot_console_observation"),
        "may_modify_accounts_or_credential_provider": ("preflight", "capture_local_accounts_and_credential_providers", "logging", "capture_account_and_logon_provider_events", "runtime_acceptance", "verify_owned_account_or_credential_provider_delta", "rollback", "restore_owned_account_and_credential_provider_state"),
        "may_delete_files_broadly": ("preflight", "capture_protected_file_tree_baseline", "logging", "capture_deleted_paths_redacted", "runtime_acceptance", "verify_no_unapproved_file_deletion", "rollback", "restore_snapshot_on_unbounded_file_change"),
        "may_remove_own_files": ("logging", "capture_self_cleanup_actions", "runtime_acceptance", "verify_only_owned_staging_was_removed", "rollback", "preserve_requested_application_during_cleanup"),
        "may_refresh_or_modify_group_policy": ("preflight", "capture_group_policy_baseline", "logging", "capture_group_policy_refresh_result", "runtime_acceptance", "verify_expected_group_policy_delta", "rollback", "restore_only_owned_policy_state"),
        "may_define_msi_custom_actions": ("preflight", "decode_msi_custom_action_metadata_before_vm", "logging", "capture_msi_custom_action_failures", "runtime_acceptance", "verify_custom_action_side_effects_separately"),
        "contains_encoded_powershell_marker": ("preflight", "inspect_encoded_powershell_payload_without_execution", "logging", "redact_encoded_payload_and_command_lines"),
        "contains_secret_like_material": ("preflight", "isolate_private_configuration_and_activation_material", "logging", "redact_secret_like_values"),
    }
    for item_id in inference_ids:
        parts = mapping.get(item_id)
        if parts:
            for index in range(0, len(parts), 2):
                add_requirements(req, parts[index], parts[index + 1])
    return {name: sorted(values) for name, values in req.items()}


def validate_base_result(base: dict[str, Any]) -> None:
    if base.get("schema_version") != BASE_SCHEMA_VERSION:
        raise ValueError(f"unsupported base schema: {base.get('schema_version')!r}")
    if (base.get("input") or {}).get("absolute_path_emitted") is not False:
        raise ValueError("base result does not preserve the absolute-path boundary")
    proof = base.get("proof") or {}
    for field in BASE_PROOF_FALSE_FIELDS:
        if proof.get(field) is not False:
            raise ValueError(f"base result proof field must be false: {field}")


def resolve_record_path(input_path: Path, relative_path: str) -> Path:
    if input_path.is_file():
        if input_path.is_symlink():
            raise ValueError("symlink_not_followed")
        return input_path
    pure = PurePosixPath(relative_path)
    if pure.is_absolute() or ".." in pure.parts:
        raise ValueError("unsafe relative path in base result")
    root = input_path.resolve()
    candidate = Path(os.path.abspath(root.joinpath(*pure.parts)))
    if candidate != root and root not in candidate.parents:
        raise ValueError("base result path escapes the input root")
    current = root
    for part in pure.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("symlink_not_followed")
    return candidate


def build_result(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    input_path = Path(args.input).expanduser().resolve()
    base_path = Path(args.base_result).expanduser().resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"input path does not exist: {input_path}")
    if not base_path.is_file():
        raise FileNotFoundError(f"base result does not exist: {base_path}")
    base = json.loads(base_path.read_text(encoding="utf-8"))
    validate_base_result(base)
    base_files = base.get("files") or []
    if len(base_files) > args.max_files:
        raise ValueError(f"file limit exceeded: {len(base_files)} > {args.max_files}")
    records: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    for base_record in base_files:
        relative_path = str(base_record.get("relative_path") or "")
        try:
            candidate = resolve_record_path(input_path, relative_path)
            if candidate.is_symlink():
                raise ValueError("symlink_not_followed")
            if not candidate.is_file():
                raise FileNotFoundError("source_file_missing")
            actual_hash = sha256_file(candidate)
            if actual_hash != base_record.get("sha256"):
                raise ValueError("hash_mismatch_since_base_analysis")
            semantic = derive_semantics(candidate, base_record, args.max_semantic_bytes)
            records.append({
                "relative_path": relative_path,
                "sha256": actual_hash,
                "hash_verified": True,
                "semantic_analysis": semantic,
            })
        except Exception as exc:
            errors.append({"relative_path": relative_path or "<missing>", "error_type": type(exc).__name__, "message": str(exc)[:300]})
    packaging = Counter(signal for item in records for signal in item["semantic_analysis"]["packaging_signals"])
    inferences = Counter(entry["id"] for item in records for entry in item["semantic_analysis"]["behavior_inferences"])
    result = {
        "schema_version": SCHEMA_VERSION,
        "analyzer_version": ANALYZER_VERSION,
        "generated_at": utc_now(),
        "base_result": {
            "schema_version": base["schema_version"],
            "sha256": sha256_file(base_path),
            "hash_verified_source_files": len(records),
        },
        "input": {"kind": "directory" if input_path.is_dir() else "file", "display_name": input_path.name, "absolute_path_emitted": False},
        "limits": {"max_files": args.max_files, "max_semantic_bytes_per_file": args.max_semantic_bytes, "package_execution_allowed": False, "network_activity_allowed": False},
        "proof": {
            "proof_level": "static_semantic_inference",
            "file_execution_performed": False,
            "archive_payload_extracted": False,
            "network_activity_performed": False,
            "target_mutation_performed": False,
            "host_mutation_performed": False,
            "signature_trust_validated": False,
            "runtime_behavior_validated": False,
            "semantic_inferences_runtime_confirmed": False,
        },
        "summary": {
            "base_files": len(base_files),
            "files_enriched": len(records),
            "error_count": len(errors),
            "packaging_signal_counts": dict(sorted(packaging.items())),
            "behavior_inference_counts": dict(sorted(inferences.items())),
        },
        "harness_requirements": derive_harness_requirements(records),
        "files": records,
        "errors": errors,
    }
    return result, 1 if errors else 0


def render_english(result: dict[str, Any]) -> str:
    summary = result["summary"]
    lines = [
        "PACKAGE SEMANTIC ANALYSIS",
        f"Base files: {summary['base_files']}",
        f"Files hash-verified and enriched: {summary['files_enriched']}",
        f"Errors: {summary['error_count']}",
        "",
        "Proof: static_semantic_inference",
        "- source hashes were re-verified before semantic inspection",
        "- no package code or custom action executed",
        "- no archive payload extracted",
        "- no network activity or host/target mutation",
        "- every behavior inference requires VM or runtime confirmation",
        "",
        "Packaging signals:",
    ]
    if summary["packaging_signal_counts"]:
        for name, count in sorted(summary["packaging_signal_counts"].items(), key=lambda item: (-item[1], item[0])):
            lines.append(f"- {name}: {count}")
    else:
        lines.append("- none observed")
    lines.extend(["", "Behavior inferences:"])
    if summary["behavior_inference_counts"]:
        for name, count in sorted(summary["behavior_inference_counts"].items(), key=lambda item: (-item[1], item[0])):
            lines.append(f"- {name}: {count} (not runtime-confirmed)")
    else:
        lines.append("- none observed")
    lines.extend(["", "Harness requirements:"])
    for category, values in result["harness_requirements"].items():
        lines.append(f"- {category}: {len(values)}")
        for value in values:
            lines.append(f"  - {value}")
    lines.extend(["", "Artifacts:", "- package_analysis.json", "- package_analysis.txt", "- package_semantic_analysis.json", "- package_semantic_analysis.txt"])
    return "\n".join(lines) + "\n"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--base-result", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--max-files", type=int, default=DEFAULT_MAX_FILES)
    parser.add_argument("--max-semantic-bytes", type=int, default=DEFAULT_MAX_SEMANTIC_BYTES)
    args = parser.parse_args(argv)
    if args.max_files <= 0 or args.max_semantic_bytes <= 0:
        parser.error("all limits must be positive integers")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        result, exit_code = build_result(args)
    except (FileNotFoundError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 2
    atomic_write(output_dir / "package_semantic_analysis.json", json.dumps(result, indent=2, sort_keys=True) + "\n")
    atomic_write(output_dir / "package_semantic_analysis.txt", render_english(result))
    print(render_english(result), end="")
    print(f"Evidence: {output_dir}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
