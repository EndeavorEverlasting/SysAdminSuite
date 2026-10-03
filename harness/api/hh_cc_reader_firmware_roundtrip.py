"""Offline H&H CC-reader firmware round-trip and batch admission seams.

Implements fail-closed contracts for:
  - unique target identity correlation
  - pre-mutation baseline freeze
  - restore-path proof gating
  - mutation admission (never invents live access)
  - baseline vs post-update vs post-rollback comparison
  - tabular batch-row normalization

This module never contacts Payment Fusion, PAXSTORE, or any reader network
surface and never authorizes mutation by itself. Live identifiers and
credentials must stay outside Git inputs.
"""
from __future__ import annotations

import csv
import json
import re
import secrets
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_POLICY_PATH = ROOT / "harness" / "api" / "hh-cc-reader-firmware-policy.json"
DEFAULT_RECEIPT_DIR = ROOT / "survey" / "output" / "hh-cc-reader"
SCHEMA = "sas-hh-cc-reader-firmware-roundtrip/v1"
BATCH_SCHEMA = "sas-hh-cc-reader-firmware-batch-row/v1"
POLICY_SCHEMA_VERSION = "sas-hh-cc-reader-firmware-policy/v1"

# Historical READERUNK specimen values must never bind to experimental targets.
FORBIDDEN_READERUNK_IPV4 = "10.217.101.192"
FORBIDDEN_READERUNK_MAC = "C840523C54B6"

REQUIRED_BASELINE_FIELDS = (
    "source_serial",
    "expected_mac",
    "current_firmware_value",
    "target_firmware_value",
    "identity_proof_state",
)

REQUIRED_RESTORE_FIELDS = (
    "starting_firmware_value",
    "restore_mechanism",
    "restore_package_or_release_ref",
    "rollback_verb",
    "post_restore_acceptance",
)

MATERIAL_COMPARE_FIELDS = (
    "source_serial",
    "expected_mac",
    "current_firmware_value",
    "application_build_value",
    "reader_ipv4",
    "configuration_profile_ref",
    "endpoint_server_values",
    "reader_settings_ref",
    "health_status",
)

BATCH_REQUIRED_COLUMNS = (
    "source_serial",
    "source_name",
    "expected_mac",
    "observed_firmware",
    "active_outdated",
    "target_firmware",
    "action",
)

BATCH_ACTIONS = frozenset({"PLAN", "UPDATE", "RESTORE"})

IDENTITY_RECOVERY_PROBLEMS = frozenset(
    {
        "missing_source_serial",
        "missing_expected_mac",
        "invalid_expected_mac",
        "duplicate_source_serial",
        "duplicate_expected_mac",
        "readerunk_mac_rejected",
    }
)

IDENTITY_TRANCHE_SERIAL_AND_MAC = "SERIAL_AND_MAC"
IDENTITY_TRANCHE_SERIAL_ONLY = "SERIAL_ONLY"
IDENTITY_TRANCHE_MAC_ONLY = "MAC_ONLY"
IDENTITY_TRANCHE_INSUFFICIENT = "IDENTITY_INSUFFICIENT"
IDENTITY_TRANCHE_INVALID = "IDENTITY_INVALID"

NETWORK_ENVIRONMENTS = frozenset(
    {
        "HOSPITAL_GUEST_SHARED",
        "CONSUMER_LAB",
        "PROTECTED_ENTERPRISE",
        "OTHER_SHARED",
    }
)

# Approved MAC forms only (colon, hyphen, or compact). No arbitrary stripping.
_MAC_COLON = re.compile(r"^(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")
_MAC_HYPHEN = re.compile(r"^(?:[0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$")
_MAC_COMPACT = re.compile(r"^[0-9A-Fa-f]{12}$")
_IPV4_RE = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d?\d)$"
)


def _norm_mac(value: Any) -> str | None:
    """Normalize an approved MAC form to compact uppercase hex.

    Accepts only colon-delimited, hyphen-delimited, or compact 12-hex forms.
    Malformed decoration is rejected rather than stripped into validity.
    """
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if _MAC_COLON.match(text) or _MAC_HYPHEN.match(text):
        return re.sub(r"[^0-9A-Fa-f]", "", text).upper()
    if _MAC_COMPACT.match(text):
        return text.upper()
    return None


def _norm_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None


def _norm_ipv4(value: Any) -> str | None:
    text = _norm_text(value)
    if text is None:
        return None
    if not _IPV4_RE.match(text):
        raise ValueError(f"invalid_ipv4:{text}")
    return text


def _identity_key(serial: Any, mac: Any) -> tuple[str | None, str | None]:
    return _norm_text(serial), _norm_mac(mac)


