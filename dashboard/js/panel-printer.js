// panel-printer.js — Printer Mapping Panel

import { sanitize, statusBadge, exportToCSV, sortRows, filterRows, makeSortable, debounce } from './utils.js';
import { buildPrinterRows } from './parsers.js';

let allRows = [];
let displayRows = [];
let sortKey = 'ComputerName';
let sortDir = 'asc';
let searchQuery = '';
let filterStatus = '';

export function renderPrinterPanel(store) {
  allRows = buildPrinterRows(store);
  displayRows = allRows;
  applyFilters();
  renderTable();
  renderSummary();
}

export function initPrinterPanel() {
  const search = document.getElementById('printer-search');
  const statusFilter = document.getElementById('printer-status-filter');

  if (search) {
    search.addEventListener('input', debounce(() => {
      searchQuery = search.value;
      applyFilters();
      renderTable();
    }, 200));
  }

  if (statusFilter) {
    statusFilter.addEventListener('change', () => {
      filterStatus = statusFilter.value;
      applyFilters();
      renderTable();
    });
  }

  const exportBtn = document.getElementById('printer-export');
  if (exportBtn) {
    exportBtn.addEventListener('click', () => {
      exportToCSV(displayRows, 'printer-mapping.csv');
    });
  }

  const tableEl = document.getElementById('printer-table');
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
    rows = filterRows(rows, ['ComputerName', 'Target', 'Driver', 'Port', 'Status', 'MAC', 'Serial'], searchQuery);
  }
  if (filterStatus) {
    rows = rows.filter(r => (r.Status || '').toLowerCase().includes(filterStatus.toLowerCase()));
  }
  displayRows = sortRows(rows, sortKey, sortDir);
}

function renderSummary() {
  const total = allRows.length;
  const success = allRows.filter(r => /ok|success|added|present|mapped/i.test(r.Status)).length;
  const failed = allRows.filter(r => /fail|error|offline|denied/i.test(r.Status)).length;
  const pending = allRows.filter(r => /plan|pending|notpresent/i.test(r.Status)).length;

  const el = document.getElementById('printer-summary');
  if (!el) return;

  el.innerHTML = `
    <div class="stat-chip stat-info">
      <span class="stat-num">${total}</span>
      <span class="stat-label">Total</span>
    </div>
    <div class="stat-chip stat-success">
      <span class="stat-num">${success}</span>
      <span class="stat-label">Mapped / OK</span>
    </div>
    <div class="stat-chip stat-error">
      <span class="stat-num">${failed}</span>
      <span class="stat-label">Failed</span>
    </div>
    <div class="stat-chip stat-warning">
      <span class="stat-num">${pending}</span>
      <span class="stat-label">Planned / Pending</span>
    </div>
  `;
}

function renderTable() {
  const tbody = document.querySelector('#printer-table tbody');
  if (!tbody) return;

  // Update badge count
  const badge = document.querySelector('[data-tab="printer"] .tab-badge');
  if (badge) badge.textContent = allRows.length;

  if (!displayRows.length) {
    tbody.innerHTML = `
      <tr><td colspan="8">
        <div class="empty-state">
          <div class="empty-icon">🖨️</div>
          <div class="empty-msg">${allRows.length ? 'No rows match your filters.' : 'No printer mapping data loaded.'}</div>
          <div class="empty-sub">${allRows.length ? '' : 'Load Preflight.csv, Results.csv, or printer_probe.csv files.'}</div>
        </div>
      </td></tr>`;
    return;
  }

  tbody.innerHTML = displayRows.map(row => {
    const source = row.Source === 'printer-probe' ? 'Probe' : (row.Source || '');
    const sourceClass = source === 'Probe' ? 'badge-info' : 'badge-muted';
    return `<tr>
      <td class="mono">${sanitize(row.ComputerName || row.Target || '—')}</td>
      <td class="mono">${sanitize(row.Target || '—')}</td>
      <td>${sanitize(row.Type || '—')}</td>
      <td>${sanitize(row.Driver || '—')}</td>
      <td class="mono">${sanitize(row.Port || row.MAC || '—')}</td>
      <td>${statusBadge(row.Status)}</td>
      <td>${sanitize(row.PreflightNotes || row.Notes || '—')}</td>
      <td><span class="badge ${sourceClass}">${sanitize(source || '—')}</span></td>
    </tr>`;
  }).join('');
}

export function getPrinterHTML() {
  return `
    <div id="printer-summary" class="summary-row"></div>
    <div class="panel-toolbar">
      <span class="panel-title">Printer Mapping</span>
      <div class="toolbar-sep"></div>
      <input class="search-box" id="printer-search" placeholder="Search machines, targets, drivers…" type="text">
      <select class="filter-select" id="printer-status-filter">
        <option value="">All Statuses</option>
        <option value="Present">Present</option>
        <option value="Added">Added</option>
        <option value="Removed">Removed</option>
        <option value="Plan">Planned</option>
        <option value="Fail">Failed</option>
        <option value="Error">Error</option>
        <option value="Offline">Offline</option>
      </select>
      <button class="icon-btn" id="printer-export">⬇ Export CSV</button>
    </div>
    <div class="table-wrapper">
      <table id="printer-table">
        <thead>
          <tr>
            <th data-col="ComputerName">Computer</th>
            <th data-col="Target">Target / Queue</th>
            <th data-col="Type">Type</th>
            <th data-col="Driver">Driver</th>
            <th data-col="Port">Port / MAC</th>
            <th data-col="Status">Status</th>
            <th data-col="Notes">Notes</th>
            <th data-col="Source">Source</th>
          </tr>
        </thead>
        <tbody></tbody>
      </table>
    </div>`;
}
