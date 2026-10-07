"""Wireless / network capability factoring for H&H CC-reader (no subnet scans)."""
from __future__ import annotations

from typing import Any

SCHEMA = "sas-hh-cc-reader-wireless-capability/v1"


def classify_wifi_topology_hypothesis(*, wifi_configured: bool | None = None) -> dict[str, Any]:
    return {
        "schema": SCHEMA,
        "capability": "wifi_connectivity",
        "result": "NOT_YET_TESTED" if wifi_configured is None else (
            "PROVEN_POSITIVE" if wifi_configured else "PROVEN_NEGATIVE"
        ),
        "retained_hypothesis": True,
        "note": "Wi-Fi co-location remains a topology hypothesis; do not assume fleet config.",
    }


def classify_network_adb(
    *,
    android_version: int | None,
    usb_adb_bootstrap_proved: bool = False,
    previously_paired_trusted: bool = False,
    pairing_ui_available: bool = False,
    operator_present: bool = False,
    exact_target_listener_observed: bool = False,
) -> dict[str, Any]:
    """Factor Android <=10 vs >=11 wireless ADB without inventing OS facts."""
    if android_version is None:
        return {
            "schema": SCHEMA,
            "capability": "network_adb",
            "result": "DEFERRED_TOPOLOGY_UNAVAILABLE",
            "reason": "android_version_unobserved",
            "standard_le10_requires_usb_bootstrap": True,
            "ge11_wireless_pairing_attended": True,
        }

    if android_version <= 10:
        if not usb_adb_bootstrap_proved:
            return {
                "schema": SCHEMA,
                "capability": "network_adb_android_le10",
                "result": "NOT_APPLICABLE",
                "reason": "standard_le10_network_adb_requires_prior_usb_bootstrap",
                "requires_prior_usb_adb": True,
                "usb_bypass": False,
            }
        return {
            "schema": SCHEMA,
            "capability": "network_adb_android_le10",
            "result": "NOT_YET_TESTED",
            "reason": "usb_bootstrap_proved_network_transaction_not_yet_run",
            "requires_prior_usb_adb": True,
        }

    # Android 11+
    if previously_paired_trusted:
        return {
            "schema": SCHEMA,
            "capability": "wireless_debugging_android_ge11",
            "result": "NOT_YET_TESTED",
            "reason": "previously_paired_trusted_requires_live_cert",
            "attended_required": False,
        }
    if not operator_present or not pairing_ui_available:
        return {
            "schema": SCHEMA,
            "capability": "wireless_debugging_android_ge11",
            "result": "INCONCLUSIVE_ATTENDED_GATE"
            if pairing_ui_available
            else "DEFERRED_OPERATOR_PRESENCE_REQUIRED",
            "reason": "pairing_qr_or_code_requires_local_interaction",
            "attended_required": True,
        }
    return {
        "schema": SCHEMA,
        "capability": "wireless_debugging_android_ge11",
        "result": "NOT_YET_TESTED",
        "reason": "attended_pairing_window_available",
        "attended_required": True,
    }


def classify_vendor_network_adb_listener(
    *,
    exact_target_identity_bound: bool,
    listener_observed: bool,
) -> dict[str, Any]:
    if not exact_target_identity_bound:
        return {
            "schema": SCHEMA,
            "capability": "vendor_enabled_network_adb_listener",
            "result": "POLICY_REFUSAL",
            "reason": "exact_target_identity_required_no_subnet_scan",
            "subnet_scan": False,
        }
    if not listener_observed:
        return {
            "schema": SCHEMA,
            "capability": "vendor_enabled_network_adb_listener",
            "result": "NOT_YET_TESTED",
            "reason": "separate_hypothesis_from_standard_wifi_adb",
            "subnet_scan": False,
        }
    return {
        "schema": SCHEMA,
        "capability": "vendor_enabled_network_adb_listener",
        "result": "PROVEN_POSITIVE",
        "subnet_scan": False,
    }


def classify_airviewer(
    *,
    mode: str,
    timed_out: bool = False,
    operator_present: bool = False,
    unattended_provisioning_evidence: bool = False,
) -> dict[str, Any]:
    mode_n = (mode or "").strip().lower()
    if mode_n == "unattended":
        if not unattended_provisioning_evidence:
            return {
                "schema": SCHEMA,
                "capability": "airviewer_unattended",
                "result": "AUTHORITY_GATE",
                "reason": "unattended_requires_exact_model_role_config_evidence",
            }
        return {
            "schema": SCHEMA,
            "capability": "airviewer_unattended",
            "result": "NOT_YET_TESTED",
            "reason": "provisioning_evidence_present_live_cert_pending",
        }
    if mode_n in {"view", "attended_view", "full_control", "resume"}:
        if timed_out and not operator_present:
            return {
                "schema": SCHEMA,
                "capability": f"airviewer_{mode_n}",
                "result": "INCONCLUSIVE_ATTENDED_GATE",
                "reason": "terminal_approval_may_be_waiting",
                "human_gate": True,
            }
        return {
            "schema": SCHEMA,
            "capability": f"airviewer_{mode_n}",
            "result": "NOT_YET_TESTED",
            "human_gate": True,
        }
    return {
        "schema": SCHEMA,
        "capability": "airviewer",
        "result": "UNKNOWN",
        "reason": "mode_unrecognized",
    }
