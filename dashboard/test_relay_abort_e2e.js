#!/usr/bin/env node
// dashboard/test_relay_abort_e2e.js - loopback E2E for relay death handling.
//
// Starts the real relay (dashboard/relay.py) on 127.0.0.1:7823, authenticates
// with the token the relay prints, drives the real relay-client.js module over a
// real WebSocket, then terminates the relay process mid-probe. The expected
// result is client-side abort/disconnect classification, not user Stop and not
// success.
//
// Scope and safety:
// - LOOPBACK ONLY. Every probe target is in 127.0.0.0/8, so probe traffic stays
//   on this host's loopback interface.
// - No scan broadening: one common port, short timeout, three loopback targets.
// - No credentials are introduced: the relay's own one-time printed token is used.
// - No live evidence is written: all probe messages stay in memory.
//
// Run: node dashboard/test_relay_abort_e2e.js
// Requires: npm install --no-save --no-package-lock ws@8

import { spawn } from 'child_process';
import { setDefaultResultOrder } from 'dns';
import { dirname, join } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const RELAY_PATH = join(__dir, 'relay.py');
const RELAY_HOST = '127.0.0.1';
const RELAY_PORT = 7823;
const LOOPBACK_TARGETS = ['127.0.0.1', '127.0.0.2', '127.0.0.3'];
const TOKEN_TIMEOUT_MS = 20000;
const CONNECT_TIMEOUT_MS = 10000;
const SCENARIO_TIMEOUT_MS = 30000;
const PYTHON = process.env.PYTHON || 'python';

let passed = 0;
let failed = 0;

function assert(ok, label, detail) {
  if (ok) {
    console.log(`PASS [relay-abort:${label}]`);
    passed++;
  } else {
    console.error(`FAIL [relay-abort:${label}]${detail ? ': ' + detail : ''}`);
    failed++;
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function withTimeout(promise, ms, label) {
  let timer;
  return Promise.race([
    promise.finally(() => clearTimeout(timer)),
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    }),
  ]);
}

function installLocalStorage() {
  const store = new Map();
  globalThis.localStorage = {
    getItem: key => (store.has(key) ? store.get(key) : null),
    setItem: (key, value) => { store.set(key, String(value)); },
    removeItem: key => { store.delete(key); },
  };
}

async function installWebSocket() {
  try {
    const wsModule = await import('ws');
    globalThis.WebSocket = wsModule.WebSocket || wsModule.default;
    return;
  } catch (_err) {
    if (typeof globalThis.WebSocket === 'function') return;
    throw new Error('WebSocket runtime missing; run: npm install --no-save --no-package-lock ws@8');
  }
}