def classify_identity_tranche(candidate: dict[str, Any]) -> dict[str, Any]:
    """Classify inventory identity completeness without weakening mutation gates.

    The tranche is planning/recovery metadata only. It never authorizes subnet
    discovery or mutation. SERIAL_AND_MAC means the inventory inputs are ready
    for an exact one-target MAC-gated probe; live correlation is still required.
    """
    serial = _norm_text(candidate.get("source_serial"))
    raw_mac = candidate.get("expected_mac")
    mac = _norm_mac(raw_mac)
    malformed_mac = raw_mac not in (None, "") and mac is None

    if malformed_mac:
        tranche = IDENTITY_TRANCHE_INVALID
        next_gate = "CORRECT_MALFORMED_MAC"
    elif serial and mac:
        tranche = IDENTITY_TRANCHE_SERIAL_AND_MAC
        next_gate = "MAC_GATED_ONE_TARGET_PROBE"
    elif serial:
        tranche = IDENTITY_TRANCHE_SERIAL_ONLY
        next_gate = "RECOVER_MAC_FROM_PHYSICAL_OR_AUTHORIZED_MANAGEMENT_EVIDENCE"
    elif mac:
        tranche = IDENTITY_TRANCHE_MAC_ONLY
        next_gate = "RECOVER_SERIAL_FROM_TRACKER_PHYSICAL_OR_AUTHORIZED_MANAGEMENT_EVIDENCE"
    else:
        tranche = IDENTITY_TRANCHE_INSUFFICIENT
        next_gate = "RECONCILE_READER_IDENTITY_BEFORE_NETWORK_PROBE"

    return {
        "tranche": tranche,
        "source_serial": serial,
        "expected_mac": mac,
        "inventory_inputs_complete": tranche == IDENTITY_TRANCHE_SERIAL_AND_MAC,
        "next_gate": next_gate,
        "broad_discovery_authorized": False,
        "mutation_authorized": False,
    }


def _field_value(blob: dict[str, Any], field: str) -> Any:
    if field in blob and blob.get(field) not in (None, ""):
        return blob.get(field)
    optional = blob.get("optional_captured") or {}
    if field in optional and optional.get(field) not in (None, ""):
        return optional.get(field)
    identity = blob.get("identity") or {}
    if field == "source_serial":
        return identity.get("source_serial") or blob.get("source_serial")
    if field == "expected_mac":
        return _norm_mac(identity.get("expected_mac") or blob.get("expected_mac"))
    if field == "reader_ipv4":
        return identity.get("live_ipv4") or blob.get("reader_ipv4")
    if field == "current_firmware_value":
        return blob.get("current_firmware_value")
    return None


def _receipt_identity(blob: dict[str, Any] | None) -> tuple[str | None, str | None]:
    if not isinstance(blob, dict):
        return None, None
    identity = blob.get("identity") if isinstance(blob.get("identity"), dict) else {}
    serial = _norm_text(
        identity.get("source_serial")
        or blob.get("source_serial")
        or blob.get("target_source_serial")
    )
    mac = _norm_mac(
        identity.get("expected_mac")
        or blob.get("expected_mac")
        or blob.get("target_mac")
        or blob.get("live_mac")
    )
    return serial, mac


def _require_same_device(
    left: dict[str, Any] | None,
    right: dict[str, Any] | None,
    *,
    label: str,
) -> list[str]:
    blockers: list[str] = []
    left_serial, left_mac = _receipt_identity(left)
    right_serial, right_mac = _receipt_identity(right)
    if not left_serial or not right_serial or left_serial != right_serial:
        blockers.append(f"{label}_source_serial_mismatch")
    if not left_mac or not right_mac or left_mac != right_mac:
        blockers.append(f"{label}_expected_mac_mismatch")
    return blockers


def load_policy(path: Path = DEFAULT_POLICY_PATH) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if data.get("schema_version") != POLICY_SCHEMA_VERSION:
        raise ValueError(
            f"unexpected firmware policy schema_version: {data.get('schema_version')!r}"
        )
    selection = data.get("selection")
    if not isinstance(selection, dict):
        raise ValueError("firmware policy missing selection object")
    if not _norm_text(selection.get("default_target")):
        raise ValueError("firmware policy missing selection.default_target")
    return data


def default_target_firmware(policy: dict[str, Any] | None = None) -> str:
    policy = policy if policy is not None else load_policy()
    target = _norm_text((policy.get("selection") or {}).get("default_target"))
    if not target:
        raise ValueError("firmware policy missing selection.default_target")
    return target


