"""Machine-readable H&H CC-reader capability ledger with derived exhaustion metrics."""
from __future__ import annotations

import json
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from harness.api.hh_cc_reader_capability_topology import RESULT_FAMILIES

SCHEMA = "sas-hh-cc-reader-capability-ledger/v1"

LEDGER_FIELDS = (
    "capability_id",
    "capability_name",
    "control_plane",
    "required_topology",
    "operator_presence",
    "interruption_cost",
    "authority_requirement",
    "credential_requirement",
    "implementation_state",
    "evidence_state",
    "latest_result",
    "latest_receipt",
    "attempt_count",
    "attended_retry_required",
    "attended_retry_successor",
    "next_reopen_condition",
    "independent_successors",
    "current_proof_ceiling",
    "field_value",
    "fleet_value",
    "presentation_disposition",
    "stakeholder_translation",
    "privacy_classification",
)


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def empty_entry(capability: dict[str, Any]) -> dict[str, Any]:
    return {
        "capability_id": capability.get("capability_id"),
        "capability_name": capability.get("capability_name"),
        "control_plane": capability.get("control_plane"),
        "required_topology": capability.get("required_topology"),
        "operator_presence": capability.get("operator_presence", "none"),
        "interruption_cost": capability.get("interruption_cost", "zero"),
        "authority_requirement": capability.get("authority_requirement"),
        "credential_requirement": capability.get("credential_requirement"),
        "implementation_state": capability.get("implementation_state", "IMPLEMENTED"),
        "evidence_state": capability.get("evidence_state", "NOT_YET_TESTED"),
        "latest_result": "NOT_YET_TESTED",
        "latest_receipt": None,
        "attempt_count": 0,
        "attended_retry_required": False,
        "attended_retry_successor": capability.get("attended_retry_successor"),
        "next_reopen_condition": capability.get("reopen_condition"),
        "independent_successors": list(capability.get("independent_successors") or []),
        "current_proof_ceiling": capability.get("proof_ceiling", "REPOSITORY"),
        "field_value": capability.get("field_value"),
        "fleet_value": capability.get("fleet_value"),
        "presentation_disposition": capability.get("presentation_disposition", "PENDING"),
        "stakeholder_translation": capability.get("stakeholder_translation")
        or {
            "finding": None,
            "consequence": None,
            "next_decision": None,
        },
        "privacy_classification": capability.get("privacy_classification", "INTERNAL"),
    }


def apply_result(
    entry: dict[str, Any],
    *,
    result: str,
    receipt: dict[str, Any] | None = None,
    stakeholder: dict[str, Any] | None = None,
) -> dict[str, Any]:
    out = deepcopy(entry)
    if result not in RESULT_FAMILIES:
        raise ValueError(f"unknown result family: {result}")
    out["latest_result"] = result
    out["evidence_state"] = result
    out["attempt_count"] = int(out.get("attempt_count") or 0) + 1
    if receipt is not None:
        sanitized = redact_secrets(receipt)
        out["latest_receipt"] = {
            "schema": sanitized.get("schema"),
            "result": result,
            "capability_id": out.get("capability_id"),
            "recorded_at": sanitized.get("recorded_at") or _now(),
            "summary": sanitized.get("summary") or sanitized.get("message"),
        }
    out["attended_retry_required"] = result in {
        "INCONCLUSIVE_ATTENDED_GATE",
        "DEFERRED_OPERATOR_PRESENCE_REQUIRED",
    }
    if stakeholder:
        out["stakeholder_translation"] = {
            "finding": stakeholder.get("finding"),
            "consequence": stakeholder.get("consequence"),
            "next_decision": stakeholder.get("next_decision"),
        }
    return out


