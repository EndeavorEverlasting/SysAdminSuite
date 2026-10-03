"""Deterministic H&H CC-reader firmware evidence event producer (SAS half).

Consumes canonical offline round-trip / runtime receipts and emits
``hh-cc-reader-firmware-event/v1`` handoff events for downstream consumers
(e.g. NYC H&H publication). This module:

- never contacts Payment Fusion, PAXSTORE, operational spreadsheets, company shares, or trackers;
- never invents firmware or strengthens proof ceilings;
- never authorizes mutation;
- never accepts publication metadata as an input that can rewrite execution truth.
"""
from __future__ import annotations

import hashlib
import json
import re
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RECEIPT_DIR = ROOT / "survey" / "output" / "hh-cc-reader"
SCHEMA = "hh-cc-reader-firmware-event/v1"
PRODUCER_REPOSITORY = "EndeavorEverlasting/SysAdminSuite"
PRODUCER_CONTRACT_VERSION = "1"
PRODUCER_MODULE = "harness/api/hh_cc_reader_firmware_event.py"

# Publication / tracker keys are rejected so they cannot rewrite execution truth.
FORBIDDEN_INPUT_KEY_PREFIXES = (
    "publication_",
    "tracker_",
    "drive_",
    "onedrive_",
    "google_drive_",
    "company_share_",
)
FORBIDDEN_INPUT_KEYS = frozenset(
    {
        "publication_state",
        "publication_attempt",
        "tracker_row",
        "tracker_writeback",
        "drive_file_id",
        "onedrive_path",
        "workbook_path",
        "dashboard_mutation",
        "company_share_path",
    }
)

# Weakest → strongest. Export never promotes past observed receipts.
PROOF_CEILING_RANK = (
    "UNPROVED",
    "IDENTITY_INCOMPLETE",
    "IDENTITY_CONFLICT",
    "DEVICE_MISMATCH",
    "UNIQUE_TARGET_RESOLVED",
    "BASELINE_INCOMPLETE",
    "BASELINE_LOCKED",
    "OUTDATED_CLASSIFIED",
    "RESTORE_PATH_PROVED",
    "MUTATION_PREVIEW_READY",
    "TARGET_UPDATE_PROVED",
    "ORIGINAL_STATE_RESTORED",
    "ROUNDTRIP_PROVEN",
    "SINGLE_READER_ROUNDTRIP_PROVED",
    "FINAL_TARGET_RUNTIME_VERIFIED",
)

_MAC_RE = re.compile(r"[^0-9A-Fa-f]")


def _norm_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _norm_mac(value: Any) -> str | None:
    if value is None or value == "":
        return None
    hex_digits = _MAC_RE.sub("", str(value)).upper()
    if len(hex_digits) != 12:
        return None
    return hex_digits


def _canonical_json(payload: Any) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def fingerprint_payload(payload: dict[str, Any]) -> str:
    """Stable SHA-256 over canonical JSON (deterministic event identity input)."""
    return hashlib.sha256(_canonical_json(payload).encode("utf-8")).hexdigest()


def receipt_content_fingerprint(receipt: dict[str, Any] | None) -> str | None:
    if not isinstance(receipt, dict) or not receipt:
        return None
    # Exclude non-semantic / volatile keys if ever present.
    stable = {
        key: value
        for key, value in receipt.items()
        if key
        not in {
            "exported_at",
            "export_timestamp",
            "wall_clock",
            "publication_state",
        }
    }
    return fingerprint_payload(stable)


def _reject_publication_fields(blob: Any, path: str = "root") -> None:
    if isinstance(blob, dict):
        for key, value in blob.items():
            lower = str(key).lower()
            if lower in FORBIDDEN_INPUT_KEYS or any(
                lower.startswith(prefix) for prefix in FORBIDDEN_INPUT_KEY_PREFIXES
            ):
                raise ValueError(f"publication_or_tracker_field_rejected:{path}.{key}")
            _reject_publication_fields(value, f"{path}.{key}")
    elif isinstance(blob, list):
        for index, item in enumerate(blob):
            _reject_publication_fields(item, f"{path}[{index}]")


