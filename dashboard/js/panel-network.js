// panel-network.js — Network & Protocol Trace Panel

import { sanitize, statusBadge, exportToCSV, sortRows, filterRows, debounce, pingToStep } from './utils.js';
import { buildProtocolRows } from './parsers.js';
import { getRelayConnected, sendRelayProbe, onRelayStatus, setRelayToken, getRelayToken, RELAY_PORT } from './relay-client.js';

let allRows = [];
let displayRows = [];
let openHosts = new Set();
let searchQuery = '';
let filterTransport = '';
let sortKey = 'Target';
let sortDir = 'asc';

// Live probe state
let liveRows = {};       // keyed by target — accumulated step results
let probeCancel = null;  // cancel function returned by sendRelayProbe
let probeRunning = false;

const PROTOCOL_STEPS = [
  { key: 'DNS',  label: 'DNS',     port: null },
  { key: 'Ping', label: 'Ping',    port: null },
  { key: '135',  label: 'TCP/135', port: '135' },
  { key: '139',  label: 'TCP/139', port: '139' },
  { key: '445',  label: 'SMB/445', port: '445' },
  { key: '3389', label: 'RDP/3389',port: '3389' },
  { key: '515',  label: 'LPR/515', port: '515' },
  { key: '631',  label: 'IPP/631', port: '631' },
  { key: '9100', label: 'RAW/9100',port: '9100' },
  { key: 'WMI',  label: 'WMI',    port: null },
  { key: 'SSH',  label: 'SSH',    port: null },
  { key: 'SMB',  label: 'SMB',    port: null },
  { key: 'SNMP', label: 'SNMP',   port: null },
  { key: 'HTTP', label: 'HTTP',   port: null },
  { key: 'ARP',  label: 'ARP',    port: null },
];

export function renderNetworkPanel(store) {
  allRows = buildProtocolRows(store);
  applyFilters();
  renderRows();
  renderSummary();
}

export function initNetworkPanel() {
  const search = document.getElementById('net-search');
  if (search) {
    search.addEventListener('input', debounce(() => {
      searchQuery = search.value;
      applyFilters();
      renderRows();
    }, 200));
  }

  const transportFilter = document.getElementById('net-transport-filter');
  if (transportFilter) {
    transportFilter.addEventListener('change', () => {
      filterTransport = transportFilter.value;
      applyFilters();
      renderRows();
    });
  }

  const sortKeyEl = document.getElementById('net-sort-key');
  if (sortKeyEl) {
    sortKeyEl.addEventListener('change', () => {
      sortKey = sortKeyEl.value;
      applyFilters();
      renderRows();
    });
  }

  const sortDirBtn = document.getElementById('net-sort-dir');
  if (sortDirBtn) {
    sortDirBtn.addEventListener('click', () => {
      sortDir = sortDir === 'asc' ? 'desc' : 'asc';
      sortDirBtn.textContent = sortDir === 'asc' ? '↑↓' : '↓↑';
      applyFilters();
      renderRows();
    });
  }

  const exportBtn = document.getElementById('net-export');
  if (exportBtn) {
    exportBtn.addEventListener('click', () => {
      // Collect all port keys across all displayed rows for dynamic columns
      const fixedExportPorts = ['135', '139', '445', '3389', '515', '631', '9100'];
      const allPortKeys = new Set(fixedExportPorts);
      displayRows.forEach(r => Object.keys(r.ports || {}).forEach(p => allPortKeys.add(p)));
      const portKeysSorted = [...allPortKeys].sort((a, b) => parseInt(a) - parseInt(b));

      const flat = displayRows.map(r => {
        const base = {
          Target: r.Target || '',
          ResolvedAddress: r.ResolvedAddress || '',
          DnsName: r.DnsName || '',
          PingStatus: r.PingStatus || '',
          TransportUsed: r.TransportUsed || '',
          IdentityStatus: r.IdentityStatus || '',
          ObservedHostName: r.ObservedHostName || '',
          ObservedSerial: r.ObservedSerial || '',
          ObservedMACs: r.ObservedMACs || '',
        };
        portKeysSorted.forEach(p => { base[`TCP_${p}`] = (r.ports || {})[p] || ''; });
        base.Notes = r.Notes || '';
        return base;
      });
      exportToCSV(flat, 'network-protocol-trace.csv');
    });
  }

  // Relay status updates
  onRelayStatus(() => updateRelayIndicator());
  updateRelayIndicator();

  // Token connect button
  const connectBtn = document.getElementById('relay-connect-btn');
  if (connectBtn) {
    connectBtn.addEventListener('click', () => {
      const input = document.getElementById('relay-token-input');
      const token = input ? input.value.trim() : '';
      if (!token) return;
      setRelayToken(token);
      updateRelayIndicator();
    });
  }

  // Allow Enter key in token input
  const tokenInput = document.getElementById('relay-token-input');
  if (tokenInput) {
    // Pre-fill from localStorage if available
    const saved = getRelayToken();
    if (saved) tokenInput.value = saved;

    tokenInput.addEventListener('keydown', e => {
      if (e.key === 'Enter') {
        const token = tokenInput.value.trim();
        if (token) { setRelayToken(token); updateRelayIndicator(); }
      }
    });
  }

  // Live probe button
  const probeBtn = document.getElementById('net-live-probe-btn');
  if (probeBtn) probeBtn.addEventListener('click', openProbeModal);
}

