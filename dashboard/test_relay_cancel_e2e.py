#!/usr/bin/env python3
"""End-to-end loopback integration test for relay probe cancellation.

This is the closed feedback loop for the dashboard Stop control: it starts the
real relay (dashboard/relay.py) as a subprocess on a loopback-only ephemeral
port, authenticates with the token the relay prints, runs a probe against three
loopback targets, sends a {"type":"probe_cancel"} after the first target's first
evidence arrives, and proves the relay actually stops server-side probing.

Scope and safety:
- LOOPBACK ONLY. Every probe target is in 127.0.0.0/8, so all probe traffic
  (DNS/ping/TCP/SNMP) stays on this host's loopback interface. No remote
  workstation, printer, or corporate target is ever contacted, and no target-box
  OS/security telemetry is produced. The WebSocket is only the operator control
  channel to the relay; it does not replace or hide probe steps.
- No scan broadening: one common port, short timeout, three loopback targets.
- No credentials are introduced: the relay's own one-time printed token is used.
- No live evidence is written: all probe messages stay in memory.

Run: python dashboard/test_relay_cancel_e2e.py
Requires: pip install websockets   (test is skipped if websockets is missing).
"""

import asyncio
import json
import os
import socket
import sys
import unittest

try:
    import websockets  # noqa: F401
    # websockets >= 13 ships the new asyncio client; older versions expose the
    # legacy client module. Prefer the new API, fall back for older installs.
    try:
        from websockets.asyncio.client import connect as ws_connect
    except Exception:  # pragma: no cover - older websockets
        from websockets.client import connect as ws_connect
    _HAS_WEBSOCKETS = True
except Exception:  # pragma: no cover - environment without websockets
    _HAS_WEBSOCKETS = False

HERE = os.path.dirname(os.path.abspath(__file__))
RELAY_PATH = os.path.join(HERE, "relay.py")

# All three targets are inside the 127.0.0.0/8 loopback range and are distinct
# strings, so step_result.target lets us tell them apart while keeping every
# probe on the local host.
LOOPBACK_TARGETS = ["127.0.0.1", "127.0.0.2", "127.0.0.3"]
PROBE_ID = "e2e-cancel-probe"

# Generous so a slow CI runner does not flake; the scenario normally finishes in
# well under a second.
TOKEN_TIMEOUT = 20
CONNECT_TIMEOUT = 10
SCENARIO_TIMEOUT = 30


def _free_loopback_port() -> int:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


async def _read_token(proc, timeout):
    """Read the relay's merged stdout until the one-time token line appears."""
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while True:
        remaining = deadline - loop.time()
        if remaining <= 0:
            raise TimeoutError("relay did not print a token in time")
        line = await asyncio.wait_for(proc.stdout.readline(), timeout=remaining)
        if not line:
            raise RuntimeError("relay exited before printing a token")
        text = line.decode("utf-8", "replace")
        if "Token only:" in text:
            return text.split("Token only:", 1)[1].strip()


async def _connect_with_retry(port, token, timeout):
    """Connect to the relay, retrying until it is listening or we time out."""
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    url = f"ws://127.0.0.1:{port}/?token={token}"
    last_err = None
    while loop.time() < deadline:
        try:
            return await ws_connect(url, open_timeout=5)
        except Exception as exc:  # relay may not be bound yet
            last_err = exc
            await asyncio.sleep(0.1)
    raise RuntimeError(f"could not connect to relay: {last_err}")


