"""Admin Box ADB control-plane classifier for H&H Kiosk4 / PAX A80.

The Admin Box plus SysAdminSuite workflows are the control plane.
ADB is a transport beneath that plane, not the plane itself.

This seam classifies host tooling, USB/PnP, ADB authorization, identity,
read-only inventory, exact-target network ADB transactions, and view-only
remote display. It never authorizes firmware, app, payment, or security
mutation. Live serials, MACs, and IPs stay out of tracked receipts.
"""
from __future__ import annotations

import argparse
import json
import re
import secrets
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]

import sys

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_version_domain import (  # noqa: E402
    classify_current_firmware_observation,
    evaluate_baseline_transition_eligibility,
    evaluate_version_domains,
    pattern_hint_domain,
)
from harness.api.android_provider import PLATFORM_TOOLS_SOURCE

SCHEMA = "sas-hh-cc-reader-adb-control-plane/v1"
DEFAULT_RECEIPT_DIR = ROOT / "survey" / "output" / "hh-cc-reader"
OWNED_CACHE_REL = "SysAdminSuite/tools/android-platform-tools"
CAMPAIGN_TARGET = "2.0.15.260522"

MODES = frozenset(
    {
        "prepare-host",
        "probe",
        "inventory",
        "tcpip-cert",
        "remote-view",
        "orchestrate",
        "classify",
    }
)

FORBIDDEN_ADB_TOKENS = (
    "adb root",
    "adb remount",
    "adb reboot",
    "adb sideload",
    "adb install",
    "adb uninstall",
    "adb push",
    "adb pull",
    "fastboot",
    "settings put",
    "setprop",
    "oem unlock",
    "flashing unlock",
    "disable-verity",
    "bugreport",
    "logcat",
)

ALLOWED_ADB_VERBS = frozenset(
    {
        "version",
        "start-server",
        "kill-server",
        "devices",
        "get-state",
        "get-serialno",
        "shell",
        "tcpip",
        "usb",
        "connect",
        "disconnect",
    }
)

ALLOWED_SHELL_PREFIXES = (
    "getprop",
    "pm list packages",
    "ps",
    "ip addr",
    "ip route",
    "dumpsys connectivity",
    "dumpsys device_policy",
    "echo",
)

FIRMWARE_PROPERTY_KEYS = (
    "ro.build.display.id",
    "ro.build.version.incremental",
    "ro.pax.model",
    "ro.pax.firmware",
    "ro.pax.os.version",
    "persist.sys.pax.firmware",
    "ro.vendor.build.fingerprint",
    "ro.build.fingerprint",
    "ro.build.version.release",
    "ro.build.version.sdk",
    "ro.product.model",
    "ro.product.manufacturer",
    "ro.product.brand",
)

PACKAGE_HINTS = {
    "paxstore": ("paxstore", "com.pax.market", "com.pax.poslite"),
    "maxstore": ("maxstore", "com.pax.maxstore"),
    "airviewer": ("airviewer", "com.pax.airviewer"),
    "experian": ("experian", "axiamed", "paymentsafe", "com.axiamed"),
    "dpc": ("devicepolicymanager", "com.google.android.apps.work", "dpc"),
}

SCREEN_VALUES = frozenset({"observed", "unobserved", "not_required"})


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _text(value: Any) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    return text or None


def _bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    text = str(value).strip().casefold()
    if text in {"1", "true", "yes"}:
        return True
    if text in {"0", "false", "no"}:
        return False
    return default


def command_is_forbidden(command: str) -> bool:
    folded = command.casefold()
    return any(token in folded for token in FORBIDDEN_ADB_TOKENS)


def command_is_allowed_readonly(command: str) -> bool:
    raw = command.strip()
    folded = raw.casefold()
    if command_is_forbidden(raw):
        return False
    if folded.startswith("adb "):
        rest = folded[4:].strip()
        if rest.startswith("-s "):
            parts = rest.split(None, 2)
            rest = parts[2] if len(parts) > 2 else ""
        verb = rest.split(None, 1)[0] if rest else ""
        if verb == "tcpip":
            return rest.strip() in {"tcpip 5555", "tcpip"}
        if verb == "connect" or verb == "disconnect":
            return True
        if verb == "shell":
            shell = rest.split(None, 1)[1] if " " in rest else ""
            return any(shell.startswith(prefix) for prefix in ALLOWED_SHELL_PREFIXES)
        return verb in ALLOWED_ADB_VERBS
    return False


def _collect_attempted_commands(evidence: dict[str, Any]) -> list[str]:
    commands: list[str] = []
    for key in ("attempted_commands", "commands_executed", "proposed_commands"):
        raw = evidence.get(key)
        if isinstance(raw, list):
            commands.extend(str(item) for item in raw if item is not None)
    for nested_key in ("host", "inventory", "network_adb", "remote_view"):
        nested = evidence.get(nested_key)
        if isinstance(nested, dict):
            extra = nested.get("attempted_commands") or nested.get("commands_executed")
            if isinstance(extra, list):
                commands.extend(str(item) for item in extra if item is not None)
    return commands


def _mutation_attempt(evidence: dict[str, Any]) -> list[str]:
    return [cmd for cmd in _collect_attempted_commands(evidence) if command_is_forbidden(cmd)]


