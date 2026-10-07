"""Topology, presence, interruption-cost, and non-terminal result contracts.

Physical co-location of Admin Box, reader USB, reader LAN, operator, and
Internet is never assumed. Missing topology is DEFERRED, not CAPABILITY_ABSENT.
"""
from __future__ import annotations

from typing import Any

SCHEMA = "sas-hh-cc-reader-capability-topology/v1"

TOPOLOGY_PROFILES = frozenset(
    {
        "DESK_COMPUTER_AVAILABLE",
        "DESK_USB_ATTENDED",
        "LAB_READER_ON_NETWORK_OPERATOR_ABSENT",
        "LAB_READER_ON_NETWORK_ATTENDED",
        "ADMIN_BOX_RELOCATED_TO_LAB",
        "DUAL_TRANSPORT_ATTENDED",
    }
)

OPERATOR_PRESENCE = frozenset({"none", "optional", "required"})
INTERRUPTION_COST = frozenset({"zero", "low", "medium", "high"})

RESULT_FAMILIES = frozenset(
    {
        "PROVEN_POSITIVE",
        "PROVEN_NEGATIVE",
        "INCONCLUSIVE_ATTENDED_GATE",
        "INCONCLUSIVE_TIMEOUT",
        "DEFERRED_TOPOLOGY_UNAVAILABLE",
        "DEFERRED_OPERATOR_PRESENCE_REQUIRED",
        "CREDENTIAL_GATE",
        "AUTHORITY_GATE",
        "POLICY_REFUSAL",
        "NOT_APPLICABLE",
        "NOT_YET_TESTED",
    }
)

COST_RANK = {"zero": 0, "low": 1, "medium": 2, "high": 3}

# Topology satisfaction: a profile satisfies required profiles that are equal
# or strictly stronger for the same physical plane.
TOPOLOGY_IMPLIES: dict[str, frozenset[str]] = {
    "DESK_COMPUTER_AVAILABLE": frozenset({"DESK_COMPUTER_AVAILABLE"}),
    "DESK_USB_ATTENDED": frozenset({"DESK_COMPUTER_AVAILABLE", "DESK_USB_ATTENDED"}),
    "LAB_READER_ON_NETWORK_OPERATOR_ABSENT": frozenset(
        {"DESK_COMPUTER_AVAILABLE", "LAB_READER_ON_NETWORK_OPERATOR_ABSENT"}
    ),
    "LAB_READER_ON_NETWORK_ATTENDED": frozenset(
        {
            "DESK_COMPUTER_AVAILABLE",
            "LAB_READER_ON_NETWORK_OPERATOR_ABSENT",
            "LAB_READER_ON_NETWORK_ATTENDED",
        }
    ),
    "ADMIN_BOX_RELOCATED_TO_LAB": frozenset(
        {
            "DESK_COMPUTER_AVAILABLE",
            "LAB_READER_ON_NETWORK_OPERATOR_ABSENT",
            "LAB_READER_ON_NETWORK_ATTENDED",
            "ADMIN_BOX_RELOCATED_TO_LAB",
        }
    ),
    "DUAL_TRANSPORT_ATTENDED": frozenset(
        {
            "DESK_COMPUTER_AVAILABLE",
            "DESK_USB_ATTENDED",
            "LAB_READER_ON_NETWORK_ATTENDED",
            "ADMIN_BOX_RELOCATED_TO_LAB",
            "DUAL_TRANSPORT_ATTENDED",
        }
    ),
}


def normalize_topology(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip().upper()
    return text if text in TOPOLOGY_PROFILES else None


def normalize_presence(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip().lower()
    return text if text in OPERATOR_PRESENCE else None


def normalize_cost(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip().lower()
    return text if text in INTERRUPTION_COST else None


def topology_satisfies(current: str | None, required: str | list[str] | None) -> bool:
    """True when current topology can run a capability requiring `required`."""
    cur = normalize_topology(current)
    if cur is None:
        return False
    if required is None:
        return True
    reqs = [required] if isinstance(required, str) else list(required)
    implied = TOPOLOGY_IMPLIES.get(cur, frozenset())
    for req in reqs:
        r = normalize_topology(req)
        if r is None:
            return False
        if r not in implied and r != cur:
            return False
    return True


def presence_satisfies(current: str | None, required: str | None) -> bool:
    cur = normalize_presence(current) or "none"
    req = normalize_presence(required) or "none"
    if req == "none":
        return True
    if req == "optional":
        return True
    return cur == "required"


def classify_measure_outcome(
    *,
    timed_out: bool = False,
    human_prompt_possible: bool = False,
    operator_present: bool = False,
    definitive_negative: bool = False,
    positive: bool = False,
    credential_missing: bool = False,
    authority_missing: bool = False,
    policy_refused: bool = False,
    not_applicable: bool = False,
    topology_ok: bool = True,
    presence_ok: bool = True,
) -> str:
    """Type a raw measure into a non-terminal result family."""
    if not_applicable:
        return "NOT_APPLICABLE"
    if policy_refused:
        return "POLICY_REFUSAL"
    if credential_missing:
        return "CREDENTIAL_GATE"
    if authority_missing:
        return "AUTHORITY_GATE"
    if not topology_ok:
        return "DEFERRED_TOPOLOGY_UNAVAILABLE"
    if not presence_ok:
        return "DEFERRED_OPERATOR_PRESENCE_REQUIRED"
    if positive:
        return "PROVEN_POSITIVE"
    if timed_out and human_prompt_possible and not operator_present:
        return "INCONCLUSIVE_ATTENDED_GATE"
    if timed_out and not definitive_negative:
        return "INCONCLUSIVE_TIMEOUT"
    if definitive_negative:
        return "PROVEN_NEGATIVE"
    if timed_out:
        return "INCONCLUSIVE_TIMEOUT"
    return "NOT_YET_TESTED"


def interruption_rank(cost: str | None) -> int:
    return COST_RANK.get(normalize_cost(cost) or "high", 99)
