#!/usr/bin/env python3
"""
SysAdmin Suite — Network Probe Relay
=====================================
A lightweight local WebSocket server that bridges the dashboard browser UI to
real network probes (DNS, ping/ICMP, TCP port checks, SNMP).

Usage
-----
  python3 dashboard/relay.py [--port 7823] [--host 127.0.0.1]

On startup a one-time secret token is printed to the terminal.
Paste it into the dashboard Network panel → relay token field to authenticate.
Only connections that present the correct token are accepted, preventing
malicious web pages from driving probes through this relay.

Dependencies
------------
  Required (stdlib only):
    asyncio, socket, subprocess, json, argparse, logging, secrets

  Optional (graceful degradation if missing):
    websockets >= 10    — pip install websockets
    pysnmp >= 4         — pip install pysnmp   (SNMP v1/v2c queries)

Protocol
--------
  WebSocket URL: ws://localhost:PORT/?token=SECRET

  Client  → Server  (JSON):
    { "type": "probe",
      "probeId":        "abc123",            # optional; relay generates one if absent
      "targets":        ["192.168.1.1", "printer.local"],
      "ports":          [135, 139, 445, 515, 631, 3389, 9100],
      "snmp_community": "public",
      "timeout":        2 }

    { "type": "probe_cancel", "probeId": "abc123" }   # stop the running probe

  Cancellation
  ------------
  A probe runs as a background task while the connection keeps reading messages,
  so a "probe_cancel" can interrupt it. The relay checks the cancel flag before
  each target and before each major step (DNS, ping, TCP batch, SNMP), so in-flight
  network activity stops promptly and remaining targets are never probed. Partial
  results already streamed to the client are preserved. This is scope control, not
  log evasion — normal OS/network telemetry is unaffected.

  Server  → Client  (JSON, streaming, one message per event):
    { "type": "probe_start",  "probeId": "...", "total": N }
    { "type": "step_result",  "probeId": "...", "target": "...", "step": "dns",
      "status": "ok|failed|skipped", "value": "..." }
    { "type": "step_result",  "probeId": "...", "target": "...", "step": "ping",
      "status": "ok|failed",  "value": "Reachable|NoPing" }
    { "type": "step_result",  "probeId": "...", "target": "...", "step": "tcp_PORT",
      "status": "ok|failed",  "value": "open|closed|filtered" }
    { "type": "step_result",  "probeId": "...", "target": "...", "step": "snmp",
      "status": "ok|failed|skipped", "value": "..." }
    { "type": "probe_done",   "probeId": "...", "total": N, "completed": M,
      "cancelled": true|false }
    { "type": "error",        "message": "..." }
"""

import argparse
import asyncio
import json
import logging
import platform
import secrets
import socket
import subprocess
import sys
from urllib.parse import urlparse, parse_qs