def adapt_getprop_to_labeled_observations(
    properties: dict[str, Any],
    *,
    observed_at: str | None = None,
    device_model: str | None = None,
) -> list[dict[str, Any]]:
    """Map Android properties into classifier-native labeled observations.

    Every plausible version/build value is captured with its exact property key.
    Only a semantically labeled Installed Firmware row is offered as a current
    firmware candidate. Numeric Android release strings are never substituted
    for campaign target 2.0.15.260522.
    """
    observed_at = observed_at or _now()
    model = device_model or _text(properties.get("ro.product.model"))
    rows: list[dict[str, Any]] = []
    for key in FIRMWARE_PROPERTY_KEYS:
        value = _text(properties.get(key))
        if not value:
            continue
        if value == CAMPAIGN_TARGET:
            continue
        rows.append(
            {
                "section": "ADB getprop",
                "field_heading": key,
                "value": value,
                "property_key": key,
                "source_surface": "authorized_adb_readonly",
                "device": {"model": model or "UNKNOWN"},
                "observed_at": observed_at,
            }
        )
        hint = pattern_hint_domain(value)
        if hint in {"paydroid_os_build", "pax_pts_device_firmware"}:
            rows.append(
                {
                    "section": "Installed Firmware",
                    "field_heading": "Installed Firmware",
                    "value": value,
                    "property_key": key,
                    "source_surface": "authorized_adb_readonly",
                    "device": {"model": model or "A80"},
                    "device_model": model or "PAX A80",
                    "observed_at": observed_at,
                }
            )
    return rows


def classify_packages(package_text: str | None) -> dict[str, str]:
    blob = (package_text or "").casefold()
    result: dict[str, str] = {}
    for name, tokens in PACKAGE_HINTS.items():
        result[name] = "PRESENT" if any(token in blob for token in tokens) else "ABSENT"
    return result


def classify_device_owner(dumpsys_text: str | None) -> str:
    blob = (dumpsys_text or "").casefold()
    if not blob:
        return "UNKNOWN"
    if "device owner" in blob or "deviceowner" in blob:
        if "none" in blob and "device owner" in blob:
            return "NO_DEVICE_OWNER_DECLARED"
        return "DEVICE_OWNER_EVIDENCE_PRESENT"
    return "NO_DEVICE_OWNER_EVIDENCE"


def _host_state(host: dict[str, Any]) -> dict[str, Any]:
    present = _bool(host.get("adb_present"))
    path = _text(host.get("adb_path"))
    version = _text(host.get("adb_version"))
    path_other = _text(host.get("path_adb_path"))
    owned = _text(host.get("owned_adb_path"))
    precedence = _text(host.get("precedence")) or "none"
    if present and path:
        state = "ADB_HOST_READY"
        next_action = "Run Probe-HHCCReaderAdb.cmd to classify USB and ADB device authorization."
    else:
        state = "ADB_HOST_NOT_INSTALLED"
        next_action = (
            "Run Prepare-HHCCReaderAdbHost.cmd to install official Google Android "
            "Platform-Tools into the SysAdminSuite local tool cache."
        )
        path = None
        version = None
    return {
        "adb_host_state": state,
        "adb_path_recorded": bool(path),
        "adb_version": version,
        "path_adb_also_present": bool(path_other),
        "owned_adb_recorded": bool(owned),
        "precedence": precedence,
        "platform_tools_source": _text(host.get("source")) or PLATFORM_TOOLS_SOURCE,
        "archive_sha256_recorded": bool(_text((host.get("install") or {}).get("archive_sha256")) if isinstance(host.get("install"), dict) else host.get("archive_sha256")),
        "next_action": next_action,
    }


def _usb_state(usb: dict[str, Any], host_ready: bool) -> dict[str, Any]:
    if not host_ready:
        return {
            "usb_enumeration_state": "NOT_EVALUATED",
            "next_action": "Install or locate adb.exe before USB classification.",
        }
    enumerated = _bool(usb.get("enumerated"))
    android = _bool(usb.get("android_composite"))
    adb_iface = _bool(usb.get("adb_interface"))
    driver_problem = _bool(usb.get("driver_problem"))
    otg_confirmed = _bool(usb.get("operator_otg_client_path_confirmed"))
    if not enumerated:
        state = "USB_DEVICE_NOT_ENUMERATED"
        nxt = "Connect the authorized Kiosk4 USB cable to the Admin Box, then rerun Probe-HHCCReaderAdb.cmd."
    elif driver_problem:
        state = "USB_DRIVER_OR_INTERFACE_UNRESOLVED"
        nxt = "Inspect Windows Device Manager for the enumerated Android/PAX USB device, then rerun Probe-HHCCReaderAdb.cmd."
    elif not android and not adb_iface:
        state = "USB_DEVICE_NOT_ENUMERATED"
        if otg_confirmed:
            nxt = (
                "Operator-confirmed micro-USB/OTG attach still produced no Android/ADB/MTP/PTP client on the Admin Box. "
                "Treat USB_OTG_ADB as not a deployment transport in this configuration. Continue LAN/management planes. "
                "Do not enable Developer Options. A80 datasheets list micro-USB 2.0 OTG, so the receptacle is not "
                "decorative; live data-path role remains open (power-only cable, device USB functions gated, or "
                "vendor/programming accessory path)."
            )
        else:
            nxt = (
                "No Android/PAX USB candidate is enumerated on the Admin Box. Physical cables can still be seated: "
                "A80 USB-HOST is terminal-host (not ADB client), and RS232 RJ45 is serial (not LAN). "
                "If micro-USB/OTG is already seated, rerun Probe-HHCCReaderAdb.cmd --otg-confirmed. "
                "Otherwise use the USB device/client path and LAN-only Ethernet. Absence here does not prove "
                "Kiosk4 cannot do ADB over a different authorized path."
            )
    elif android and not adb_iface:
        state = "USB_DEVICE_ENUMERATED_NO_ADB_INTERFACE"
        nxt = "An Android USB composite appeared without an ADB interface. USB debugging may be off. This does not prove Kiosk4 cannot do ADB."
    else:
        state = "USB_ADB_INTERFACE_PRESENT"
        nxt = "Run adb devices classification via Probe-HHCCReaderAdb.cmd."
    return {
        "usb_enumeration_state": state,
        "android_usb_present": android,
        "adb_interface_present": adb_iface,
        "pax_or_a80_hint": _bool(usb.get("pax_or_a80_hint")),
        "next_action": nxt,
    }