async def _run_cancel_scenario():
    """Start the relay, probe loopback targets, cancel after first evidence."""
    port = _free_loopback_port()
    # -u (and PYTHONUNBUFFERED) so the relay's banner/token flush immediately
    # instead of sitting in a block-buffered pipe.
    env = dict(os.environ, PYTHONUNBUFFERED="1")
    proc = await asyncio.create_subprocess_exec(
        sys.executable, "-u", RELAY_PATH, "--host", "127.0.0.1", "--port", str(port),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        env=env,
    )
    messages = []
    cancel_index = None
    try:
        token = await _read_token(proc, TOKEN_TIMEOUT)
        ws = await _connect_with_retry(port, token, CONNECT_TIMEOUT)
        try:
            await ws.send(json.dumps({
                "type": "probe",
                "probeId": PROBE_ID,
                "targets": LOOPBACK_TARGETS,
                "ports": [80],
                "snmp_community": "public",
                "timeout": 1,
            }))

            async for raw in ws:
                msg = json.loads(raw)
                messages.append(msg)

                # As soon as the first target produces evidence, request cancel.
                if msg.get("type") == "step_result" and cancel_index is None:
                    cancel_index = len(messages) - 1
                    await ws.send(json.dumps({
                        "type": "probe_cancel", "probeId": PROBE_ID,
                    }))

                if msg.get("type") == "probe_done":
                    break
        finally:
            await ws.close()
    finally:
        try:
            proc.terminate()
        except ProcessLookupError:
            pass
        try:
            await asyncio.wait_for(proc.wait(), timeout=10)
        except asyncio.TimeoutError:  # pragma: no cover - defensive
            proc.kill()
            await proc.wait()

    return messages, cancel_index


@unittest.skipUnless(_HAS_WEBSOCKETS, "websockets package is required for the relay E2E test")
class RelayCancelE2ETests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Loopback-only guard: refuse to run if the target list ever drifts off
        # the loopback range. This keeps the test from contacting a real host.
        for t in LOOPBACK_TARGETS:
            assert t.startswith("127."), f"non-loopback target in E2E test: {t}"
        try:
            cls.messages, cls.cancel_index = asyncio.run(
                asyncio.wait_for(_run_cancel_scenario(), timeout=SCENARIO_TIMEOUT)
            )
        except Exception as exc:  # surface relay/runtime failures clearly
            raise AssertionError(f"relay cancel E2E scenario failed: {exc}") from exc

    def _probe_done(self):
        done = [m for m in self.messages if m.get("type") == "probe_done"]
        self.assertTrue(done, "relay never sent a probe_done message")
        return done[-1]

    def test_cancel_was_triggered(self):
        self.assertIsNotNone(self.cancel_index,
                             "no step_result arrived, so cancel was never sent")

    def test_probe_done_reports_cancelled(self):
        done = self._probe_done()
        self.assertTrue(done.get("cancelled") is True,
                        f"probe_done did not report cancelled: {done}")

    def test_completed_at_most_one_target(self):
        done = self._probe_done()
        self.assertIn("completed", done, "probe_done missing completed count")
        self.assertLessEqual(done["completed"], 1,
                             f"more than one target completed: {done}")

    def test_no_results_for_targets_two_and_three(self):
        # After cancellation the relay must not emit any evidence for the second
        # or third target. Targets 1/2/3 are distinct strings, so this is exact.
        later_targets = {LOOPBACK_TARGETS[1], LOOPBACK_TARGETS[2]}
        leaked = [m for m in self.messages
                  if m.get("type") == "step_result" and m.get("target") in later_targets]
        self.assertEqual(leaked, [],
                         f"relay leaked results for cancelled targets: {leaked}")

    def test_client_classifies_stopped_with_partial(self):
        # This mirrors how dashboard/js/panel-network.js _finishProbe decides the
        # "Probe stopped. Partial results preserved." state: cancelled and not
        # aborted, with a usable completed count.
        done = self._probe_done()
        self.assertTrue(done.get("cancelled") is True)
        self.assertNotEqual(done.get("aborted"), True,
                            "a user-initiated stop must not be classified as aborted")
        self.assertLessEqual(done.get("completed", 99), 1)
        # Partial evidence for the first target should be preserved in-stream.
        first_target_results = [m for m in self.messages
                                if m.get("type") == "step_result"
                                and m.get("target") == LOOPBACK_TARGETS[0]]
        self.assertTrue(first_target_results,
                        "no partial results were preserved for the first target")


if __name__ == "__main__":
    unittest.main(verbosity=2)
