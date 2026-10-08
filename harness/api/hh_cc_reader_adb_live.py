"""Live Admin Box collection for the H&H ADB control-plane classifier.

Host Platform-Tools install, USB/PnP, allowlisted Android debug client calls,
exact-IP network transaction, and view-only display tool detection. Firmware,
app, payment, and security mutation commands are refused.
"""
from __future__ import annotations

import os
import re
import subprocess
import time
from pathlib import Path
from typing import Any

from harness.api.android_provider import (PLATFORM_TOOLS_SOURCE, OWNED_DIR, HOST_LEASE_DIR, _run, _which, resolve_host, collect_devices, allowed_shell, parse_getprop, bind_identity, certify_network)

def collect_usb() -> dict[str, Any]:
    ps = (
        "Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | "
        "ForEach-Object { $_.FriendlyName + '|' + $_.Status + '|' + $_.Class }"
    )
    proc = _run(["powershell.exe", "-NoLogo", "-NoProfile", "-Command", ps], timeout=60)
    lines = [line for line in (proc.stdout or "").splitlines() if line.strip()]
    android = False
    adb_iface = False
    pax = False
    driver = False
    android_like = 0
    for line in lines:
        name, _, rest = line.partition("|")
        status, _, cls = rest.partition("|")
        name_l = name.casefold()
        # Do not scan InstanceId: hex tokens like A80 create false PAX/Android hits.
        if re.search(r"\bandroid\b|\badb interface\b|\bpaydroid\b|android composite", name_l):
            android = True
            android_like += 1
        if re.search(r"\badb interface\b|\bandroid adb\b|\bwinusb.*adb\b", name_l):
            adb_iface = True
            android = True
        if re.search(r"\bpax\b|\ba80\b|\bpaydroid\b", name_l):
            pax = True
            android = True
            android_like += 1
        if android and re.search(r"unknown|failed|error", (status + " " + cls).casefold()):
            driver = True
    return {
        "enumerated": bool(lines),
        "android_composite": android,
        "adb_interface": adb_iface,
        "pax_or_a80_hint": pax,
        "driver_problem": driver,
        "android_like_name_count": android_like,
        "instance_count": len(lines),
    }


def first_ipv4(text: str) -> str | None:
    for match in re.finditer(r"inet\s+(\d+\.\d+\.\d+\.\d+)", text):
        if match.group(1) != "127.0.0.1":
            return match.group(1)
    return None


def mac_in_text(text: str, expected: str | None) -> bool:
    if not expected:
        return False
    compact_expected = re.sub(r"[^A-Fa-f0-9]", "", expected).upper()
    compact_text = re.sub(r"[^A-Fa-f0-9]", "", text).upper()
    return bool(compact_expected) and compact_expected in compact_text