def _device_rows(evidence: dict[str, Any]) -> list[dict[str, Any]]:
    rows = evidence.get("adb_devices")
    if isinstance(rows, list):
        return [row for row in rows if isinstance(row, dict)]
    return []


def _device_state(evidence: dict[str, Any], host_ready: bool) -> dict[str, Any]:
    if not host_ready:
        return {
            "adb_device_state": "ADB_HOST_NOT_INSTALLED",
            "adb_auth_state": "NOT_EVALUATED",
            "next_action": "Install official Platform-Tools, then rerun Probe-HHCCReaderAdb.cmd.",
        }
    rows = _device_rows(evidence)
    usb_rows = [row for row in rows if str(row.get("transport") or "usb").casefold() != "tcp"]
    count = len(usb_rows) if usb_rows else len(rows)
    if count > 1:
        return {
            "adb_device_state": "ADB_MULTIPLE_DEVICES_BLOCKED",
            "adb_auth_state": "NOT_EVALUATED",
            "device_count": count,
            "next_action": "Disconnect extra Android USB devices so exactly one authorized Kiosk4 remains, then rerun Probe-HHCCReaderAdb.cmd.",
        }
    if count == 0:
        return {
            "adb_device_state": "ADB_NO_DEVICE",
            "adb_auth_state": "NOT_EVALUATED",
            "device_count": 0,
            "next_action": "Use USB/PnP evidence: reconnect the authorized cable, then rerun Probe-HHCCReaderAdb.cmd. Do not claim Kiosk4 has no ADB.",
        }
    row = usb_rows[0] if usb_rows else rows[0]
    status = str(row.get("state") or "").strip().casefold()
    if status == "unauthorized":
        return {
            "adb_device_state": "ADB_DEVICE_UNAUTHORIZED",
            "adb_auth_state": "AUTHORIZATION_REQUIRED",
            "adb_transport_present": True,
            "device_count": 1,
            "proved": "USB ADB transport is present between the Admin Box and the Android ADB daemon.",
            "next_action": "On Kiosk4, approve the Admin Box RSA debugging key, then rerun Probe-HHCCReaderAdb.cmd.",
            "attended_retry_required": True,
            "human_screen_gate": True,
        }
    if status == "offline":
        return {
            "adb_device_state": "ADB_DEVICE_OFFLINE",
            "adb_auth_state": "OFFLINE",
            "adb_transport_present": True,
            "device_count": 1,
            "next_action": "Reconnect USB to the same authorized Kiosk4, then rerun Probe-HHCCReaderAdb.cmd.",
        }
    if status in {"device", "ready"}:
        return {
            "adb_device_state": "ADB_DEVICE_READY",
            "adb_auth_state": "AUTHORIZED",
            "adb_transport_present": True,
            "device_count": 1,
            "proved": "Authorized USB ADB session exists.",
            "next_action": "Run Capture-HHCCReaderAdbInventory.cmd for read-only Android inventory.",
        }
    return {
        "adb_device_state": "ADB_NO_DEVICE",
        "adb_auth_state": "UNRESOLVED",
        "device_count": count,
        "next_action": "Rerun Probe-HHCCReaderAdb.cmd and capture adb devices -l output privately.",
    }


def _identity_state(evidence: dict[str, Any], device_ready: bool) -> dict[str, Any]:
    if not device_ready:
        return {
            "identity_state": "ADB_IDENTITY_UNRESOLVED",
            "reason": "device_not_ready",
        }
    ident = evidence.get("identity") if isinstance(evidence.get("identity"), dict) else {}
    mac_match = _bool(ident.get("mac_correlated"))
    vendor_match = _bool(ident.get("vendor_props_match"))
    expected = _bool(ident.get("expected_identity_available"))
    single = _bool(ident.get("single_usb_attachment"))
    if mac_match or vendor_match:
        return {
            "identity_state": "ADB_IDENTITY_BOUND",
            "bind_basis": "mac" if mac_match else "vendor_props",
            "single_usb_attachment_not_sufficient": True,
            "next_action": "Run Capture-HHCCReaderAdbInventory.cmd, then continue exact-target network ADB only with the device-derived IP.",
        }
    if expected and not mac_match and ident.get("observed_mac_ref"):
        return {
            "identity_state": "ADB_IDENTITY_UNRESOLVED",
            "reason": "expected_private_identity_did_not_correlate",
            "next_action": "Do not treat the ADB serial as the payment-terminal serial. Re-check private expected MAC against Android-reported MAC.",
        }
    if single and not expected:
        return {
            "identity_state": "ADB_IDENTITY_UNRESOLVED",
            "reason": "single_usb_attachment_is_local_context_only",
            "next_action": "Supply the existing private expected MAC (or vendor identity evidence) and rerun Probe-HHCCReaderAdb.cmd.",
        }
    return {
        "identity_state": "ADB_IDENTITY_UNRESOLVED",
        "reason": "insufficient_safe_correlation",
        "next_action": "Correlate ADB session to private Kiosk4 identity using expected MAC or vendor properties; do not copy live identifiers into Git.",
    }