def resolve_target_identity(candidate: dict[str, Any]) -> dict[str, Any]:
    """Correlate tracker/network/management identity; fail closed on ambiguity."""
    source_serial = _norm_text(candidate.get("source_serial"))
    source_name = _norm_text(candidate.get("source_name"))
    expected_mac = _norm_mac(candidate.get("expected_mac"))
    live_mac = _norm_mac(candidate.get("live_mac"))
    live_ipv4 = candidate.get("live_ipv4")
    if live_ipv4 is not None and str(live_ipv4).strip():
        live_ipv4 = _norm_ipv4(live_ipv4)
    else:
        live_ipv4 = None
    probe_mac_match = candidate.get("probe_mac_match")
    raw_network_environment = _norm_text(candidate.get("network_environment"))
    network_environment = raw_network_environment.upper() if raw_network_environment else None
    conflicts = list(candidate.get("identity_conflicts") or [])
    reasons: list[str] = []
    tranche = classify_identity_tranche(candidate)

    if not source_serial:
        reasons.append("missing_source_serial")
    if candidate.get("expected_mac") not in (None, "") and expected_mac is None:
        reasons.append("malformed_expected_mac")
    elif not expected_mac:
        reasons.append("missing_or_invalid_expected_mac")
    if candidate.get("live_mac") not in (None, "") and live_mac is None:
        reasons.append("malformed_live_mac")
    if network_environment is None:
        reasons.append("network_environment_unclassified")
    elif network_environment not in NETWORK_ENVIRONMENTS:
        reasons.append("network_environment_invalid")

    if live_ipv4 == FORBIDDEN_READERUNK_IPV4:
        reasons.append("readerunk_ipv4_leakage_rejected")
    if expected_mac == FORBIDDEN_READERUNK_MAC or live_mac == FORBIDDEN_READERUNK_MAC:
        reasons.append("readerunk_mac_leakage_rejected")

    if live_mac and expected_mac and live_mac != expected_mac:
        reasons.append("live_mac_mismatch")
        conflicts.append({"field": "mac", "expected": expected_mac, "observed": live_mac})

    if probe_mac_match is False:
        reasons.append("probe_mac_match_false")
    elif probe_mac_match is not True:
        reasons.append("probe_mac_match_not_proved")

    if live_ipv4 is None:
        reasons.append("live_ipv4_missing")

    if conflicts:
        reasons.append("identity_conflicts_present")

    alternate = candidate.get("alternate_identities") or []
    if isinstance(alternate, list) and len(alternate) > 1:
        reasons.append("ambiguous_alternate_identities")

    unique = not reasons
    state = "UNIQUE_TARGET_RESOLVED" if unique else "IDENTITY_CONFLICT"
    if "readerunk_ipv4_leakage_rejected" in reasons or "readerunk_mac_leakage_rejected" in reasons:
        state = "DEVICE_MISMATCH"
    elif any(
        reason
        in {
            "missing_source_serial",
            "missing_or_invalid_expected_mac",
            "malformed_expected_mac",
            "malformed_live_mac",
            "probe_mac_match_not_proved",
            "live_ipv4_missing",
            "network_environment_unclassified",
            "network_environment_invalid",
        }
        for reason in reasons
    ):
        state = "IDENTITY_INCOMPLETE"

    return {
        "schema": SCHEMA,
        "artifact": "target-resolution-receipt",
        "state": state,
        "unique_target": unique,
        "source_serial": source_serial,
        "source_name": source_name,
        "identity_tranche": tranche["tranche"],
        "identity_next_gate": tranche["next_gate"],
        "broad_discovery_authorized": False,
        "expected_mac": expected_mac,
        "live_mac": live_mac,
        "live_ipv4": live_ipv4,
        "probe_mac_match": probe_mac_match,
        "network_environment": network_environment,
        "network_environment_classified": network_environment in NETWORK_ENVIRONMENTS,
        "rejection_reasons": reasons,
        "identity_conflicts": conflicts,
        "mutation_authorized": False,
    }


