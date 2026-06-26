// relay-client.js — WebSocket relay connection manager
// Manages the authenticated connection to the local Python relay (dashboard/relay.py).
// Exported functions are available to all panel modules via the bundle.

import { emitRunEvent } from './run-control.js';

export const RELAY_PORT = 7823;
export const RELAY_HOST = 'localhost';
const RELAY_TOKEN_KEY = 'sas_relay_token';
const RECONNECT_DELAY = 5000;
// How long to wait for the relay to acknowledge a cancel before the client
// falls back to a local cancelled state (so Start re-enables even if the relay
// is slow to answer). The relay normally answers within one step boundary.
const CANCEL_ACK_TIMEOUT = 6000;

/** Generate a per-probe id so cancel requests target the right probe. */
function _genProbeId() {
  try {
    if (typeof crypto !== 'undefined' && crypto && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
  } catch (e) { /* fall through to manual id */ }
  return 'probe-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
}

let _ws = null;
let _connected = false;
let _reconnectTimer = null;
let _statusCallbacks = [];

export function onRelayStatus(cb) {
  _statusCallbacks.push(cb);
}

function _notifyStatus() {
  for (const cb of _statusCallbacks) {
    try { cb(_connected); } catch (e) { /* ignore */ }
  }
}

export function getRelayConnected() {
  return _connected;
}

/** Get the token saved in localStorage (may be empty). */
export function getRelayToken() {
  try { return localStorage.getItem(RELAY_TOKEN_KEY) || ''; } catch (e) { return ''; }
}

/**
 * Save token and immediately reconnect with the new credential.
 * Accepts either a raw token string OR a full relay URL
 * (ws://localhost:7823/?token=abc123) — the token is extracted automatically.
 * This lets operators paste whatever the relay printed to the terminal.
 */
export function setRelayToken(input) {
  let token = (input || '').trim();
  // If the operator pasted a full ws:// URL, extract the ?token= param
  if (token.startsWith('ws://') || token.startsWith('wss://')) {
    try {
      // Use a fake https:// prefix so URL() can parse it
      const u = new URL(token.replace(/^wss?:\/\//, 'https://'));
      const t = u.searchParams.get('token');
      if (t) token = t;
    } catch (e) { /* leave token as-is */ }
  }
  try { localStorage.setItem(RELAY_TOKEN_KEY, token); } catch (e) { /* ignore */ }
  _disconnect();
  if (token) _connect();
}

function _disconnect() {
  if (_reconnectTimer) { clearTimeout(_reconnectTimer); _reconnectTimer = null; }
  if (_ws) {
    const ws = _ws;
    _ws = null;
    try { ws.close(); } catch (e) { /* ignore */ }
  }
  if (_connected) {
    _connected = false;
    _notifyStatus();
  }
}

function _scheduleReconnect() {
  if (_reconnectTimer) return;
  _reconnectTimer = setTimeout(() => {
    _reconnectTimer = null;
    _connect();
  }, RECONNECT_DELAY);
}

function _connect() {
  if (_ws && (_ws.readyState === WebSocket.CONNECTING || _ws.readyState === WebSocket.OPEN)) return;

  const token = getRelayToken();
  if (!token) return; // no token — do not auto-connect (avoid unauthenticated probes)

  const url = `ws://${RELAY_HOST}:${RELAY_PORT}/?token=${encodeURIComponent(token)}`;
  let ws;
  try {
    ws = new WebSocket(url);
  } catch (e) {
    _scheduleReconnect();
    return;
  }
  _ws = ws;

  ws.addEventListener('open', () => {
    _connected = true;
    _notifyStatus();
  });

  ws.addEventListener('close', (ev) => {
    const wasConnected = _connected;
    _connected = false;
    _ws = null;
    if (wasConnected) _notifyStatus();
    // 1008 = policy violation (wrong token / origin) — don't retry
    if (ev.code === 1008) {
      _notifyStatus();
      return;
    }
    _scheduleReconnect();
  });

  ws.addEventListener('error', () => {
    // close event will follow; no action needed here
  });
}

export function initRelayConnection() {
  // Only connect if a token is already stored — operator must supply token first
  if (getRelayToken()) _connect();
}

/**
 * Send a probe request and receive streaming results.
 * @param {object} req       — { targets, ports, snmp_community, timeout }
 * @param {function} onMessage — called with each parsed JSON message
 * @param {function} onDone    — called when probe_done received or WS closes mid-probe
 * @param {function} onError   — called with an error string
 * @returns {function} cancel  — call to stop the probe; sends a real cancel to the relay
 */
export function sendRelayProbe(req, onMessage, onDone, onError) {
  const runId = req && req.runId;
  const relayReq = Object.assign({}, req || {});
  delete relayReq.runId;

  if (!_connected || !_ws) {
    if (runId) {
      emitRunEvent(runId, 'RunFailed', {
        source: 'relay-client',
        summary: 'Relay not connected',
        payload: { message: 'Relay not connected' },
      });
    }
    if (onError) onError('Relay not connected');
    return () => {};
  }

  let active = true;
  let cancelTimer = null;
  const ws = _ws;
  const probeId = _genProbeId();

  function cleanup() {
    active = false;
    ws.removeEventListener('message', listener);
    ws.removeEventListener('close', closeListener);
    if (cancelTimer) { clearTimeout(cancelTimer); cancelTimer = null; }
  }

  function listener(event) {
    if (!active) return;
    let msg;
    try { msg = JSON.parse(event.data); } catch (e) { return; }
    // If the relay tags messages with a probeId, ignore ones for other probes.
    if (msg.probeId && msg.probeId !== probeId) return;
    if (runId) {
      if (msg.type === 'probe_start') {
        emitRunEvent(runId, 'RunStarted', {
          source: 'relay-server',
          summary: `Relay accepted probe for ${msg.total || 0} target(s)`,
          payload: { total: msg.total || 0, completed: 0 },
        });
      } else if (msg.type === 'step_result') {
        emitRunEvent(runId, 'RunStepResult', {
          source: 'relay-server',
          summary: `Probe step result: ${msg.step || 'step'} ${msg.status || ''}`,
          payload: {
            target: msg.target || '',
            step: msg.step || '',
            status: msg.status || '',
            value: msg.value || '',
          },
        });
      } else if (msg.type === 'probe_done') {
        if (msg.cancelled) {
          emitRunEvent(runId, 'StopAcknowledged', {
            source: 'relay-server',
            summary: 'Relay acknowledged probe cancellation',
            payload: { completed: msg.completed, total: msg.total },
          });
          emitRunEvent(runId, 'PartialResultsPreserved', {
            source: 'dashboard-parser',
            summary: 'Partial probe results preserved locally',
            payload: { completed: msg.completed, total: msg.total },
          });
          emitRunEvent(runId, 'RunStopped', {
            source: 'relay-server',
            summary: 'Relay stopped probe before remaining targets',
            payload: { completed: msg.completed, total: msg.total },
          });
        } else {
          emitRunEvent(runId, 'RunCompleted', {
            source: 'relay-server',
            summary: 'Relay probe completed',
            payload: { completed: msg.completed, total: msg.total },
          });
        }
      } else if (msg.type === 'error') {
        emitRunEvent(runId, 'RunFailed', {
          source: 'relay-server',
          summary: msg.message || 'Relay reported an error',
          payload: { message: msg.message || 'Relay reported an error' },
        });
      }
    }
    if (onMessage) onMessage(msg);
    if (msg.type === 'probe_done' || msg.type === 'error') {
      cleanup();
      if (onDone) onDone(msg);
    }
  }

  function closeListener() {
    if (!active) return;
    cleanup();
    // The relay socket dropped mid-probe: classify as aborted/disconnected,
    // never as a successful completion.
    if (runId) {
      emitRunEvent(runId, 'RunDisconnected', {
        source: 'relay-client',
        summary: 'Relay socket closed before probe completion',
      });
      emitRunEvent(runId, 'PartialResultsPreserved', {
        source: 'dashboard-parser',
        summary: 'Partial probe results preserved locally after disconnect',
      });
    }
    if (onDone) onDone({ type: 'probe_done', probeId, aborted: true });
  }

  ws.addEventListener('message', listener);
  ws.addEventListener('close', closeListener);

  try {
    if (runId) {
      emitRunEvent(runId, 'RunStarting', {
        source: 'relay-client',
        summary: 'Probe request sent to relay',
      });
    }
    ws.send(JSON.stringify(Object.assign({ type: 'probe', probeId }, relayReq)));
  } catch (e) {
    cleanup();
    if (runId) {
      emitRunEvent(runId, 'RunFailed', {
        source: 'relay-client',
        summary: 'Failed to send probe request',
        payload: { message: String(e) },
      });
    }
    if (onError) onError(String(e));
  }

  return function cancel() {
    if (!active) return;
    // Tell the relay to stop issuing network checks. UI-only cancellation is not
    // enough — without this message the relay keeps probing every target.
    try {
      ws.send(JSON.stringify({ type: 'probe_cancel', probeId }));
      if (runId) {
        emitRunEvent(runId, 'StopSent', {
          source: 'relay-client',
          summary: 'Cancel message sent to relay',
        });
      }
    } catch (e) {
      // Socket is already gone — classify as aborted/disconnected, not success.
      cleanup();
      if (runId) {
        emitRunEvent(runId, 'RunDisconnected', {
          source: 'relay-client',
          summary: 'Relay socket closed before cancel acknowledgement',
        });
      }
      if (onDone) onDone({ type: 'probe_done', probeId, aborted: true });
      return;
    }
    // Wait for the relay's authoritative probe_done (cancelled:true). If it does
    // not arrive in time, fall back to a local cancelled state so the UI re-enables.
    if (!cancelTimer) {
      cancelTimer = setTimeout(() => {
        if (!active) return;
        cleanup();
        if (runId) {
          emitRunEvent(runId, 'RunDisconnected', {
            source: 'relay-client',
            summary: 'Relay cancel acknowledgement timed out',
          });
          emitRunEvent(runId, 'PartialResultsPreserved', {
            source: 'dashboard-parser',
            summary: 'Partial probe results preserved locally after cancel timeout',
          });
        }
        if (onDone) onDone({ type: 'probe_done', probeId, cancelled: true, ackTimeout: true });
      }, CANCEL_ACK_TIMEOUT);
    }
  };
}
