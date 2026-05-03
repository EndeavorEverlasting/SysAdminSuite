// panel-inventory.js — Hardware Inventory Panel

import { sanitize, statusBadge, exportToCSV, sortRows, filterRows, makeSortable, debounce } from './utils.js';
import { buildInventoryRows } from './parsers.js';

let allRows = [];
let displayRows = [];
let sortKey = 'HostName';
let sortDir = 'asc';
let searchQuery = '';
let expandedHosts = new Set();

export function renderInventoryPanel(store) {
  allRows = buildInventoryRows(store);
  displayRows = allRows;
  applyFilters();
  renderTable();
  renderSummary(store);
}

export function initInventoryPanel() {
  const search = document.getElementById('inv-search');
  if (search) {
    search.addEventListener('input', debounce(() => {
      searchQuery = search.value;
      applyFilters();
      renderTable();
    }, 200));
  }

  const exportBtn = document.getElementById('inv-export');
  if (exportBtn) {
    exportBtn.addEventListener('click', () => {
      const flat = displayRows.map(r => ({
        HostName: r.HostName || '',
        Serial: r.Serial || '',
        MACAddress: r.MACAddress || '',
        IPAddress: r.IPAddress || '',
        Model: r.Model || '',
        Manufacturer: r.Manufacturer || '',
        RAMTotal: r.RAMTotal || '',
        RAMSpeed: r.RAMSpeed || '',
        RAMType: r.RAMType || '',
        MonitorSerials: r.MonitorSerials || '',
        Status: r.Status || '',
        Site: r.Site || '',
        Room: r.Room || ''
      }));
      exportToCSV(flat, 'hardware-inventory.csv');
    });
  }

  const tableEl = document.getElementById('inv-table');
  if (tableEl) {
    makeSortable(tableEl, (col, dir) => {
      sortKey = col;
      sortDir = dir;
      displayRows = sortRows(displayRows, sortKey, sortDir);
      renderTable();
    });
  }
}

function applyFilters() {
  let rows = allRows;
  if (searchQuery) {
    rows = filterRows(rows, ['HostName', 'Serial', 'MACAddress', 'IPAddress', 'Model', 'Manufacturer', 'Status', 'Site', 'Room'], searchQuery);
  }
  displayRows = sortRows(rows, sortKey, sortDir);
}

function renderSummary(store) {
  const el = document.getElementById('inv-summary');
  if (!el) return;

  const total = allRows.length;
  const ok = allRows.filter(r => /ok|online/i.test(r.Status)).length;
  const offline = allRows.filter(r => /offline/i.test(r.Status)).length;
  const failed = allRows.filter(r => /fail|error/i.test(r.Status)).length;
  const withRam = allRows.filter(r => r.RAMTotal).length;

  el.innerHTML = `
    <div class="stat-chip stat-info">
      <span class="stat-num">${total}</span>
      <span class="stat-label">Hosts</span>
    </div>
    <div class="stat-chip stat-success">
      <span class="stat-num">${ok}</span>
      <span class="stat-label">Online</span>
    </div>
    <div class="stat-chip stat-error">
      <span class="stat-num">${offline + failed}</span>
      <span class="stat-label">Offline / Failed</span>
    </div>
    <div class="stat-chip stat-info">
      <span class="stat-num">${withRam}</span>
      <span class="stat-label">With RAM Data</span>
    </div>
  `;
}