def freeze_baseline(observation: dict[str, Any], identity: dict[str, Any] | None = None) -> dict[str, Any]:
    """Freeze a pre-mutation baseline receipt. Missing/mismatched fields block mutation."""
    identity = identity if identity is not None else resolve_target_identity(observation)
    missing = [field for field in REQUIRED_BASELINE_FIELDS if not _norm_text(observation.get(field))]
    if identity.get("state") != "UNIQUE_TARGET_RESOLVED":
        missing.append("unique_target_identity")
    if observation.get("identity_proof_state") != "UNIQUE_TARGET_RESOLVED":
        if "identity_proof_state" not in missing:
            missing.append("identity_proof_state_not_unique")

    observation_serial, observation_mac = _identity_key(
        observation.get("source_serial"), observation.get("expected_mac")
    )
    identity_serial, identity_mac = _identity_key(
        identity.get("source_serial"), identity.get("expected_mac")
    )
    if observation_serial != identity_serial:
        missing.append("source_serial_identity_mismatch")
    if observation_mac is None or identity_mac is None or observation_mac != identity_mac:
        missing.append("expected_mac_identity_mismatch")

    optional_captured = {
        field: observation.get(field)
        for field in (
            "application_build_value",
            "reader_ipv4",
            "pfcc_axia_identity_ref",
            "configuration_profile_ref",
            "endpoint_server_values",
            "reader_settings_ref",
            "batch_or_config_state_ref",
            "package_version_identifiers",
            "health_status",
            "authority_result_ref",
            "native_config_export_ref",
            "captured_at",
        )
        if observation.get(field) not in (None, "")
    }

    locked = not missing
    return {
        "schema": SCHEMA,
        "artifact": "pre-mutation-baseline",
        "state": "BASELINE_LOCKED" if locked else "BASELINE_INCOMPLETE",
        "baseline_locked": locked,
        "missing_fields": missing,
        "identity": {
            "source_serial": identity_serial,
            "source_name": identity.get("source_name"),
            "expected_mac": identity_mac,
            "live_ipv4": identity.get("live_ipv4") or observation.get("reader_ipv4"),
            "state": identity.get("state"),
        },
        "source_serial": identity_serial,
        "expected_mac": identity_mac,
        "current_firmware_value": _norm_text(observation.get("current_firmware_value")),
        "target_firmware_value": _norm_text(observation.get("target_firmware_value")),
        "optional_captured": optional_captured,
        "mutation_authorized": False,
    }


def evaluate_restore_path(restore_evidence: dict[str, Any], baseline: dict[str, Any] | None = None) -> dict[str, Any]:
    """Prove restoration is possible before any forward mutation."""
    missing = [field for field in REQUIRED_RESTORE_FIELDS if not _norm_text(restore_evidence.get(field))]
    if baseline is None:
        missing.append("baseline_missing")
    elif not baseline.get("baseline_locked"):
        missing.append("baseline_not_locked")
    else:
        missing.extend(_require_same_device(baseline, restore_evidence, label="restore"))
        starting = _norm_text(restore_evidence.get("starting_firmware_value"))
        baseline_fw = _norm_text(baseline.get("current_firmware_value"))
        if starting and baseline_fw and starting != baseline_fw:
            missing.append("starting_firmware_mismatch_vs_baseline")

    serial, mac = _receipt_identity(restore_evidence)
    if baseline is not None and baseline.get("baseline_locked"):
        serial, mac = _receipt_identity(baseline)

    proved = not missing
    return {
        "schema": SCHEMA,
        "artifact": "restore-path-proof",
        "state": "RESTORE_PATH_PROVED" if proved else "RESTORE_PATH_INCOMPLETE",
        "restore_path_proved": proved,
        "missing_fields": missing,
        "identity": {"source_serial": serial, "expected_mac": mac},
        "source_serial": serial,
        "expected_mac": mac,
        "restore_plan": {
            field: _norm_text(restore_evidence.get(field)) for field in REQUIRED_RESTORE_FIELDS
        },
        "mutation_authorized": False,
    }


def evaluate_outdated_eligibility(
    *,
    observed_firmware: str | None,
    active_outdated: Any,
    target_firmware: str | None = None,
    policy: dict[str, Any] | None = None,
    source_serial: str | None = None,
    expected_mac: str | None = None,
) -> dict[str, Any]:
    """Classify OUTDATED under existing tracker/policy rules without inventing."""
    target = _norm_text(target_firmware)
    if target is None:
        target = default_target_firmware(policy)
    observed = _norm_text(observed_firmware)
    outdated_text = _norm_text(active_outdated)
    reasons: list[str] = []
    serial, mac = _identity_key(source_serial, expected_mac)

    if not observed:
        reasons.append("observed_firmware_missing")
    if outdated_text is None:
        reasons.append("active_outdated_missing")

    tracker_yes = outdated_text is not None and outdated_text.strip().lower() in {
        "yes",
        "y",
        "true",
        "1",
        "outdated",
    }
    tracker_no = outdated_text is not None and outdated_text.strip().lower() in {
        "no",
        "n",
        "false",
        "0",
        "current",
    }

    if observed and observed == target:
        if tracker_yes:
            state = "RECONCILIATION_REQUIRED"
            outdated = False
            reasons.append("tracker_outdated_but_observed_equals_target")
        else:
            state = "ALREADY_ON_TARGET"
            outdated = False
            reasons.append("observed_equals_target")
    elif tracker_yes and observed and observed != target:
        state = "OUTDATED_CLASSIFIED"
        outdated = True
    elif tracker_no and observed and observed != target:
        state = "RECONCILIATION_REQUIRED"
        outdated = False
        reasons.append("tracker_not_outdated_but_firmware_differs_from_target")
    else:
        state = "ELIGIBILITY_INCOMPLETE"
        outdated = False

    return {
        "schema": SCHEMA,
        "artifact": "update-eligibility",
        "state": state,
        "outdated_classified": outdated,
        "observed_firmware": observed,
        "target_firmware": target,
        "active_outdated": outdated_text,
        "identity": {"source_serial": serial, "expected_mac": mac},
        "source_serial": serial,
        "expected_mac": mac,
        "reasons": reasons,
        "mutation_authorized": False,
    }


