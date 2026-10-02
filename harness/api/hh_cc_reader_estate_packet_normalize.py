"""P5-B deterministic packet normalization seam.

Populates settled/derivable estate-authority packet fields from repository
policy and already-captured observations. Never invents live firmware,
package visibility, or package/release identifiers. Never contacts Payment
Fusion / PAXSTORE / network surfaces.
"""
from __future__ import annotations

import copy
import json
import re
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_estate_authority import (
    DEFAULT_POLICY_PATH,
    UNKNOWN_MARKERS,
    load_policy,
)


def _resolved_firmware_value(value: Any) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    if not text:
        return None
    upper = text.upper()
    if upper in UNKNOWN_MARKERS or upper.startswith("UNKNOWN"):
        return None
    return text

DEFAULT_TEMPLATE = (
    ROOT / "docs" / "examples" / "hh-cc-reader-proven-path-authority-packet.template.json"
)
DEFAULT_MECHANISM_ID = "payment-fusion-control-center"
DEFAULT_DISPOSITION = "CREDENTIAL_GATE"

LIVE_WORKSHEET: tuple[dict[str, str], ...] = (
    {
        "id": "authenticated_estate_access",
        "look_for": "Authorized login/MFA reaches the H&H estate",
        "where": "gateway.paymentfusion.com Non-bank Users -> BoA MSU, or cc.paymentfusion.com SSO",
        "capture": "session reached estate: yes/no; exact barrier if no",
        "not_shown_valid": "no",
        "blocks_p5": "yes until authenticated",
        "evidence_state_until_captured": "INTERACTIVE_AUTH_REQUIRED",
        "importance": "CRITICAL",
        "packet_fields": "authorized_readonly_session,access_state",
    },
    {
        "id": "minimum_read_role",
        "look_for": "Account exposes terminal + firmware/software + auto-update/assignment views",
        "where": "Control Center Terminal management / role entitlements",
        "capture": "role_scope_ok yes/no",
        "not_shown_valid": "no",
        "blocks_p5": "yes if role denied",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "CRITICAL",
        "packet_fields": "role_scope_ok",
    },
    {
        "id": "representative_a80",
        "look_for": "One representative H&H A80 located without create/enroll",
        "where": "Control Center -> Terminal management",
        "capture": "found yes/no; then sanitized external index key only",
        "not_shown_valid": "no",
        "blocks_p5": "yes if none found",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "CRITICAL",
        "packet_fields": "representative_terminal_bound,reader_identity_ref",
    },
    {
        "id": "current_firmware_value",
        "look_for": "Exact current firmware/version on that A80",
        "where": "terminal firmware/software detail",
        "capture": "exact sanitized version string",
        "not_shown_valid": "no",
        "blocks_p5": "yes",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "CRITICAL",
        "packet_fields": "current_firmware_observed,current_firmware_value",
    },
    {
        "id": "target_package_exposed",
        "look_for": "Does the surface expose package 2.0.15.260522?",
        "where": "Automatic terminal updating / IngEstate software repository",
        "capture": "YES or NO (UNKNOWN cannot promote)",
        "not_shown_valid": "YES means package not exposed (conflict path; still completes P5)",
        "blocks_p5": "YES/NO complete P5; UNKNOWN does not promote",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "CRITICAL",
        "packet_fields": "package_exposed_for_target",
    },
    {
        "id": "package_release_reference",
        "look_for": "Stable package/release/list/software/repository ID for .15 IF ANY",
        "where": "same package/software repository record",
        "capture": "surface-native id OR NONE_OBSERVED; never invent; not another firmware version",
        "not_shown_valid": "yes — surface evidence, not operator failure; may trigger P5-D only if package YES and no separate id",
        "blocks_p5": "conditional (P5-D) when package YES and schema cannot represent absence",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "USEFUL",
        "packet_fields": "package_release_id",
    },
    {
        "id": "assignment_method",
        "look_for": "Assignment/update affordance verb",
        "where": "policy/job UI",
        "capture": "exact verb text; observe only; do not invoke",
        "not_shown_valid": "yes — record UNKNOWN_SURFACE_NOT_EXPOSED",
        "blocks_p5": "USEFUL",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "USEFUL",
        "packet_fields": "assignment_method",
    },
    {
        "id": "reboot_reconnect_behavior",
        "look_for": "Stated reboot/reconnect behavior",
        "where": "same authority text",
        "capture": "exact stated behavior",
        "not_shown_valid": "yes",
        "blocks_p5": "USEFUL",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "USEFUL",
        "packet_fields": "reboot_reconnect_behavior",
    },
    {
        "id": "rollback_exception_path",
        "look_for": "Rollback/cancel/exception behavior",
        "where": "same authority text",
        "capture": "exact stated behavior",
        "not_shown_valid": "yes",
        "blocks_p5": "USEFUL",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "USEFUL",
        "packet_fields": "rollback_exception_path",
    },
    {
        "id": "post_update_acceptance",
        "look_for": "Post-update success criterion",
        "where": "same authority text",
        "capture": "exact stated criterion",
        "not_shown_valid": "yes",
        "blocks_p5": "USEFUL",
        "evidence_state_until_captured": "LIVE_VALUE_NOT_CAPTURED",
        "importance": "USEFUL",
        "packet_fields": "post_update_acceptance",
    },
)