def _inventory_state(evidence: dict[str, Any], device_ready: bool) -> dict[str, Any]:
    inv = evidence.get("inventory") if isinstance(evidence.get("inventory"), dict) else {}
    if not device_ready:
        return {
            "inventory_state": "NOT_EVALUATED",
            "firmware_evidence_state": "NOT_CAPTURED",
        }
    commands = inv.get("commands") if isinstance(inv.get("commands"), dict) else {}
    if not commands and not inv:
        return {
            "inventory_state": "NOT_EVALUATED",
            "next_action": "Run Capture-HHCCReaderAdbInventory.cmd.",
        }
    required = (
        "getprop",
        "pm_list_packages",
        "ps",
        "ip_addr",
        "ip_route",
        "dumpsys_connectivity",
        "dumpsys_device_policy",
    )
    ok_count = 0
    unsupported: list[str] = []
    failed: list[str] = []
    for name in required:
        row = commands.get(name) if isinstance(commands.get(name), dict) else {}
        if _bool(row.get("ok")):
            ok_count += 1
        elif _bool(row.get("unsupported")):
            unsupported.append(name)
        elif row:
            failed.append(name)
        else:
            failed.append(name)
    if ok_count == len(required):
        inv_state = "ADB_READONLY_INVENTORY_CAPTURED"
    elif ok_count or unsupported:
        inv_state = "ADB_READONLY_INVENTORY_PARTIAL"
    else:
        inv_state = "ADB_READONLY_INVENTORY_PARTIAL"
    props = {}
    getprop = commands.get("getprop") if isinstance(commands.get("getprop"), dict) else {}
    if isinstance(getprop.get("properties"), dict):
        props = getprop["properties"]
    elif isinstance(inv.get("properties"), dict):
        props = inv["properties"]
    labeled = adapt_getprop_to_labeled_observations(
        props,
        observed_at=_text(inv.get("observed_at")),
        device_model=_text(props.get("ro.product.model")),
    )
    domain = evaluate_version_domains(labeled) if labeled else {
        "campaign_target_domain_state": "VERSION_DOMAIN_UNRESOLVED",
        "primary_observation": None,
        "mutation_performed": False,
    }
    current_bind = None
    for row in labeled:
        if str(row.get("field_heading")) == "Installed Firmware":
            current_bind = classify_current_firmware_observation(row)
            break
    packages = classify_packages(_text((commands.get("pm_list_packages") or {}).get("stdout")) or _text(inv.get("packages_text")))
    owner = classify_device_owner(_text((commands.get("dumpsys_device_policy") or {}).get("stdout")) or _text(inv.get("device_policy_text")))
    android_release = _text(props.get("ro.build.version.release"))
    firmware_state = "CANDIDATES_CAPTURED_UNBOUND"
    if current_bind and current_bind.get("classification") == "CURRENT_FIRMWARE_BOUND":
        firmware_state = "AUTHORITATIVE_LABELED_CANDIDATE"
    elif not labeled:
        firmware_state = "NO_VERSION_PROPERTIES"
    return {
        "inventory_state": inv_state,
        "unsupported_commands": unsupported,
        "failed_commands": failed,
        "android_release_sanitized": bool(android_release),
        "android_release_key": "ro.build.version.release" if android_release else None,
        "build_evidence": "PROPERTIES_CAPTURED" if props else "ABSENT",
        "management_agent_state": packages.get("paxstore") or "UNKNOWN",
        "airviewer_state": packages.get("airviewer") or "UNKNOWN",
        "experian_or_payment_package_state": packages.get("experian") or "UNKNOWN",
        "maxstore_state": packages.get("maxstore") or "UNKNOWN",
        "device_owner_state": owner,
        "package_hints": packages,
        "firmware_evidence_state": firmware_state,
        "labeled_observations": labeled,
        "version_domain": domain.get("campaign_target_domain_state"),
        "primary_observation_bound": bool(domain.get("primary_observation")),
        "current_firmware_classification": (
            current_bind.get("classification") if current_bind else None
        ),
        "baseline_transition": (
            evaluate_baseline_transition_eligibility(
                current_bind,
                next((row for row in labeled if row.get("field_heading") == "Installed Firmware"), {}),
            ).get("baseline_transition")
            if current_bind
            else "REJECT"
        ),
        "campaign_target_not_substituted": True,
        "mutation_performed": False,
        "next_action": (
            "Run Classify-HHCCReaderVersionDomain.cmd on the sanitized labeled observations, then Evaluate-HHCCReaderFirmwareRoundtrip.cmd baseline when a current-firmware bind exists."
            if labeled
            else "Inventory captured no version properties; keep baseline BASELINE_INCOMPLETE."
        ),
    }