def evaluate_mutation_admission(
    *,
    identity: dict[str, Any],
    baseline: dict[str, Any],
    restore_path: dict[str, Any],
    eligibility: dict[str, Any],
    authority_packet_state: str | None,
    explicit_one_reader_mutation_authorization: bool,
    dry_run: bool = True,
) -> dict[str, Any]:
    """Admit only a dry-run plan unless every gate is proved for one device."""
    blockers: list[str] = []
    if identity.get("state") != "UNIQUE_TARGET_RESOLVED":
        blockers.append("identity_not_unique")
    if not baseline.get("baseline_locked"):
        blockers.append("baseline_not_locked")
    if not restore_path.get("restore_path_proved"):
        blockers.append("restore_path_not_proved")
    if not eligibility.get("outdated_classified"):
        blockers.append("not_outdated_classified")
    if authority_packet_state != "COMPLETE":
        blockers.append("authority_packet_not_complete")
    if not explicit_one_reader_mutation_authorization:
        blockers.append("explicit_one_reader_mutation_authorization_missing")

    blockers.extend(_require_same_device(identity, baseline, label="identity_baseline"))
    blockers.extend(_require_same_device(identity, restore_path, label="identity_restore"))
    blockers.extend(_require_same_device(identity, eligibility, label="identity_eligibility"))
    blockers.extend(_require_same_device(baseline, restore_path, label="baseline_restore"))

    baseline_fw = _norm_text(baseline.get("current_firmware_value"))
    target_fw = _norm_text(baseline.get("target_firmware_value")) or _norm_text(
        eligibility.get("target_firmware")
    )
    eligibility_observed = _norm_text(eligibility.get("observed_firmware"))
    if baseline_fw and eligibility_observed and baseline_fw != eligibility_observed:
        blockers.append("eligibility_observed_firmware_mismatch")
    if target_fw and _norm_text(eligibility.get("target_firmware")) and target_fw != _norm_text(
        eligibility.get("target_firmware")
    ):
        blockers.append("eligibility_target_firmware_mismatch")
    if baseline_fw and target_fw and baseline_fw == target_fw:
        blockers.append("baseline_already_on_target")

    admitted = not blockers
    plan = {
        "mode": "DRY_RUN" if dry_run or not admitted else "APPLY_CANDIDATE",
        "target_source_serial": identity.get("source_serial"),
        "target_mac": identity.get("expected_mac"),
        "source_firmware": baseline_fw,
        "target_firmware": target_fw,
        "rollback_source": restore_path.get("restore_plan"),
        "authority_packet_state": authority_packet_state,
        "blockers": blockers,
    }
    return {
        "schema": SCHEMA,
        "artifact": "mutation-preview",
        "state": "MUTATION_PREVIEW_READY" if admitted else "MUTATION_BLOCKED",
        "mutation_authorized": False,
        "apply_candidate": admitted and not dry_run,
        "dry_run_plan": plan,
        "blockers": blockers,
    }