def _blank(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, bool):
        return False
    text = str(value).strip()
    return text == ""


def _unknownish(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, bool):
        return False
    text = str(value).strip().upper()
    return text in UNKNOWN_MARKERS or text.startswith("UNKNOWN")


def generate_authority_packet_id(*, when: datetime | None = None) -> str:
    stamp = (when or datetime.now(timezone.utc)).strftime("%Y%m%d")
    return f"hh-cc-p5-{stamp}-pfcc-{secrets.token_hex(3)}"


def sanitize_reader_identity_ref(external_index_key: str) -> str:
    """Build a non-secret reader alias from an external evidence-index key."""
    raw = str(external_index_key or "").strip()
    if not raw:
        raise ValueError("external_index_key is required to bind reader_identity_ref")
    lowered = raw.lower()
    for forbidden in ("http://", "https://", "@", "password", "token", "cookie"):
        if forbidden in lowered:
            raise ValueError("external_index_key looks secret-bearing; refuse")
    if re.search(r"(?i)\b(?:\d{1,3}\.){3}\d{1,3}\b", raw):
        raise ValueError("external_index_key must not embed IPv4")
    if re.search(r"(?i)([0-9a-f]{2}[:-]){5}[0-9a-f]{2}", raw):
        raise ValueError("external_index_key must not embed MAC")
    slug = re.sub(r"[^a-zA-Z0-9._-]+", "-", raw).strip("-._")
    if len(slug) < 4:
        raise ValueError("external_index_key too short after sanitization")
    if not slug.lower().startswith("ext-"):
        slug = f"ext-{slug}"
    return slug[:80]


