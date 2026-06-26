#!/usr/bin/env node
// dashboard/test_run_control_lifecycle.js — Run Control lifecycle reducer smoke.
// Run: node dashboard/test_run_control_lifecycle.js

import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));

let passed = 0;
let failed = 0;
function assert(ok, label, detail) {
  if (ok) { console.log(`PASS [run-control:${label}]`); passed++; }
  else { console.error(`FAIL [run-control:${label}]${detail ? ': ' + detail : ''}`); failed++; }
}

function makeClassList() {
  const set = new Set();
  return {
    add: (...names) => names.forEach(name => set.add(name)),
    remove: (...names) => names.forEach(name => set.delete(name)),
    contains: name => set.has(name),
    toggle: (name, force) => {
      const want = force === undefined ? !set.has(name) : !!force;
      if (want) set.add(name); else set.delete(name);
      return want;
    },
    _set: set,
  };
}

function makeEl(id) {
  const el = {
    id,
    textContent: '',
    disabled: false,
    dataset: {},
    _listeners: {},
    classList: makeClassList(),
    addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
    click() { (this._listeners.click || []).forEach(fn => fn({ target: this })); },
  };
  return el;
}

const elements = new Map();
for (const id of ['run-control-banner', 'run-control-text', 'run-control-meta', 'run-control-stop']) {
  elements.set(id, makeEl(id));
}
elements.get('run-control-banner').classList.add('hidden');
elements.get('run-control-stop').classList.add('hidden');

global.document = {
  getElementById: id => elements.get(id) || null,
};
global.setInterval = () => 1;
global.clearInterval = () => {};

const runControlUrl = 'file://' + join(__dir, 'js', 'run-control.js').replace(/\\/g, '/');
const {
  _resetRunControlForTests,
  createRun,
  emitRunEvent,
  getRunEvents,
  getRunState,
  initRunControl,
  isRunStoppable,
  requestStop,
  setRunStopHandler,
  subscribeRunEvents,
} = await import(runControlUrl);

function assertEventShape(runId) {
  const bad = getRunEvents(runId).filter(ev => !ev.runId || !ev.timestamp || !ev.source || !ev.summary);
  assert(bad.length === 0, 'event-shape', `events missing required fields: ${JSON.stringify(bad)}`);
}

// requested -> running -> completed
_resetRunControlForTests();
let run = createRun({ kind: 'Network probe', source: 'ui', targetsSummary: '2 target(s)', total: 2 });
assert(getRunState(run.runId).state === 'requested', 'requested-state', 'createRun should request work');
emitRunEvent(run.runId, 'RunStarted', {
  source: 'relay-server',
  summary: 'Relay accepted probe',
  payload: { total: 2, completed: 0 },
});
assert(getRunState(run.runId).state === 'running', 'running-state', 'RunStarted did not move to running');
emitRunEvent(run.runId, 'RunCompleted', {
  source: 'relay-server',
  summary: 'Relay probe completed',
  payload: { total: 2, completed: 2 },
});
assert(getRunState(run.runId).state === 'completed', 'completed-state', 'RunCompleted did not move to completed');
assertEventShape(run.runId);

// requested -> running -> stopping -> stopped
_resetRunControlForTests();
run = createRun({ kind: 'Network probe', source: 'ui', targetsSummary: '3 target(s)', total: 3 });
emitRunEvent(run.runId, 'RunStarted', {
  source: 'relay-server',
  summary: 'Relay accepted probe',
  payload: { total: 3, completed: 0 },
});
let stopHandlerCalled = false;
let eventTypes = [];
subscribeRunEvents(ev => eventTypes.push(ev.type));
setRunStopHandler(run.runId, () => { stopHandlerCalled = true; });
requestStop(run.runId);
assert(stopHandlerCalled, 'stop-handler-called', 'StopRequested did not invoke worker cancel handler');
assert(getRunState(run.runId).state === 'stopping', 'stop-request-stopping', 'StopRequested should be intent, not stopped');
emitRunEvent(run.runId, 'StopSent', { source: 'relay-client', summary: 'Cancel sent to relay' });
assert(getRunState(run.runId).state === 'stopping', 'stop-sent-still-stopping', 'StopSent should not imply stopped');
emitRunEvent(run.runId, 'StopAcknowledged', {
  source: 'relay-server',
  summary: 'Relay acknowledged cancellation',
  payload: { total: 3, completed: 1 },
});
assert(getRunState(run.runId).state === 'stopping', 'stop-ack-still-stopping', 'StopAcknowledged should not skip RunStopped');
emitRunEvent(run.runId, 'PartialResultsPreserved', {
  source: 'dashboard-parser',
  summary: 'Partial results preserved locally',
});
emitRunEvent(run.runId, 'RunStopped', {
  source: 'relay-server',
  summary: 'Relay stopped before remaining targets',
  payload: { total: 3, completed: 1 },
});
assert(getRunState(run.runId).state === 'stopped', 'stopped-state', 'RunStopped did not move to stopped');
assert(getRunState(run.runId).partialResultsPreserved === true, 'partial-preserved', 'partial result flag missing');
assert(eventTypes.includes('StopRequested') && eventTypes.includes('StopSent') && eventTypes.includes('StopAcknowledged'),
  'intent-vs-ack-events', `missing stop lifecycle events: ${eventTypes.join(',')}`);

