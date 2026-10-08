"""Reusable AndroidProvider primitives. Workload policy stays above this seam.

Only a qualified local bundle executes. No PATH fallback or public-network
acquisition occurs during device operations. Private identifiers remain local.
"""
from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import time
import zipfile
from contextlib import contextmanager
from pathlib import Path, PureWindowsPath
from typing import Any

PLATFORM_TOOLS_SOURCE = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
OWNED_DIR = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "SysAdminSuite/tools/android-platform-tools"
HOST_LEASE_DIR = Path(os.environ.get("ProgramData", str(Path.home()))) / "SysAdminSuite/android-provider"
ROLES = frozenset({"ptop_lab", "adminbox_reference", "technician_adminbox_field"})
REQUIRED_COMPONENTS = frozenset({"adb.exe", "AdbWinApi.dll", "AdbWinUsbApi.dll", "source.properties"})
ALLOWED_SHELL = (
    "getprop", "pm list packages", "ps", "ip addr", "ip route",
    "dumpsys connectivity", "dumpsys device_policy",
)
MANIFEST = "sas-platform-tools.json"


def _run(args: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
    environment = dict(os.environ)
    for name in ("ADB_SERVER_SOCKET", "ANDROID_ADB_SERVER_PORT", "ADB_VENDOR_KEYS"):
        environment.pop(name, None)
    environment["ADB_MDNS_AUTO_CONNECT"] = ""
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False, env=environment)


def _which(name: str) -> Path | None:
    found = shutil.which(name)
    return Path(found) if found else None


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_bundle(directory: Path) -> dict[str, Any]:
    """Verify every manifested byte before invoking the executable."""
    result: dict[str, Any] = {"state": "MISSING_BUNDLE", "manifest": None}
    try:
        manifest = json.loads((directory / MANIFEST).read_text(encoding="utf-8"))
        components = manifest["component_manifest"]
        if (manifest.get("schema_version") != "sas-android-runtime/v1"
                or manifest.get("source") != PLATFORM_TOOLS_SOURCE
                or manifest.get("qualification_state") != "QUALIFIED"
                or not manifest.get("version") or not manifest.get("qualified_at")
                or not re.fullmatch(r"[a-f0-9]{64}", str(manifest.get("sha256", "")))
                or not isinstance(components, dict)
                or not REQUIRED_COMPONENTS.issubset(components)):
            return {"state": "INVALID_MANIFEST", "manifest": None}
        for relative, digest in components.items():
            candidate = directory / relative
            path = candidate.resolve()
            if (not path.is_relative_to(directory.resolve()) or candidate.is_symlink()
                    or any(p.is_symlink() for p in candidate.parents if p != directory.parent)
                    or Path(relative).name.casefold().startswith("adbkey")):
                return {"state": "INVALID_MANIFEST", "manifest": None}
            if not path.is_file():
                return {"state": "INCOMPLETE_BUNDLE", "manifest": None}
            if not re.fullmatch(r"[a-f0-9]{64}", str(digest)) or sha256(path) != digest:
                return {"state": "HASH_MISMATCH", "manifest": None}
        actual = {p.relative_to(directory).as_posix() for p in directory.rglob("*") if p.is_file() and p.name != MANIFEST}
        if actual != set(components):
            return {"state": "UNMANIFESTED_COMPONENT", "manifest": None}
        result = {"state": "READY", "manifest": manifest}
    except FileNotFoundError:
        pass
    except (OSError, ValueError, KeyError, TypeError):
        result["state"] = "INVALID_MANIFEST"
    return result


