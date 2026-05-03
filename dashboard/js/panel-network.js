// panel-network.js — Network & Protocol Trace Panel

import { sanitize, statusBadge, exportToCSV, sortRows, filterRows, debounce, pingToStep } from './utils.js';
import { buildProtocolRows } from './parsers.js';

let allRows = [];
let displayRows = [];
let openHosts = new Set();
let searchQuery = '';
let filterTransport = '';
let sortKey = 'Target';
let sortDir = 'asc';

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
      const flat = displayRows.map(r => ({
        Target: r.Target || '',
        ResolvedAddress: r.ResolvedAddress || '',
        DnsName: r.DnsName || '',
        PingStatus: r.PingStatus || '',
        TransportUsed: r.TransportUsed || '',
        IdentityStatus: r.IdentityStatus || '',
        ObservedHostName: r.ObservedHostName || '',
        ObservedSerial: r.ObservedSerial || '',
        ObservedMACs: r.ObservedMACs || '',
        TCP_135: r.ports?.['135'] || '',
        TCP_139: r.ports?.['139'] || '',
        SMB_445: r.ports?.['445'] || '',
        RDP_3389: r.ports?.['3389'] || '',
        LPR_515: r.ports?.['515'] || '',
        IPP_631: r.ports?.['631'] || '',
        RAW_9100: r.ports?.['9100'] || '',
        Notes: r.Notes || ''
      }));
      exportToCSV(flat, 'network-protocol-trace.csv');
    });
  }
}

function applyFilters() {
  let rows = allRows;
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

  const total = allRows.length;
  const reachable = allRows.filter(r => pingToStep(r.PingStatus) === 'success').length;
  const identified = allRows.filter(r => /collected/i.test(r.IdentityStatus)).length;
  const unreachable = allRows.filter(r => pingToStep(r.PingStatus) === 'failed').length;

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
        <div class="empty-sub">${allRows.length ? '' : 'Load workstation_identity.csv, network_preflight.csv, or printer_probe.csv.'}</div>
      </div>`;
    return;
  }

  container.innerHTML = displayRows.map(row => {
    const isOpen = openHosts.has(row.Target);
    const transport = row.TransportUsed || '';
    const identityStatus = row.IdentityStatus || '';

    const identityBadgeClass = /collected/i.test(identityStatus) ? 'badge-success' :
                                /unreachable/i.test(identityStatus) ? 'badge-error' :
                                /needsapproved/i.test(identityStatus) ? 'badge-warning' : 'badge-muted';

    const pingStep = pingToStep(row.PingStatus || '');
    const pingClass = pingStep === 'success' ? 'badge-success' : pingStep === 'failed' ? 'badge-error' : 'badge-muted';

    const ladderHtml = PROTOCOL_STEPS.map(step => {
      const status = getStepStatus(row, step);
      const cls = stepBadgeClass(status);
      const portVal = step.port ? ((row.ports || {})[step.port] || '') : '';
      const title = portVal ? `${step.label}: ${portVal}` : step.label;
      return `<div class="proto-step ${cls}" title="${sanitize(title)}">
        <div class="proto-dot"></div>
        ${sanitize(step.label)}
      </div>`;
    }).join('');

    const metaHtml = [
      ['Resolved IP', row.ResolvedAddress],
      ['DNS Name', row.DnsName],
      ['Ping', row.PingStatus],
      ['Observed Host', row.ObservedHostName],
      ['Serial', row.ObservedSerial],
      ['MACs', row.ObservedMACs],
      ['SMB Recon', row.SmbRecon],
      ['Timestamp', row.Timestamp],
      ['Notes', row.Notes],
    ].filter(([, v]) => v).map(([k, v]) =>
      `<div class="protocol-meta-row">
        <span class="meta-key">${sanitize(k)}</span>
        <span class="meta-val">${sanitize(v)}</span>
      </div>`
    ).join('');

    return `
      <div class="protocol-accordion">
        <div class="protocol-row-header ${isOpen ? 'open' : ''}" data-host="${sanitize(row.Target)}">
          <span class="protocol-toggle">▶</span>
          <span class="protocol-host">${sanitize(row.Target)}</span>
          <div class="protocol-badges">
            <span class="badge ${pingClass}">${sanitize(row.PingStatus || 'NoPing')}</span>
            ${transport ? `<span class="badge badge-accent" title="Transport Used">🔌 ${sanitize(transport)}</span>` : ''}
            ${identityStatus ? `<span class="badge ${identityBadgeClass}">${sanitize(identityStatus)}</span>` : ''}
            ${row.ResolvedAddress ? `<span class="badge badge-muted mono">${sanitize(row.ResolvedAddress)}</span>` : ''}
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
    </div>
    <div class="table-wrapper" id="net-accordion"></div>`;
}
