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
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_POLICY_PATH = ROOT / "harness" / "api" / "hh-cc-reader-firmware-policy.json"
SCHEMA = "sas-hh-cc-reader-firmware-roundtrip/v1"
BATCH_SCHEMA = "sas-hh-cc-reader-firmware-batch-row/v1"

# Historical READERUNK specimen values must never bind to Kiosk4.
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

_MAC_RE = re.compile(r"[^0-9A-Fa-f]")
_IPV4_RE = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d?\d)$"
)


def _norm_mac(value: Any) -> str | None:
    if value is None:
        return None
    text = _MAC_RE.sub("", str(value).strip()).upper()
    if len(text) != 12:
        return None
    return text


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


def load_policy(path: Path = DEFAULT_POLICY_PATH) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    assert data.get("schema_version") == "sas-hh-cc-reader-firmware-policy/v1"
    return data


def default_target_firmware(policy: dict[str, Any] | None = None) -> str:
    policy = policy if policy is not None else load_policy()
    selection = policy.get("selection") or {}
    target = selection.get("selected_candidate_id") or selection.get("planning_target")
    if not target:
        # Fall back to the documented governed planning candidate.
        target = "2.0.15.260522"
    return str(target)


def resolve_target_identity(candidate: dict[str, Any]) -> dict[str, Any]:
    """Correlate tracker/network/management identity; fail closed on ambiguity.

    Acceptance for UNIQUE_TARGET_RESOLVED:
      - source_serial present
      - expected_mac present and well-formed
      - no READERUNK leakage
      - when live_mac is supplied it must equal expected_mac
      - when probe_mac_match is supplied it must be True
      - no conflicting alternate serial/mac pairs
    """
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
    conflicts = list(candidate.get("identity_conflicts") or [])
    reasons: list[str] = []

    if not source_serial:
        reasons.append("missing_source_serial")
    if not expected_mac:
        reasons.append("missing_or_invalid_expected_mac")

    if live_ipv4 == FORBIDDEN_READERUNK_IPV4:
        reasons.append("readerunk_ipv4_leakage_rejected")
    if expected_mac == FORBIDDEN_READERUNK_MAC or live_mac == FORBIDDEN_READERUNK_MAC:
        reasons.append("readerunk_mac_leakage_rejected")

    if live_mac and expected_mac and live_mac != expected_mac:
        reasons.append("live_mac_mismatch")
        conflicts.append(
            {
                "field": "mac",
                "expected": expected_mac,
                "observed": live_mac,
            }
        )

    if probe_mac_match is False:
        reasons.append("probe_mac_match_false")
    elif probe_mac_match is not True:
        # UNIQUE_TARGET_RESOLVED requires a MAC-gated Probe-HHCCReader proof.
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
            "probe_mac_match_not_proved",
            "live_ipv4_missing",
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
        "expected_mac": expected_mac,
        "live_mac": live_mac,
        "live_ipv4": live_ipv4,
        "probe_mac_match": probe_mac_match,
        "rejection_reasons": reasons,
        "identity_conflicts": conflicts,
        "mutation_authorized": False,
    }


def freeze_baseline(observation: dict[str, Any], identity: dict[str, Any] | None = None) -> dict[str, Any]:
    """Freeze a pre-mutation baseline receipt. Missing fields block mutation."""
    identity = identity if identity is not None else resolve_target_identity(observation)
    missing = [field for field in REQUIRED_BASELINE_FIELDS if not _norm_text(observation.get(field))]
    if identity.get("state") != "UNIQUE_TARGET_RESOLVED":
        missing.append("unique_target_identity")
    if observation.get("identity_proof_state") != "UNIQUE_TARGET_RESOLVED":
        # Observation must explicitly carry the proved identity state.
        if "identity_proof_state" not in missing:
            missing.append("identity_proof_state_not_unique")

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
            "source_serial": identity.get("source_serial"),
            "source_name": identity.get("source_name"),
            "expected_mac": identity.get("expected_mac"),
            "live_ipv4": identity.get("live_ipv4") or observation.get("reader_ipv4"),
            "state": identity.get("state"),
        },
        "current_firmware_value": _norm_text(observation.get("current_firmware_value")),
        "target_firmware_value": _norm_text(observation.get("target_firmware_value")),
        "optional_captured": optional_captured,
        "mutation_authorized": False,
    }