def compare_roundtrip_states(
    baseline: dict[str, Any],
    post_update: dict[str, Any],
    post_rollback: dict[str, Any],
) -> dict[str, Any]:
    """Compare baseline vs post-update vs post-rollback for controlled fields."""
    prerequisites: list[str] = []
    if not isinstance(baseline, dict) or not baseline.get("baseline_locked"):
        prerequisites.append("baseline_not_locked")
    baseline_fw = _norm_text(_field_value(baseline, "current_firmware_value")) if isinstance(baseline, dict) else None
    target_fw = _norm_text(baseline.get("target_firmware_value")) if isinstance(baseline, dict) else None
    post_update_fw = _norm_text(_field_value(post_update, "current_firmware_value")) if isinstance(post_update, dict) else None
    post_rollback_fw = _norm_text(_field_value(post_rollback, "current_firmware_value")) if isinstance(post_rollback, dict) else None

    for label, blob in (
        ("baseline", baseline),
        ("post_update", post_update),
        ("post_rollback", post_rollback),
    ):
        if not isinstance(blob, dict):
            prerequisites.append(f"{label}_missing")
            continue
        serial, mac = _receipt_identity(blob)
        if not serial:
            prerequisites.append(f"{label}_source_serial_missing")
        if not mac:
            prerequisites.append(f"{label}_expected_mac_missing")

    if isinstance(baseline, dict) and isinstance(post_update, dict):
        prerequisites.extend(_require_same_device(baseline, post_update, label="baseline_post_update"))
    if isinstance(baseline, dict) and isinstance(post_rollback, dict):
        prerequisites.extend(_require_same_device(baseline, post_rollback, label="baseline_post_rollback"))

    if not baseline_fw:
        prerequisites.append("baseline_firmware_missing")
    if not target_fw:
        prerequisites.append("target_firmware_missing")
    if not post_update_fw:
        prerequisites.append("post_update_firmware_missing")
    if not post_rollback_fw:
        prerequisites.append("post_rollback_firmware_missing")

    deltas: list[dict[str, Any]] = []
    mismatches: list[str] = []
    if not prerequisites:
        for field in MATERIAL_COMPARE_FIELDS:
            b = _field_value(baseline, field)
            u = _field_value(post_update, field)
            r = _field_value(post_rollback, field)
            if field == "expected_mac":
                b = _norm_mac(b)
                u = _norm_mac(u)
                r = _norm_mac(r)
            deltas.append({"field": field, "baseline": b, "post_update": u, "post_rollback": r})
            if b in (None, ""):
                if field in {"source_serial", "expected_mac", "current_firmware_value"}:
                    mismatches.append(field)
                continue
            if r != b:
                mismatches.append(field)

    forward_update_proved = (
        not prerequisites
        and baseline_fw is not None
        and target_fw is not None
        and post_update_fw == target_fw
        and post_update_fw != baseline_fw
    )
    rollback_state_matched = not prerequisites and not mismatches and post_rollback_fw == baseline_fw
    roundtrip_proven = rollback_state_matched and forward_update_proved

    if prerequisites:
        state = "COMPARE_PREREQUISITES_MISSING"
    elif not forward_update_proved and rollback_state_matched:
        state = "ROLLBACK_STATE_MATCHED"
    elif roundtrip_proven:
        state = "ROUNDTRIP_PROVEN"
    elif rollback_state_matched:
        state = "ORIGINAL_STATE_RESTORED"
    else:
        state = "ROLLBACK_DRIFT_DETECTED"

    return {
        "schema": SCHEMA,
        "artifact": "rollback-comparison",
        "state": state,
        "restored": rollback_state_matched,
        "rollback_state_matched": rollback_state_matched,
        "forward_update_proved": forward_update_proved,
        "roundtrip_proven": roundtrip_proven,
        "prerequisites_missing": prerequisites,
        "mismatched_fields": mismatches,
        "delta": deltas,
        "baseline_firmware": baseline_fw,
        "target_firmware": target_fw,
        "post_update_firmware": post_update_fw,
        "post_rollback_firmware": post_rollback_fw,
        "mutation_authorized": False,
    }