function renderTable() {
  const tbody = document.querySelector('#inv-table tbody');
  if (!tbody) return;

  const badge = document.querySelector('[data-tab="inventory"] .tab-badge');
  if (badge) badge.textContent = allRows.length;

  if (!displayRows.length) {
    tbody.innerHTML = `
      <tr><td colspan="9">
        <div class="empty-state">
          <div class="empty-icon">🖥️</div>
          <div class="empty-msg">${allRows.length ? 'No rows match your filters.' : 'No hardware inventory data loaded.'}</div>
          <div class="empty-sub">${allRows.length ? '' : 'Load MachineInfo_Output.csv, RamInfo_Output.csv, or NeuronNetworkInventory CSV/JSON.'}</div>
        </div>
      </td></tr>`;
    return;
  }

  tbody.innerHTML = displayRows.map(row => {
    const isExpanded = expandedHosts.has(row.HostName);
    const hasDetail = row.RAMTotal || row.MonitorSerials || row._ramSticks || row.Manufacturer;
    const expandBtn = hasDetail
      ? `<span class="expand-toggle" data-host="${sanitize(row.HostName)}" style="cursor:pointer;user-select:none;margin-right:6px;color:var(--text-muted)">${isExpanded ? '▼' : '▶'}</span>`
      : '<span style="margin-right:16px"></span>';

    const mac = (row.MACAddress || '').split(';').filter(Boolean)[0] || '—';
    const ip  = (row.IPAddress || '').split(';').filter(Boolean)[0] || '—';
    const monitors = (row.MonitorSerials || '').split(';').filter(Boolean);
    const monDisplay = monitors.length ? monitors.length + ' monitor' + (monitors.length > 1 ? 's' : '') : '—';

    let detailRow = '';
    if (isExpanded && hasDetail) {
      const sticks = row._ramSticks || [];
      const sticksHtml = sticks.map(s =>
        `<div class="inv-detail-kv"><span class="inv-detail-k">${sanitize(s.DeviceLocator || s.BankLabel || 'Stick')}</span><span class="inv-detail-v">${sanitize(s.CapacityGB || '')}GB ${sanitize(s.MemoryType || '')} ${sanitize(s.Speed || '')}MHz ${sanitize(s.Manufacturer || '')}</span></div>`
      ).join('');

      detailRow = `<tr class="inv-expand-row">
        <td colspan="9">
          <div class="inv-detail">
            ${row.Manufacturer ? `<div class="inv-detail-kv"><span class="inv-detail-k">Manufacturer</span><span class="inv-detail-v">${sanitize(row.Manufacturer)}</span></div>` : ''}
            ${row.Model ? `<div class="inv-detail-kv"><span class="inv-detail-k">Model</span><span class="inv-detail-v">${sanitize(row.Model)}</span></div>` : ''}
            ${row.UUID ? `<div class="inv-detail-kv"><span class="inv-detail-k">UUID</span><span class="inv-detail-v">${sanitize(row.UUID)}</span></div>` : ''}
            ${(row.MACAddress || '').split(';').filter(Boolean).map(m => `<div class="inv-detail-kv"><span class="inv-detail-k">MAC</span><span class="inv-detail-v">${sanitize(m)}</span></div>`).join('')}
            ${(row.IPAddress || '').split(';').filter(Boolean).map(i => `<div class="inv-detail-kv"><span class="inv-detail-k">IP</span><span class="inv-detail-v">${sanitize(i)}</span></div>`).join('')}
            ${row.RAMTotal ? `<div class="inv-detail-kv"><span class="inv-detail-k">RAM Total</span><span class="inv-detail-v">${sanitize(row.RAMTotal)} ${sanitize(row.RAMType || '')} @ ${sanitize(row.RAMSpeed || '')}</span></div>` : ''}
            ${sticksHtml}
            ${monitors.map(m => `<div class="inv-detail-kv"><span class="inv-detail-k">Monitor S/N</span><span class="inv-detail-v">${sanitize(m)}</span></div>`).join('')}
            ${row.Site ? `<div class="inv-detail-kv"><span class="inv-detail-k">Site</span><span class="inv-detail-v">${sanitize(row.Site)}</span></div>` : ''}
            ${row.Room ? `<div class="inv-detail-kv"><span class="inv-detail-k">Room</span><span class="inv-detail-v">${sanitize(row.Room)}</span></div>` : ''}
          </div>
        </td>
      </tr>`;
    }

    return `<tr class="inv-host-row" data-host="${sanitize(row.HostName)}">
      <td class="mono">${expandBtn}${sanitize(row.HostName || '—')}</td>
      <td class="mono">${sanitize(row.Serial || '—')}</td>
      <td class="mono">${sanitize(mac)}</td>
      <td class="mono">${sanitize(ip)}</td>
      <td>${sanitize(row.RAMTotal || '—')}</td>
      <td class="mono">${sanitize(row.RAMSpeed || '—')}</td>
      <td>${sanitize(monDisplay)}</td>
      <td>${sanitize(row.Model || row.Manufacturer || '—')}</td>
      <td>${statusBadge(row.Status || '—')}</td>
    </tr>${detailRow}`;
  }).join('');

  // Bind expand toggles
  tbody.querySelectorAll('.expand-toggle').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const host = btn.dataset.host;
      if (expandedHosts.has(host)) expandedHosts.delete(host);
      else expandedHosts.add(host);
      renderTable();
    });
  });
}

export function getInventoryHTML() {
  return `
    <div id="inv-summary" class="summary-row"></div>
    <div class="panel-toolbar">
      <span class="panel-title">Hardware Inventory</span>
      <div class="toolbar-sep"></div>
      <input class="search-box" id="inv-search" placeholder="Search hostname, serial, MAC, IP…" type="text">
      <button class="icon-btn" id="inv-export">⬇ Export CSV</button>
    </div>
    <div class="table-wrapper">
      <table id="inv-table">
        <thead>
          <tr>
            <th data-col="HostName">Host Name</th>
            <th data-col="Serial">Serial #</th>
            <th data-col="MACAddress">MAC Address</th>
            <th data-col="IPAddress">IP Address</th>
            <th data-col="RAMTotal">RAM</th>
            <th data-col="RAMSpeed">Speed</th>
            <th>Monitors</th>
            <th data-col="Model">Model</th>
            <th data-col="Status">Status</th>
          </tr>
        </thead>
        <tbody></tbody>
      </table>
    </div>`;
}