def _network_state(evidence: dict[str, Any], device_ready: bool, identity_bound: bool) -> dict[str, Any]:
    net = evidence.get("network_adb") if isinstance(evidence.get("network_adb"), dict) else {}
    if not net:
        return {
            "network_adb_state": "NOT_EVALUATED",
            "network_adb_revert_state": "NOT_EVALUATED",
        }
    if _bool(net.get("scanned")) or _bool(net.get("subnet_scan")):
        return {
            "network_adb_state": "POLICY_SAFETY_CONTROL",
            "network_adb_revert_state": "NOT_EVALUATED",
            "next_action": "Do not scan for port 5555. Derive the exact device IP from the authorized USB session, then rerun Certify-HHCCReaderAdbTcpip.cmd.",
        }
    if not device_ready or not identity_bound:
        return {
            "network_adb_state": "NOT_EVALUATED",
            "network_adb_revert_state": "NOT_EVALUATED",
            "next_action": "Prove USB ADB_DEVICE_READY and ADB_IDENTITY_BOUND before exact-target network ADB.",
        }
    if not _bool(net.get("device_ip_known")):
        return {
            "network_adb_state": "NETWORK_ADB_CERT_INCONCLUSIVE",
            "network_adb_revert_state": "NOT_EVALUATED",
            "next_action": "Derive the IPv4 from the same authorized device inventory (ip addr) or private same-device evidence, then rerun Certify-HHCCReaderAdbTcpip.cmd. Never scan.",
        }
    connect = str(net.get("connect_result") or "").strip().casefold()
    proof = _bool(net.get("readonly_proof_over_network"))
    revert_issued = _bool(net.get("usb_revert_issued"))
    listener_gone = net.get("network_listener_gone")
    already = _bool(net.get("already_listening"))
    if already and not _bool(net.get("tcpip_issued")):
        net_state = "NETWORK_ADB_ALREADY_AVAILABLE"
    elif connect in {"refused", "connection_refused"}:
        net_state = "NETWORK_ADB_NOT_LISTENING"
    elif connect in {"success", "connected"} and proof:
        net_state = "NETWORK_ADB_CERTIFIED"
    elif connect in {"success", "connected"} and not proof:
        net_state = "NETWORK_ADB_CERT_INCONCLUSIVE"
    else:
        net_state = "NETWORK_ADB_CERT_INCONCLUSIVE"
    if revert_issued and listener_gone is True:
        revert_state = "NETWORK_ADB_REVERTED"
    elif revert_issued and listener_gone is False:
        revert_state = "NETWORK_ADB_REVERT_FAILED"
    elif net_state == "NETWORK_ADB_CERTIFIED":
        revert_state = "NETWORK_ADB_REVERT_FAILED"
    else:
        revert_state = "NOT_EVALUATED" if not revert_issued else "NETWORK_ADB_REVERT_FAILED"
    nxt = "Exact-target network ADB is complete and USB mode was proved restored."
    if revert_state == "NETWORK_ADB_REVERT_FAILED":
        nxt = "NETWORK_ADB_REVERT_FAILED: run Certify-HHCCReaderAdbTcpip.cmd cleanup (adb usb / disconnect) on the same authorized device and prove the network listener is gone."
    elif net_state == "NETWORK_ADB_NOT_LISTENING":
        nxt = "Exact-IP connect was refused. Record NETWORK_ADB_NOT_LISTENING; do not scan. Continue independent inventory/remote-view work."
    elif net_state != "NETWORK_ADB_CERTIFIED":
        nxt = "Retry exact-IP adb connect only; never subnet-scan. Cleanup must still return adbd to USB."
    return {
        "network_adb_state": net_state,
        "network_adb_revert_state": revert_state,
        "ip_derived_not_printed": True,
        "next_action": nxt,
    }


def _remote_state(evidence: dict[str, Any], device_ready: bool) -> dict[str, Any]:
    remote = evidence.get("remote_view") if isinstance(evidence.get("remote_view"), dict) else {}
    if not remote:
        return {
            "remote_view_state": "NOT_EVALUATED",
            "remote_control_state": "not_tested",
        }
    if not device_ready:
        return {
            "remote_view_state": "REMOTE_VIEW_UNAVAILABLE",
            "remote_control_state": "not_tested",
            "next_action": "Establish authorized USB ADB first, then run Certify-HHCCReaderRemoteView.cmd.",
        }
    if not _bool(remote.get("tool_present")):
        return {
            "remote_view_state": "REMOTE_VIEW_UNAVAILABLE",
            "remote_control_state": "not_tested",
            "next_action": "No accepted scrcpy-equivalent tool is present on the Admin Box. Do not invent a second downloader; locate an existing authorized binary or stop at REMOTE_VIEW_UNAVAILABLE.",
        }
    if _bool(remote.get("control_injected")):
        return {
            "remote_view_state": "POLICY_SAFETY_CONTROL",
            "remote_control_state": "forbidden_input_not_tested",
            "next_action": "First live certification is view-only. Rerun Certify-HHCCReaderRemoteView.cmd without injecting input.",
        }
    if _bool(remote.get("interactive_gate")):
        return {
            "remote_view_state": "REMOTE_VIEW_INCONCLUSIVE",
            "remote_control_state": "not_tested",
            "attended_retry_required": True,
            "human_screen_gate": True,
            "next_action": "On Kiosk4, approve the view-only remote-display prompt if shown, then rerun Certify-HHCCReaderRemoteView.cmd.",
        }
    if _bool(remote.get("stream_proven")):
        return {
            "remote_view_state": "REMOTE_VIEW_PROVEN",
            "remote_control_state": "not_tested",
            "admin_box_remote_view_capable": True,
            "next_action": "View-only remote display is proved. Do not inject input. Full remote-control certification is a separate later capability.",
        }
    return {
        "remote_view_state": "REMOTE_VIEW_INCONCLUSIVE",
        "remote_control_state": "not_tested",
        "next_action": "Rerun Certify-HHCCReaderRemoteView.cmd in view-only mode.",
    }