def derive_checklist_satisfied(inputs: dict[str, Any], policy: dict[str, Any]) -> dict[str, bool]:
    """Derive checklist booleans from captured observation evidence only."""
    fw = _resolved_firmware_value(inputs.get("current_firmware_value"))
    package = str(inputs.get("package_exposed_for_target") or "").strip().upper()
    release = inputs.get("package_release_id")
    package_resolved = package in {"YES", "NO"} and not _unknownish(release)
    if package == "NO" and str(release or "").strip().upper() == "NONE_OBSERVED":
        package_resolved = True

    derived = {
        "confirm-authorized-readonly-session": bool(inputs.get("authorized_readonly_session")),
        "confirm-minimum-read-role": bool(inputs.get("role_scope_ok")),
        "locate-representative-a80": bool(inputs.get("representative_terminal_bound")),
        "bind-reader-identity-ref": bool(inputs.get("representative_terminal_bound"))
        and not _blank(inputs.get("reader_identity_ref")),
        "observe-current-firmware": bool(inputs.get("current_firmware_observed")) and fw is not None,
        "inspect-automatic-update-policy": not _blank(inputs.get("assignment_method"))
        or not _blank(inputs.get("management_owner")),
        "resolve-target-package-visibility": package_resolved,
        "record-assignment-method": not _blank(inputs.get("assignment_method")),
        "record-reboot-reconnect-behavior": not _blank(inputs.get("reboot_reconnect_behavior")),
        "record-rollback-exception-path": not _blank(inputs.get("rollback_exception_path")),
        "record-post-update-acceptance": not _blank(inputs.get("post_update_acceptance")),
        "emit-sanitized-authority-packet": (
            bool(inputs.get("authorized_readonly_session"))
            and not _blank(inputs.get("authority_packet_id"))
            and str(inputs.get("access_state") or "") == "PROVEN_ACCESS"
            and package_resolved
            and fw is not None
            and not _blank(inputs.get("management_owner"))
            and not _blank(inputs.get("assignment_method"))
            and not _blank(inputs.get("reboot_reconnect_behavior"))
            and not _blank(inputs.get("rollback_exception_path"))
            and not _blank(inputs.get("post_update_acceptance"))
        ),
    }

    # Keep only checklist ids owned by policy.
    allowed = {item["id"] for item in policy["readonly_estate_checklist"]["items"]}
    return {item_id: bool(derived.get(item_id, False)) for item_id in allowed}


def remaining_live_worksheet(inputs: dict[str, Any]) -> list[dict[str, str]]:
    """Return only genuinely live observations still needed."""
    remaining: list[dict[str, str]] = []
    for item in LIVE_WORKSHEET:
        fields = [part.strip() for part in item["packet_fields"].split(",") if part.strip()]
        needed = False
        for field in fields:
            value = inputs.get(field)
            if field in {"authorized_readonly_session", "role_scope_ok", "representative_terminal_bound", "current_firmware_observed"}:
                if not bool(value):
                    needed = True
            elif field == "access_state":
                if str(value or "") != "PROVEN_ACCESS":
                    needed = True
            elif field == "current_firmware_value":
                if _resolved_firmware_value(value) is None:
                    needed = True
            elif field == "package_exposed_for_target":
                if str(value or "").strip().upper() not in {"YES", "NO"}:
                    needed = True
            elif field == "package_release_id":
                exposed = str(inputs.get("package_exposed_for_target") or "").strip().upper()
                if exposed == "YES" and _unknownish(value):
                    needed = True
                elif exposed == "NO" and str(value or "").strip().upper() != "NONE_OBSERVED":
                    needed = True
                elif exposed not in {"YES", "NO"}:
                    needed = True
            else:
                if _blank(value) or _unknownish(value):
                    needed = True
        if needed:
            remaining.append(dict(item))
    return remaining


