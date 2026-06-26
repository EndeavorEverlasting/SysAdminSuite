// run-control.js — shared lifecycle state for dashboard runs.
//
// Buttons express intent; lifecycle events prove current run reality.

const ACTIVE_STATES = new Set(['requested', 'approved', 'starting', 'running', 'stopping']);
const STOPPABLE_STATES = new Set(['requested', 'approved', 'starting', 'running', 'stopping']);
const TERMINAL_STATES = new Set(['stopped', 'completed', 'failed', 'aborted', 'disconnected']);
const VALID_SOURCES = new Set(['ui', 'relay-client', 'relay-server', 'script', 'dashboard-parser']);
const EXTERNAL_COMMAND_KINDS = new Set(['Command generation']);
const CTRL_C_STOP_HINT = 'To stop a copied command, press Ctrl+C in the terminal where it is running.';

let _runs = new Map();
let _events = [];
let _listeners = [];
let _stopHandlers = new Map();
let _bannerTimer = null;

function _now() {
  return new Date().toISOString();
}

function _genRunId() {
  try {
    if (typeof crypto !== 'undefined' && crypto && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
  } catch (_) { /* fall through */ }
  return 'run-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
}

function _safeSource(source) {
  return VALID_SOURCES.has(source) ? source : 'ui';
}

function _safeSummary(summary) {
  return String(summary || '').slice(0, 240);
}

function _initialRun(runId, details) {
  return {
    runId,
    kind: details.kind || 'run',
    state: 'idle',
    createdAt: _now(),
    updatedAt: null,
    startedAt: null,
    endedAt: null,
    source: _safeSource(details.source),
    summary: _safeSummary(details.targetsSummary || details.summary || ''),
    progress: { completed: 0, total: details.total || null },
    current: { target: '', step: '' },
    partialResultsPreserved: false,
    externalOnly: !!details.externalOnly || EXTERNAL_COMMAND_KINDS.has(details.kind),
    lastEvent: null,
    lastError: '',
  };
}

export function isRunStoppable(run) {
  if (!run || !STOPPABLE_STATES.has(run.state)) return false;
  if (run.externalOnly || EXTERNAL_COMMAND_KINDS.has(run.kind)) return false;
  return true;
}

function _reduce(run, event) {
  const next = Object.assign({}, run, {
    updatedAt: event.timestamp,
    lastEvent: event.type,
  });
  const payload = event.payload || {};

  if (payload.total !== undefined) {
    next.progress = Object.assign({}, next.progress, { total: payload.total });
  }
  if (payload.completed !== undefined) {
    next.progress = Object.assign({}, next.progress, { completed: payload.completed });
  }
  if (payload.target !== undefined || payload.step !== undefined) {
    next.current = Object.assign({}, next.current, {
      target: payload.target !== undefined ? String(payload.target || '') : next.current.target,
      step: payload.step !== undefined ? String(payload.step || '') : next.current.step,
    });
  }

  switch (event.type) {
    case 'RunRequested':
      next.state = 'requested';
      break;
    case 'RunApproved':
      next.state = 'approved';
      break;
    case 'RunCreated':
      if (next.state === 'idle') next.state = 'requested';
      break;
    case 'RunStarting':
      next.state = 'starting';
      break;
    case 'RunStarted':
      next.state = 'running';
      next.startedAt = next.startedAt || event.timestamp;
      break;
    case 'RunStepStarted':
    case 'RunStepResult':
    case 'RunProgress':
      if (!TERMINAL_STATES.has(next.state)) next.state = 'running';
      break;
    case 'StopRequested':
    case 'StopSent':
    case 'StopAcknowledged':
    case 'RunStopping':
      if (!TERMINAL_STATES.has(next.state)) next.state = 'stopping';
      break;
    case 'RunStopped':
      next.state = 'stopped';
      next.endedAt = event.timestamp;
      break;
    case 'RunCompleted':
      next.state = 'completed';
      next.endedAt = event.timestamp;
      break;
    case 'RunFailed':
      next.state = 'failed';
      next.lastError = _safeSummary(payload.message || event.summary);
      next.endedAt = event.timestamp;
      break;
    case 'RunAborted':
      next.state = 'aborted';
      next.endedAt = event.timestamp;
      break;
    case 'RunDisconnected':
      next.state = 'disconnected';
      next.endedAt = event.timestamp;
      break;
    case 'PartialResultsPreserved':
      next.partialResultsPreserved = true;
      break;
    case 'RunEvidenceWritten':
      break;
    case 'CommandGenerated':
      next.state = 'approved';
      next.externalOnly = true;
      break;
    case 'CommandCopied':
    case 'AwaitingExternalResults':
      if (!TERMINAL_STATES.has(next.state)) next.state = 'running';
      next.externalOnly = true;
      next.startedAt = next.startedAt || event.timestamp;
      break;
    case 'EvidenceLoaded':
      if (!TERMINAL_STATES.has(next.state)) next.state = 'running';
      break;
    default:
      break;
  }

  next.summary = event.summary || next.summary;
  return next;
}

function _notify(event, run) {
  _updateRunBanner();
  for (const listener of _listeners.slice()) {
    try { listener(event, run); } catch (_) { /* isolate listeners */ }
  }
}

export function createRun({
  kind,
  source = 'ui',
  targetsSummary = '',
  total = null,
  stopHandler = null,
  externalOnly = false,
} = {}) {
  const runId = _genRunId();
  const run = _initialRun(runId, { kind, source, targetsSummary, total, externalOnly });
  _runs.set(runId, run);
  if (stopHandler) _stopHandlers.set(runId, stopHandler);
  emitRunEvent(runId, 'RunCreated', {
    source,
    summary: `${run.kind} created`,
    payload: { total },
  });
  emitRunEvent(runId, 'RunRequested', {
    source,
    summary: `${run.kind} requested: ${targetsSummary || 'scoped run'}`,
    payload: { total },
  });
  return getRunState(runId);
}

export function emitRunEvent(runId, type, details = {}) {
  if (!runId || !_runs.has(runId)) return null;
  const run = _runs.get(runId);
  const event = {
    runId,
    type,
    timestamp: details.timestamp || _now(),
    source: _safeSource(details.source || run.source),
    summary: _safeSummary(details.summary || type),
    payload: details.payload || {},
  };
  const next = _reduce(run, event);
  _runs.set(runId, next);
  _events.push(event);
  _notify(event, next);
  return event;
}

export function subscribeRunEvents(listener) {
  if (typeof listener !== 'function') return () => {};
  _listeners.push(listener);
  return () => {
    _listeners = _listeners.filter(fn => fn !== listener);
  };
}

export function getRunState(runId) {
  const run = _runs.get(runId);
  return run ? JSON.parse(JSON.stringify(run)) : null;
}

export function getRunEvents(runId) {
  return _events.filter(ev => !runId || ev.runId === runId).map(ev => JSON.parse(JSON.stringify(ev)));
}

export function getActiveRun() {
  const active = Array.from(_runs.values())
    .filter(run => ACTIVE_STATES.has(run.state))
    .sort((a, b) => String(b.updatedAt || b.createdAt).localeCompare(String(a.updatedAt || a.createdAt)))[0];
  return active ? getRunState(active.runId) : null;
}

export function setRunStopHandler(runId, handler) {
  if (!runId) return;
  if (typeof handler === 'function') _stopHandlers.set(runId, handler);
  else _stopHandlers.delete(runId);
}

export function requestStop(runId) {
  const run = getRunState(runId);
  if (!run || !STOPPABLE_STATES.has(run.state)) return false;
  emitRunEvent(runId, 'StopRequested', {
    source: 'ui',
    summary: `${run.kind} stop requested`,
  });
  const handler = _stopHandlers.get(runId);
  if (handler) {
    try { handler(); } catch (err) {
      emitRunEvent(runId, 'RunFailed', {
        source: 'ui',
        summary: 'Stop request failed before reaching worker',
        payload: { message: String(err) },
      });
    }
  }
  return true;
}

function _formatElapsed(run) {
  if (!run || !run.startedAt) return '';
  const start = Date.parse(run.startedAt);
  if (!Number.isFinite(start)) return '';
  const seconds = Math.max(0, Math.floor((Date.now() - start) / 1000));
  if (seconds < 60) return `${seconds}s`;
  return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

function _bannerText(run) {
  if (!run) return '';
  if (run.kind === 'Command generation') {
    if (run.state === 'approved') {
      return 'Survey commands generated. Copy and run them in an external terminal.';
    }
    if (run.state === 'running') {
      if (run.lastEvent === 'CommandCopied') {
        return `Command copied. ${CTRL_C_STOP_HINT}`;
      }
      if (run.lastEvent === 'AwaitingExternalResults' || run.lastEvent === 'EvidenceLoaded') {
        return `Awaiting external results. ${CTRL_C_STOP_HINT}`;
      }
      return `Command-generation workflow active. ${CTRL_C_STOP_HINT}`;
    }
    if (run.state === 'completed') return 'Evidence loaded from external command run.';
    if (run.state === 'failed') return `Command-generation workflow failed: ${run.lastError || run.summary}`;
  }
  const kind = run.kind || 'Run';
  const total = run.progress && run.progress.total;
  const completed = run.progress && run.progress.completed;
  const countText = total ? ` - ${completed || 0} of ${total} targets checked` : '';
  const stepText = run.current && run.current.step ? ` - ${run.current.step}` : '';
  const elapsed = _formatElapsed(run);
  const elapsedText = elapsed ? ` - ${elapsed}` : '';

  if (run.state === 'stopping') return `${kind} stopping${countText}.`;
  if (run.state === 'stopped') return `${kind} stopped. Partial results preserved.`;
  if (run.state === 'completed') return `${kind} completed${countText}.`;
  if (run.state === 'failed') return `${kind} failed: ${run.lastError || run.summary}`;
  if (run.state === 'aborted') return `${kind} aborted. Partial results preserved.`;
  if (run.state === 'disconnected') return `${kind} disconnected. Partial results may be incomplete.`;
  if (run.state === 'running') return `${kind} running${countText}${stepText}${elapsedText}.`;
  return `${kind} ${run.state}${countText}.`;
}

function _latestRun() {
  return Array.from(_runs.values())
    .sort((a, b) => String(b.updatedAt || b.createdAt).localeCompare(String(a.updatedAt || a.createdAt)))[0] || null;
}

function _updateRunBanner() {
  const banner = typeof document !== 'undefined' ? document.getElementById('run-control-banner') : null;
  if (!banner) return;
  const text = document.getElementById('run-control-text');
  const meta = document.getElementById('run-control-meta');
  const stopBtn = document.getElementById('run-control-stop');
  const run = getActiveRun() || _latestRun();

  banner.classList.toggle('hidden', !run || run.state === 'idle');
  banner.classList.toggle('run-control-terminal', !!run && TERMINAL_STATES.has(run.state));
  if (text) text.textContent = run ? _bannerText(run) : '';
  if (meta) meta.textContent = run ? `source: ${run.source} - state: ${run.state}` : '';
  if (stopBtn) {
    const stoppable = isRunStoppable(run);
    stopBtn.classList.toggle('hidden', !stoppable);
    stopBtn.disabled = !!run && run.state === 'stopping';
    stopBtn.textContent = run && run.state === 'stopping' ? 'Stopping...' : 'Stop';
    stopBtn.dataset.runId = run ? run.runId : '';
  }
}

export function initRunControl() {
  const stopBtn = typeof document !== 'undefined' ? document.getElementById('run-control-stop') : null;
  if (stopBtn && !stopBtn.dataset.runControlBound) {
    stopBtn.dataset.runControlBound = '1';
    stopBtn.addEventListener('click', () => {
      const runId = stopBtn.dataset.runId;
      if (runId) requestStop(runId);
    });
  }
  if (_bannerTimer) clearInterval(_bannerTimer);
  if (typeof setInterval === 'function') {
    _bannerTimer = setInterval(_updateRunBanner, 1000);
    if (_bannerTimer && typeof _bannerTimer.unref === 'function') _bannerTimer.unref();
  }
  _updateRunBanner();
}

export function _resetRunControlForTests() {
  _runs = new Map();
  _events = [];
  _listeners = [];
  _stopHandlers = new Map();
  if (_bannerTimer) {
    try { clearInterval(_bannerTimer); } catch (_) { /* ignore */ }
    _bannerTimer = null;
  }
}
