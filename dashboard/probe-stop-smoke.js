#!/usr/bin/env node
// dashboard/probe-stop-smoke.js — runtime proof that Stop sends a real cancel.
// Run: node dashboard/probe-stop-smoke.js
//
// Loads the real relay-client.js module under a mock WebSocket and proves the
// critical safety contract: a probe Stop sends a `probe_cancel` (with the same
// probeId as the probe) to the relay — it is NOT a UI-only listener teardown.
// Also proves disconnect mid-probe is classified as aborted, never success.

import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));

let passed = 0;
let failed = 0;
function assert(ok, label, detail) {
  if (ok) { console.log(`PASS [probe-stop:${label}]`); passed++; }
  else { console.error(`FAIL [probe-stop:${label}]${detail ? ': ' + detail : ''}`); failed++; }
}

// ── Mock WebSocket ──────────────────────────────────────────────────────────
let lastSocket = null;
class MockWebSocket {
  constructor(url) {
    this.url = url;
    this.sent = [];
    this._listeners = {};
    this.readyState = 1; // OPEN
    lastSocket = this;
  }
  addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); }
  removeEventListener(type, fn) {
    if (this._listeners[type]) this._listeners[type] = this._listeners[type].filter(f => f !== fn);
  }
  send(data) { this.sent.push(JSON.parse(data)); }
  close() { this.readyState = 3; this._fire('close', { code: 1000 }); }
  _fire(type, ev) { (this._listeners[type] || []).slice().forEach(fn => fn(ev)); }
  sentOfType(t) { return this.sent.filter(m => m.type === t); }
}
MockWebSocket.CONNECTING = 0;
MockWebSocket.OPEN = 1;
MockWebSocket.CLOSING = 2;
MockWebSocket.CLOSED = 3;

global.WebSocket = MockWebSocket;
const _store = new Map();
global.localStorage = {
  getItem: k => (_store.has(k) ? _store.get(k) : null),
  setItem: (k, v) => _store.set(k, String(v)),
  removeItem: k => _store.delete(k),
};

// Load the real module (Node resolves the ESM file directly).
const relayClientUrl = 'file://' + join(__dir, 'js', 'relay-client.js').replace(/\\/g, '/');
const { setRelayToken, getRelayConnected, sendRelayProbe } = await import(relayClientUrl);

// Connect: setting a token triggers _connect() which creates a MockWebSocket.
setRelayToken('test-token-123');
assert(lastSocket !== null, 'socket-created', 'no WebSocket created on token set');
lastSocket._fire('open');
assert(getRelayConnected() === true, 'relay-connected', 'relay did not report connected after open');

// ── Probe 1: Stop must send probe_cancel with the matching probeId ───────────
let doneMsg1 = null;
const cancel1 = sendRelayProbe(
  { targets: ['t1', 't2'], ports: [80], snmp_community: 'public', timeout: 1 },
  () => {},
  (d) => { doneMsg1 = d; },
  (e) => { assert(false, 'probe1-no-error', e); },
);

const probeMsgs = lastSocket.sentOfType('probe');
assert(probeMsgs.length === 1, 'probe-sent', `expected 1 probe message, got ${probeMsgs.length}`);
const probeId = probeMsgs[0].probeId;
assert(typeof probeId === 'string' && probeId.length > 0, 'probe-has-id', 'probe message missing probeId');

// Trigger Stop.
cancel1();
const cancelMsgs = lastSocket.sentOfType('probe_cancel');
assert(cancelMsgs.length === 1, 'cancel-sent-to-relay',
  'Stop did not send a probe_cancel to the relay (UI-only cancel is a defect)');
assert(cancelMsgs[0].probeId === probeId, 'cancel-matches-probe-id',
  `cancel probeId ${cancelMsgs[0].probeId} != probe ${probeId}`);

// Relay acknowledges with an authoritative cancelled probe_done.
lastSocket._fire('message', { data: JSON.stringify({ type: 'probe_done', probeId, total: 2, completed: 1, cancelled: true }) });
assert(doneMsg1 && doneMsg1.cancelled === true, 'cancel-ack-honored',
  'client did not surface the relay cancelled probe_done');
assert(doneMsg1 && doneMsg1.completed === 1, 'partial-count-preserved',
  'client lost the partial completion count');

// ── Probe 2: mid-probe disconnect is classified as aborted, not success ──────
let doneMsg2 = null;
sendRelayProbe(
  { targets: ['t3'], ports: [80], snmp_community: 'public', timeout: 1 },
  () => {},
  (d) => { doneMsg2 = d; },
  () => {},
);
lastSocket.close();
assert(doneMsg2 && doneMsg2.aborted === true, 'disconnect-classified-aborted',
  'mid-probe disconnect was not classified as aborted/disconnected');
assert(!(doneMsg2 && doneMsg2.cancelled), 'disconnect-not-success',
  'aborted probe must not also be reported as a clean cancel/success');

console.log(`\nProbe stop: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