def normalize_packet(
    packet: dict[str, Any],
    *,
    policy: dict[str, Any] | None = None,
    external_index_key: str | None = None,
    mechanism_id: str = DEFAULT_MECHANISM_ID,
) -> dict[str, Any]:
    """Return a deep-copied packet with settled/derivable fields populated."""
    if not isinstance(packet, dict):
        raise ValueError("packet root must be a JSON object")
    if "evaluator_inputs" not in packet or not isinstance(packet["evaluator_inputs"], dict):
        raise ValueError("packet missing evaluator_inputs object")

    policy_data = policy if policy is not None else load_policy()
    out = copy.deepcopy(packet)
    inputs = out["evaluator_inputs"]

    # Settled / derivable — never overwrite an already-set eligible mechanism.
    if _blank(inputs.get("mechanism_id")):
        inputs["mechanism_id"] = mechanism_id
    if _blank(inputs.get("current_disposition")):
        inputs["current_disposition"] = DEFAULT_DISPOSITION
    inputs["mutation_intent"] = False
    if inputs.get("mutation_actions_observed") is None:
        inputs["mutation_actions_observed"] = []
    else:
        # Keep list form; strip any accidental non-strings without inventing actions.
        actions = inputs.get("mutation_actions_observed") or []
        if isinstance(actions, str):
            actions = [actions] if actions.strip() else []
        inputs["mutation_actions_observed"] = [str(a) for a in actions if str(a).strip()]

    target = policy_data["selection"]["default_target"]
    inputs["target_firmware_planning_candidate"] = target

    if _blank(inputs.get("authority_packet_id")):
        inputs["authority_packet_id"] = generate_authority_packet_id()

    if external_index_key is not None and str(external_index_key).strip():
        inputs["reader_identity_ref"] = sanitize_reader_identity_ref(external_index_key)
        inputs["representative_terminal_bound"] = True

    # Never invent live firmware / package visibility / release id.
    # If package is NO and release blank, set NONE_OBSERVED as the truthful conflict marker.
    if str(inputs.get("package_exposed_for_target") or "").strip().upper() == "NO":
        if _blank(inputs.get("package_release_id")) or _unknownish(inputs.get("package_release_id")):
            inputs["package_release_id"] = "NONE_OBSERVED"

    inputs["checklist_satisfied"] = derive_checklist_satisfied(inputs, policy_data)

    # Mirror settled bookkeeping onto acceptance_record_fields when present.
    acceptance = out.get("acceptance_record_fields")
    if isinstance(acceptance, dict):
        acceptance["MECHANISM_ID"] = inputs.get("mechanism_id")
        acceptance["TARGET_FIRMWARE_PLANNING_CANDIDATE"] = target
        acceptance["MUTATION_PERFORMED"] = False
        acceptance["AUTHORITY_PACKET_ID"] = inputs.get("authority_packet_id")
        if inputs.get("reader_identity_ref"):
            acceptance["READER_IDENTITY_REF"] = inputs.get("reader_identity_ref")
        if str(inputs.get("access_state") or ""):
            acceptance["ACCESS_STATE"] = inputs.get("access_state")

    # Sync checklist_items[].satisfied when the template array is present.
    items = out.get("checklist_items")
    if isinstance(items, list):
        satisfied = inputs["checklist_satisfied"]
        for item in items:
            if isinstance(item, dict) and item.get("id") in satisfied:
                item["satisfied"] = bool(satisfied[item["id"]])

    out["_p5b_normalization"] = {
        "schema": "sas.hh-cc-reader.p5b-normalization/v1",
        "mechanism_id": inputs.get("mechanism_id"),
        "target_firmware_planning_candidate": target,
        "authority_packet_id": inputs.get("authority_packet_id"),
        "live_observations_remaining": remaining_live_worksheet(inputs),
        "invented_live_values": False,
        "network_contact": False,
    }
    return out