// ── Relay indicator ───────────────────────────────────────────────────────────

function updateRelayIndicator() {
  const dot = document.getElementById('relay-dot');
  const label = document.getElementById('relay-label');
  const probeBtn = document.getElementById('net-live-probe-btn');
  const tokenInput = document.getElementById('relay-token-input');
  const connectBtn = document.getElementById('relay-connect-btn');

  const connected = getRelayConnected();
  const hasToken = !!getRelayToken();

  if (dot) {
    dot.className = 'relay-dot ' + (connected ? 'relay-connected' : 'relay-disconnected');
  }
  if (label) {
    label.textContent = connected ? 'Relay connected' : (hasToken ? 'Relay offline' : 'No token');
    label.title = connected
      ? `Relay connected — ws://localhost:${RELAY_PORT}`
      : `Paste the token printed by: python3 dashboard/relay.py`;
  }
  if (probeBtn) {
    // Always enabled — when relay is offline the button opens a fallback
    // instruction view; when connected it opens the real probe modal.
    probeBtn.disabled = probeRunning;
    probeBtn.textContent = connected ? '📡 Live Probe' : '📡 Probe / Commands';
    probeBtn.title = connected
      ? 'Run live network probe via local relay'
      : 'Relay offline — shows setup instructions and command-gen fallback';
  }
  // Hide token input once connected (token is saved); show when disconnected
  if (tokenInput) tokenInput.style.display = connected ? 'none' : '';
  if (connectBtn) connectBtn.style.display = connected ? 'none' : '';
}

// ── Live probe modal (relay offline fallback) ─────────────────────────────────