def _pick_terminal(mode: str, parts: dict[str, Any]) -> str:
    if parts.get("mutation_blocked"):
        return "POLICY_SAFETY_CONTROL"
    host = parts["host"]["adb_host_state"]
    device = parts["device"]["adb_device_state"]
    usb = parts["usb"]["usb_enumeration_state"]
    ident = parts["identity"]["identity_state"]
    inv = parts["inventory"].get("inventory_state")
    net = parts["network"]["network_adb_state"]
    revert = parts["network"]["network_adb_revert_state"]
    remote = parts["remote"]["remote_view_state"]
    if mode == "prepare-host":
        return host
    if mode == "probe":
        if host != "ADB_HOST_READY":
            return host
        if device in {
            "ADB_DEVICE_UNAUTHORIZED",
            "ADB_DEVICE_OFFLINE",
            "ADB_DEVICE_READY",
            "ADB_MULTIPLE_DEVICES_BLOCKED",
        }:
            return device
        if device == "ADB_NO_DEVICE":
            if usb in {
                "USB_DEVICE_NOT_ENUMERATED",
                "USB_DEVICE_ENUMERATED_NO_ADB_INTERFACE",
                "USB_DRIVER_OR_INTERFACE_UNRESOLVED",
            }:
                return usb
            return device
        return device
    if mode == "inventory":
        if device != "ADB_DEVICE_READY":
            if host != "ADB_HOST_READY":
                return host
            if device == "ADB_NO_DEVICE" and usb in {
                "USB_DEVICE_NOT_ENUMERATED",
                "USB_DEVICE_ENUMERATED_NO_ADB_INTERFACE",
                "USB_DRIVER_OR_INTERFACE_UNRESOLVED",
            }:
                return usb
            return device
        return inv or "ADB_READONLY_INVENTORY_PARTIAL"
    if mode == "tcpip-cert":
        if revert == "NETWORK_ADB_REVERT_FAILED":
            return "NETWORK_ADB_REVERT_FAILED"
        if net and net != "NOT_EVALUATED":
            return net
        if host != "ADB_HOST_READY":
            return host
        if device != "ADB_DEVICE_READY":
            if device == "ADB_NO_DEVICE" and usb in {
                "USB_DEVICE_NOT_ENUMERATED",
                "USB_DEVICE_ENUMERATED_NO_ADB_INTERFACE",
                "USB_DRIVER_OR_INTERFACE_UNRESOLVED",
            }:
                return usb
            return device
        if ident != "ADB_IDENTITY_BOUND":
            return ident
        return net or "NETWORK_ADB_CERT_INCONCLUSIVE"
    if mode == "remote-view":
        if remote and remote != "NOT_EVALUATED":
            return remote
        return device if device != "ADB_DEVICE_READY" else "REMOTE_VIEW_UNAVAILABLE"
    # orchestrate / classify
    if host != "ADB_HOST_READY":
        return host
    if device != "ADB_DEVICE_READY":
        if device == "ADB_NO_DEVICE" and usb in {
            "USB_DEVICE_NOT_ENUMERATED",
            "USB_DEVICE_ENUMERATED_NO_ADB_INTERFACE",
            "USB_DRIVER_OR_INTERFACE_UNRESOLVED",
        }:
            return usb
        return device
    if ident != "ADB_IDENTITY_BOUND":
        return ident
    if inv in {"ADB_READONLY_INVENTORY_PARTIAL", "NOT_EVALUATED"}:
        return inv if inv != "NOT_EVALUATED" else device
    if revert == "NETWORK_ADB_REVERT_FAILED":
        return "NETWORK_ADB_REVERT_FAILED"
    if net in {"NETWORK_ADB_CERTIFIED", "NETWORK_ADB_ALREADY_AVAILABLE", "NETWORK_ADB_NOT_LISTENING", "NETWORK_ADB_CERT_INCONCLUSIVE"}:
        if remote in {"REMOTE_VIEW_PROVEN", "REMOTE_VIEW_INCONCLUSIVE", "REMOTE_VIEW_UNAVAILABLE"}:
            return remote if remote != "REMOTE_VIEW_UNAVAILABLE" or net != "NETWORK_ADB_CERTIFIED" else net
        return net
    if remote and remote != "NOT_EVALUATED":
        return remote
    return inv or device