def evaluate_restore_path(restore_evidence: dict[str, Any], baseline: dict[str, Any] | None = None) -> dict[str, Any]:
    """Prove restoration is possible before any forward mutation."""
    missing = [field for field in REQUIRED_RESTORE_FIELDS if not _norm_text(restore_evidence.get(field))]
    if baseline is not None and not baseline.get("baseline_locked"):
        missing.append("baseline_not_locked")
    if baseline is not None:
        starting = _norm_text(restore_evidence.get("starting_firmware_value"))
        baseline_fw = _norm_text(baseline.get("current_firmware_value"))
        if starting and baseline_fw and starting != baseline_fw:
            missing.append("starting_firmware_mismatch_vs_baseline")

    proved = not missing
    return {
        "schema": SCHEMA,
        "artifact": "restore-path-proof",
        "state": "RESTORE_PATH_PROVED" if proved else "RESTORE_PATH_INCOMPLETE",
        "restore_path_proved": proved,
        "missing_fields": missing,
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
) -> dict[str, Any]:
    """Classify OUTDATED under existing tracker/policy rules without inventing."""
    target = _norm_text(target_firmware) or default_target_firmware(policy)
    observed = _norm_text(observed_firmware)
    outdated_text = _norm_text(active_outdated)
    reasons: list[str] = []

    if not observed:
        reasons.append("observed_firmware_missing")
    if outdated_text is None:
        reasons.append("active_outdated_missing")

    # Do not classify from numeric ordering alone.
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
    """Admit only a dry-run plan unless every gate is proved.

    Even when all gates pass, this seam never executes mutation. It only emits
    a plan and a boolean that higher authorized runtimes may consult.
    """
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

    admitted = not blockers
    plan = {
        "mode": "DRY_RUN" if dry_run or not admitted else "APPLY_CANDIDATE",
        "target_source_serial": identity.get("source_serial"),
        "target_mac": identity.get("expected_mac"),
        "source_firmware": baseline.get("current_firmware_value"),
        "target_firmware": baseline.get("target_firmware_value") or eligibility.get("target_firmware"),
        "rollback_source": restore_path.get("restore_plan"),
        "authority_packet_state": authority_packet_state,
        "blockers": blockers,
    }
    return {
        "schema": SCHEMA,
        "artifact": "mutation-preview",
        "state": "MUTATION_PREVIEW_READY" if admitted else "MUTATION_BLOCKED",
        "mutation_authorized": False,  # this seam never authorizes live mutation
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
    deltas: list[dict[str, Any]] = []
    mismatches: list[str] = []

    def field_value(blob: dict[str, Any], field: str) -> Any:
        if field in blob:
            return blob.get(field)
        optional = blob.get("optional_captured") or {}
        if field in optional:
            return optional.get(field)
        identity = blob.get("identity") or {}
        if field == "source_serial":
            return identity.get("source_serial") or blob.get("source_serial")
        if field == "expected_mac":
            return identity.get("expected_mac") or blob.get("expected_mac")
        if field == "reader_ipv4":
            return identity.get("live_ipv4") or blob.get("reader_ipv4")
        return None

    for field in MATERIAL_COMPARE_FIELDS:
        b = field_value(baseline, field)
        u = field_value(post_update, field)
        r = field_value(post_rollback, field)
        entry = {"field": field, "baseline": b, "post_update": u, "post_rollback": r}
        deltas.append(entry)
        # Only compare fields present on the baseline freeze.
        if b in (None, ""):
            continue
        if r != b:
            mismatches.append(field)

    restored = not mismatches
    return {
        "schema": SCHEMA,
        "artifact": "rollback-comparison",
        "state": "ORIGINAL_STATE_RESTORED" if restored else "ROLLBACK_DRIFT_DETECTED",
        "restored": restored,
        "mismatched_fields": mismatches,
        "delta": deltas,
        "mutation_authorized": False,
    }


def normalize_batch_rows(rows: list[dict[str, Any]], *, execute_serial: str | None = None) -> dict[str, Any]:
    """Normalize tabular CC-reader batch rows and fail closed on conflicts.

    execute_serial, when provided, restricts the executable set to that one
    validated serial so a single-device experiment cannot expand silently.
    """
    if not rows:
        return {
            "schema": BATCH_SCHEMA,
            "artifact": "batch-plan",
            "state": "BATCH_EMPTY",
            "rows": [],
            "executable_rows": [],
            "blocked_rows": [],
            "mutation_authorized": False,
        }

    seen_serials: dict[str, int] = {}
    seen_macs: dict[str, int] = {}
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
        action = (_norm_text(row.get("action")) or "").upper()
        if action and action not in BATCH_ACTIONS:
            problems.append("invalid_action")
        if mac is None and _norm_text(row.get("expected_mac")):
            problems.append("invalid_expected_mac")
        if serial:
            if serial in seen_serials:
                problems.append("duplicate_source_serial")
            seen_serials[serial] = index
        if mac:
            if mac in seen_macs:
                problems.append("duplicate_expected_mac")
            seen_macs[mac] = index
        if mac == FORBIDDEN_READERUNK_MAC:
            problems.append("readerunk_mac_rejected")

        entry = {
            "row_index": index,
            "source_serial": serial,
            "source_name": _norm_text(row.get("source_name")),
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
    if execute_serial:
        execute_serial = _norm_text(execute_serial)
        narrowed: list[dict[str, Any]] = []
        for row in executable:
            if row["source_serial"] == execute_serial:
                narrowed.append(row)
            else:
                row = dict(row)
                row["executable"] = False
                row["problems"] = list(row["problems"]) + ["outside_single_device_execution_scope"]
                blocked.append(row)
        executable = narrowed

    state = "BATCH_PLAN_READY" if executable and not blocked else "BATCH_PLAN_BLOCKED"
    if executable and blocked:
        state = "BATCH_PLAN_PARTIAL"
    if execute_serial and len(executable) > 1:
        state = "BATCH_PLAN_BLOCKED"
        for row in executable:
            row["executable"] = False
            row["problems"] = list(row["problems"]) + ["single_device_scope_expanded"]
        blocked.extend(executable)
        executable = []

    return {
        "schema": BATCH_SCHEMA,
        "artifact": "batch-plan",
        "state": state,
        "row_count": len(normalized),
        "executable_count": len(executable),
        "blocked_count": len(blocked),
        "rows": normalized,
        "executable_rows": executable,
        "blocked_rows": blocked,
        "execute_serial_scope": execute_serial,
        "mutation_authorized": False,
    }


def load_batch_csv(path: Path) -> list[dict[str, Any]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        return [dict(row) for row in reader]


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="H&H CC reader firmware round-trip offline seams")
    parser.add_argument(
        "mode",
        choices=("identity", "baseline", "restore", "eligibility", "preview", "compare", "batch"),
    )
    parser.add_argument("--input", required=True, help="JSON input path for the selected mode")
    parser.add_argument("--output", help="Optional JSON output path")
    parser.add_argument(
        "--execute-serial",
        help="For batch mode: restrict executable rows to one validated serial",
    )
    args = parser.parse_args(argv)

    payload = json.loads(Path(args.input).read_text(encoding="utf-8-sig"))
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
            observed_firmware=payload.get("observed_firmware") or payload.get("current_firmware_value"),
            active_outdated=payload.get("active_outdated"),
            target_firmware=payload.get("target_firmware") or payload.get("target_firmware_value"),
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
    elif args.mode == "compare":
        result = compare_roundtrip_states(
            payload["baseline"],
            payload["post_update"],
            payload["post_rollback"],
        )
    else:
        if isinstance(payload, list):
            rows = payload
        elif "rows" in payload:
            rows = payload["rows"]
        else:
            rows = load_batch_csv(Path(args.input))
        result = normalize_batch_rows(rows, execute_serial=args.execute_serial)

    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
