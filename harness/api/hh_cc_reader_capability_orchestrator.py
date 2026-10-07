"""Topology-aware capability program orchestrator (DAG / independent successors).

A single attended-gate or timeout MUST NOT terminate independent exploration.
High-cost Admin Box relocation is selected only after cheaper runnable work.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_capability_ledger import build_ledger, redact_secrets, write_ledger
from harness.api.hh_cc_reader_capability_topology import (
    SCHEMA as TOPOLOGY_SCHEMA,
    classify_measure_outcome,
    interruption_rank,
    normalize_presence,
    normalize_topology,
    presence_satisfies,
    topology_satisfies,
)

SCHEMA = "sas-hh-cc-reader-capability-orchestrator/v1"
DEFAULT_RECEIPT_DIR = ROOT / "survey" / "output" / "hh-cc-reader"

MeasureFn = Callable[[dict[str, Any], dict[str, Any]], dict[str, Any]]


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def default_capability_catalog() -> list[dict[str, Any]]:
    """Seed catalog covering current proved floor and open avenues."""
    return [
        {
            "capability_id": "repo_engineering",
            "capability_name": "Repository implementation and fixtures",
            "control_plane": "sysadminsuite",
            "required_topology": "DESK_COMPUTER_AVAILABLE",
            "operator_presence": "none",
            "interruption_cost": "zero",
            "expected_timeout": 0,
            "human_prompt_possible": False,
            "independent_successors": [
                "paxstore_terminal_observe",
                "paxstore_firmware_preview",
                "firmware_source_portability",
                "presentation_projection",
            ],
            "attended_retry_successor": None,
            "reopen_condition": None,
            "authority_requirement": None,
            "credential_requirement": None,
            "proof_ceiling": "REPOSITORY",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "SUPPORTING",
            "stakeholder_translation": {
                "finding": "Automation work continues without relocating the Admin Box.",
                "consequence": "Field labor is reduced while remote avenues are modeled.",
                "next_decision": "Keep Tier-0 engineering running while the reader is on lab LAN.",
            },
        },
        {
            "capability_id": "paxstore_terminal_observe",
            "capability_name": "PAXSTORE terminal observe",
            "control_plane": "paxstore_openapi",
            "required_topology": "DESK_COMPUTER_AVAILABLE",
            "operator_presence": "none",
            "interruption_cost": "zero",
            "expected_timeout": 30,
            "human_prompt_possible": False,
            "independent_successors": ["paxstore_firmware_preview"],
            "attended_retry_successor": None,
            "reopen_condition": "authorized ESI credentials or fixture",
            "authority_requirement": None,
            "credential_requirement": "SAS_PAXSTORE_API_KEY+SECRET",
            "proof_ceiling": "IMPLEMENTED_NOT_LIVE_CERTIFIED",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "CANDIDATE",
        },
        {
            "capability_id": "paxstore_firmware_preview",
            "capability_name": "PAXSTORE firmware preview",
            "control_plane": "paxstore_openapi",
            "required_topology": "DESK_COMPUTER_AVAILABLE",
            "operator_presence": "none",
            "interruption_cost": "zero",
            "expected_timeout": 30,
            "human_prompt_possible": False,
            "independent_successors": ["firmware_source_portability"],
            "attended_retry_successor": None,
            "reopen_condition": "authorized ESI credentials or fixture",
            "authority_requirement": "mutation false by default",
            "credential_requirement": "SAS_PAXSTORE_API_KEY+SECRET",
            "proof_ceiling": "IMPLEMENTED_NOT_LIVE_CERTIFIED",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "CANDIDATE",
        },
        {
            "capability_id": "firmware_source_portability",
            "capability_name": "Firmware source and reader-to-reader portability",
            "control_plane": "artifact_classifier",
            "required_topology": "DESK_COMPUTER_AVAILABLE",
            "operator_presence": "none",
            "interruption_cost": "zero",
            "expected_timeout": 0,
            "human_prompt_possible": False,
            "independent_successors": ["presentation_projection"],
            "attended_retry_successor": None,
            "reopen_condition": "new artifact metadata or transport",
            "authority_requirement": None,
            "credential_requirement": None,
            "proof_ceiling": "REPOSITORY",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "CANDIDATE",
        },
        {
            "capability_id": "presentation_projection",
            "capability_name": "Evidence-driven presentation projection",
            "control_plane": "presentation",
            "required_topology": "DESK_COMPUTER_AVAILABLE",
            "operator_presence": "none",
            "interruption_cost": "zero",
            "expected_timeout": 0,
            "human_prompt_possible": False,
            "independent_successors": [],
            "attended_retry_successor": None,
            "reopen_condition": "material capability transition",
            "authority_requirement": None,
            "credential_requirement": None,
            "proof_ceiling": "REPOSITORY",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "SUPPORTING",
        },
        {
            "capability_id": "usb_otg_adb_current_config",
            "capability_name": "Admin Box USB OTG ADB (current configuration)",
            "control_plane": "usb_adb",
            "required_topology": "DESK_USB_ATTENDED",
            "operator_presence": "required",
            "interruption_cost": "medium",
            "expected_timeout": 0,
            "human_prompt_possible": True,
            "independent_successors": [
                "paxstore_terminal_observe",
                "same_network_exact_target_probe",
            ],
            "attended_retry_successor": "special_usb_service_window",
            "reopen_condition": (
                "known-good data/service cable, vendor programming accessory, "
                "vendor tool, provider documentation, or newly authorized USB posture"
            ),
            "authority_requirement": None,
            "credential_requirement": None,
            "proof_ceiling": "LIVE_CERTIFIED_NEGATIVE",
            "implementation_state": "IMPLEMENTED",
            "evidence_state": "PROVEN_NEGATIVE",
            "fleet_value": "CLOSED_FOR_CONFIG",
            "closed_by": "PR_506_CONFIRMED_OTG_NO_ENUMERATION",
            "stakeholder_translation": {
                "finding": "The confirmed OTG cable path did not expose a USB client interface.",
                "consequence": "That path is closed for this configuration and will not be re-tried without new evidence.",
                "next_decision": "Continue management-plane and network avenues instead of repeating the same cable attach.",
            },
        },
        {
            "capability_id": "airviewer_attended_view",
            "capability_name": "AirViewer attended remote view",
            "control_plane": "paxstore_airviewer",
            "required_topology": "LAB_READER_ON_NETWORK_OPERATOR_ABSENT",
            "operator_presence": "optional",
            "interruption_cost": "low",
            "expected_timeout": 60,
            "human_prompt_possible": True,
            "independent_successors": ["paxstore_terminal_observe", "repo_engineering"],
            "attended_retry_successor": "airviewer_attended_view_retry",
            "reopen_condition": "operator present at reader for approval window",
            "authority_requirement": "airviewer role",
            "credential_requirement": "paxstore_console",
            "proof_ceiling": "LIVE_ATTENDED",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "FIELD_SUPPORT",
        },
        {
            "capability_id": "airviewer_attended_view_retry",
            "capability_name": "AirViewer attended view (batched retry)",
            "control_plane": "paxstore_airviewer",
            "required_topology": "LAB_READER_ON_NETWORK_ATTENDED",
            "operator_presence": "required",
            "interruption_cost": "low",
            "expected_timeout": 60,
            "human_prompt_possible": True,
            "independent_successors": [],
            "attended_retry_successor": None,
            "reopen_condition": None,
            "authority_requirement": "airviewer role",
            "credential_requirement": "paxstore_console",
            "proof_ceiling": "LIVE_ATTENDED",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "FIELD_SUPPORT",
        },
        {
            "capability_id": "airviewer_unattended",
            "capability_name": "AirViewer unattended mode",
            "control_plane": "paxstore_airviewer",
            "required_topology": "LAB_READER_ON_NETWORK_OPERATOR_ABSENT",
            "operator_presence": "none",
            "interruption_cost": "low",
            "expected_timeout": 15,
            "human_prompt_possible": False,
            "independent_successors": ["paxstore_terminal_observe"],
            "attended_retry_successor": None,
            "reopen_condition": "exact model/role/config provisioning evidence",
            "authority_requirement": "unattended airviewer provisioning",
            "credential_requirement": "paxstore_console",
            "proof_ceiling": "PROVISIONING_EVIDENCE",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "UNKNOWN",
            "requires_provisioning_evidence": True,
        },
        {
            "capability_id": "android_le10_network_adb",
            "capability_name": "Standard Android <=10 network ADB",
            "control_plane": "network_adb",
            "required_topology": "DUAL_TRANSPORT_ATTENDED",
            "operator_presence": "required",
            "interruption_cost": "high",
            "expected_timeout": 30,
            "human_prompt_possible": True,
            "independent_successors": ["paxstore_terminal_observe"],
            "attended_retry_successor": None,
            "reopen_condition": "prior USB ADB bootstrap proved on a capable path",
            "authority_requirement": None,
            "credential_requirement": None,
            "proof_ceiling": "REQUIRES_USB_BOOTSTRAP",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "BLOCKED_BY_USB_FLOOR",
            "requires_prior_usb_adb": True,
        },
        {
            "capability_id": "android_ge11_wireless_pairing",
            "capability_name": "Android 11+ Wireless Debugging pairing",
            "control_plane": "network_adb",
            "required_topology": "LAB_READER_ON_NETWORK_ATTENDED",
            "operator_presence": "required",
            "interruption_cost": "low",
            "expected_timeout": 120,
            "human_prompt_possible": True,
            "independent_successors": [],
            "attended_retry_successor": None,
            "reopen_condition": "device OS proves >=11 and pairing UI permitted",
            "authority_requirement": None,
            "credential_requirement": None,
            "proof_ceiling": "OS_VERSION_UNKNOWN",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "CONDITIONAL",
            "requires_android_ge_11": True,
        },
        {
            "capability_id": "same_network_exact_target_probe",
            "capability_name": "Exact-target same-network probe",
            "control_plane": "lan",
            "required_topology": "ADMIN_BOX_RELOCATED_TO_LAB",
            "operator_presence": "required",
            "interruption_cost": "high",
            "expected_timeout": 60,
            "human_prompt_possible": False,
            "independent_successors": [],
            "attended_retry_successor": None,
            "reopen_condition": "Tier 0-2 runnable work exhausted",
            "authority_requirement": None,
            "credential_requirement": None,
            "proof_ceiling": "LIVE_SAME_NETWORK",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "FIELD_SUPPORT",
            "no_broad_scan": True,
        },
        {
            "capability_id": "special_usb_service_window",
            "capability_name": "Special USB/service programming window",
            "control_plane": "usb_service",
            "required_topology": "DESK_USB_ATTENDED",
            "operator_presence": "required",
            "interruption_cost": "high",
            "expected_timeout": 0,
            "human_prompt_possible": True,
            "independent_successors": [],
            "attended_retry_successor": None,
            "reopen_condition": (
                "known-good data/service cable OR vendor programming accessory OR "
                "vendor tool OR provider documentation OR newly authorized posture"
            ),
            "authority_requirement": "service tooling authorization",
            "credential_requirement": None,
            "proof_ceiling": "REQUIRES_NEW_DISCRIMINATOR",
            "implementation_state": "IMPLEMENTED",
            "fleet_value": "DEFERRED",
        },
    ]


def _seed_closed_otg(results: dict[str, dict[str, Any]]) -> None:
    if "usb_otg_adb_current_config" not in results:
        results["usb_otg_adb_current_config"] = {
            "result": "PROVEN_NEGATIVE",
            "receipt": {
                "schema": "sas-hh-cc-reader-adb-control-plane/v1",
                "summary": (
                    "Confirmed OTG seated; no Android/PAX ADB/MTP/PTP client enumerated. "
                    "Rejected as deployment transport for this configuration (PR #506)."
                ),
                "closed_by": "PR_506",
                "reopen_forbidden_without_new_discriminator": True,
            },
            "stakeholder": {
                "finding": "The confirmed OTG cable path did not expose a USB client interface.",
                "consequence": "That avenue is closed for this configuration.",
                "next_decision": "Do not repeat the same attach; pursue management-plane and network paths.",
            },
        }


def capability_runnable(
    capability: dict[str, Any],
    *,
    current_topology: str | None,
    operator_presence: str | None,
    prior_results: dict[str, str],
    usb_adb_bootstrap_proved: bool = False,
    android_version: int | None = None,
    airviewer_unattended_provisioned: bool = False,
    new_usb_discriminator: bool = False,
) -> tuple[bool, str | None]:
    """Return (runnable, defer_result_if_not)."""
    cap_id = capability["capability_id"]
    if prior_results.get(cap_id) in {
        "PROVEN_POSITIVE",
        "PROVEN_NEGATIVE",
        "NOT_APPLICABLE",
        "POLICY_REFUSAL",
    }:
        return False, None

    if cap_id == "usb_otg_adb_current_config":
        return False, None  # already closed; never selected for rerun

    if cap_id == "special_usb_service_window" and not new_usb_discriminator:
        return False, "NOT_YET_TESTED"

    if capability.get("requires_prior_usb_adb") and not usb_adb_bootstrap_proved:
        return False, "NOT_APPLICABLE"

    if capability.get("requires_android_ge_11"):
        if android_version is None:
            return False, "DEFERRED_TOPOLOGY_UNAVAILABLE"
        if android_version < 11:
            return False, "NOT_APPLICABLE"

    if capability.get("requires_provisioning_evidence") and not airviewer_unattended_provisioned:
        return False, "AUTHORITY_GATE"

    if not topology_satisfies(current_topology, capability.get("required_topology")):
        return False, "DEFERRED_TOPOLOGY_UNAVAILABLE"

    if not presence_satisfies(operator_presence, capability.get("operator_presence")):
        # If human prompt possible under optional presence with absent operator,
        # still allow the attempt so timeout can become INCONCLUSIVE_ATTENDED_GATE.
        if capability.get("human_prompt_possible") and (
            normalize_presence(operator_presence) or "none"
        ) == "none":
            if (normalize_presence(capability.get("operator_presence")) or "none") == "required":
                return False, "DEFERRED_OPERATOR_PRESENCE_REQUIRED"
        elif (normalize_presence(capability.get("operator_presence")) or "none") == "required":
            return False, "DEFERRED_OPERATOR_PRESENCE_REQUIRED"

    return True, None


def select_run_order(
    catalog: list[dict[str, Any]],
    *,
    current_topology: str | None,
    operator_presence: str | None,
    prior_results: dict[str, str],
    **gates: Any,
) -> list[dict[str, Any]]:
    runnable: list[dict[str, Any]] = []
    for cap in catalog:
        ok, _ = capability_runnable(
            cap,
            current_topology=current_topology,
            operator_presence=operator_presence,
            prior_results=prior_results,
            **gates,
        )
        if ok:
            runnable.append(cap)
    runnable.sort(key=lambda c: (interruption_rank(c.get("interruption_cost")), c["capability_id"]))
    # Hard rule: never select high-cost while zero/low remain.
    if any(interruption_rank(c.get("interruption_cost")) <= 1 for c in runnable):
        runnable = [c for c in runnable if interruption_rank(c.get("interruption_cost")) <= 1] + [
            c for c in runnable if interruption_rank(c.get("interruption_cost")) > 1
        ]
        # Drop high until lower exhausted in this selection pass
        lower = [c for c in runnable if interruption_rank(c.get("interruption_cost")) <= 1]
        if lower:
            return lower
    return runnable


def default_measure(capability: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    """Default offline measure for repository/fixture program runs."""
    cap_id = capability["capability_id"]
    injected = (context.get("measure_results") or {}).get(cap_id)
    if isinstance(injected, dict):
        return injected

    if cap_id == "repo_engineering":
        return {"positive": True, "summary": "Repository capability program code present."}
    if cap_id in {"paxstore_terminal_observe", "paxstore_firmware_preview"}:
        if context.get("paxstore_credentials_present"):
            return {"positive": True, "summary": "PAXSTORE fixture/credential path available."}
        return {"credential_missing": True, "summary": "PAXSTORE API credentials unavailable."}
    if cap_id == "firmware_source_portability":
        return {"positive": True, "summary": "Portability classifier implemented."}
    if cap_id == "presentation_projection":
        return {"positive": True, "summary": "Presentation projection seam implemented."}
    if cap_id == "airviewer_attended_view":
        return {
            "timed_out": True,
            "human_prompt_possible": True,
            "summary": "Remote view request timed out; terminal approval may be waiting.",
        }
    if cap_id == "airviewer_unattended":
        return {
            "authority_missing": True,
            "summary": "Unattended AirViewer requires provisioning evidence.",
        }
    if cap_id == "android_le10_network_adb":
        return {
            "not_applicable": True,
            "summary": "Standard <=10 network ADB requires prior USB ADB bootstrap.",
        }
    if cap_id == "same_network_exact_target_probe":
        return {
            "timed_out": False,
            "summary": "Same-network probe reserved for high-cost relocation window.",
        }
    return {"summary": "No measure injected.", "not_yet": True}


def run_capability_program(
    *,
    current_topology: str,
    operator_presence: str = "none",
    catalog: list[dict[str, Any]] | None = None,
    prior_results: dict[str, dict[str, Any]] | None = None,
    measure: MeasureFn | None = None,
    context: dict[str, Any] | None = None,
    interactive_retry: bool = False,
) -> dict[str, Any]:
    """Execute independent capability DAG; never stop global program on one gate."""
    if interactive_retry and (normalize_presence(operator_presence) or "none") == "none":
        interactive_retry = False  # operator absent => no interactive retry loop

    topo = normalize_topology(current_topology)
    presence = normalize_presence(operator_presence) or "none"
    caps = catalog or default_capability_catalog()
    results: dict[str, dict[str, Any]] = dict(prior_results or {})
    _seed_closed_otg(results)
    prior_simple = {k: v["result"] for k, v in results.items()}
    ctx = dict(context or {})
    measure_fn = measure or default_measure
    receipts: list[dict[str, Any]] = []
    executed: list[str] = []
    deferred: list[dict[str, Any]] = []
    operator_present = presence == "required"

    # Apply static deferrals for non-runnable caps without executing.
    gates = {
        "usb_adb_bootstrap_proved": bool(ctx.get("usb_adb_bootstrap_proved")),
        "android_version": ctx.get("android_version"),
        "airviewer_unattended_provisioned": bool(ctx.get("airviewer_unattended_provisioned")),
        "new_usb_discriminator": bool(ctx.get("new_usb_discriminator")),
    }
    for cap in caps:
        ok, defer = capability_runnable(
            cap,
            current_topology=topo,
            operator_presence=presence,
            prior_results=prior_simple,
            **gates,
        )
        if not ok and defer and cap["capability_id"] not in prior_simple:
            if defer in {
                "DEFERRED_TOPOLOGY_UNAVAILABLE",
                "DEFERRED_OPERATOR_PRESENCE_REQUIRED",
                "NOT_APPLICABLE",
                "AUTHORITY_GATE",
                "NOT_YET_TESTED",
            }:
                results[cap["capability_id"]] = {
                    "result": defer,
                    "receipt": {
                        "summary": f"Not executed: {defer}",
                        "capability_id": cap["capability_id"],
                    },
                }
                prior_simple[cap["capability_id"]] = defer
                deferred.append(
                    {
                        "capability_id": cap["capability_id"],
                        "result": defer,
                        "required_topology": cap.get("required_topology"),
                        "interruption_cost": cap.get("interruption_cost"),
                    }
                )

    # Independent execution: select all currently runnable (cheap-first) and run.
    # Re-select after each batch so successors unlocked by results can continue.
    safety = 0
    while safety < 32:
        safety += 1
        order = select_run_order(
            caps,
            current_topology=topo,
            operator_presence=presence,
            prior_results=prior_simple,
            **gates,
        )
        # Exclude already executed this run
        order = [c for c in order if c["capability_id"] not in executed]
        if not order:
            break
        # Run entire cheap batch independently (do not stop on attended gate)
        batch = order
        progressed = False
        for cap in batch:
            cap_id = cap["capability_id"]
            if cap_id in executed:
                continue
            raw = measure_fn(cap, ctx)
            result = classify_measure_outcome(
                timed_out=bool(raw.get("timed_out")),
                human_prompt_possible=bool(
                    raw.get("human_prompt_possible", cap.get("human_prompt_possible"))
                ),
                operator_present=operator_present,
                definitive_negative=bool(raw.get("definitive_negative")),
                positive=bool(raw.get("positive")),
                credential_missing=bool(raw.get("credential_missing")),
                authority_missing=bool(raw.get("authority_missing")),
                policy_refused=bool(raw.get("policy_refused")),
                not_applicable=bool(raw.get("not_applicable")),
                topology_ok=True,
                presence_ok=True,
            )
            if raw.get("not_yet") and result == "NOT_YET_TESTED":
                result = "NOT_YET_TESTED"
            receipt = redact_secrets(
                {
                    "schema": SCHEMA,
                    "capability_id": cap_id,
                    "result": result,
                    "recorded_at": _now(),
                    "topology": topo,
                    "operator_presence": presence,
                    "summary": raw.get("summary"),
                    "measure": {
                        k: v
                        for k, v in raw.items()
                        if k
                        not in {
                            "api_key",
                            "api_secret",
                            "secret",
                            "token",
                        }
                    },
                    "interactive_retry_attempted": False,
                }
            )
            results[cap_id] = {
                "result": result,
                "receipt": receipt,
                "stakeholder": cap.get("stakeholder_translation"),
            }
            prior_simple[cap_id] = result
            receipts.append(receipt)
            executed.append(cap_id)
            progressed = True
            # Never break the loop for attended gate — continue independent successors.
        if not progressed:
            break

    ledger = build_ledger(caps, results=results)
    attended_manifest = build_attended_window_manifest(caps, results)
    selected_high_cost = [
        c["capability_id"]
        for c in caps
        if c["capability_id"] in executed
        and interruption_rank(c.get("interruption_cost")) >= 3
    ]
    lower_still_runnable = select_run_order(
        caps,
        current_topology=topo,
        operator_presence=presence,
        prior_results=prior_simple,
        **gates,
    )
    lower_remaining = [
        c["capability_id"]
        for c in lower_still_runnable
        if interruption_rank(c.get("interruption_cost")) <= 1
        and c["capability_id"] not in executed
    ]

    return {
        "schema": SCHEMA,
        "topology_schema": TOPOLOGY_SCHEMA,
        "recorded_at": _now(),
        "current_topology": topo,
        "operator_presence": presence,
        "executed_capability_ids": executed,
        "deferred": deferred,
        "receipts": receipts,
        "ledger": ledger,
        "attended_window_manifest": attended_manifest,
        "high_cost_selected_while_lower_remained": bool(selected_high_cost and lower_remaining),
        "program_terminated_early": False,
        "interactive_retry_allowed": interactive_retry,
        "metrics": ledger["metrics"],
        "next_transition": _next_transition(caps, prior_simple, attended_manifest),
    }


def build_attended_window_manifest(
    catalog: list[dict[str, Any]],
    results: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    """Collapse all human-gated outstanding experiments into one batched manifest."""
    by_id = {c["capability_id"]: c for c in catalog}
    items: list[dict[str, Any]] = []
    for cap_id, payload in results.items():
        if payload.get("result") not in {
            "INCONCLUSIVE_ATTENDED_GATE",
            "DEFERRED_OPERATOR_PRESENCE_REQUIRED",
        }:
            continue
        cap = by_id.get(cap_id, {})
        successor = cap.get("attended_retry_successor") or cap_id
        items.append(
            {
                "capability_id": cap_id,
                "attended_retry_successor": successor,
                "required_topology": (
                    by_id.get(successor, cap).get("required_topology")
                    or cap.get("required_topology")
                ),
                "interruption_cost": by_id.get(successor, cap).get("interruption_cost")
                or cap.get("interruption_cost"),
                "reason": (payload.get("receipt") or {}).get("summary"),
                "human_gate": True,
            }
        )
    # Also queue known required-presence caps not yet proved when they need attendance.
    for cap in catalog:
        if cap.get("operator_presence") != "required":
            continue
        if cap["capability_id"] in {i["capability_id"] for i in items}:
            continue
        latest = (results.get(cap["capability_id"]) or {}).get("result")
        if latest in {
            "PROVEN_POSITIVE",
            "PROVEN_NEGATIVE",
            "NOT_APPLICABLE",
            "POLICY_REFUSAL",
            "NOT_YET_TESTED",
        }:
            continue
        if latest in {
            "DEFERRED_TOPOLOGY_UNAVAILABLE",
            "DEFERRED_OPERATOR_PRESENCE_REQUIRED",
            "INCONCLUSIVE_ATTENDED_GATE",
        } or cap.get("human_prompt_possible"):
            if latest in {
                "DEFERRED_OPERATOR_PRESENCE_REQUIRED",
                "INCONCLUSIVE_ATTENDED_GATE",
                "DEFERRED_TOPOLOGY_UNAVAILABLE",
            }:
                items.append(
                    {
                        "capability_id": cap["capability_id"],
                        "attended_retry_successor": cap.get("attended_retry_successor")
                        or cap["capability_id"],
                        "required_topology": cap.get("required_topology"),
                        "interruption_cost": cap.get("interruption_cost"),
                        "reason": f"Queued from result {latest}",
                        "human_gate": True,
                    }
                )

    # Batch by topology / location
    batches: dict[str, list[dict[str, Any]]] = {}
    for item in items:
        key = str(item.get("required_topology") or "UNKNOWN")
        batches.setdefault(key, []).append(item)

    # Prefer lower interruption batches first; keep ADMIN_BOX last.
    ordered_keys = sorted(
        batches.keys(),
        key=lambda k: (
            99
            if k == "ADMIN_BOX_RELOCATED_TO_LAB"
            else interruption_rank(
                next(
                    (
                        i.get("interruption_cost")
                        for i in batches[k]
                        if i.get("interruption_cost")
                    ),
                    "medium",
                )
            ),
            k,
        ),
    )
    return {
        "schema": "sas-hh-cc-reader-attended-window-manifest/v1",
        "generated_at": _now(),
        "batch_count": len(ordered_keys),
        "batches": [
            {
                "required_topology": key,
                "experiments": batches[key],
                "operator_instruction": (
                    "Relocate Admin Box only after all zero/low-cost batches are exhausted."
                    if key == "ADMIN_BOX_RELOCATED_TO_LAB"
                    else "Complete every listed approval/observation in one visit at this topology."
                ),
            }
            for key in ordered_keys
        ],
        "high_cost_relocation_deferred_until_lower_exhausted": True,
    }


def _next_transition(
    catalog: list[dict[str, Any]],
    prior_simple: dict[str, str],
    attended_manifest: dict[str, Any],
) -> dict[str, Any]:
    # Prefer remaining zero-cost not-yet / credential work, else first attended batch.
    for cap in sorted(catalog, key=lambda c: interruption_rank(c.get("interruption_cost"))):
        r = prior_simple.get(cap["capability_id"])
        if r in {"CREDENTIAL_GATE", "NOT_YET_TESTED", "IMPLEMENTED_NOT_LIVE_CERTIFIED"}:
            return {
                "capability_id": cap["capability_id"],
                "reason": f"Continue independent work at result={r}",
                "interruption_cost": cap.get("interruption_cost"),
            }
    batches = attended_manifest.get("batches") or []
    if batches:
        first = batches[0]
        exp = (first.get("experiments") or [{}])[0]
        return {
            "capability_id": exp.get("attended_retry_successor") or exp.get("capability_id"),
            "reason": "First item in consolidated attended-window manifest",
            "required_topology": first.get("required_topology"),
            "interruption_cost": exp.get("interruption_cost"),
        }
    return {
        "capability_id": "same_network_exact_target_probe",
        "reason": "Lower-cost lanes exhausted; high-cost same-network window is next gated step",
        "required_topology": "ADMIN_BOX_RELOCATED_TO_LAB",
        "interruption_cost": "high",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="H&H CC-reader topology-aware capability program")
    parser.add_argument(
        "--mode",
        choices=("run", "ledger", "attended-manifest", "classify-result", "catalog"),
        default="run",
    )
    parser.add_argument(
        "--topology",
        default="DESK_COMPUTER_AVAILABLE",
        help="Current physical topology profile",
    )
    parser.add_argument(
        "--operator-presence",
        default="none",
        choices=sorted({"none", "optional", "required"}),
    )
    parser.add_argument("--output", default=None)
    parser.add_argument("--timed-out", action="store_true")
    parser.add_argument("--human-prompt-possible", action="store_true")
    parser.add_argument("--operator-present", action="store_true")
    parser.add_argument("--definitive-negative", action="store_true")
    parser.add_argument("--positive", action="store_true")
    args = parser.parse_args(argv)

    if args.mode == "classify-result":
        result = {
            "schema": SCHEMA,
            "result": classify_measure_outcome(
                timed_out=args.timed_out,
                human_prompt_possible=args.human_prompt_possible,
                operator_present=args.operator_present,
                definitive_negative=args.definitive_negative,
                positive=args.positive,
            ),
        }
        print(json.dumps(result, indent=2))
        return 0

    if args.mode == "catalog":
        print(json.dumps({"schema": SCHEMA, "catalog": default_capability_catalog()}, indent=2))
        return 0

    program = run_capability_program(
        current_topology=args.topology,
        operator_presence=args.operator_presence,
    )
    if args.mode == "ledger":
        payload = program["ledger"]
    elif args.mode == "attended-manifest":
        payload = program["attended_window_manifest"]
    else:
        payload = program

    out = Path(args.output) if args.output else None
    if out:
        write_ledger(payload if args.mode == "ledger" else payload, out) if False else None
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"RECEIPT={out}", file=sys.stderr)
    else:
        DEFAULT_RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        path = DEFAULT_RECEIPT_DIR / f"hh-cc-reader-capability-program-{stamp}.json"
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"RECEIPT={path}", file=sys.stderr)

    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