def evaluate_control_plane(evidence: dict[str, Any]) -> dict[str, Any]:
    mode = _text(evidence.get("mode")) or "classify"
    if mode not in MODES:
        mode = "classify"
    forbidden = _mutation_attempt(evidence)
    host = _host_state(evidence.get("host") if isinstance(evidence.get("host"), dict) else {})
    host_ready = host["adb_host_state"] == "ADB_HOST_READY"
    usb = _usb_state(evidence.get("usb") if isinstance(evidence.get("usb"), dict) else {}, host_ready)
    device = _device_state(evidence, host_ready)
    ready = device.get("adb_device_state") == "ADB_DEVICE_READY"
    identity = _identity_state(evidence, ready)
    bound = identity.get("identity_state") == "ADB_IDENTITY_BOUND"
    inventory = _inventory_state(evidence, ready)
    network = _network_state(evidence, ready, bound)
    remote = _remote_state(evidence, ready)
    mutation_blocked = bool(forbidden)
    parts = {
        "host": host,
        "usb": usb,
        "device": device,
        "identity": identity,
        "inventory": inventory,
        "network": network,
        "remote": remote,
        "mutation_blocked": mutation_blocked,
    }
    terminal = _pick_terminal(mode, parts)
    screen = _text(evidence.get("screen_confirmation")) or "not_required"
    if terminal == "ADB_DEVICE_UNAUTHORIZED" and screen == "not_required":
        screen = "unobserved"
    if screen not in SCREEN_VALUES:
        screen = "unobserved"
    attended = bool(
        device.get("attended_retry_required")
        or remote.get("attended_retry_required")
        or terminal in {"ADB_DEVICE_UNAUTHORIZED", "REMOTE_VIEW_INCONCLUSIVE", "HUMAN_SCREEN_GATE"}
    )
    next_action = None
    for block in (device, usb, host, identity, inventory, network, remote):
        if block.get("next_action") and (
            terminal in str(block.values())
            or terminal == block.get("adb_device_state")
            or terminal == block.get("adb_host_state")
            or terminal == block.get("usb_enumeration_state")
            or terminal == block.get("identity_state")
            or terminal == block.get("inventory_state")
            or terminal == block.get("network_adb_state")
            or terminal == block.get("network_adb_revert_state")
            or terminal == block.get("remote_view_state")
        ):
            next_action = block.get("next_action")
            break
    if mutation_blocked:
        terminal = "POLICY_SAFETY_CONTROL"
        next_action = "Forbidden Android mutation command was refused. Continue with read-only ADB only."
    if not next_action:
        next_action = host.get("next_action")
    proved = device.get("proved") or host["adb_host_state"]
    artifact_kind = {
        "prepare-host": "adb-host-readiness",
        "probe": "adb-device-probe",
        "inventory": "adb-readonly-inventory",
        "tcpip-cert": "adb-network-live-cert",
        "remote-view": "adb-remote-view-live-cert",
    }.get(mode, "adb-device-probe")
    receipt = {
        "schema_version": SCHEMA,
        "artifact": artifact_kind,
        "mode": mode,
        "generated_at": _now(),
        "architecture": "ADMIN_BOX_CONTROL_PLANE",
        "evidence_category": {
            "host_tooling": "REPOSITORY_CAPABILITY" if host_ready else "REPOSITORY_CAPABILITY",
            "usb_and_adb_session": "CONTROL_TRANSPORT_CAPABILITY",
            "android_inventory": "DEVICE_CAPABILITY",
            "mutation_denial": "POLICY_SAFETY_CONTROL",
        },
        "state": terminal,
        "adb_host_state": host["adb_host_state"],
        "adb_path_recorded": host["adb_path_recorded"],
        "adb_version": host["adb_version"],
        "adb_precedence": host["precedence"],
        "usb_enumeration_state": usb["usb_enumeration_state"],
        "adb_device_state": device.get("adb_device_state"),
        "adb_auth_state": device.get("adb_auth_state"),
        "adb_transport_present": bool(device.get("adb_transport_present")),
        "screen_confirmation": screen,
        "attended_retry_required": attended,
        "human_screen_gate": bool(device.get("human_screen_gate") or remote.get("human_screen_gate")),
        "identity_state": identity.get("identity_state"),
        "inventory_state": inventory.get("inventory_state"),
        "android_release_recorded": inventory.get("android_release_sanitized"),
        "build_evidence": inventory.get("build_evidence"),
        "management_agent_state": inventory.get("management_agent_state"),
        "airviewer_state": inventory.get("airviewer_state"),
        "device_owner_state": inventory.get("device_owner_state"),
        "firmware_evidence_state": inventory.get("firmware_evidence_state"),
        "version_domain": inventory.get("version_domain"),
        "primary_observation_bound": inventory.get("primary_observation_bound"),
        "current_firmware_classification": inventory.get("current_firmware_classification"),
        "baseline_transition": inventory.get("baseline_transition"),
        "labeled_observations": inventory.get("labeled_observations") or [],
        "network_adb_state": network.get("network_adb_state"),
        "network_adb_revert_state": network.get("network_adb_revert_state"),
        "remote_view_state": remote.get("remote_view_state"),
        "remote_control_state": remote.get("remote_control_state"),
        "admin_box_remote_view_capable": bool(remote.get("admin_box_remote_view_capable")),
        "proved": proved,
        "next_action": next_action,
        "mutation_authorized": False,
        "mutation_performed": False,
        "forbidden_commands_refused": forbidden,
        "campaign_target_not_used_as_current": True,
        "live_identifiers_redacted": True,
    }
    return receipt