logging.basicConfig(
    level=logging.INFO,
    format="[relay] %(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("relay")

DEFAULT_PORT = 7823
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORTS = [135, 139, 445, 3389, 515, 631, 9100]
DEFAULT_SNMP_COMMUNITY = "public"
DEFAULT_TIMEOUT = 2

# Allowed browser origins — only localhost and file:// origins may connect.
_ALLOWED_ORIGINS = {
    "null",          # file:// pages send Origin: null
    "localhost",
    "127.0.0.1",
    "::1",
}

# ── Optional dependency detection ────────────────────────────────────────────

try:
    import websockets
    _HAS_WEBSOCKETS = True
except ImportError:
    _HAS_WEBSOCKETS = False

# SNMP dependency note
# ─────────────────────────────────────────────────────────────────────────────
# The relay uses the SYNCHRONOUS pysnmp.hlapi API (classic pysnmp 4.x style).
# pysnmp.hlapi.getCmd() is a generator; next() on it does one blocking SNMP
# GET — the correct usage inside a thread executor.
#
# Tested with:  pip install "pysnmp>=4.4,<5"  (pysnmp-4.4.x on PyPI)
# The newer pysnmp-lextudio (5.x, distributed as "pysnmp" on PyPI ≥5.0) uses
# a different async API and may break this import.  If SNMP shows as disabled,
# pin the version:  pip install "pysnmp>=4.4,<5"
# ─────────────────────────────────────────────────────────────────────────────
try:
    from pysnmp.hlapi import (  # noqa: E402
        SnmpEngine,
        CommunityData,
        UdpTransportTarget,
        ContextData,
        ObjectType,
        ObjectIdentity,
        getCmd,
    )
    _HAS_PYSNMP = True
except ImportError:
    _HAS_PYSNMP = False


# ── Security helpers ──────────────────────────────────────────────────────────

def _check_origin(headers) -> bool:
    """Return True if the request Origin is an allowed local origin."""
    origin = ""
    try:
        origin = headers.get("Origin", "").lower().strip()
    except Exception:
        return True  # headers object may not support .get in all websockets versions

    if not origin or origin == "null":
        return True  # file:// pages or same-origin

    try:
        parsed = urlparse(origin)
        host = parsed.hostname or ""
    except Exception:
        return False

    return host in _ALLOWED_ORIGINS


def _check_token(path: str, expected: str) -> bool:
    """Return True if the URL query param ?token= matches the expected secret."""
    try:
        qs = parse_qs(urlparse(path).query)
        provided = qs.get("token", [None])[0]
        if provided is None:
            return False
        return secrets.compare_digest(provided, expected)
    except Exception:
        return False


# ── Probe helpers ─────────────────────────────────────────────────────────────

async def probe_dns(target: str, timeout: int) -> dict:
    """Resolve target hostname to an IPv4 address using stdlib socket."""
    loop = asyncio.get_event_loop()
    try:
        infos = await asyncio.wait_for(
            loop.run_in_executor(
                None,
                lambda: socket.getaddrinfo(target, None, socket.AF_INET),
            ),
            timeout=timeout,
        )
        ip = infos[0][4][0] if infos else None
        if ip:
            return {"status": "ok", "value": ip}
        return {"status": "failed", "value": "no A record"}
    except asyncio.TimeoutError:
        return {"status": "failed", "value": "timeout"}
    except socket.gaierror as exc:
        return {"status": "failed", "value": str(exc)}


async def probe_ping(target: str, timeout: int) -> dict:
    """Send one ICMP echo request using the system ping binary."""
    system = platform.system().lower()
    if system == "windows":
        cmd = ["ping", "-n", "1", "-w", str(timeout * 1000), target]
    else:
        cmd = ["ping", "-c", "1", "-W", str(timeout), target]

    loop = asyncio.get_event_loop()
    try:
        result = await asyncio.wait_for(
            loop.run_in_executor(
                None,
                lambda: subprocess.run(
                    cmd,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                ),
            ),
            timeout=timeout + 2,
        )
        if result.returncode == 0:
            return {"status": "ok", "value": "Reachable"}
        return {"status": "failed", "value": "NoPing"}
    except asyncio.TimeoutError:
        return {"status": "failed", "value": "timeout"}
    except Exception as exc:
        return {"status": "failed", "value": str(exc)}


async def probe_tcp(target: str, port: int, timeout: int) -> dict:
    """Attempt a TCP connection to target:port."""
    try:
        _, writer = await asyncio.wait_for(
            asyncio.open_connection(target, port),
            timeout=timeout,
        )
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        return {"status": "ok", "value": "open"}
    except asyncio.TimeoutError:
        return {"status": "failed", "value": "filtered"}
    except (ConnectionRefusedError, OSError):
        return {"status": "failed", "value": "closed"}


async def probe_snmp(target: str, community: str, timeout: int) -> dict:
    """
    Query SNMP sysDescr OID (1.3.6.1.2.1.1.1.0) using the synchronous
    pysnmp.hlapi API run inside a thread executor.

    pysnmp.hlapi.getCmd() is a generator.  Calling next() on it executes
    one blocking SNMP GET request (correct usage for thread-based concurrency).
    """
    if not _HAS_PYSNMP:
        return {"status": "skipped", "value": "pysnmp not installed — pip install pysnmp"}

    loop = asyncio.get_event_loop()

    def _snmp_sync():
        # getCmd is a synchronous generator from pysnmp.hlapi (not asyncio).
        # next() blocks until the SNMP reply arrives or the timeout fires.
        error_indication, error_status, error_index, var_binds = next(
            getCmd(
                SnmpEngine(),
                CommunityData(community, mpModel=1),          # v2c
                UdpTransportTarget(
                    (target, 161),
                    timeout=float(timeout),
                    retries=0,
                ),
                ContextData(),
                ObjectType(ObjectIdentity("1.3.6.1.2.1.1.1.0")),  # sysDescr
            )
        )
        if error_indication:
            return {"status": "failed", "value": str(error_indication)}
        if error_status:
            return {"status": "failed", "value": f"{error_status} at {var_binds[int(error_index) - 1] if error_index else '?'}"}
        for _oid, val in var_binds:
            return {"status": "ok", "value": str(val)[:200]}
        return {"status": "failed", "value": "empty response"}

    try:
        result = await asyncio.wait_for(
            loop.run_in_executor(None, _snmp_sync),
            timeout=timeout + 5,
        )
        return result
    except asyncio.TimeoutError:
        return {"status": "failed", "value": "timeout"}
    except Exception as exc:
        return {"status": "failed", "value": str(exc)}


# ── Per-target probe orchestrator ─────────────────────────────────────────────

async def probe_target(ws, target: str, ports: list, snmp_community: str, timeout: int,
                       cancel_event=None, probe_id=None):
    """Run all probe steps for one target and stream results over ws.

    If ``cancel_event`` is set at any checkpoint (before ping, before the TCP
    batch, before SNMP) the probe stops early and no further network activity is
    issued for this target. Results already sent are preserved by the client.
    """

    def cancelled():
        return cancel_event is not None and cancel_event.is_set()

    async def send(step, status, value):
        await ws.send(json.dumps({
            "type": "step_result",
            "probeId": probe_id,
            "target": target,
            "step": step,
            "status": status,
            "value": value,
        }))

    if cancelled():
        return

    # DNS
    dns = await probe_dns(target, timeout)
    await send("dns", dns["status"], dns["value"])
    # Use resolved IP for lower-level probes to avoid repeated DNS lookups
    probe_addr = dns["value"] if dns["status"] == "ok" else target

    if cancelled():
        return

    # Ping
    ping = await probe_ping(probe_addr, timeout)
    await send("ping", ping["status"], ping["value"])

    if cancelled():
        return

    # TCP ports (run concurrently for speed)
    port_coros = {str(p): probe_tcp(probe_addr, p, timeout) for p in ports}
    tcp_results = await asyncio.gather(*port_coros.values(), return_exceptions=True)
    for port_str, result in zip(port_coros.keys(), tcp_results):
        if isinstance(result, Exception):
            await send(f"tcp_{port_str}", "failed", str(result))
        else:
            await send(f"tcp_{port_str}", result["status"], result["value"])

    if cancelled():
        return

    # SNMP
    snmp = await probe_snmp(probe_addr, snmp_community, timeout)
    await send("snmp", snmp["status"], snmp["value"])


# ── Probe orchestration (cancellable) ─────────────────────────────────────────

async def run_probe(ws, probe_id, targets, ports, community, timeout, cancel_event):
    """Probe every target sequentially while honoring ``cancel_event``.

    Checks for cancellation before each target so a Stop request halts further
    network activity instead of merely hiding the browser UI. Streams a
    ``probe_done`` with ``cancelled`` and ``completed`` counts. Returns the
    ``(completed, cancelled)`` tuple so callers/tests can assert behavior.
    """
    await ws.send(json.dumps({
        "type": "probe_start", "probeId": probe_id, "total": len(targets),
    }))

    completed = 0
    for target in targets:
        if cancel_event.is_set():
            break
        try:
            await probe_target(ws, target, ports, community, timeout, cancel_event, probe_id)
        except Exception as exc:
            log.warning("Error probing %s: %s", target, exc)
            await ws.send(json.dumps({
                "type": "step_result", "probeId": probe_id, "target": target,
                "step": "error", "status": "failed", "value": str(exc),
            }))
        # If cancellation arrived during this target, treat it as not completed
        # (partial results already streamed are preserved on the client).
        if cancel_event.is_set():
            break
        completed += 1

    cancelled = cancel_event.is_set()
    await ws.send(json.dumps({
        "type": "probe_done", "probeId": probe_id,
        "total": len(targets), "completed": completed, "cancelled": cancelled,
    }))
    if cancelled:
        log.info("Probe %s cancelled — %d of %d target(s) completed",
                 probe_id, completed, len(targets))
    else:
        log.info("Probe %s complete — %d target(s)", probe_id, len(targets))
    return completed, cancelled


# ── WebSocket connection handler ──────────────────────────────────────────────

async def handle_connection(ws, secret_token: str):
    """
    Authenticate then serve probe requests.
    Authentication: the WS URL must include ?token=<secret_token>.
    Origin validation: only localhost / null (file://) origins are accepted.
    """
    # websockets >= 10 exposes request path via ws.request.path or ws.path
    path = ""
    try:
        path = ws.request.path if hasattr(ws, "request") and ws.request else getattr(ws, "path", "")
    except Exception:
        pass

    # Origin check
    try:
        headers = ws.request.headers if hasattr(ws, "request") and ws.request else {}
    except Exception:
        headers = {}

    if not _check_origin(headers):
        log.warning("Rejected connection — disallowed origin")
        await ws.close(1008, "Forbidden origin")
        return

    # Token check
    if not _check_token(path, secret_token):
        log.warning("Rejected connection — missing or incorrect token")
        await ws.close(1008, "Invalid token")
        return

    remote = getattr(ws, "remote_address", ("?", "?"))
    log.info("Authenticated client connected from %s:%s", *remote)

    # Per-connection probe state. The probe runs as a background task so the
    # connection keeps reading messages and can honor a "probe_cancel".
    state = {"probe_id": None, "task": None, "cancel_event": None}

    async def cancel_current():
        ev = state["cancel_event"]
        task = state["task"]
        if ev is not None:
            ev.set()
        if task is not None and not task.done():
            try:
                await asyncio.wait_for(asyncio.shield(task), timeout=15)
            except Exception:
                pass

    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send(json.dumps({"type": "error", "message": "Invalid JSON"}))
                continue

            mtype = msg.get("type")

            # Cancellation request — stop the running probe (if the id matches or
            # no id was supplied). Safe to receive at any time.
            if mtype == "probe_cancel":
                pid = msg.get("probeId")
                if state["probe_id"] and (pid is None or pid == state["probe_id"]):
                    log.info("Cancellation requested for probe %s", state["probe_id"])
                    if state["cancel_event"] is not None:
                        state["cancel_event"].set()
                continue

            if mtype != "probe":
                await ws.send(json.dumps({
                    "type": "error",
                    "message": f"Unknown message type: {mtype}",
                }))
                continue

            targets = [str(t).strip() for t in msg.get("targets", []) if str(t).strip()]
            ports = list(dict.fromkeys(
                int(p) for p in msg.get("ports", DEFAULT_PORTS)
                if str(p).strip().isdigit() and 1 <= int(p) <= 65535
            ))  # deduplicated, order preserved
            community = str(msg.get("snmp_community", DEFAULT_SNMP_COMMUNITY))[:64]
            timeout = max(1, min(int(msg.get("timeout", DEFAULT_TIMEOUT)), 30))

            if not targets:
                await ws.send(json.dumps({"type": "error", "message": "No targets provided"}))
                continue

            if len(targets) > 256:
                await ws.send(json.dumps({"type": "error", "message": "Too many targets (max 256)"}))
                continue

            # Cap port count to prevent accidental high-concurrency probes
            MAX_PORTS = 64
            if len(ports) > MAX_PORTS:
                ports = ports[:MAX_PORTS]
                log.warning("Port list truncated to %d (max %d)", MAX_PORTS, MAX_PORTS)

            # If a probe is already running, cancel it before starting a new one.
            await cancel_current()

            probe_id = str(msg.get("probeId") or secrets.token_hex(8))
            cancel_event = asyncio.Event()
            state["probe_id"] = probe_id
            state["cancel_event"] = cancel_event
            log.info("Probing %d target(s) [probe %s]: %s",
                     len(targets), probe_id, ", ".join(targets[:5]))

            async def _runner(pid=probe_id, t=targets, p=ports, c=community,
                              to=timeout, ev=cancel_event):
                try:
                    await run_probe(ws, pid, t, p, c, to, ev)
                except Exception as exc:
                    log.warning("Probe %s ended unexpectedly: %s", pid, exc)
                finally:
                    if state["probe_id"] == pid:
                        state["probe_id"] = None
                        state["task"] = None
                        state["cancel_event"] = None

            state["task"] = asyncio.create_task(_runner())

    except Exception as exc:
        log.warning("Connection closed unexpectedly: %s", exc)
    finally:
        # Never leave a probe task running after the connection ends.
        await cancel_current()
        log.info("Client disconnected from %s:%s", *remote)


# ── Entry point ───────────────────────────────────────────────────────────────

async def main(host: str, port: int):
    if not _HAS_WEBSOCKETS:
        log.error("The 'websockets' package is required. Install it with:")
        log.error("  pip install websockets")
        sys.exit(1)

    # Generate a cryptographically random one-time secret token.
    # Any WebSocket connection without this token is refused.
    secret_token = secrets.token_urlsafe(24)

    relay_url = f"ws://{host}:{port}/?token={secret_token}"

    print()
    print("=" * 68)
    print("  SysAdmin Suite — Network Probe Relay")
    print("=" * 68)
    print()
    print(f"  Relay URL:   {relay_url}")
    print()
    print(f"  Token only:  {secret_token}")
    print()
    print("  Paste either the full Relay URL or the Token only into the")
    print("  dashboard Network panel (relay token field) then click Connect.")
    print()
    print(f"  SNMP support: {'enabled (pysnmp)' if _HAS_PYSNMP else 'disabled  (pip install pysnmp)'}")
    print()
    print("  Press Ctrl+C to stop.")
    print("=" * 68)
    print()

    log.info("Binding WebSocket server on ws://%s:%d", host, port)

    handler = lambda ws: handle_connection(ws, secret_token)

    try:
        async with websockets.serve(
            handler,
            host,
            port,
            ping_interval=20,
            ping_timeout=10,
        ) as server:
            await server.wait_closed()
    except OSError as exc:
        log.error("Cannot bind to %s:%d — %s", host, port, exc)
        log.error("Is another relay already running? Try --port <number>.")
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="SysAdmin Suite Network Probe Relay.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_PORT,
        help=f"WebSocket port to listen on (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--host", default=DEFAULT_HOST,
        help=f"Interface to bind to (default: {DEFAULT_HOST})",
    )
    args = parser.parse_args()

    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        log.info("Relay stopped.")