function startRelay() {
  const env = { ...process.env, PYTHONUNBUFFERED: '1' };
  const proc = spawn(PYTHON, ['-u', RELAY_PATH, '--host', RELAY_HOST, '--port', String(RELAY_PORT)], {
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  proc.output = '';
  proc.stdout.setEncoding('utf8');
  proc.stderr.setEncoding('utf8');
  proc.stdout.on('data', chunk => { proc.output += chunk; });
  proc.stderr.on('data', chunk => { proc.output += chunk; });
  return proc;
}

function readToken(proc) {
  return withTimeout(new Promise((resolve, reject) => {
    function scan() {
      const match = proc.output.match(/Token only:\s*(\S+)/);
      if (match) resolve(match[1]);
    }
    proc.stdout.on('data', scan);
    proc.stderr.on('data', scan);
    proc.once('exit', code => {
      reject(new Error(`relay exited before printing token (code ${code}): ${proc.output}`));
    });
    scan();
  }), TOKEN_TIMEOUT_MS, 'relay token');
}

async function stopRelay(proc) {
  if (!proc || proc.exitCode !== null) return;
  if (!proc.killed) proc.kill('SIGTERM');
  const exited = new Promise(resolve => proc.once('exit', resolve));
  try {
    await withTimeout(exited, 5000, 'relay SIGTERM');
  } catch (_err) {
    if (proc.exitCode === null) proc.kill('SIGKILL');
    await new Promise(resolve => proc.once('exit', resolve));
  }
}

async function waitForConnected(getRelayConnected) {
  const deadline = Date.now() + CONNECT_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (getRelayConnected()) return;
    await sleep(100);
  }
  throw new Error('relay-client did not report connected in time');
}

function classifyProbeDone(doneMsg, totalTargets) {
  if (doneMsg && doneMsg.aborted) {
    return 'Relay disconnected - probe aborted. Partial results preserved.';
  }
  if (doneMsg && doneMsg.cancelled) {
    const completed = typeof doneMsg.completed === 'number' ? doneMsg.completed : null;
    const total = typeof doneMsg.total === 'number' ? doneMsg.total : totalTargets;
    return completed !== null
      ? `Probe stopped. Partial results preserved (${completed} of ${total} target(s) completed).`
      : 'Probe stopped. Partial results preserved.';
  }
  return `Probe complete - ${totalTargets} target(s) done.`;
}

async function runScenario() {
  for (const target of LOOPBACK_TARGETS) {
    assert(target.startsWith('127.'), 'loopback-target-guard', `non-loopback target: ${target}`);
  }

  setDefaultResultOrder('ipv4first');
  installLocalStorage();
  await installWebSocket();

  const relayClientUrl = pathToFileURL(join(__dir, 'js', 'relay-client.js')).href;
  const { setRelayToken, getRelayConnected, sendRelayProbe } = await import(relayClientUrl);

  const relay = startRelay();
  const messages = [];
  let firstEvidence = null;
  let doneMsg = null;
  let doneResolve;
  let doneReject;
  const donePromise = new Promise((resolve, reject) => {
    doneResolve = resolve;
    doneReject = reject;
  });

  try {
    const token = await readToken(relay);
    setRelayToken(token);
    await waitForConnected(getRelayConnected);

    sendRelayProbe(
      {
        targets: LOOPBACK_TARGETS,
        ports: [80],
        snmp_community: 'public',
        timeout: 1,
      },
      msg => {
        messages.push(msg);
        if (msg.type === 'step_result' && !firstEvidence) {
          firstEvidence = msg;
          relay.kill('SIGTERM');
        }
      },
      msg => {
        doneMsg = msg;
        doneResolve(msg);
      },
      err => {
        doneReject(new Error(String(err)));
      },
    );

    doneMsg = await withTimeout(donePromise, SCENARIO_TIMEOUT_MS, 'abort scenario');
  } finally {
    try { setRelayToken(''); } catch (_err) { /* best effort cleanup */ }
    await stopRelay(relay);
  }

  return { messages, firstEvidence, doneMsg };
}

try {
  const { messages, firstEvidence, doneMsg } = await runScenario();
  const serverDone = messages.filter(msg => msg.type === 'probe_done');
  const firstTargetResults = messages.filter(
    msg => msg.type === 'step_result' && msg.target === LOOPBACK_TARGETS[0],
  );
  const label = classifyProbeDone(doneMsg, LOOPBACK_TARGETS.length);

  assert(firstEvidence !== null, 'partial-evidence-arrived',
    'relay died before any step_result was preserved');
  assert(firstTargetResults.length > 0, 'partial-results-preserved',
    'no partial results were preserved for the first loopback target');
  assert(doneMsg && doneMsg.aborted === true, 'classifies-aborted-disconnected',
    `done message was ${JSON.stringify(doneMsg)}`);
  assert(!(doneMsg && doneMsg.cancelled === true), 'not-cancelled',
    'relay death must not be classified as a user Stop');
  assert(!label.startsWith('Probe complete'), 'not-success',
    `aborted probe was classified as success: ${label}`);
  assert(label.includes('probe aborted'), 'aborted-label',
    `abort label did not mirror panel-network classification: ${label}`);
  assert(serverDone.length === 0, 'no-server-probe-done',
    `relay should not emit authoritative probe_done after process death: ${JSON.stringify(serverDone)}`);
} catch (err) {
  assert(false, 'scenario', err && err.stack ? err.stack : String(err));
}

console.log(`\nRelay abort E2E: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