function _openFallbackModal() {
  const existing = document.getElementById('net-fallback-modal');
  if (existing) existing.remove();

  const modal = document.createElement('div');
  modal.id = 'net-fallback-modal';
  modal.className = 'modal-backdrop';
  modal.innerHTML = `
    <div class="modal" style="width:560px;max-width:98vw">
      <div class="modal-header">
        <span class="modal-title">📡 Network Probe — Relay Not Connected</span>
        <p class="modal-subtitle">Without the local relay, the dashboard uses command-generation mode:
          copy the generated scripts, run them on an admin machine, then drag the CSV output back here.</p>
        <button class="modal-close" id="fb-modal-close">×</button>
      </div>
      <div class="modal-body" style="gap:14px">
        <div style="padding:10px 14px;background:rgba(79,142,247,0.08);border:1px solid rgba(79,142,247,0.25);border-radius:6px;font-size:11px;color:var(--text-dim)">
          <strong style="color:var(--text)">Option A — Start the relay (enables real-time probing)</strong><br>
          Run this command on your admin machine, then paste the printed token into the relay field above:<br>
          <code style="display:block;margin-top:6px;padding:6px 8px;background:var(--bg3);border-radius:4px;user-select:all">python3 dashboard/relay.py</code>
          <span style="color:var(--text-muted)">Requires Python 3.8+ and: pip install websockets (pip install pysnmp for SNMP)</span>
        </div>
        <div style="padding:10px 14px;background:rgba(245,158,11,0.07);border:1px solid rgba(245,158,11,0.2);border-radius:6px;font-size:11px;color:var(--text-dim)">
          <strong style="color:var(--text)">Option B — Command-generation mode (browser fallback)</strong><br>
          Switch to <strong>⚡ Live (Command-Gen)</strong> mode in the header, enter your targets, and click
          <em>Generate Probe Commands</em> to get copy-paste Bash and PowerShell scripts.
          Drag the resulting CSV files back here to populate the panel.
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn-secondary" id="fb-modal-close2">Close</button>
        <button class="btn-primary" id="fb-switch-live">⚡ Switch to Command-Gen Mode</button>
      </div>
    </div>`;

  document.body.appendChild(modal);

  const close = () => modal.remove();
  modal.querySelector('#fb-modal-close').addEventListener('click', close);
  modal.querySelector('#fb-modal-close2').addEventListener('click', close);
  modal.addEventListener('click', e => { if (e.target === modal) close(); });

  modal.querySelector('#fb-switch-live').addEventListener('click', () => {
    close();
    // Switch to Live (Command-Gen) mode
    const liveBtn = document.querySelector('.mode-btn[data-mode="live"]');
    if (liveBtn) liveBtn.click();
  });
}

// ── Live probe modal ──────────────────────────────────────────────────────────

function openProbeModal() {
  // Fallback: relay not connected — show relay setup instructions and
  // offer the browser command-generation mode as an alternative.
  if (!getRelayConnected()) {
    _openFallbackModal();
    return;
  }

  const existing = document.getElementById('net-probe-modal');
  if (existing) existing.remove();

  const modal = document.createElement('div');
  modal.id = 'net-probe-modal';
  modal.className = 'modal-backdrop';
  modal.innerHTML = `
    <div class="modal" style="width:560px;max-width:98vw">
      <div class="modal-header">
        <span class="modal-title">📡 Live Network Probe</span>
        <p class="modal-subtitle">Targets are probed via the local relay. Results stream into the Network panel in real time.</p>
        <button class="modal-close" id="probe-modal-close">×</button>
      </div>
      <div class="modal-body" style="gap:12px">
        <div>
          <label style="font-size:11px;font-weight:600;color:var(--text-dim);display:block;margin-bottom:4px">Targets (comma or newline separated — hostname or IP):</label>
          <textarea id="probe-targets-input" style="width:100%;height:90px;padding:8px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:6px;color:var(--text);font-family:var(--mono);font-size:11px;resize:vertical" placeholder="192.168.1.10&#10;printer.local&#10;workstation-01"></textarea>
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
          <div>
            <label style="font-size:11px;font-weight:600;color:var(--text-dim);display:block;margin-bottom:4px">TCP Ports (comma separated):</label>
            <input id="probe-ports-input" type="text" value="135,139,445,3389,515,631,9100"
              style="width:100%;padding:6px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:6px;color:var(--text);font-family:var(--mono);font-size:11px">
          </div>
          <div>
            <label style="font-size:11px;font-weight:600;color:var(--text-dim);display:block;margin-bottom:4px">SNMP Community:</label>
            <input id="probe-snmp-input" type="text" value="public"
              style="width:100%;padding:6px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:6px;color:var(--text);font-family:var(--mono);font-size:11px">
          </div>
        </div>
        <div>
          <label style="font-size:11px;font-weight:600;color:var(--text-dim);display:block;margin-bottom:4px">Timeout per check (seconds):</label>
          <input id="probe-timeout-input" type="number" value="2" min="1" max="30"
            style="width:80px;padding:6px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:6px;color:var(--text);font-size:11px">
        </div>
        <div id="probe-progress" style="display:none;font-size:11px;color:var(--text-dim);font-family:var(--mono)"></div>
      </div>
      <div class="modal-footer">
        <button class="btn-secondary" id="probe-modal-cancel">Cancel</button>
        <button class="btn-primary" id="probe-modal-start">▶ Start Probe</button>
      </div>
    </div>`;

  document.body.appendChild(modal);

  const close = () => modal.remove();
  modal.querySelector('#probe-modal-close').addEventListener('click', close);
  modal.querySelector('#probe-modal-cancel').addEventListener('click', close);
  modal.addEventListener('click', e => { if (e.target === modal) close(); });

  modal.querySelector('#probe-modal-start').addEventListener('click', () => {
    const targetsRaw = modal.querySelector('#probe-targets-input').value;
    const portsRaw = modal.querySelector('#probe-ports-input').value;
    const community = modal.querySelector('#probe-snmp-input').value.trim() || 'public';
    const timeout = parseInt(modal.querySelector('#probe-timeout-input').value, 10) || 2;

    const targets = targetsRaw
      .split(/[,\n\s]+/)
      .map(t => t.trim())
      .filter(Boolean);

    if (!targets.length) {
      alert('Enter at least one target.');
      return;
    }

    const ports = portsRaw
      .split(',')
      .map(p => parseInt(p.trim(), 10))
      .filter(p => !isNaN(p) && p > 0 && p < 65536);

    startLiveProbe(targets, ports, community, timeout, modal);
  });
}