def redact_secrets(payload: dict[str, Any]) -> dict[str, Any]:
    """Strip credential-like keys from receipt payloads."""
    banned = {
        "api_key",
        "api_secret",
        "password",
        "secret",
        "token",
        "authorization",
        "SAS_PAXSTORE_API_KEY",
        "SAS_PAXSTORE_API_SECRET",
    }

    def walk(node: Any) -> Any:
        if isinstance(node, dict):
            out = {}
            for key, value in node.items():
                if str(key).lower() in {b.lower() for b in banned} or "secret" in str(key).lower():
                    out[key] = "[REDACTED]"
                else:
                    out[key] = walk(value)
            return out
        if isinstance(node, list):
            return [walk(item) for item in node]
        return node

    return walk(payload)


def derive_metrics(entries: list[dict[str, Any]]) -> dict[str, int]:
    """Derive exhaustion metrics; never hardcode totals."""
    total = len(entries)
    attempted = sum(1 for e in entries if int(e.get("attempt_count") or 0) > 0)
    proven_pos = sum(1 for e in entries if e.get("latest_result") == "PROVEN_POSITIVE")
    proven_neg = sum(
        1
        for e in entries
        if e.get("latest_result") in {"PROVEN_NEGATIVE", "NOT_APPLICABLE", "POLICY_REFUSAL"}
    )
    attended = sum(1 for e in entries if e.get("latest_result") == "INCONCLUSIVE_ATTENDED_GATE")
    cred = sum(1 for e in entries if e.get("latest_result") == "CREDENTIAL_GATE")
    auth = sum(1 for e in entries if e.get("latest_result") == "AUTHORITY_GATE")
    topo = sum(
        1
        for e in entries
        if e.get("latest_result")
        in {"DEFERRED_TOPOLOGY_UNAVAILABLE", "DEFERRED_OPERATOR_PRESENCE_REQUIRED"}
    )
    implemented_not_live = sum(
        1
        for e in entries
        if e.get("implementation_state") == "IMPLEMENTED"
        and e.get("current_proof_ceiling") in {"REPOSITORY", "FIXTURE", "IMPLEMENTED_NOT_LIVE_CERTIFIED"}
        and e.get("latest_result")
        not in {"PROVEN_POSITIVE", "PROVEN_NEGATIVE"}
    )
    fleet = sum(
        1
        for e in entries
        if e.get("fleet_value") in {"FLEET_CAPABLE", "FLEET_DEPLOYMENT_CAPABLE", True}
        or e.get("latest_result") == "PROVEN_POSITIVE"
        and e.get("fleet_value") == "CANDIDATE"
    )
    return {
        "TOTAL_AVENUES_MODELED": total,
        "TECHNICALLY_ATTEMPTED": attempted,
        "PROVEN_POSITIVE": proven_pos,
        "PROVEN_NEGATIVE_OR_CLOSED": proven_neg,
        "INCONCLUSIVE_ATTENDED": attended,
        "CREDENTIAL_GATED": cred,
        "AUTHORITY_GATED": auth,
        "TOPOLOGY_DEFERRED": topo,
        "IMPLEMENTED_NOT_LIVE_CERTIFIED": implemented_not_live,
        "FLEET_DEPLOYMENT_CAPABLE": fleet,
    }


def build_ledger(
    catalog: list[dict[str, Any]],
    *,
    results: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    entries = [empty_entry(cap) for cap in catalog]
    by_id = {e["capability_id"]: e for e in entries}
    for cap_id, payload in (results or {}).items():
        if cap_id not in by_id:
            continue
        by_id[cap_id] = apply_result(
            by_id[cap_id],
            result=payload["result"],
            receipt=payload.get("receipt"),
            stakeholder=payload.get("stakeholder"),
        )
    ordered = [by_id[c["capability_id"]] for c in catalog if c["capability_id"] in by_id]
    return {
        "schema": SCHEMA,
        "artifact": "hh-cc-reader-capability-ledger",
        "generated_at": _now(),
        "entries": ordered,
        "metrics": derive_metrics(ordered),
    }


def write_ledger(ledger: dict[str, Any], path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(ledger, indent=2) + "\n", encoding="utf-8")
    return path
