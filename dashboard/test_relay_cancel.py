#!/usr/bin/env python3
"""Unit tests for the relay probe cancellation path (dashboard/relay.py).

These tests prove that a Stop request actually halts server-side probing:
the relay must stop before remaining targets and report a cancelled probe with
partial-completion counts. No real network probing is performed — probe_target
is replaced with a fake so the loop logic is tested in isolation.

Run: python dashboard/test_relay_cancel.py
"""

import asyncio
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import relay  # noqa: E402


class FakeWS:
    """Minimal async WebSocket stand-in that records JSON messages sent."""

    def __init__(self):
        self.sent = []

    async def send(self, data):
        self.sent.append(json.loads(data))

    def messages_of_type(self, mtype):
        return [m for m in self.sent if m.get("type") == mtype]

    def first(self, mtype):
        msgs = self.messages_of_type(mtype)
        return msgs[0] if msgs else None


class RunProbeCancelTests(unittest.TestCase):
    def _patch_probe_target(self, fake):
        original = relay.probe_target
        relay.probe_target = fake
        self.addCleanup(lambda: setattr(relay, "probe_target", original))

    def test_cancel_before_start_probes_no_targets(self):
        ws = FakeWS()
        cancel_event = asyncio.Event()
        cancel_event.set()  # cancelled before the loop even begins

        calls = []

        async def fake_probe_target(ws_, target, ports, community, timeout,
                                    cancel_event=None, probe_id=None):
            calls.append(target)

        self._patch_probe_target(fake_probe_target)

        completed, cancelled = asyncio.run(
            relay.run_probe(ws, "p1", ["t1", "t2", "t3"], [80], "public", 1, cancel_event)
        )

        self.assertEqual(calls, [], "no targets should be probed when cancelled up front")
        self.assertEqual(completed, 0)
        self.assertTrue(cancelled)
        done = ws.first("probe_done")
        self.assertIsNotNone(done)
        self.assertTrue(done["cancelled"])
        self.assertEqual(done["completed"], 0)
        self.assertEqual(done["total"], 3)
        self.assertEqual(done["probeId"], "p1")

    def test_cancel_midway_stops_remaining_targets(self):
        ws = FakeWS()
        cancel_event = asyncio.Event()
        calls = []

        async def fake_probe_target(ws_, target, ports, community, timeout,
                                    cancel_event=None, probe_id=None):
            calls.append(target)
            # Simulate a Stop arriving while the first target is being probed.
            if len(calls) == 1:
                cancel_event.set()

        self._patch_probe_target(fake_probe_target)

        completed, cancelled = asyncio.run(
            relay.run_probe(ws, "p2", ["t1", "t2", "t3"], [80], "public", 1, cancel_event)
        )

        self.assertEqual(calls, ["t1"], "relay must not probe targets after cancellation")
        self.assertTrue(cancelled)
        done = ws.first("probe_done")
        self.assertTrue(done["cancelled"])
        self.assertEqual(done["total"], 3)

    def test_no_cancel_completes_all_targets(self):
        ws = FakeWS()
        cancel_event = asyncio.Event()
        calls = []

        async def fake_probe_target(ws_, target, ports, community, timeout,
                                    cancel_event=None, probe_id=None):
            calls.append(target)

        self._patch_probe_target(fake_probe_target)

        completed, cancelled = asyncio.run(
            relay.run_probe(ws, "p3", ["t1", "t2"], [80], "public", 1, cancel_event)
        )

        self.assertEqual(calls, ["t1", "t2"])
        self.assertEqual(completed, 2)
        self.assertFalse(cancelled)
        done = ws.first("probe_done")
        self.assertFalse(done["cancelled"])
        self.assertEqual(done["completed"], 2)

    def test_probe_target_short_circuits_when_cancelled(self):
        """probe_target must issue no network steps when cancel is already set."""
        ws = FakeWS()
        cancel_event = asyncio.Event()
        cancel_event.set()

        asyncio.run(
            relay.probe_target(ws, "t1", [80], "public", 1, cancel_event, "p4")
        )

        self.assertEqual(ws.sent, [], "no step_result should be sent for a cancelled target")


if __name__ == "__main__":
    unittest.main(verbosity=2)