function startLiveProbe(targets, ports, community, timeout, modal) {
  if (!getRelayConnected()) return;
  if (probeRunning && probeCancel) probeCancel();

  liveRows = {};
  probeRunning = true;
  updateRelayIndicator();

  const startBtn = modal.querySelector('#probe-modal-start');
  const cancelBtn = modal.querySelector('#probe-modal-cancel');
  const progress = modal.querySelector('#probe-progress');

  if (startBtn) { startBtn.disabled = true; startBtn.textContent = '⏳ Probing…'; }
  if (cancelBtn) cancelBtn.textContent = 'Stop';
  if (progress) { progress.style.display = ''; progress.textContent = `Probing ${targets.length} target(s)…`; }

  // Initialise live rows for each target so they appear immediately
  for (const t of targets) {
    liveRows[t] = _makeLiveRow(t);
  }
  _refreshLive();

  probeCancel = sendRelayProbe(
    { targets, ports, snmp_community: community, timeout },
    (msg) => {
      if (msg.type === 'step_result') {
        _applyStepResult(msg);
        if (progress) {
          progress.textContent = `Probing ${targets.length} target(s) — ${msg.target} / ${msg.step}`;
        }
        _refreshLive();
      } else if (msg.type === 'probe_start') {
        if (progress) progress.textContent = `Probing ${msg.total} target(s)…`;
      }
    },
    (doneMsg) => {
      probeRunning = false;
      probeCancel = null;
      updateRelayIndicator();
      if (progress) {
        const label = doneMsg.cancelled ? 'Probe cancelled.' : doneMsg.aborted ? 'Relay disconnected.' : `Probe complete — ${targets.length} target(s) done.`;
        progress.textContent = label;
      }
      if (startBtn) { startBtn.disabled = false; startBtn.textContent = '▶ Start Probe'; }
      if (cancelBtn) cancelBtn.textContent = 'Close';
      _refreshLive();
    },
    (err) => {
      probeRunning = false;
      probeCancel = null;
      updateRelayIndicator();
      if (progress) progress.textContent = `Error: ${err}`;
      if (startBtn) { startBtn.disabled = false; startBtn.textContent = '▶ Start Probe'; }
    },
  );

  if (cancelBtn) {
    cancelBtn.addEventListener('click', () => {
      if (probeRunning && probeCancel) {
        probeCancel();
        probeRunning = false;
        probeCancel = null;
        updateRelayIndicator();
      }
      modal.remove();
    }, { once: true });
  }
}