def normalize_batch_rows(rows: list[dict[str, Any]], *, execute_serial: str | None = None) -> dict[str, Any]:
    """Normalize tabular CC-reader batch rows and fail closed on conflicts.

    execute_serial semantics:
      - None: no single-device scope filter
      - non-empty: restrict executable rows to that serial
      - empty string: explicit empty scope; block all rows
    """
    if not rows:
        return {
            "schema": BATCH_SCHEMA,
            "artifact": "batch-plan",
            "state": "BATCH_EMPTY",
            "row_count": 0,
            "executable_count": 0,
            "blocked_count": 0,
            "identity_tranche_counts": {},
            "identity_ready_count": 0,
            "identity_recovery_count": 0,
            "identity_recovery_rows": [],
            "rows": [],
            "executable_rows": [],
            "blocked_rows": [],
            "execute_serial_scope": None if execute_serial is None else _norm_text(execute_serial),
            "mutation_authorized": False,
        }

    serial_values = [_norm_text(row.get("source_serial")) for row in rows]
    mac_values = [_norm_mac(row.get("expected_mac")) for row in rows]
    serial_counts = Counter(value for value in serial_values if value)
    mac_counts = Counter(value for value in mac_values if value)

    normalized: list[dict[str, Any]] = []
    blocked: list[dict[str, Any]] = []

    for index, raw in enumerate(rows):
        row = {str(k).strip(): raw.get(k) for k in raw}
        problems: list[str] = []
        for col in BATCH_REQUIRED_COLUMNS:
            if not _norm_text(row.get(col)):
                problems.append(f"missing_{col}")
        serial = _norm_text(row.get("source_serial"))
        mac = _norm_mac(row.get("expected_mac"))
        tranche = classify_identity_tranche(row)
        action = (_norm_text(row.get("action")) or "").upper()
        if action and action not in BATCH_ACTIONS:
            problems.append("invalid_action")
        if mac is None and _norm_text(row.get("expected_mac")):
            problems.append("invalid_expected_mac")
        if serial and serial_counts[serial] > 1:
            problems.append("duplicate_source_serial")
        if mac and mac_counts[mac] > 1:
            problems.append("duplicate_expected_mac")
        if mac == FORBIDDEN_READERUNK_MAC:
            problems.append("readerunk_mac_rejected")

        identity_recovery_required = (
            tranche["tranche"] != IDENTITY_TRANCHE_SERIAL_AND_MAC
            or any(problem in IDENTITY_RECOVERY_PROBLEMS for problem in problems)
        )
        identity_admission_state = (
            "RECOVERY_REQUIRED" if identity_recovery_required else "READY_FOR_IDENTITY_PROBE"
        )
        identity_next_gate = tranche["next_gate"]
        if (
            identity_recovery_required
            and tranche["tranche"] == IDENTITY_TRANCHE_SERIAL_AND_MAC
        ):
            identity_next_gate = "RECONCILE_IDENTITY_CONFLICTS_BEFORE_NETWORK_PROBE"

        entry = {
            "row_index": index,
            "source_serial": serial,
            "source_name": _norm_text(row.get("source_name")),
            "identity_tranche": tranche["tranche"],
            "identity_next_gate": identity_next_gate,
            "identity_admission_state": identity_admission_state,
            "identity_recovery_required": identity_recovery_required,
            "broad_discovery_authorized": False,
            "expected_mac": mac,
            "observed_firmware": _norm_text(row.get("observed_firmware")),
            "active_outdated": _norm_text(row.get("active_outdated")),
            "target_firmware": _norm_text(row.get("target_firmware")),
            "action": action or None,
            "baseline_ref": _norm_text(row.get("baseline_ref")),
            "restore_plan_ref": _norm_text(row.get("restore_plan_ref")),
            "problems": problems,
            "executable": not problems,
        }
        if problems:
            blocked.append(entry)
        normalized.append(entry)

    executable = [row for row in normalized if row["executable"]]
    if execute_serial is not None:
        scoped = _norm_text(execute_serial)
        narrowed: list[dict[str, Any]] = []
        for row in executable:
            if scoped and row["source_serial"] == scoped:
                narrowed.append(row)
            else:
                row = dict(row)
                row["executable"] = False
                reason = (
                    "empty_execute_serial_scope"
                    if not scoped
                    else "outside_single_device_execution_scope"
                )
                row["problems"] = [*row["problems"], reason]
                blocked.append(row)
        executable = narrowed
        # Duplicated identities remain non-executable even when selected.
        still_executable: list[dict[str, Any]] = []
        for row in executable:
            if row["source_serial"] and serial_counts[row["source_serial"]] > 1:
                row = dict(row)
                row["executable"] = False
                row["problems"] = [*row["problems"], "duplicate_source_serial"]
                blocked.append(row)
            elif row["expected_mac"] and mac_counts[row["expected_mac"]] > 1:
                row = dict(row)
                row["executable"] = False
                row["problems"] = [*row["problems"], "duplicate_expected_mac"]
                blocked.append(row)
            else:
                still_executable.append(row)
        executable = still_executable

    state = "BATCH_PLAN_READY" if executable and not blocked else "BATCH_PLAN_BLOCKED"
    if executable and blocked:
        state = "BATCH_PLAN_PARTIAL"
    if execute_serial is not None and len(executable) > 1:
        state = "BATCH_PLAN_BLOCKED"
        for row in executable:
            row["executable"] = False
            row["problems"] = [*row["problems"], "single_device_scope_expanded"]
        blocked.extend(executable)
        executable = []

    tranche_counts = dict(Counter(row["identity_tranche"] for row in normalized))
    recovery_rows = [row for row in normalized if row["identity_recovery_required"]]
    ready_identity_rows = [
        row for row in normalized if row["identity_admission_state"] == "READY_FOR_IDENTITY_PROBE"
    ]

    return {
        "schema": BATCH_SCHEMA,
        "artifact": "batch-plan",
        "state": state,
        "row_count": len(normalized),
        "executable_count": len(executable),
        "blocked_count": len(blocked),
        "identity_tranche_counts": tranche_counts,
        "identity_ready_count": len(ready_identity_rows),
        "identity_recovery_count": len(recovery_rows),
        "identity_recovery_rows": recovery_rows,
        "rows": normalized,
        "executable_rows": executable,
        "blocked_rows": blocked,
        "execute_serial_scope": None if execute_serial is None else _norm_text(execute_serial),
        "mutation_authorized": False,
    }