def collect_live_evidence(
    mode: str,
    *,
    allow_install: bool = False,
    expected_mac: str | None = None,
    otg_confirmed: bool = False,
    transport_authorized: bool = False,
    profile_authority: dict[str, Any] | None = None,
) -> dict[str, Any]:
    host = resolve_host()
    archive_sha = None
    if host["chosen"] is None and allow_install:
        try:
            raise RuntimeError("Use qualified local-bundle preparation; install_platform_tools acquisition is disabled")
            host = resolve_host()
        except Exception as exc:  # noqa: BLE001
            host["install_error"] = str(exc)
    usb = collect_usb()
    if otg_confirmed:
        usb["operator_otg_client_path_confirmed"] = True
    devices: list[dict[str, Any]] = []
    if host["chosen"]:
        devices = collect_devices(host["chosen"])
    usb_rows = [row for row in devices if row.get("transport") != "tcp"]
    ready = len(usb_rows) == 1 and usb_rows[0].get("state") == "device"
    serial = usb_rows[0].get("_serial") if ready else None
    identity = {
        "expected_identity_available": bool(expected_mac),
        "mac_correlated": False,
        "vendor_props_match": False,
        "single_usb_attachment": len(usb_rows) == 1,
    }
    inventory = None
    network = None
    remote = None
    if mode in {"inventory", "orchestrate", "tcpip-cert", "remote-view", "classify"} and ready and host["chosen"]:
        getprop = allowed_shell(host["chosen"], "getprop", serial)
        props = parse_getprop(str(getprop.get("stdout") or ""))
        packages = allowed_shell(host["chosen"], "pm list packages", serial)
        ps_out = allowed_shell(host["chosen"], "ps", serial)
        ip_addr = allowed_shell(host["chosen"], "ip addr", serial)
        ip_route = allowed_shell(host["chosen"], "ip route", serial)
        conn = allowed_shell(host["chosen"], "dumpsys connectivity", serial)
        policy = allowed_shell(host["chosen"], "dumpsys device_policy", serial)
        identity["mac_correlated"] = mac_in_text(str(ip_addr.get("stdout") or ""), expected_mac)
        model = props.get("ro.product.model") or ""
        identity["vendor_props_match"] = bool(re.search(r"A80|PAX", model, re.I))
        inventory = {
            "observed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "commands": {
                "getprop": {**getprop, "properties": props},
                "pm_list_packages": packages,
                "ps": ps_out,
                "ip_addr": ip_addr,
                "ip_route": ip_route,
                "dumpsys_connectivity": conn,
                "dumpsys_device_policy": policy,
            },
        }
        if mode in {"tcpip-cert", "orchestrate", "classify"}:
            ip = first_ipv4(str(ip_addr.get("stdout") or ""))
            network = {
                "device_ip_known": bool(ip),
                "scanned": False,
                "tcpip_issued": False,
                "connect_result": "not_attempted",
                "readonly_proof_over_network": False,
                "usb_revert_issued": False,
                "network_listener_gone": None,
                "already_listening": False,
            }
            # H&H interpretation remains here; transport mechanics belong to the provider.
            # Vendor/model alone cannot authorize a stateful transport transition.
            stable = props.get("ro.serialno") or props.get("ro.boot.serialno")
            if ip and expected_mac and identity["mac_correlated"] and stable:
                observation = {**usb_rows[0], "properties": props, "device_ip": ip}
                key = "ro.serialno" if props.get("ro.serialno") else "ro.boot.serialno"
                binding = bind_identity([observation], {key: stable})
                transaction = certify_network(host["chosen"], binding, ip,
                    authorized=transport_authorized, lease_dir=HOST_LEASE_DIR, profile_authority=profile_authority)
                network.update(transaction)
    if mode in {"remote-view", "orchestrate", "classify"}:
        local_scrcpy = Path(os.environ.get("LOCALAPPDATA", "")) / "SysAdminSuite" / "tools" / "scrcpy" / "scrcpy.exe"
        tool = local_scrcpy if local_scrcpy.is_file() else _which("scrcpy")
        remote = {
            "tool": "scrcpy" if tool else None,
            "tool_present": bool(tool),
            "no_control": True,
            "stream_proven": False,
            "interactive_gate": False,
            "control_injected": False,
        }
        if tool and ready:
            try:
                proc = subprocess.Popen(
                    [str(tool), "--no-control", "--no-audio", "--max-fps", "5", "--serial", serial],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                time.sleep(3)
                if proc.poll() is None:
                    remote["stream_proven"] = False  # Process survival is not frame evidence.
                    proc.terminate()
                else:
                    remote["interactive_gate"] = True
            except OSError:
                remote["interactive_gate"] = True
    classify_mode = "classify" if mode == "orchestrate" else mode
    evidence: dict[str, Any] = {
        "mode": classify_mode,
        "screen_confirmation": "unobserved",
        "host": {
            "adb_present": bool(host["chosen"]),
            "adb_path": "OWNED_OR_LOCAL_PATH" if host["chosen"] else None,
            "adb_version": host.get("version"),
            "path_adb_path": "PATH_ADB_PRESENT" if host.get("path_adb") else None,
            "owned_adb_path": "OWNED_CACHE_PRESENT" if host.get("owned") else None,
            "precedence": host.get("precedence"),
            "source": PLATFORM_TOOLS_SOURCE,
            "install": {
                "archive_sha256": archive_sha,
                "cache_location": "LOCALAPPDATA/SysAdminSuite/tools/android-platform-tools",
            },
        },
        "usb": usb,
        "adb_devices": [{"serial_token": row["serial_token"], "state": row["state"], "transport": row["transport"]} for row in devices],
        "identity": identity,
    }
    if inventory:
        evidence["inventory"] = inventory
    if network:
        evidence["network_adb"] = network
    if remote:
        evidence["remote_view"] = remote
    return evidence