function _makeLiveRow(target) {
  return {
    Target: target,
    ResolvedAddress: '',
    DnsName: '',
    PingStatus: 'Probing…',
    TransportUsed: 'relay',
    IdentityStatus: '',
    ports: {},
    steps: {},
    _isLive: true,
  };
}

function _applyStepResult(msg) {
  const { target, step, status, value } = msg;
  if (!liveRows[target]) liveRows[target] = _makeLiveRow(target);
  const row = liveRows[target];

  const ok = status === 'ok';
  const stepStatus = ok ? 'success' : status === 'skipped' ? 'skipped' : 'failed';

  if (step === 'dns') {
    row.ResolvedAddress = ok ? value : '';
    row.steps['DNS'] = stepStatus;
  } else if (step === 'ping') {
    row.PingStatus = value; // 'Reachable' or 'NoPing'
    row.steps['Ping'] = stepStatus;
  } else if (step === 'snmp') {
    row.steps['SNMP'] = stepStatus;
    if (ok) row.Notes = `SNMP: ${value}`;
  } else if (step.startsWith('tcp_')) {
    const port = step.slice(4); // '135', '445', etc.
    row.ports[port] = ok ? 'open' : (value === 'filtered' ? 'filtered' : 'closed');
  }
}

function _refreshLive() {
  applyFilters();
  renderRows();
  renderSummary();
}

// ── Filters & sorting ─────────────────────────────────────────────────────────

/**
 * Build the merged row set that includes both CSV-loaded rows and any live
 * probe rows.  Live rows permanently override allRows entries for the same
 * target — they are first-class state, not a temporary swap.
 */
function _mergedRows() {
  const liveList = Object.values(liveRows);
  if (!liveList.length) return allRows;
  const liveTargets = new Set(Object.keys(liveRows));
  return [...allRows.filter(r => !liveTargets.has(r.Target)), ...liveList];
}

function applyFilters() {
  let rows = _mergedRows();
  if (searchQuery) {
    rows = filterRows(rows, ['Target', 'ResolvedAddress', 'DnsName', 'TransportUsed', 'IdentityStatus', 'ObservedHostName', 'ObservedSerial'], searchQuery);
  }
  if (filterTransport) {
    rows = rows.filter(r => (r.TransportUsed || '').toLowerCase().includes(filterTransport.toLowerCase()));
  }
  displayRows = sortRows(rows, sortKey, sortDir);
}

function renderSummary() {
  const el = document.getElementById('net-summary');
  if (!el) return;

  const merged = _mergedRows();
  const total = merged.length;
  const reachable = merged.filter(r => pingToStep(r.PingStatus) === 'success').length;
  const identified = merged.filter(r => /collected/i.test(r.IdentityStatus)).length;
  const unreachable = merged.filter(r => pingToStep(r.PingStatus) === 'failed').length;

  el.innerHTML = `
    <div class="stat-chip stat-info">
      <span class="stat-num">${total}</span>
      <span class="stat-label">Targets</span>
    </div>
    <div class="stat-chip stat-success">
      <span class="stat-num">${reachable}</span>
      <span class="stat-label">Reachable</span>
    </div>
    <div class="stat-chip stat-success">
      <span class="stat-num">${identified}</span>
      <span class="stat-label">Identity Collected</span>
    </div>
    <div class="stat-chip stat-error">
      <span class="stat-num">${unreachable}</span>
      <span class="stat-label">Unreachable</span>
    </div>
  `;
}