def _rank(ceiling: str | None) -> int:
    if not ceiling:
        return 0
    try:
        return PROOF_CEILING_RANK.index(ceiling)
    except ValueError:
        return 0


def _max_ceiling(*candidates: str | None) -> str:
    best = "UNPROVED"
    for candidate in candidates:
        if _rank(candidate) > _rank(best):
            best = candidate or best
    return best


def _identity_binding(identity: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(identity, dict):
        return {}
    nested = identity.get("identity") if isinstance(identity.get("identity"), dict) else {}
    serial = _norm_text(identity.get("source_serial") or nested.get("source_serial"))
    mac = _norm_mac(identity.get("expected_mac") or nested.get("expected_mac") or identity.get("live_mac"))
    return {
        "source_serial": serial,
        "expected_mac": mac,
        "source_name": _norm_text(identity.get("source_name") or nested.get("source_name")),
        "live_ipv4": _norm_text(identity.get("live_ipv4") or nested.get("live_ipv4")),
        "state": _norm_text(identity.get("state") or nested.get("state")),
        "probe_mac_match": identity.get("probe_mac_match"),
    }


def _derive_proof_ceiling(bundle: dict[str, Any]) -> str:
    identity = bundle.get("identity") if isinstance(bundle.get("identity"), dict) else {}
    baseline = bundle.get("baseline") if isinstance(bundle.get("baseline"), dict) else {}
    eligibility = bundle.get("eligibility") if isinstance(bundle.get("eligibility"), dict) else {}
    restore = bundle.get("restore_path") if isinstance(bundle.get("restore_path"), dict) else {}
    preview = bundle.get("preview") if isinstance(bundle.get("preview"), dict) else {}
    compare = bundle.get("compare") if isinstance(bundle.get("compare"), dict) else {}
    post_update = bundle.get("post_update") if isinstance(bundle.get("post_update"), dict) else {}
    post_rollback = bundle.get("post_rollback") if isinstance(bundle.get("post_rollback"), dict) else {}
    final_runtime = bundle.get("final_runtime") if isinstance(bundle.get("final_runtime"), dict) else {}

    ceiling = "UNPROVED"
    identity_state = _norm_text(identity.get("state"))
    if identity_state:
        ceiling = _max_ceiling(ceiling, identity_state)

    if baseline:
        if baseline.get("baseline_locked") is True and _norm_text(baseline.get("state")) == "BASELINE_LOCKED":
            ceiling = _max_ceiling(ceiling, "BASELINE_LOCKED")
        else:
            ceiling = _max_ceiling(ceiling, _norm_text(baseline.get("state")) or "BASELINE_INCOMPLETE")

    if eligibility.get("outdated_classified") is True:
        ceiling = _max_ceiling(ceiling, "OUTDATED_CLASSIFIED")
    elif _norm_text(eligibility.get("state")):
        ceiling = _max_ceiling(ceiling, _norm_text(eligibility.get("state")))

    if restore.get("restore_path_proved") is True:
        ceiling = _max_ceiling(ceiling, "RESTORE_PATH_PROVED")
    elif _norm_text(restore.get("state")):
        ceiling = _max_ceiling(ceiling, _norm_text(restore.get("state")))

    if _norm_text(preview.get("state")) == "MUTATION_PREVIEW_READY":
        ceiling = _max_ceiling(ceiling, "MUTATION_PREVIEW_READY")

    post_update_state = _norm_text(post_update.get("state") or post_update.get("operation_result"))
    if post_update_state == "TARGET_UPDATE_PROVED" or (
        _norm_text(post_update.get("current_firmware_value"))
        and _norm_text(baseline.get("target_firmware_value"))
        and _norm_text(post_update.get("current_firmware_value"))
        == _norm_text(baseline.get("target_firmware_value"))
        and post_update.get("forward_update_proved") is True
    ):
        ceiling = _max_ceiling(ceiling, "TARGET_UPDATE_PROVED")

    if compare.get("roundtrip_proven") is True or _norm_text(compare.get("state")) == "ROUNDTRIP_PROVEN":
        ceiling = _max_ceiling(ceiling, "ROUNDTRIP_PROVEN")
        ceiling = _max_ceiling(ceiling, "SINGLE_READER_ROUNDTRIP_PROVED")
    if post_rollback.get("original_state_restored") is True or _norm_text(
        post_rollback.get("state")
    ) == "ORIGINAL_STATE_RESTORED":
        ceiling = _max_ceiling(ceiling, "ORIGINAL_STATE_RESTORED")

    final_state = _norm_text(final_runtime.get("state") or final_runtime.get("operation_result"))
    if final_state == "FINAL_TARGET_RUNTIME_VERIFIED" or final_runtime.get("final_runtime_verified") is True:
        ceiling = _max_ceiling(ceiling, "FINAL_TARGET_RUNTIME_VERIFIED")

    # Explicit override only when it does not strengthen beyond derived evidence.
    explicit = _norm_text(bundle.get("proof_ceiling"))
    if explicit and _rank(explicit) <= _rank(ceiling):
        return explicit
    if explicit and _rank(explicit) > _rank(ceiling):
        # Fail closed: do not accept a stronger explicit claim than receipts support.
        return ceiling
    return ceiling


def _event_class_for_ceiling(ceiling: str) -> str:
    mapping = {
        "UNPROVED": "EXECUTION_UNPROVED",
        "IDENTITY_INCOMPLETE": "IDENTITY_PROGRESS",
        "IDENTITY_CONFLICT": "IDENTITY_BLOCKED",
        "DEVICE_MISMATCH": "IDENTITY_BLOCKED",
        "UNIQUE_TARGET_RESOLVED": "IDENTITY_RESOLVED",
        "BASELINE_INCOMPLETE": "BASELINE_PROGRESS",
        "BASELINE_LOCKED": "BASELINE_LOCKED",
        "OUTDATED_CLASSIFIED": "ELIGIBILITY_CLASSIFIED",
        "RESTORE_PATH_PROVED": "RESTORE_PATH_PROVED",
        "MUTATION_PREVIEW_READY": "MUTATION_PREVIEW_READY",
        "TARGET_UPDATE_PROVED": "TARGET_UPDATE_PROVED",
        "ORIGINAL_STATE_RESTORED": "ORIGINAL_STATE_RESTORED",
        "ROUNDTRIP_PROVEN": "SINGLE_READER_ROUNDTRIP_PROVED",
        "SINGLE_READER_ROUNDTRIP_PROVED": "SINGLE_READER_ROUNDTRIP_PROVED",
        "FINAL_TARGET_RUNTIME_VERIFIED": "FINAL_TARGET_RUNTIME_VERIFIED",
    }
    return mapping.get(ceiling, "EXECUTION_PROGRESS")


def _disposition(ceiling: str, bundle: dict[str, Any]) -> str:
    if ceiling in {"IDENTITY_CONFLICT", "DEVICE_MISMATCH"}:
        return "FAILED"
    if ceiling in {
        "TARGET_UPDATE_PROVED",
        "ORIGINAL_STATE_RESTORED",
        "ROUNDTRIP_PROVEN",
        "SINGLE_READER_ROUNDTRIP_PROVED",
        "FINAL_TARGET_RUNTIME_VERIFIED",
    }:
        return "SUCCESS"
    if ceiling in {"BASELINE_INCOMPLETE", "IDENTITY_INCOMPLETE", "UNPROVED"}:
        return "BLOCKED"
    if ceiling == "UNIQUE_TARGET_RESOLVED":
        baseline = bundle.get("baseline") if isinstance(bundle.get("baseline"), dict) else {}
        if baseline and baseline.get("baseline_locked") is not True:
            return "BLOCKED"
        return "IN_PROGRESS"
    return "IN_PROGRESS"


def _downstream_interpretable(ceiling: str) -> bool:
    # Downstream may interpret progress/blocked events; completeness is separate.
    return ceiling != "UNPROVED"


def _evidence_complete_for_downstream(ceiling: str) -> bool:
    return ceiling in {
        "TARGET_UPDATE_PROVED",
        "ORIGINAL_STATE_RESTORED",
        "ROUNDTRIP_PROVEN",
        "SINGLE_READER_ROUNDTRIP_PROVED",
        "FINAL_TARGET_RUNTIME_VERIFIED",
        "BASELINE_LOCKED",
        "RESTORE_PATH_PROVED",
        "OUTDATED_CLASSIFIED",
        "MUTATION_PREVIEW_READY",
        "UNIQUE_TARGET_RESOLVED",
    }


def export_firmware_event(bundle: dict[str, Any]) -> dict[str, Any]:
    """Build one deterministic firmware evidence event from SAS receipts.

    Downstream publication systems are not consulted. Missing tracker / Drive /
    OneDrive cannot block export. Publication fields in the input are rejected.
    """
    if not isinstance(bundle, dict):
        raise ValueError("bundle_must_be_object")
    _reject_publication_fields(bundle)

    identity = bundle.get("identity") if isinstance(bundle.get("identity"), dict) else None
    baseline = bundle.get("baseline") if isinstance(bundle.get("baseline"), dict) else None
    eligibility = bundle.get("eligibility") if isinstance(bundle.get("eligibility"), dict) else None
    restore = bundle.get("restore_path") if isinstance(bundle.get("restore_path"), dict) else None
    preview = bundle.get("preview") if isinstance(bundle.get("preview"), dict) else None
    compare = bundle.get("compare") if isinstance(bundle.get("compare"), dict) else None
    post_update = bundle.get("post_update") if isinstance(bundle.get("post_update"), dict) else None
    post_rollback = bundle.get("post_rollback") if isinstance(bundle.get("post_rollback"), dict) else None
    final_runtime = bundle.get("final_runtime") if isinstance(bundle.get("final_runtime"), dict) else None

    if not any(
        isinstance(item, dict) and item
        for item in (
            identity,
            baseline,
            eligibility,
            restore,
            preview,
            compare,
            post_update,
            post_rollback,
            final_runtime,
        )
    ):
        raise ValueError("no_canonical_execution_receipts")

    # Fail closed: never invent firmware from empty observations.
    for label, blob, key in (
        ("baseline", baseline, "current_firmware_value"),
        ("post_update", post_update, "current_firmware_value"),
        ("post_rollback", post_rollback, "current_firmware_value"),
        ("final_runtime", final_runtime, "current_firmware_value"),
        ("eligibility", eligibility, "observed_firmware"),
    ):
        if isinstance(blob, dict) and key in blob and blob.get(key) in ("", None):
            # Explicit null/empty is allowed; inventing a default is not.
            continue

    binding = _identity_binding(identity or baseline or {})
    proof_ceiling = _derive_proof_ceiling(bundle)
    event_class = _norm_text(bundle.get("event_class")) or _event_class_for_ceiling(proof_ceiling)
    # Refuse an event_class that implies a stronger ceiling than evidence supports.
    implied = None
    for ceiling_name, mapped in (
        ("FINAL_TARGET_RUNTIME_VERIFIED", "FINAL_TARGET_RUNTIME_VERIFIED"),
        ("SINGLE_READER_ROUNDTRIP_PROVED", "SINGLE_READER_ROUNDTRIP_PROVED"),
        ("ROUNDTRIP_PROVEN", "ROUNDTRIP_PROVEN"),
        ("TARGET_UPDATE_PROVED", "TARGET_UPDATE_PROVED"),
        ("BASELINE_LOCKED", "BASELINE_LOCKED"),
    ):
        if event_class == mapped and _rank(proof_ceiling) < _rank(ceiling_name):
            implied = ceiling_name
            break
    if implied:
        raise ValueError(f"event_class_exceeds_proof_ceiling:{event_class}>{proof_ceiling}")

    starting_fw = None
    if isinstance(baseline, dict):
        starting_fw = _norm_text(baseline.get("current_firmware_value"))
    if starting_fw is None and isinstance(eligibility, dict):
        starting_fw = _norm_text(eligibility.get("observed_firmware"))

    target_fw = None
    if isinstance(baseline, dict):
        target_fw = _norm_text(baseline.get("target_firmware_value"))
    if target_fw is None and isinstance(eligibility, dict):
        target_fw = _norm_text(eligibility.get("target_firmware") or eligibility.get("target_firmware_value"))
    if target_fw is None:
        target_fw = _norm_text(bundle.get("governed_target_firmware"))

    resulting_fw = None
    if isinstance(final_runtime, dict):
        resulting_fw = _norm_text(final_runtime.get("current_firmware_value"))
    if resulting_fw is None and isinstance(post_update, dict):
        resulting_fw = _norm_text(post_update.get("current_firmware_value"))

    receipt_refs: list[dict[str, Any]] = []
    for name, receipt in (
        ("identity", identity),
        ("baseline", baseline),
        ("eligibility", eligibility),
        ("restore_path", restore),
        ("preview", preview),
        ("compare", compare),
        ("post_update", post_update),
        ("post_rollback", post_rollback),
        ("final_runtime", final_runtime),
    ):
        if not isinstance(receipt, dict):
            continue
        receipt_refs.append(
            {
                "receipt_kind": name,
                "artifact": receipt.get("artifact"),
                "state": receipt.get("state"),
                "content_fingerprint": receipt_content_fingerprint(receipt),
                "path_ref": _norm_text((bundle.get("receipt_paths") or {}).get(name))
                if isinstance(bundle.get("receipt_paths"), dict)
                else None,
            }
        )

    evidence_binding = {
        "schema": SCHEMA,
        "event_class": event_class,
        "execution_run_id": _norm_text(bundle.get("execution_run_id")),
        "target_logical_ref": _norm_text(bundle.get("target_logical_ref")),
        "identity_binding": {
            "source_serial": binding.get("source_serial"),
            "expected_mac": binding.get("expected_mac"),
            "identity_proof_state": binding.get("state"),
            "probe_mac_match": binding.get("probe_mac_match"),
        },
        "baseline_proof_state": _norm_text(baseline.get("state")) if isinstance(baseline, dict) else None,
        "observed_starting_firmware": starting_fw,
        "governed_target_firmware": target_fw,
        "observed_resulting_firmware": resulting_fw,
        "forward_operation_result": _norm_text(
            (post_update or {}).get("state") or (post_update or {}).get("operation_result")
        )
        if isinstance(post_update, dict)
        else None,
        "restore_operation_result": _norm_text(
            (post_rollback or {}).get("state") or (post_rollback or {}).get("operation_result")
        )
        if isinstance(post_rollback, dict)
        else None,
        "final_runtime_result": _norm_text(
            (final_runtime or {}).get("state") or (final_runtime or {}).get("operation_result")
        )
        if isinstance(final_runtime, dict)
        else None,
        "proof_ceiling": proof_ceiling,
        "receipt_fingerprints": [
            {
                "receipt_kind": item["receipt_kind"],
                "content_fingerprint": item["content_fingerprint"],
                "state": item["state"],
            }
            for item in receipt_refs
        ],
    }
    evidence_fp = fingerprint_payload(evidence_binding)
    event_id = "hh-cc-fw-evt-" + hashlib.sha256(
        f"{SCHEMA}|{evidence_fp}".encode("utf-8")
    ).hexdigest()[:32]

    timestamps: dict[str, Any] = {}
    for name, receipt in (
        ("identity", identity),
        ("baseline", baseline),
        ("compare", compare),
        ("final_runtime", final_runtime),
    ):
        if not isinstance(receipt, dict):
            continue
        captured = _norm_text(receipt.get("captured_at"))
        optional = receipt.get("optional_captured")
        if captured is None and isinstance(optional, dict):
            captured = _norm_text(optional.get("captured_at"))
        if captured:
            timestamps[name] = captured
    if isinstance(bundle.get("evidence_timestamps"), dict):
        for key, value in bundle["evidence_timestamps"].items():
            if _norm_text(value):
                timestamps[str(key)] = _norm_text(value)

    disposition = _disposition(proof_ceiling, bundle)
    event = {
        "schema": SCHEMA,
        "event_id": event_id,
        "event_class": event_class,
        "producer": {
            "repository": PRODUCER_REPOSITORY,
            "contract_version": PRODUCER_CONTRACT_VERSION,
            "module": PRODUCER_MODULE,
            "schema": SCHEMA,
        },
        "execution_run_id": _norm_text(bundle.get("execution_run_id")),
        "target_logical_ref": _norm_text(bundle.get("target_logical_ref")),
        "identity_proof_state": binding.get("state"),
        "baseline_proof_state": _norm_text(baseline.get("state")) if isinstance(baseline, dict) else None,
        "identity_binding": {
            # Runtime may carry private binding; tracked fixtures must sanitize.
            "source_serial_ref": binding.get("source_serial"),
            "expected_mac_ref": binding.get("expected_mac"),
            "source_name": binding.get("source_name"),
            "probe_mac_match": binding.get("probe_mac_match"),
        },
        "observed_starting_firmware": starting_fw,
        "governed_target_firmware": target_fw,
        "observed_resulting_firmware": resulting_fw,
        "forward_operation_result": evidence_binding["forward_operation_result"],
        "restore_operation_result": evidence_binding["restore_operation_result"],
        "final_runtime_result": evidence_binding["final_runtime_result"],
        "canonical_execution_state": proof_ceiling,
        "proof_ceiling": proof_ceiling,
        "execution_disposition": disposition,
        "downstream_interpretable": _downstream_interpretable(proof_ceiling),
        "evidence_complete_for_downstream": _evidence_complete_for_downstream(proof_ceiling),
        "authoritative_receipt_refs": receipt_refs,
        "evidence_fingerprint": evidence_fp,
        "evidence_timestamps": timestamps,
        "mutation_authorized": False,
        "publication_dependency": {
            "tracker_required": False,
            "google_drive_required": False,
            "onedrive_required": False,
            "downstream_repo_required": False,
        },
    }
    return event


def write_event(event: dict[str, Any], output: Path | None = None) -> Path:
    if output is not None:
        out = output
        out.parent.mkdir(parents=True, exist_ok=True)
    else:
        DEFAULT_RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        out = DEFAULT_RECEIPT_DIR / f"hh-cc-reader-firmware-event-{stamp}-{secrets.token_hex(4)}.json"
    out.write_text(json.dumps(event, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return out


def load_bundle(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError("bundle_must_be_object")
    # Optional: inline receipt file paths under receipt_paths.
    paths = payload.get("receipt_paths")
    if isinstance(paths, dict):
        for key, rel in paths.items():
            if key in payload and isinstance(payload[key], dict):
                continue
            if not rel:
                continue
            receipt_path = Path(str(rel))
            if not receipt_path.is_absolute():
                receipt_path = (path.parent / receipt_path).resolve()
            if receipt_path.is_file():
                loaded = json.loads(receipt_path.read_text(encoding="utf-8-sig"))
                if isinstance(loaded, dict):
                    payload[key] = loaded
    return payload


def main(argv: list[str] | None = None) -> int:
    import argparse
    import sys

    parser = argparse.ArgumentParser(
        description="Export hh-cc-reader-firmware-event/v1 from SAS execution receipts (offline)."
    )
    parser.add_argument("--input", required=True, help="Bundle JSON of canonical SAS receipts")
    parser.add_argument(
        "--output",
        help="Optional event JSON output (default: ignored survey/output/hh-cc-reader receipt)",
    )
    args = parser.parse_args(argv)

    try:
        bundle = load_bundle(Path(args.input))
        event = export_firmware_event(bundle)
    except (OSError, ValueError, json.JSONDecodeError, TypeError, KeyError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    out_path = Path(args.output) if args.output else None
    artifact = write_event(event, out_path)
    print(f"ARTIFACT={artifact}")
    print(f"EVENT_ID={event['event_id']}")
    print(f"PROOF_CEILING={event['proof_ceiling']}")
    print(f"SCHEMA={event['schema']}")
    print(json.dumps(event, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