// running -> disconnected
_resetRunControlForTests();
run = createRun({ kind: 'Network probe', source: 'ui', targetsSummary: '1 target(s)', total: 1 });
emitRunEvent(run.runId, 'RunStarted', { source: 'relay-server', summary: 'Relay accepted probe' });
emitRunEvent(run.runId, 'RunDisconnected', { source: 'relay-client', summary: 'Relay socket closed' });
assert(getRunState(run.runId).state === 'disconnected', 'disconnected-state', 'RunDisconnected did not move to disconnected');

// running -> failed
_resetRunControlForTests();
run = createRun({ kind: 'Network probe', source: 'ui', targetsSummary: '1 target(s)', total: 1 });
emitRunEvent(run.runId, 'RunStarted', { source: 'relay-server', summary: 'Relay accepted probe' });
emitRunEvent(run.runId, 'RunFailed', {
  source: 'relay-client',
  summary: 'Relay error',
  payload: { message: 'relay error' },
});
assert(getRunState(run.runId).state === 'failed', 'failed-state', 'RunFailed did not move to failed');

// Persistent global Stop exists outside the probe modal and dispatches StopRequested.
_resetRunControlForTests();
initRunControl();
run = createRun({ kind: 'Network probe', source: 'ui', targetsSummary: '4 target(s)', total: 4 });
emitRunEvent(run.runId, 'RunStarted', {
  source: 'relay-server',
  summary: 'Relay accepted probe',
  payload: { total: 4, completed: 0 },
});
let bannerStopCalled = false;
setRunStopHandler(run.runId, () => { bannerStopCalled = true; });
const banner = elements.get('run-control-banner');
const stopBtn = elements.get('run-control-stop');
assert(!banner.classList.contains('hidden'), 'global-banner-visible', 'global Run Control banner stayed hidden');
assert(!stopBtn.classList.contains('hidden'), 'global-stop-visible', 'global Stop stayed hidden while run active');
stopBtn.click();
assert(bannerStopCalled, 'global-stop-dispatches', 'global Stop did not dispatch requestStop');
assert(getRunState(run.runId).state === 'stopping', 'global-stop-stopping', 'global Stop did not move state to stopping');

// Command-generation runs are external-only and never expose Stop.
_resetRunControlForTests();
initRunControl();
run = createRun({
  kind: 'Command generation',
  source: 'ui',
  targetsSummary: '2 target(s)',
  total: 2,
  externalOnly: true,
});
emitRunEvent(run.runId, 'CommandGenerated', {
  source: 'ui',
  summary: 'Survey commands generated',
});
emitRunEvent(run.runId, 'AwaitingExternalResults', {
  source: 'ui',
  summary: 'Awaiting external shell results',
});
assert(getRunState(run.runId).state === 'running', 'command-gen-running', 'command gen should await external results');
assert(isRunStoppable(getRunState(run.runId)) === false, 'command-gen-not-stoppable', 'external command runs must not be stoppable');
assert(stopBtn.classList.contains('hidden'), 'command-gen-stop-hidden', 'Stop must stay hidden for command-generation runs');
emitRunEvent(run.runId, 'EvidenceLoaded', {
  source: 'dashboard-parser',
  summary: 'Evidence loaded: network_preflight.csv',
});
emitRunEvent(run.runId, 'RunEvidenceWritten', {
  source: 'dashboard-parser',
  summary: 'Loaded evidence preserved locally',
});
emitRunEvent(run.runId, 'RunCompleted', {
  source: 'dashboard-parser',
  summary: 'External command evidence loaded',
});
assert(getRunState(run.runId).state === 'completed', 'command-gen-completed', 'evidence load should complete command-gen run');

_resetRunControlForTests();

console.log(`\nRun Control lifecycle: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
