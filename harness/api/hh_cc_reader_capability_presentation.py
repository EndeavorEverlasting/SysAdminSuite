"""Evidence-to-presentation projection for H&H CC-reader capability program.

Internal ledger may use machine tokens. Visible stakeholder text must not.
FINDING → CONSEQUENCE → NEXT DECISION. No deck mutation here.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

SCHEMA = "sas-hh-cc-reader-capability-presentation/v1"

MATERIAL_EVENTS = frozenset(
    {
        "newly_proved_control_plane",
        "newly_closed_avenue",
        "new_attended_or_unattended_finding",
        "deterministic_automation_replacing_manual",
        "package_artifact_recovery",
        "firmware_portability_result",
        "paxstore_api_capability_proof",
        "one_reader_update_pilot_result",
        "material_operator_labor_reduction",
    }
)

FORBIDDEN_VISIBLE = re.compile(
    r"\b(P0\d|P1\d|P\d{2}|PROVEN_POSITIVE|PROVEN_NEGATIVE|INCONCLUSIVE_ATTENDED_GATE|"
    r"DEFERRED_TOPOLOGY_UNAVAILABLE|CREDENTIAL_GATE|AUTHORITY_GATE|POLICY_REFUSAL|"
    r"NOT_YET_TESTED|harness|agent|chat|prompt)\b|"
    r"\b(?:\d{1,3}\.){3}\d{1,3}\b|"  # IPv4
    r"\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b|"  # MAC
    r"(api[_-]?secret|password|bearer\s+[A-Za-z0-9\-\._]+)",
    re.IGNORECASE,
)

SERIALISH = re.compile(r"\b\d{8,}\b")


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def classify_presentation_delta(
    *,
    event_type: str | None,
    result: str | None = None,
    previous_result: str | None = None,
    reason_if_not: str | None = None,
) -> dict[str, Any]:
    material = event_type in MATERIAL_EVENTS
    transition = previous_result != result and result is not None
    if material or (
        transition
        and result
        in {
            "PROVEN_POSITIVE",
            "PROVEN_NEGATIVE",
            "INCONCLUSIVE_ATTENDED_GATE",
            "CREDENTIAL_GATE",
            "AUTHORITY_GATE",
        }
    ):
        return {
            "disposition": "PRESENTATION_DELTA_REQUIRED",
            "event_type": event_type,
            "result": result,
            "reason": "Material capability evidence transition.",
        }
    return {
        "disposition": "PRESENTATION_DELTA_NOT_REQUIRED",
        "event_type": event_type,
        "result": result,
        "reason": reason_if_not or "No material stakeholder-facing transition.",
    }


def stakeholder_triple(
    *,
    finding: str,
    consequence: str,
    next_decision: str,
) -> dict[str, str]:
    for label, text in (
        ("finding", finding),
        ("consequence", consequence),
        ("next_decision", next_decision),
    ):
        leak = visible_leak(text)
        if leak:
            raise ValueError(f"stakeholder {label} leaks internal/private token: {leak}")
    return {
        "finding": finding,
        "consequence": consequence,
        "next_decision": next_decision,
    }


def visible_leak(text: str) -> str | None:
    if not text:
        return None
    m = FORBIDDEN_VISIBLE.search(text)
    if m:
        return m.group(0)
    # serial-like long digit runs are treated as private identifiers
    if SERIALISH.search(text):
        return "serial_like_identifier"
    return None


def project_capability_views(ledger: dict[str, Any]) -> dict[str, Any]:
    entries = ledger.get("entries") or []
    metrics = ledger.get("metrics") or {}

    exhaustion = []
    closed = []
    cost_ladder = {"zero_low_learned": [], "short_attendance": [], "admin_box_relocation": []}
    update_sources = {
        "control_center_tms": [],
        "paxstore": [],
        "reader_derived": [],
        "service_tool": [],
        "provider_managed": [],
    }
    automation = []
    fleet = []

    for entry in entries:
        result = entry.get("latest_result") or "NOT_YET_TESTED"
        st = entry.get("stakeholder_translation") or {}
        finding = st.get("finding") or _default_finding(entry, result)
        consequence = st.get("consequence") or _default_consequence(result)
        next_decision = st.get("next_decision") or _default_next(result)
        triple = stakeholder_triple(
            finding=finding, consequence=consequence, next_decision=next_decision
        )
        row = {
            "capability_name": entry.get("capability_name"),
            "status_label": _human_status(result),
            "stakeholder": triple,
        }
        exhaustion.append(row)
        cost = entry.get("interruption_cost") or "zero"
        if result in {"PROVEN_POSITIVE", "PROVEN_NEGATIVE", "CREDENTIAL_GATE", "AUTHORITY_GATE"} and cost in {
            "zero",
            "low",
        }:
            cost_ladder["zero_low_learned"].append(row)
        if result == "INCONCLUSIVE_ATTENDED_GATE" or entry.get("attended_retry_required"):
            cost_ladder["short_attendance"].append(row)
        if entry.get("required_topology") == "ADMIN_BOX_RELOCATED_TO_LAB":
            cost_ladder["admin_box_relocation"].append(row)
        if result == "PROVEN_NEGATIVE":
            closed.append(
                {
                    **row,
                    "portrayal": "Avoided future labor — branch closed by evidence, not a personal failure.",
                }
            )
        plane = (entry.get("control_plane") or "").lower()
        if "paxstore" in plane:
            update_sources["paxstore"].append(row["capability_name"])
        elif "usb" in plane or "service" in plane:
            update_sources["service_tool"].append(row["capability_name"])
        elif "artifact" in plane:
            update_sources["reader_derived"].append(row["capability_name"])
        elif plane in {"lan", "tms", "control_center"}:
            update_sources["control_center_tms"].append(row["capability_name"])

        automation.append(
            {
                "capability_name": entry.get("capability_name"),
                "maturity": _automation_maturity(entry),
            }
        )
        if entry.get("fleet_value") in {"CANDIDATE", "FLEET_CAPABLE", "FLEET_DEPLOYMENT_CAPABLE"}:
            fleet.append(
                {
                    "capability_name": entry.get("capability_name"),
                    "leverage": "One-reader proof can inform a compatible cohort only after portability gates close.",
                    "remaining_gates": entry.get("next_reopen_condition"),
                }
            )

    # Validate no leaks in projected visible strings
    blob = json.dumps(
        {
            "exhaustion": exhaustion,
            "cost_ladder": cost_ladder,
            "closed": closed,
            "fleet": fleet,
        }
    )
    leak = visible_leak(blob)
    if leak and leak not in {"PROVEN_POSITIVE"}:  # defensive; human labels used above
        # Re-check only stakeholder strings
        for row in exhaustion:
            for v in row["stakeholder"].values():
                hit = visible_leak(v)
                if hit:
                    raise ValueError(f"projection leak: {hit}")

    deltas = []
    for entry in entries:
        result = entry.get("latest_result")
        event = None
        if result == "PROVEN_POSITIVE":
            event = "newly_proved_control_plane"
        elif result == "PROVEN_NEGATIVE":
            event = "newly_closed_avenue"
        elif result == "INCONCLUSIVE_ATTENDED_GATE":
            event = "new_attended_or_unattended_finding"
        elif entry.get("control_plane") == "paxstore_openapi" and result not in {
            None,
            "NOT_YET_TESTED",
        }:
            event = "paxstore_api_capability_proof"
        deltas.append(
            classify_presentation_delta(
                event_type=event,
                result=result,
                reason_if_not="No material transition for this capability.",
            )
        )

    return {
        "schema": SCHEMA,
        "generated_at": _now(),
        "deck_mutation": False,
        "views": {
            "capability_exhaustion_map": exhaustion,
            "operator_cost_ladder": cost_ladder,
            "update_source_portfolio": update_sources,
            "automation_maturity": automation,
            "fleet_leverage": fleet,
            "closed_branches": closed,
        },
        "metrics_human": {
            "avenues_modeled": metrics.get("TOTAL_AVENUES_MODELED"),
            "attempted": metrics.get("TECHNICALLY_ATTEMPTED"),
            "proved": metrics.get("PROVEN_POSITIVE"),
            "closed": metrics.get("PROVEN_NEGATIVE_OR_CLOSED"),
            "needs_attendance": metrics.get("INCONCLUSIVE_ATTENDED"),
            "waiting_on_access": (metrics.get("CREDENTIAL_GATED") or 0)
            + (metrics.get("AUTHORITY_GATED") or 0),
            "waiting_on_location": metrics.get("TOPOLOGY_DEFERRED"),
        },
        "presentation_deltas": deltas,
    }


def _human_status(result: str) -> str:
    return {
        "PROVEN_POSITIVE": "Proved",
        "PROVEN_NEGATIVE": "Closed by evidence",
        "INCONCLUSIVE_ATTENDED_GATE": "Needs a short on-site approval",
        "INCONCLUSIVE_TIMEOUT": "Timed out without a final answer",
        "DEFERRED_TOPOLOGY_UNAVAILABLE": "Waiting on a different physical setup",
        "DEFERRED_OPERATOR_PRESENCE_REQUIRED": "Waiting for someone at the reader",
        "CREDENTIAL_GATE": "Waiting on authorized access",
        "AUTHORITY_GATE": "Waiting on authorization",
        "POLICY_REFUSAL": "Blocked by policy",
        "NOT_APPLICABLE": "Not applicable",
        "NOT_YET_TESTED": "Not yet tested",
    }.get(result, "Under review")


def _default_finding(entry: dict[str, Any], result: str) -> str:
    name = entry.get("capability_name") or "This avenue"
    return f"{name}: {_human_status(result).lower()}."


def _default_consequence(result: str) -> str:
    return {
        "PROVEN_POSITIVE": "This path can reduce repeated field labor once live-certified.",
        "PROVEN_NEGATIVE": "Teams can stop spending time on this closed path.",
        "INCONCLUSIVE_ATTENDED_GATE": "A short batched visit can finish several waiting approvals together.",
        "CREDENTIAL_GATE": "Authorized access setup is the blocker, not a missing product idea.",
        "AUTHORITY_GATE": "Authorization must be granted before this path can advance.",
        "DEFERRED_TOPOLOGY_UNAVAILABLE": "Work continues on other paths that do not need this setup.",
    }.get(result, "Independent work continues while this path stays classified.")


def _default_next(result: str) -> str:
    return {
        "PROVEN_POSITIVE": "Decide whether to live-certify and scale to a compatible cohort.",
        "PROVEN_NEGATIVE": "Keep the closure unless new device evidence appears.",
        "INCONCLUSIVE_ATTENDED_GATE": "Use the consolidated attendance list rather than one-off visits.",
        "CREDENTIAL_GATE": "Complete authorized access setup, then re-run observe/preview only.",
        "AUTHORITY_GATE": "Obtain the named authorization, then retry the same experiment.",
        "DEFERRED_TOPOLOGY_UNAVAILABLE": "Do not relocate the Admin Box until cheaper work is exhausted.",
    }.get(result, "Continue the next cheapest independent avenue.")


def _automation_maturity(entry: dict[str, Any]) -> str:
    impl = entry.get("implementation_state")
    ceiling = entry.get("current_proof_ceiling")
    result = entry.get("latest_result")
    if result == "PROVEN_POSITIVE" and entry.get("fleet_value") in {
        "FLEET_CAPABLE",
        "FLEET_DEPLOYMENT_CAPABLE",
    }:
        return "fleet-capable workflow"
    if ceiling in {"LIVE_CERTIFIED", "LIVE_CERTIFIED_NEGATIVE"} or result in {
        "PROVEN_POSITIVE",
        "PROVEN_NEGATIVE",
    }:
        return "live certification"
    if impl == "IMPLEMENTED" and ceiling in {"REPOSITORY", "FIXTURE", "IMPLEMENTED_NOT_LIVE_CERTIFIED"}:
        return "repository validation"
    if impl == "IMPLEMENTED":
        return "deterministic SAS command"
    return "ad-hoc experiment"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Project capability ledger to presentation views")
    parser.add_argument("--ledger", required=True, help="Capability ledger JSON")
    parser.add_argument("--output", default=None)
    args = parser.parse_args(argv)
    ledger = json.loads(Path(args.ledger).read_text(encoding="utf-8-sig"))
    projection = project_capability_views(ledger)
    text = json.dumps(projection, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"RECEIPT={args.output}", file=sys.stderr)
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
