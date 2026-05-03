// relay-client.js — WebSocket relay connection manager
// Manages the authenticated connection to the local Python relay (dashboard/relay.py).
// Exported functions are available to all panel modules via the bundle.

export const RELAY_PORT = 7823;
export const RELAY_HOST = 'localhost';
const RELAY_TOKEN_KEY = 'sas_relay_token';
const RECONNECT_DELAY = 5000;

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
 * @returns {function} cancel  — call to abort early
 */
export function sendRelayProbe(req, onMessage, onDone, onError) {
  if (!_connected || !_ws) {
    if (onError) onError('Relay not connected');
    return () => {};
  }

  let active = true;
  const ws = _ws;

  function listener(event) {
    if (!active) return;
    let msg;
    try { msg = JSON.parse(event.data); } catch (e) { return; }
    if (onMessage) onMessage(msg);
    if (msg.type === 'probe_done' || msg.type === 'error') {
      active = false;
      ws.removeEventListener('message', listener);
      ws.removeEventListener('close', closeListener);
      if (onDone) onDone(msg);
    }
  }

  function closeListener() {
    if (!active) return;
    active = false;
    ws.removeEventListener('message', listener);
    if (onDone) onDone({ type: 'probe_done', aborted: true });
  }

  ws.addEventListener('message', listener);
  ws.addEventListener('close', closeListener);

  try {
    ws.send(JSON.stringify(Object.assign({ type: 'probe' }, req)));
  } catch (e) {
    active = false;
    ws.removeEventListener('message', listener);
    ws.removeEventListener('close', closeListener);
    if (onError) onError(String(e));
  }

  return function cancel() {
    active = false;
    ws.removeEventListener('message', listener);
    ws.removeEventListener('close', closeListener);
    if (onDone) onDone({ type: 'probe_done', cancelled: true });
  };
}