def load_packet_or_template(path: Path | None) -> dict[str, Any]:
    source = path if path is not None else DEFAULT_TEMPLATE
    if not source.is_file():
        raise FileNotFoundError(f"packet/template not found: {source}")
    data = json.loads(source.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError(f"packet root must be a JSON object: {source}")
    return data


def write_worksheet_markdown(remaining: list[dict[str, str]], path: Path, *, packet_id: str) -> None:
    lines = [
        "# H&H CC Reader P5-C — Minimal Operator Worksheet",
        f"# AUTHORITY_PACKET_ID={packet_id}",
        f"# mechanism_id={DEFAULT_MECHANISM_ID}",
        "# Generated by Normalize-HHCCReaderEstatePacket (P5-B)",
        "# Forbidden: push, assign, activate, approve, reset, sideload, enroll, reassign, network/package/policy change, write",
        "",
        "## Login path",
        "1. https://gateway.paymentfusion.com/ -> Non-bank Users Login Here",
        "2. BoA MSU: https://secure.bankofamerica.com/sparta/login/msu/msu-login-auth/?flow=hps-pfg&environment=PRODUCTION",
        "3. Alternate SSO: https://cc.paymentfusion.com/users/sign_in",
        "",
        "## Remaining live observations",
        "",
        "| # | What to look for | Where | Capture | Not shown valid? | Blocks P5? | State |",
        "|---|---|---|---|---|---|---|",
    ]
    for idx, item in enumerate(remaining, start=1):
        lines.append(
            "| {idx} | {look} | {where} | {capture} | {shown} | {blocks} | {state} |".format(
                idx=idx,
                look=item["look_for"],
                where=item["where"],
                capture=item["capture"],
                shown=item["not_shown_valid"],
                blocks=item["blocks_p5"],
                state=item["evidence_state_until_captured"],
            )
        )
    lines.extend(
        [
            "",
            "## Settled (do not re-ask)",
            "- Target firmware 2.0.15.260522 = SETTLED_POLICY",
            f"- mechanism_id = {DEFAULT_MECHANISM_ID}",
            "- Mutation unauthorized throughout P5",
            "- package_release_id is NOT another firmware version",
            "",
            "## After observations",
            "Update the external packet, then:",
            "",
            "```bat",
            "Evaluate-HHCCReaderEstateAuthority.cmd %TEMP%\\hh-cc-p5-packet-fill.json",
            "```",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    import argparse
    import sys

    parser = argparse.ArgumentParser(
        description=(
            "P5-B: normalize settled/derivable fields on one external sanitized "
            "estate-authority packet and emit the remaining live-observation worksheet."
        )
    )
    parser.add_argument(
        "packet_json",
        nargs="?",
        default=None,
        help="Existing external packet JSON (default: create from repository template)",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output path for normalized external packet (keep outside Git)",
    )
    parser.add_argument(
        "--worksheet",
        default=None,
        help="Optional markdown worksheet path for remaining live observations",
    )
    parser.add_argument(
        "--external-index-key",
        default=None,
        help="Optional non-secret external evidence-index key used to bind reader_identity_ref",
    )
    parser.add_argument(
        "--policy",
        default=str(DEFAULT_POLICY_PATH),
        help="Firmware policy path",
    )
    args = parser.parse_args(argv)

    packet_path = Path(args.packet_json).expanduser() if args.packet_json else None
    try:
        packet = load_packet_or_template(packet_path)
        policy = load_policy(Path(args.policy))
        normalized = normalize_packet(
            packet,
            policy=policy,
            external_index_key=args.external_index_key,
        )
    except (OSError, ValueError, AssertionError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    out_path = Path(args.output).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # Strip internal helper before write? Keep _p5b_normalization as operator-facing provenance.
    out_path.write_text(json.dumps(normalized, indent=2) + "\n", encoding="utf-8")

    remaining = normalized.get("_p5b_normalization", {}).get("live_observations_remaining", [])
    packet_id = normalized["evaluator_inputs"].get("authority_packet_id")
    worksheet_path = Path(args.worksheet).expanduser() if args.worksheet else None
    if worksheet_path is not None:
        worksheet_path.parent.mkdir(parents=True, exist_ok=True)
        write_worksheet_markdown(remaining, worksheet_path, packet_id=str(packet_id))

    print(f"PACKET_OUT={out_path}")
    print(f"AUTHORITY_PACKET_ID={packet_id}")
    print(f"MECHANISM_ID={normalized['evaluator_inputs'].get('mechanism_id')}")
    print(
        "TARGET_FIRMWARE_PLANNING_CANDIDATE="
        f"{normalized['evaluator_inputs'].get('target_firmware_planning_candidate')}"
    )
    print(f"LIVE_OBSERVATIONS_REMAINING={len(remaining)}")
    print(f"INVENTED_LIVE_VALUES={normalized['_p5b_normalization']['invented_live_values']}")
    if worksheet_path is not None:
        print(f"WORKSHEET={worksheet_path}")
    for item in remaining:
        print(f"LIVE_REMAINING={item['id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