def format_technician_stdout(receipt: dict[str, Any], evidence_path: Path | None = None) -> str:
    lines = [
        f"STATE={receipt['state']}",
        f"PROVED={receipt.get('proved') or receipt['state']}",
        f"ADB_HOST_STATE={receipt['adb_host_state']}",
        f"USB_ENUMERATION_STATE={receipt['usb_enumeration_state']}",
        f"ADB_DEVICE_STATE={receipt['adb_device_state']}",
        f"ADB_AUTH_STATE={receipt['adb_auth_state']}",
        f"SCREEN_CONFIRMATION={receipt['screen_confirmation']}",
        f"IDENTITY_STATE={receipt['identity_state']}",
        f"INVENTORY_STATE={receipt.get('inventory_state')}",
        f"FIRMWARE_EVIDENCE_STATE={receipt.get('firmware_evidence_state')}",
        f"VERSION_DOMAIN={receipt.get('version_domain')}",
        f"NETWORK_ADB_STATE={receipt.get('network_adb_state')}",
        f"NETWORK_ADB_REVERT_STATE={receipt.get('network_adb_revert_state')}",
        f"REMOTE_VIEW_STATE={receipt.get('remote_view_state')}",
        f"REMOTE_CONTROL_STATE={receipt.get('remote_control_state')}",
        f"ATTENDED_RETRY_REQUIRED={str(receipt['attended_retry_required']).lower()}",
        f"MUTATION_AUTHORIZED=false",
        f"NEXT_ACTION={receipt['next_action']}",
    ]
    if evidence_path:
        lines.append(f"EVIDENCE={evidence_path}")
    return "\n".join(lines) + "\n"


def write_receipt(receipt: dict[str, Any], output: Path | None = None, output_dir: Path | None = None) -> Path:
    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        return output
    out_dir = output_dir if output_dir is not None else DEFAULT_RECEIPT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    path = out_dir / f"hh-cc-reader-{receipt.get('artifact', 'adb-device-probe')}-{stamp}-{secrets.token_hex(4)}.json"
    path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Classify Admin Box ADB control-plane evidence.")
    parser.add_argument("--input", default=None, help="Evidence JSON (fixture or private live capture).")
    parser.add_argument("--live", default=None, choices=sorted(MODES))
    parser.add_argument("--allow-install", action="store_true")
    parser.add_argument("--authorize-transport", action="store_true", help="Explicit authority for the exact-target transport transaction; never firmware authority.")
    parser.add_argument("--expected-mac", default=None)
    parser.add_argument(
        "--otg-confirmed",
        action="store_true",
        help="Operator confirms micro-USB/OTG client cable is already seated (attended physical fact).",
    )
    parser.add_argument("--output", default=None)
    parser.add_argument("--output-dir", default=None)
    args = parser.parse_args(argv)
    if args.live:
        from harness.api.hh_cc_reader_adb_live import collect_live_evidence

        evidence = collect_live_evidence(
            args.live,
            allow_install=args.allow_install,
            expected_mac=args.expected_mac,
            otg_confirmed=args.otg_confirmed,
            transport_authorized=args.authorize_transport,
        )
    elif args.input:
        source = Path(args.input)
        if not source.is_file():
            sys.stderr.write(f"ERROR: evidence file not found: {source}\n")
            return 2
        evidence = json.loads(source.read_text(encoding="utf-8-sig"))
        if not isinstance(evidence, dict):
            sys.stderr.write("ERROR: evidence JSON must be an object\n")
            return 2
        if args.otg_confirmed:
            usb = evidence.get("usb") if isinstance(evidence.get("usb"), dict) else {}
            usb = dict(usb)
            usb["operator_otg_client_path_confirmed"] = True
            evidence["usb"] = usb
    else:
        sys.stderr.write("ERROR: provide --input EVIDENCE.json or --live MODE\n")
        return 2
    receipt = evaluate_control_plane(evidence)
    out = Path(args.output) if args.output else None
    out_dir = Path(args.output_dir) if args.output_dir else None
    path = write_receipt(receipt, output=out, output_dir=out_dir)
    private = DEFAULT_RECEIPT_DIR / f"hh-cc-reader-adb-private-evidence-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.json"
    if args.live:
        DEFAULT_RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
        private.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        sys.stderr.write(f"PRIVATE_EVIDENCE={private}\n")
    labeled = receipt.get("labeled_observations") or []
    if labeled and args.live:
        capture_path = DEFAULT_RECEIPT_DIR / "hh-cc-reader-adb-labeled-observations.json"
        capture = {
            "schema": "sas-hh-cc-reader-kiosk4-version-evidence-capture/v1",
            "capture_state": "LABELED_OBSERVATIONS_PRESENT",
            "source_surface": "authorized_adb_readonly",
            "labeled_observations": labeled,
        }
        capture_path.write_text(json.dumps(capture, indent=2) + "\n", encoding="utf-8")
        classify_out = DEFAULT_RECEIPT_DIR / "hh-cc-reader-adb-version-domain.json"
        classify = subprocess.run(
            [sys.executable, str(ROOT / "harness/api/hh_cc_reader_version_domain.py"), "--input", str(capture_path), "--output", str(classify_out)],
            capture_output=True,
            text=True,
            check=False,
        )
        sys.stderr.write(f"VERSION_DOMAIN_CMD_EXIT={classify.returncode}\n")
        sys.stderr.write(f"VERSION_DOMAIN_CAPTURE={capture_path}\n")
        if classify.returncode == 0:
            sys.stderr.write(f"VERSION_DOMAIN_RECEIPT={classify_out}\n")
            if receipt.get("current_firmware_classification") == "CURRENT_FIRMWARE_BOUND":
                sys.stderr.write(
                    "BASELINE_NEXT=Evaluate-HHCCReaderFirmwareRoundtrip.cmd baseline using the existing private identity packet plus this labeled current_firmware_value. Do not invent identity fields.\n"
                )
    sys.stdout.write(format_technician_stdout(receipt, path))
    sys.stderr.write(f"RECEIPT={path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