def prepare_bundle(archive: Path, expected_sha256: str, directory: Path | None = None) -> dict[str, Any]:
    """Explicit offline preparation from an operator-approved official ZIP hash.

    Hash authority is an input, not inferred from an arbitrary downloaded file.
    Existing qualified bytes are preserved if preparation fails.
    """
    from datetime import datetime, timezone

    directory = directory or OWNED_DIR
    if not re.fullmatch(r"[a-f0-9]{64}", expected_sha256) or sha256(archive) != expected_sha256:
        raise RuntimeError("ARCHIVE_HASH_MISMATCH")
    directory.parent.mkdir(parents=True, exist_ok=True)
    with provider_lease(HOST_LEASE_DIR), tempfile.TemporaryDirectory(dir=directory.parent) as temporary:
        if host_server_state(directory / "adb.exe") != "STOPPED":
            raise RuntimeError("STOP_OWNED_SERVER_BEFORE_RUNTIME_PREPARATION")
        staging = Path(temporary) / "bundle"
        staging.mkdir()
        with zipfile.ZipFile(archive) as zipped:
            names = set()
            for entry in zipped.infolist():
                name = entry.filename.replace("\\", "/")
                pieces = name.split("/")
                segments = pieces[:-1] if entry.is_dir() else pieces
                if (not name.startswith("platform-tools/") or any(p in {"", ".", ".."} or p.endswith((".", " ")) or PureWindowsPath(p).is_reserved() for p in segments) or ":" in name
                        or (entry.external_attr >> 16) & 0o170000 == 0o120000):
                    raise RuntimeError("UNSAFE_ARCHIVE_ENTRY")
                if entry.is_dir():
                    continue
                relative = name[len("platform-tools/"):]
                if not relative or relative.casefold() in names or Path(relative).name.casefold().startswith("adbkey") or Path(relative).name == MANIFEST:
                    raise RuntimeError("UNSAFE_ARCHIVE_ENTRY")
                names.add(relative.casefold())
                target = staging / relative
                if not target.resolve().is_relative_to(staging.resolve()):
                    raise RuntimeError("UNSAFE_ARCHIVE_ENTRY")
                target.parent.mkdir(parents=True, exist_ok=True)
                with zipped.open(entry) as source, target.open("wb") as destination:
                    shutil.copyfileobj(source, destination)
        if not all((staging / name).is_file() for name in REQUIRED_COMPONENTS):
            raise RuntimeError("INCOMPLETE_BUNDLE")
        properties = (staging / "source.properties").read_text(encoding="utf-8")
        match = re.search(r"^Pkg.Revision\s*=\s*(\S+)", properties, re.M)
        if not match:
            raise RuntimeError("VERSION_METADATA_REQUIRED")
        manifest = {"schema_version": "sas-android-runtime/v1", "source": PLATFORM_TOOLS_SOURCE,
                    "version": match.group(1), "sha256": expected_sha256,
                    "component_manifest": {p.relative_to(staging).as_posix(): sha256(p) for p in sorted(staging.rglob("*")) if p.is_file()},
                    "qualification_state": "QUALIFIED", "qualified_at": datetime.now(timezone.utc).isoformat()}
        (staging / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        if verify_bundle(staging)["state"] != "READY":
            raise RuntimeError("STAGED_BUNDLE_INVALID")
        backup = directory.with_name(directory.name + ".previous")
        if backup.exists():
            raise RuntimeError("PRIOR_RUNTIME_BACKUP_REQUIRES_REVIEW")
        existed = directory.exists()
        if existed:
            directory.rename(backup)
        try:
            shutil.copytree(staging, directory)
            if verify_bundle(directory)["state"] != "READY":
                raise RuntimeError("DESTINATION_BUNDLE_INVALID")
        except Exception:
            if directory.exists():
                shutil.rmtree(directory)
            if existed:
                backup.rename(directory)
            raise
        # Preserve the previous runtime for explicit rollback; no destructive cleanup.
        return manifest


def resolve_host(directory: Path | None = None) -> dict[str, Any]:
    directory = directory or OWNED_DIR
    qualification = verify_bundle(directory)
    path_adb = _which("adb")
    competitors = [path_adb] if path_adb else []
    for env in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(env):
            candidate = Path(os.environ[env]) / "platform-tools/adb.exe"
            if candidate.is_file() and candidate not in competitors:
                competitors.append(candidate)
    owned = directory / "adb.exe"
    chosen = owned if qualification["state"] == "READY" else None
    version = None
    if chosen:
        try:
            proc = _run([str(chosen), "version"])
            if proc.returncode != 0:
                qualification["state"] = "RUNTIME_EXECUTION_FAILED"
                chosen = None
            else:
                version = proc.stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            qualification["state"] = "RUNTIME_EXECUTION_FAILED"
            chosen = None
    return {
        "chosen": chosen, "path_adb": path_adb, "owned": owned if owned.is_file() else None,
        "precedence": "owned_preferred_path_also_present" if chosen and path_adb and path_adb.resolve() != owned.resolve() else "owned" if chosen else "none",
        "version": version, "qualification": qualification,
        "competing_runtime_count": sum(p.resolve() != owned.resolve() for p in competitors),
    }


def parse_devices(text: str) -> list[dict[str, Any]]:
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(("List of devices", "*")):
            continue
        parts = line.split()
        if len(parts) < 2:
            rows.append({"state": "unsupported", "transport": "unknown", "serial_token": "SERIAL_PRESENT", "_serial": parts[0]})
            continue
        serial, state = parts[:2]
        rows.append({"serial_token": "SERIAL_PRESENT", "state": state,
                     "transport": "tcp" if ":" in serial else "usb", "_serial": serial,
                     "_transport_id": next((p.split(":", 1)[1] for p in parts[2:] if p.startswith("transport_id:")), None)})
    return rows


def classify_devices(rows: list[dict[str, Any]], usb: dict[str, Any] | None = None) -> str:
    if not rows:
        return "ANDROID_USB_WITHOUT_ADB" if usb and usb.get("android_composite") else "NO_ANDROID_DEVICE"
    if len(rows) > 1:
        return "MULTIPLE_DEVICES"
    return {"device": "READY", "unauthorized": "ADB_UNAUTHORIZED", "offline": "ADB_OFFLINE"}.get(rows[0]["state"], "UNSUPPORTED_STATE")


def host_server_state(adb: Path) -> str:
    listeners = _run(["powershell.exe", "-NoLogo", "-NoProfile", "-Command",
                      "@(Get-NetTCPConnection -State Listen -LocalPort 5037 -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{address=$_.LocalAddress; executable=(Get-Process -Id $_.OwningProcess -ErrorAction Stop).Path} }) | ConvertTo-Json -Compress"], timeout=20)
    if listeners.returncode:
        return "UNKNOWN"
    if not listeners.stdout.strip():
        return "STOPPED"
    try:
        listeners_json = json.loads(listeners.stdout)
        listeners_json = listeners_json if isinstance(listeners_json, list) else [listeners_json]
        valid = bool(listeners_json) and all(row["address"] in {"127.0.0.1", "::1"} and Path(row["executable"]).resolve() == adb.resolve() for row in listeners_json)
    except (ValueError, KeyError, TypeError):
        valid = False
    return "OWNED_LOOPBACK" if valid else "UNTRUSTED_LISTENER"


def collect_devices(adb: Path, *, lease_held: bool = False) -> list[dict[str, Any]]:
    if not lease_held:
        with provider_lease(HOST_LEASE_DIR):
            return collect_devices(adb, lease_held=True)
    if host_server_state(adb) not in {"STOPPED", "OWNED_LOOPBACK"}:
        raise RuntimeError("LOOPBACK_SERVER_NOT_PROVEN")
    # Do not let start-server kill/replace a competing server before admission.
    start = _run([str(adb), "-L", "tcp:127.0.0.1:5037", "start-server"], timeout=20)
    if start.returncode:
        raise RuntimeError("HOST_SERVER_START_FAILED")
    if host_server_state(adb) != "OWNED_LOOPBACK":
        raise RuntimeError("LOOPBACK_SERVER_NOT_PROVEN")
    proc = _run([str(adb), "-H", "127.0.0.1", "-P", "5037", "devices", "-l"], timeout=20)
    if proc.returncode:
        raise RuntimeError("DEVICE_ENUMERATION_FAILED")
    return parse_devices(proc.stdout or "")


def allowed_shell(adb: Path, command: str, serial: str | None) -> dict[str, Any]:
    if command not in ALLOWED_SHELL or not serial:
        raise RuntimeError("EXACT_TARGET_AND_TYPED_OPERATION_REQUIRED")
    proc = _run([str(adb), "-H", "127.0.0.1", "-P", "5037", "-s", serial, "shell", command], timeout=40)
    text = (proc.stdout or "") + (proc.stderr or "")
    unsupported = bool(re.search(r"not found|Unknown command|inaccessible or not found", text, re.I))
    return {"ok": proc.returncode == 0 and not unsupported, "unsupported": unsupported,
            "stdout_present": bool(text.strip()), "stdout": text}


def parse_getprop(text: str) -> dict[str, str]:
    props = {}
    for line in text.splitlines():
        match = re.match(r"^\[([^\]]+)\]: \[([^\]]*)\]$", line.strip()) or re.match(r"^([\w.]+)=(.*)$", line.strip())
        if match:
            props[match.group(1)] = match.group(2)
    return props


def bind_identity(observations: list[dict[str, Any]], expected: dict[str, str]) -> dict[str, Any]:
    """Require private expected stable properties; model alone never binds identity."""
    if (not isinstance(expected, dict) or not expected
            or not all(isinstance(k, str) and isinstance(v, str) and v.strip() for k, v in expected.items())
            or not any(k in expected and expected[k].strip().casefold() not in {"unknown", "none", "null", "0"} for k in ("ro.serialno", "ro.boot.serialno"))):
        return {"state": "BLOCK", "reason": "EXPECTED_STABLE_IDENTITY_REQUIRED", "devices": []}
    groups: dict[str, list[dict[str, Any]]] = {}
    for item in observations:
        props = item.get("properties", {})
        if item.get("state") != "device" or not all(props.get(k) == v for k, v in expected.items()):
            return {"state": "BLOCK", "reason": "IDENTITY_MISMATCH_OR_UNREADY_ALIAS", "devices": []}
        identity = hashlib.sha256(json.dumps(expected, sort_keys=True).encode()).hexdigest()
        groups.setdefault(identity, []).append(item)
    if len(groups) != 1:
        return {"state": "BLOCK", "reason": "AMBIGUOUS_IDENTITY", "devices": []}
    identity, aliases = next(iter(groups.items()))
    if sum(x.get("transport") == "usb" for x in aliases) > 1:
        return {"state": "BLOCK", "reason": "DUPLICATE_USB_IDENTITY", "devices": []}
    return {"state": "IDENTITY_BOUND", "identity_ref": identity, "expected": dict(expected), "devices": aliases}


@contextmanager
def provider_lease(directory: Path):
    """Exclusive host lease; crash remnants fail closed for explicit recovery."""
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "android-provider.lock"
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise RuntimeError("PROVIDER_LEASE_BUSY") from exc
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump({"pid": os.getpid(), "created_at": time.time()}, stream)
        yield
    finally:
        path.unlink()


def certify_network(adb: Path, binding: dict[str, Any], ip: str, *, authorized: bool, lease_dir: Path) -> dict[str, Any]:
    """Exact target transaction. Revert, listener and USB proof are mandatory."""
    result: dict[str, Any] = {"result": "BLOCK", "cleanup": "NOT_REQUIRED", "authority": "AUTHORIZED" if authorized else "MUTATION_GATED",
                              "tcpip_issued": False, "connect_result": "not_attempted", "readonly_proof_over_network": False,
                              "usb_revert_issued": False, "network_listener_gone": None}
    if not authorized or binding.get("state") != "IDENTITY_BOUND":
        return result
    rebound = bind_identity(binding.get("devices", []), binding.get("expected", {}))
    if rebound["state"] != "IDENTITY_BOUND" or rebound["identity_ref"] != binding.get("identity_ref"):
        result["reason"] = "INVALID_IDENTITY_BINDING"
        return result
    address = ipaddress.ip_address(ip)
    if address.version != 4 or address.is_loopback or address.is_unspecified or address.is_multicast:
        return result
    aliases = binding["devices"]
    usb = [a for a in aliases if a.get("transport") == "usb" and a.get("state") == "device"]
    if len(usb) != 1 or usb[0].get("device_ip") != ip:
        return result
    serial = usb[0]["_serial"]
    endpoint = f"{ip}:5555"
    prefix = [str(adb), "-H", "127.0.0.1", "-P", "5037"]
    with provider_lease(lease_dir):
        if verify_bundle(adb.parent)["state"] != "READY":
            result["reason"] = "RUNTIME_REQUALIFICATION_REQUIRED"
            return result
        journal_path = lease_dir / "transport-transaction.json"
        if journal_path.is_file():
            previous = json.loads(journal_path.read_text(encoding="utf-8"))
            if previous.get("cleanup") != "PROVEN":
                result["reason"] = "PRIOR_TRANSPORT_RECOVERY_REQUIRED"
                return result
        current = collect_devices(adb, lease_held=True)
        usb_current = [r for r in current if r.get("transport") == "usb"]
        if len(usb_current) != 1 or usb_current[0]["_serial"] != serial or usb_current[0]["state"] != "device":
            return result
        properties = allowed_shell(adb, "getprop", serial)
        observed = parse_getprop(properties["stdout"])
        expected_properties = binding["expected"]
        if not properties["ok"] or not all(observed.get(k) == v for k, v in expected_properties.items()):
            return result
        network = allowed_shell(adb, "ip addr", serial)
        if not network["ok"] or ip not in re.findall(r"inet\s+(\d+\.\d+\.\d+\.\d+)", network["stdout"]):
            return result
        attempted = False
        tcp_identity_bound = False
        try:
            journal_path.write_text(json.dumps({"identity_ref": binding["identity_ref"], "cleanup": "PENDING", "result": "INCOMPLETE"}) + "\n", encoding="utf-8")
            attempted = True  # Even timeout/partial mutation requires cleanup.
            switch = _run(prefix + ["-s", serial, "tcpip", "5555"], timeout=20)
            result["tcpip_issued"] = switch.returncode == 0
            if switch.returncode:
                raise RuntimeError("TCP_TRANSITION_FAILED")
            connect = _run(prefix + ["connect", endpoint], timeout=20)
            connected = connect.returncode == 0 and bool(re.search(r"^(already )?connected to ", connect.stdout or "", re.M))
            result["connect_result"] = "success" if connected else "refused"
            if not connected:
                raise RuntimeError("CONNECT_FAILED")
            proof = allowed_shell(adb, "getprop", endpoint)
            observed = parse_getprop(proof["stdout"])
            expected = binding["expected"]
            same = all(observed.get(k) == v for k, v in expected.items())
            tcp_identity_bound = proof["ok"] and same
            result["readonly_proof_over_network"] = proof["ok"] and same
            result["result"] = "SUCCESS" if result["readonly_proof_over_network"] else "BLOCK"
        except (RuntimeError, OSError, subprocess.TimeoutExpired):
            result["result"] = "BLOCK"
        finally:
            if attempted:
                result["cleanup"] = "FAILED"
                try:
                    # TCP alias may survive when the original USB alias disappears.
                    # Never mutate a TCP endpoint until its identity was bound.
                    reverted = _run(prefix + ["-s", endpoint if tcp_identity_bound else serial, "usb"], timeout=20)
                    if reverted.returncode and tcp_identity_bound:
                        reverted = _run(prefix + ["-s", serial, "usb"], timeout=20)
                    result["usb_revert_issued"] = reverted.returncode == 0
                    disconnected = _run(prefix + ["disconnect", endpoint], timeout=20)
                    usb_ready = False
                    listener_closed = False
                    alias_gone = False
                    for _ in range(3):
                        after = _run(prefix + ["devices", "-l"], timeout=20)
                        rows = parse_devices(after.stdout or "")
                        usb_ready = after.returncode == 0 and any(r["_serial"] == serial and r["state"] == "device" for r in rows)
                        alias_gone = after.returncode == 0 and not any(r["_serial"] == endpoint for r in rows)
                        try:
                            with socket.create_connection((ip, 5555), timeout=2):
                                listener_closed = False
                        except ConnectionRefusedError:
                            listener_closed = True
                        except OSError:
                            listener_closed = False  # Unreachable is not proof of closed.
                        if usb_ready and alias_gone and listener_closed:
                            break
                        time.sleep(1)
                    result["network_listener_gone"] = listener_closed and alias_gone
                    usb_identity = allowed_shell(adb, "getprop", serial) if usb_ready else {"ok": False, "stdout": ""}
                    restored = parse_getprop(usb_identity["stdout"])
                    usb_identity_matches = usb_identity["ok"] and all(restored.get(k) == v for k, v in binding["expected"].items())
                    if result["usb_revert_issued"] and disconnected.returncode == 0 and usb_ready and usb_identity_matches and result["network_listener_gone"]:
                        result["cleanup"] = "PROVEN"
                except (OSError, subprocess.TimeoutExpired):
                    pass
                if result["cleanup"] != "PROVEN":
                    result["result"] = "INCOMPLETE"
                try:
                    journal_path.write_text(json.dumps({**result, "identity_ref": binding["identity_ref"]}) + "\n", encoding="utf-8")
                except OSError:
                    result["result"] = "INCOMPLETE"
                    result["reason"] = "CLEANUP_RECEIPT_WRITE_FAILED"
    return result


def collect_usb() -> dict[str, Any]:
    """Generic PnP presence; workload/vendor interpretation is deliberately absent."""
    proc = _run(["powershell.exe", "-NoLogo", "-NoProfile", "-Command",
                 "Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $_.FriendlyName + '|' + $_.Status }"], timeout=30)
    text = proc.stdout or ""
    return {"android_composite": bool(re.search(r"android|adb interface|paydroid", text, re.I)),
            "adb_interface": bool(re.search(r"adb interface|android adb", text, re.I)),
            "enumeration_proven": proc.returncode == 0}


class AndroidProvider:
    """One role-configured provider for all supported Windows management nodes."""

    def __init__(self, role: str, directory: Path | None = None):
        if role not in ROLES:
            raise ValueError("UNSUPPORTED_NODE_ROLE")
        self.role = role
        self.directory = directory or OWNED_DIR

    def status(self) -> dict[str, Any]:
        host = resolve_host(self.directory)
        manifest = host["qualification"].get("manifest") or {}
        return {"node_role": self.role, "state": host["qualification"]["state"],
                "runtime": "SAS_OWNED_PLATFORM_TOOLS" if host["chosen"] else None,
                "runtime_version": manifest.get("version"), "client_version": host["version"],
                "runtime_sha256": manifest.get("sha256"), "source": manifest.get("source"),
                "competing_runtime_count": host["competing_runtime_count"],
                "offline_ready": bool(host["chosen"]), "authority": "READ_ONLY_ALLOWED",
                "proof": "REPOSITORY_VALIDATED", "cleanup": "NOT_REQUIRED"}

    def server(self, stop: bool = False) -> dict[str, Any]:
        receipt = self.status()
        receipt.update({"result": "BLOCK", "operation": "stop-server" if stop else "doctor",
                        "next_action": "Resolve runtime readiness before server inspection."})
        if receipt["state"] != "READY":
            return receipt
        adb = self.directory / "adb.exe"
        with provider_lease(HOST_LEASE_DIR):
            state = host_server_state(adb)
            receipt["server_state"] = state
            receipt["server_version"] = None
            receipt["server_version_basis"] = "UNPROVEN"
            if state == "OWNED_LOOPBACK":
                receipt["server_version"] = receipt["client_version"]
                receipt["server_version_basis"] = "OWNING_EXECUTABLE_EQUALS_QUALIFIED_CLIENT"
                diagnostic = _run([str(adb), "-H", "127.0.0.1", "-P", "5037", "server-status"], timeout=20)
                receipt["server_diagnostics"] = diagnostic.stdout if diagnostic.returncode == 0 else None
                if stop:
                    stopped = _run([str(adb), "-H", "127.0.0.1", "-P", "5037", "kill-server"], timeout=20)
                    state = host_server_state(adb)
                    receipt["server_state"] = state
                    receipt["result"] = "SUCCESS" if stopped.returncode == 0 and state == "STOPPED" else "INCOMPLETE"
                else:
                    receipt["result"] = "SUCCESS"
            elif state == "STOPPED":
                receipt["result"] = "SUCCESS"
            receipt["next_action"] = "Inspect the host server receipt; untrusted listeners require attended ownership resolution."
        return receipt

    def inspect(self, operation: str, expected: dict[str, str] | None = None, *, authorized: bool = False) -> dict[str, Any]:
        if operation not in {"probe", "inventory", "tcpip-cert"}:
            raise ValueError("UNSUPPORTED_TYPED_OPERATION")
        receipt = self.status()
        receipt["lifecycle"] = ["RUNTIME_QUALIFIED"] if receipt["state"] == "READY" else []
        receipt.update({"operation": operation, "result": "BLOCK", "next_action": "Prepare a qualified local Platform-Tools bundle."})
        if receipt["state"] != "READY":
            return receipt
        host = resolve_host(self.directory)
        adb = host["chosen"]
        with provider_lease(HOST_LEASE_DIR):
            usb = collect_usb()
            rows = collect_devices(adb, lease_held=True)
            receipt["lifecycle"].extend(["HOST_SERVER_READY", "TARGET_ENUMERATED"])
            receipt["state"] = classify_devices(rows, usb)
            receipt["transport_aliases"] = [{"state": r["state"], "transport": r["transport"]} for r in rows]
            receipt["next_action"] = "Resolve USB/ADB readiness and approved private expected identity."
            if operation == "probe":
                receipt["result"] = "SUCCESS" if receipt["state"] == "READY" else "BLOCK"
                return receipt
            observations = []
            for row in rows:
                if row["state"] == "device":
                    props_result = allowed_shell(adb, "getprop", row["_serial"])
                    if not props_result["ok"]:
                        receipt["state"] = "IDENTITY_READ_FAILED"
                        return receipt
                    observations.append({**row, "properties": parse_getprop(props_result["stdout"])})
                else:
                    observations.append(row)
            binding = bind_identity(observations, expected or {})
            receipt["state"] = binding["state"]
            if binding["state"] != "IDENTITY_BOUND":
                receipt["reason"] = binding["reason"]
                return receipt
            receipt["logical_identity_ref"] = binding["identity_ref"]
            receipt["lifecycle"].extend(["IDENTITY_BOUND", "SESSION_READY"])
            selected = next((x for x in binding["devices"] if x["transport"] == "usb"), binding["devices"][0])
            inventory = {command: allowed_shell(adb, command, selected["_serial"]) for command in ALLOWED_SHELL}
            # Raw output goes only into the private ignored receipt, never stdout/Git.
            receipt["inventory"] = inventory
            receipt["lifecycle"].append("OPERATION_EXECUTED")
            receipt["result"] = "SUCCESS" if all(x["ok"] for x in inventory.values()) else "INCOMPLETE"
            receipt["next_action"] = "Inspect the private inventory receipt."
            if operation != "tcpip-cert":
                receipt["lifecycle"].extend(["CLEANUP_PROVEN", "LEASE_RELEASED"])
                return receipt
            ips = set(re.findall(r"inet\s+(\d+\.\d+\.\d+\.\d+)", inventory["ip addr"]["stdout"])) - {"127.0.0.1"}
            if len(ips) != 1 or selected["transport"] != "usb":
                receipt.update({"result": "BLOCK", "reason": "EXACT_DEVICE_IP_AMBIGUOUS"})
                return receipt
            selected["device_ip"] = next(iter(ips))
        # certify_network acquires its own lease. Revalidate identity inside its
        # lease before transitioning so this handoff cannot create a race.
        transaction = certify_network(adb, binding, selected["device_ip"], authorized=authorized, lease_dir=HOST_LEASE_DIR)
        receipt.update(transaction)
        if transaction["cleanup"] == "PROVEN":
            receipt["lifecycle"].append("CLEANUP_PROVEN")
        receipt["lifecycle"].append("LEASE_RELEASED")
        receipt["next_action"] = "Inspect transport cleanup evidence; unresolved cleanup requires attended recovery."
        return receipt