def load_batch_csv(path: Path) -> list[dict[str, Any]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"csv_missing_header:{path}")
        return [dict(row) for row in reader]


def load_batch_input(path: Path) -> list[dict[str, Any]]:
    """Load batch rows from JSON or CSV using deterministic extension-based routing."""
    suffix = path.suffix.lower()
    if suffix == ".csv":
        return load_batch_csv(path)
    if suffix in {".json", ".jsonl"}:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        if isinstance(payload, list):
            return payload
        if isinstance(payload, dict) and isinstance(payload.get("rows"), list):
            return payload["rows"]
        raise ValueError("json_batch_requires_rows_array_or_list_root")
    raise ValueError(f"unsupported_batch_input_extension:{suffix or '<none>'}")


def write_receipt(mode: str, result: dict[str, Any], output: Path | None = None) -> Path:
    if output is not None:
        out = output
        out.parent.mkdir(parents=True, exist_ok=True)
    else:
        DEFAULT_RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        out = DEFAULT_RECEIPT_DIR / f"hh-cc-reader-firmware-roundtrip-{mode}-{stamp}-{secrets.token_hex(4)}.json"
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    out.write_text(text, encoding="utf-8")
    return out


def main(argv: list[str] | None = None) -> int:
    import argparse
    import sys

    parser = argparse.ArgumentParser(description="H&H CC reader firmware round-trip offline seams")
    parser.add_argument(
        "mode",
        choices=("identity", "baseline", "restore", "eligibility", "preview", "compare", "batch"),
    )
    parser.add_argument("--input", required=True, help="Input path for the selected mode")
    parser.add_argument(
        "--output",
        help="Optional JSON output path (default: ignored survey/output/hh-cc-reader receipt)",
    )
    parser.add_argument(
        "--execute-serial",
        default=None,
        help="For batch mode: restrict executable rows to one validated serial",
    )
    args = parser.parse_args(argv)
    input_path = Path(args.input)

    try:
        if args.mode == "batch":
            rows = load_batch_input(input_path)
            result = normalize_batch_rows(rows, execute_serial=args.execute_serial)
        else:
            payload = json.loads(input_path.read_text(encoding="utf-8-sig"))
            if args.mode == "identity":
                result = resolve_target_identity(payload)
            elif args.mode == "baseline":
                identity = resolve_target_identity(payload)
                result = freeze_baseline(payload, identity)
            elif args.mode == "restore":
                baseline = payload.get("baseline")
                result = evaluate_restore_path(payload.get("restore_evidence") or payload, baseline)
            elif args.mode == "eligibility":
                result = evaluate_outdated_eligibility(
                    observed_firmware=payload.get("observed_firmware")
                    or payload.get("current_firmware_value"),
                    active_outdated=payload.get("active_outdated"),
                    target_firmware=payload.get("target_firmware") or payload.get("target_firmware_value"),
                    source_serial=payload.get("source_serial"),
                    expected_mac=payload.get("expected_mac"),
                )
            elif args.mode == "preview":
                result = evaluate_mutation_admission(
                    identity=payload["identity"],
                    baseline=payload["baseline"],
                    restore_path=payload["restore_path"],
                    eligibility=payload["eligibility"],
                    authority_packet_state=payload.get("authority_packet_state"),
                    explicit_one_reader_mutation_authorization=bool(
                        payload.get("explicit_one_reader_mutation_authorization")
                    ),
                    dry_run=bool(payload.get("dry_run", True)),
                )
            else:
                result = compare_roundtrip_states(
                    payload["baseline"],
                    payload["post_update"],
                    payload["post_rollback"],
                )
    except (OSError, ValueError, json.JSONDecodeError, KeyError, TypeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    out_path = Path(args.output) if args.output else None
    receipt = write_receipt(args.mode, result, out_path)
    print(f"ARTIFACT={receipt}")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