function getStepStatus(row, step) {
  // For port steps, check the ports map
  if (step.port) {
    const portStatus = (row.ports || {})[step.port];
    if (!portStatus) return 'skipped';
    if (/open/i.test(portStatus)) return 'success';
    if (/closed|filtered/i.test(portStatus)) return 'failed';
    return 'skipped';
  }
  // For named steps
  const s = (row.steps || {})[step.key];
  if (!s) {
    // Infer from context
    if (step.key === 'DNS') return row.ResolvedAddress ? 'success' : 'failed';
    if (step.key === 'Ping') return pingToStep(row.PingStatus || '');
    return 'skipped';
  }
  return s;
}

function stepBadgeClass(status) {
  if (status === 'success') return 'success';
  if (status === 'failed') return 'failed';
  if (status === 'partial') return 'partial';
  return 'skipped';
}

function renderRows() {
  const container = document.getElementById('net-accordion');
  if (!container) return;

  const badge = document.querySelector('[data-tab="network"] .tab-badge');
  if (badge) badge.textContent = allRows.length;

  if (!displayRows.length) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-icon">📡</div>
        <div class="empty-msg">${allRows.length ? 'No rows match your filters.' : 'No network or protocol data loaded.'}</div>
        <div class="empty-sub">${allRows.length ? '' : 'Load workstation_identity.csv, network_preflight.csv, or printer_probe.csv — or use Live Probe if the relay is running.'}</div>
      </div>`;
    return;
  }

  container.innerHTML = displayRows.map(row => {
    const isOpen = openHosts.has(row.Target);
    const transport = row.TransportUsed || '';
    const identityStatus = row.IdentityStatus || '';
    const isLive = !!row._isLive;

    const identityBadgeClass = /collected/i.test(identityStatus) ? 'badge-success' :
                                /unreachable/i.test(identityStatus) ? 'badge-error' :
                                /needsapproved/i.test(identityStatus) ? 'badge-warning' : 'badge-muted';

    const pingStep = pingToStep(row.PingStatus || '');
    const pingClass = pingStep === 'success' ? 'badge-success' : pingStep === 'failed' ? 'badge-error' : 'badge-muted';

    // Fixed protocol ladder steps
    const fixedPortKeys = new Set(PROTOCOL_STEPS.filter(s => s.port).map(s => s.port));
    const fixedLadder = PROTOCOL_STEPS.map(step => {
      const status = getStepStatus(row, step);
      const cls = stepBadgeClass(status);
      const portVal = step.port ? ((row.ports || {})[step.port] || '') : '';
      const title = portVal ? `${step.label}: ${portVal}` : step.label;
      return `<div class="proto-step ${cls}" title="${sanitize(title)}">
        <div class="proto-dot"></div>
        ${sanitize(step.label)}
      </div>`;
    });
    // Extra ports from live probes that are not in the fixed ladder
    const extraPortSteps = Object.entries(row.ports || {})
      .filter(([port]) => !fixedPortKeys.has(port))
      .map(([port, portStatus]) => {
        const ok = /open/i.test(portStatus);
        const failed = /closed|filtered/i.test(portStatus);
        const cls = ok ? 'success' : failed ? 'failed' : 'skipped';
        return `<div class="proto-step ${cls} proto-step-extra" title="TCP/${sanitize(port)}: ${sanitize(portStatus)}">
          <div class="proto-dot"></div>
          TCP/${sanitize(port)}
        </div>`;
      });
    const ladderHtml = [...fixedLadder, ...extraPortSteps].join('');

    const metaHtml = [
      ['Resolved IP', row.ResolvedAddress],
      ['DNS Name', row.DnsName],
      ['Ping', row.PingStatus],
      ['Observed Host', row.ObservedHostName],
      ['Serial', row.ObservedSerial],
      ['MACs', row.ObservedMACs],
      ['SMB Recon', row.SmbRecon],
      ['SNMP Info', row.Notes && row.Notes.startsWith('SNMP:') ? row.Notes : null],
      ['Timestamp', row.Timestamp],
      ['Notes', row.Notes && !row.Notes.startsWith('SNMP:') ? row.Notes : null],
    ].filter(([, v]) => v).map(([k, v]) =>
      `<div class="protocol-meta-row">
        <span class="meta-key">${sanitize(k)}</span>
        <span class="meta-val">${sanitize(v)}</span>
      </div>`
    ).join('');

    return `
      <div class="protocol-accordion${isLive ? ' protocol-live' : ''}">
        <div class="protocol-row-header ${isOpen ? 'open' : ''}" data-host="${sanitize(row.Target)}">
          <span class="protocol-toggle">▶</span>
          <span class="protocol-host">${sanitize(row.Target)}</span>
          <div class="protocol-badges">
            <span class="badge ${pingClass}">${sanitize(row.PingStatus || 'NoPing')}</span>
            ${transport ? `<span class="badge badge-accent" title="Transport Used">🔌 ${sanitize(transport)}</span>` : ''}
            ${identityStatus ? `<span class="badge ${identityBadgeClass}">${sanitize(identityStatus)}</span>` : ''}
            ${row.ResolvedAddress ? `<span class="badge badge-muted mono">${sanitize(row.ResolvedAddress)}</span>` : ''}
            ${isLive ? `<span class="badge badge-relay">⚡ live</span>` : ''}
          </div>
        </div>
        <div class="protocol-detail ${isOpen ? 'open' : ''}">
          <div class="protocol-ladder">${ladderHtml}</div>
          <div class="protocol-meta">${metaHtml}</div>
        </div>
      </div>
    `;
  }).join('');

  // Bind accordion toggles
  container.querySelectorAll('.protocol-row-header').forEach(header => {
    header.addEventListener('click', () => {
      const host = header.dataset.host;
      if (openHosts.has(host)) openHosts.delete(host);
      else openHosts.add(host);
      const detail = header.nextElementSibling;
      if (detail) detail.classList.toggle('open', openHosts.has(host));
      header.classList.toggle('open', openHosts.has(host));
    });
  });
}

export function getNetworkHTML() {
  return `
    <div id="net-summary" class="summary-row"></div>
    <div class="panel-toolbar">
      <span class="panel-title">Network &amp; Protocol Trace</span>
      <div class="toolbar-sep"></div>
      <input class="search-box" id="net-search" placeholder="Search target, IP, hostname, transport…" type="text">
      <select class="filter-select" id="net-transport-filter">
        <option value="">All Transports</option>
        <option value="WMI">WMI</option>
        <option value="SSH">SSH</option>
        <option value="ARP">ARP</option>
        <option value="SNMP">SNMP</option>
        <option value="SMB">SMB</option>
        <option value="relay">relay</option>
      </select>
      <select class="filter-select" id="net-sort-key">
        <option value="Target">Sort: Target</option>
        <option value="PingStatus">Sort: Ping</option>
        <option value="TransportUsed">Sort: Transport</option>
        <option value="IdentityStatus">Sort: Identity</option>
        <option value="ResolvedAddress">Sort: IP</option>
      </select>
      <button class="icon-btn" id="net-sort-dir" title="Toggle sort direction">↑↓</button>
      <button class="icon-btn" id="net-export">⬇ Export CSV</button>
      <div class="toolbar-sep"></div>
      <div class="relay-indicator" id="relay-indicator">
        <span class="relay-dot relay-disconnected" id="relay-dot"></span>
        <span class="relay-label" id="relay-label">Relay offline</span>
      </div>
      <input class="relay-token-input" id="relay-token-input" type="text"
        placeholder="Paste relay token…"
        title="Paste the token printed by: python3 dashboard/relay.py">
      <button class="icon-btn relay-connect-btn" id="relay-connect-btn" title="Connect to relay with this token">Connect</button>
      <button class="icon-btn relay-probe-btn" id="net-live-probe-btn" title="Run live probe or get setup instructions">📡 Probe / Commands</button>
    </div>
    <div class="table-wrapper" id="net-accordion"></div>`;
}
