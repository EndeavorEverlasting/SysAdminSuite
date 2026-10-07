"""Live Admin Box collection for the H&H ADB control-plane classifier.

Host Platform-Tools install, USB/PnP, allowlisted Android debug client calls,
exact-IP network transaction, and view-only display tool detection. Firmware,
app, payment, and security mutation commands are refused.
"""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import time
import zipfile
from pathlib import Path
from typing import Any
from urllib.request import urlopen

from harness.api.hh_cc_reader_adb_control_plane import PLATFORM_TOOLS_SOURCE

OWNED_DIR = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "SysAdminSuite" / "tools" / "android-platform-tools"
ALLOWED_SHELL = (
    "getprop",
    "pm list packages",
    "ps",
    "ip addr",
    "ip route",
    "dumpsys connectivity",
    "dumpsys device_policy",
)
SDK_CANDIDATES = (
    OWNED_DIR / "adb.exe",
    Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk" / "platform-tools" / "adb.exe",
    Path(os.environ.get("ANDROID_HOME", "")) / "platform-tools" / "adb.exe" if os.environ.get("ANDROID_HOME") else None,
    Path(os.environ.get("ANDROID_SDK_ROOT", "")) / "platform-tools" / "adb.exe" if os.environ.get("ANDROID_SDK_ROOT") else None,
    Path(r"C:\Android\platform-tools\adb.exe"),
)


def _run(args: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)


def _which(name: str) -> Path | None:
    found = shutil.which(name)
    return Path(found) if found else None


def resolve_host() -> dict[str, Any]:
    path_adb = _which("adb")
    found: list[Path] = []
    for item in SDK_CANDIDATES:
        if item and item.is_file():
            found.append(item)
    owned = OWNED_DIR / "adb.exe"
    chosen: Path | None = None
    precedence = "none"
    if owned.is_file():
        chosen = owned
        precedence = "owned_preferred_path_also_present" if path_adb and path_adb.resolve() != owned.resolve() else "owned"
    elif found:
        chosen = found[0]
        precedence = "existing_sdk_or_cache"
    elif path_adb:
        chosen = path_adb
        precedence = "path"
    version = None
    if chosen:
        proc = _run([str(chosen), "version"])
        version = (proc.stdout or proc.stderr).strip() or None
    return {
        "chosen": chosen,
        "path_adb": path_adb,
        "owned": owned if owned.is_file() else None,
        "precedence": precedence,
        "version": version,
    }


def install_platform_tools() -> str | None:
    OWNED_DIR.parent.mkdir(parents=True, exist_ok=True)
    zip_path = OWNED_DIR.parent / "platform-tools-latest-windows.zip"
    with urlopen(PLATFORM_TOOLS_SOURCE, timeout=120) as response:  # noqa: S310 - official Google URL
        data = response.read()
    zip_path.write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()
    extract = OWNED_DIR.parent / "platform-tools-extract"
    if extract.exists():
        shutil.rmtree(extract)
    extract.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(extract)
    adb_files = list(extract.rglob("adb.exe"))
    if not adb_files:
        raise RuntimeError("Downloaded archive did not contain adb.exe")
    src = adb_files[0].parent
    if OWNED_DIR.exists():
        shutil.rmtree(OWNED_DIR)
    shutil.copytree(src, OWNED_DIR)
    return digest


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


def collect_devices(adb: Path) -> list[dict[str, Any]]:
    _run([str(adb), "start-server"], timeout=20)
    proc = _run([str(adb), "devices", "-l"], timeout=20)
    rows: list[dict[str, Any]] = []
    for line in (proc.stdout or "").splitlines():
        match = re.match(r"^(\S+)\s+(device|unauthorized|offline)\b", line.strip())
        if not match:
            continue
        serial = match.group(1)
        transport = "tcp" if re.search(r"\d+\.\d+\.\d+\.\d+:", serial) else "usb"
        rows.append({"serial_token": "SERIAL_PRESENT", "state": match.group(2), "transport": transport, "_serial": serial})
    return rows


def allowed_shell(adb: Path, command: str, serial: str | None) -> dict[str, Any]:
    if command not in ALLOWED_SHELL:
        raise RuntimeError(f"Refused non-allowlisted shell: {command}")
    args = [str(adb)]
    if serial:
        args.extend(["-s", serial])
    args.extend(["shell", command])
    proc = _run(args, timeout=40)
    text = (proc.stdout or "") + (proc.stderr or "")
    unsupported = bool(re.search(r"not found|Unknown command|inaccessible or not found", text, re.I))
    return {
        "ok": (not unsupported) and bool(text.strip() or proc.returncode == 0),
        "unsupported": unsupported,
        "stdout_present": bool(text.strip()),
        "stdout": text,
    }


def parse_getprop(text: str) -> dict[str, str]:
    props: dict[str, str] = {}
    for line in text.splitlines():
        match = re.match(r"^\[([^\]]+)\]: \[([^\]]*)\]$", line.strip())
        if match:
            props[match.group(1)] = match.group(2)
            continue
        match = re.match(r"^([\w.]+)=(.*)$", line.strip())
        if match:
            props[match.group(1)] = match.group(2)
    return props


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
) -> dict[str, Any]:
    host = resolve_host()
    archive_sha = None
    if host["chosen"] is None and allow_install:
        try:
            archive_sha = install_platform_tools()
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
            if ip and (identity["mac_correlated"] or identity["vendor_props_match"]):
                try:
                    _run([str(host["chosen"]), "tcpip", "5555"], timeout=20)
                    network["tcpip_issued"] = True
                    time.sleep(2)
                    connect = _run([str(host["chosen"]), "connect", f"{ip}:5555"], timeout=20)
                    text = (connect.stdout or "") + (connect.stderr or "")
                    if re.search(r"connected", text, re.I):
                        network["connect_result"] = "success"
                        proof = _run(
                            [str(host["chosen"]), "-s", f"{ip}:5555", "shell", "getprop", "ro.build.version.release"],
                            timeout=20,
                        )
                        network["readonly_proof_over_network"] = bool((proof.stdout or "").strip())
                    elif re.search(r"refused|failed|cannot", text, re.I):
                        network["connect_result"] = "refused"
                    else:
                        network["connect_result"] = "inconclusive"
                finally:
                    _run([str(host["chosen"]), "usb"], timeout=20)
                    network["usb_revert_issued"] = True
                    _run([str(host["chosen"]), "disconnect", f"{ip}:5555"], timeout=20)
                    time.sleep(1)
                    after = _run([str(host["chosen"]), "devices", "-l"], timeout=20)
                    network["network_listener_gone"] = f"{ip}:5555" not in (after.stdout or "")
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
                    [str(tool), "--no-control", "--no-audio", "--max-fps", "5"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                time.sleep(3)
                if proc.poll() is None:
                    remote["stream_proven"] = True
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
