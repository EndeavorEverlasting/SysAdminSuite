// panel-tasks.js — Remote Task / QR Activity Panel

import { sanitize, statusBadge, exportToCSV, sortRows, filterRows, makeSortable, debounce, formatTimestamp } from './utils.js';

let allRows = [];
let displayRows = [];
let sortKey = 'Timestamp';
let sortDir = 'desc';
let searchQuery = '';
let filterStatus = '';

export function renderTasksPanel(store) {
  allRows = buildTaskRows(store);
  applyFilters();
  renderTable();
  renderSummary();
}

function buildTaskRows(store) {
  const rows = [];

  for (const row of (store.remoteTasks || [])) {
    // Normalize field names from various possible log formats
    rows.push({
      Timestamp: row.Timestamp || row.timestamp || row.Date || row.date || '',
      Machine: row.ComputerName || row.Machine || row.Target || row.TargetMachine || row.HostName || '',
      TaskName: row.TaskName || row.Name || row.Task || row.TechTask || row.Action || '',
      TaskId: row.TaskId || row.Id || row.QRCode || '',
      Outcome: row.Outcome || row.Status || row.Result || row.State || '',
      Operator: row.Operator || row.User || row.RunAs || '',
      Duration: row.Duration || row.DurationMs || '',
      Notes: row.Notes || row.ErrorMessage || row.Message || '',
      Source: 'remote-task'
    });
  }

  // Also pull from statusJson if available
  // (RunControl status may contain task trace)
  return rows;
}

export function initTasksPanel() {
  const search = document.getElementById('tasks-search');
  if (search) {
    search.addEventListener('input', debounce(() => {
      searchQuery = search.value;
      applyFilters();
      renderTable();
    }, 200));
  }

  const statusFilter = document.getElementById('tasks-status-filter');
  if (statusFilter) {
    statusFilter.addEventListener('change', () => {
      filterStatus = statusFilter.value;
      applyFilters();
      renderTable();
    });
  }

  const exportBtn = document.getElementById('tasks-export');
  if (exportBtn) {
    exportBtn.addEventListener('click', () => {
      exportToCSV(displayRows, 'remote-tasks.csv');
    });
  }

  const tableEl = document.getElementById('tasks-table');
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
    rows = filterRows(rows, ['Machine', 'TaskName', 'TaskId', 'Outcome', 'Operator', 'Notes'], searchQuery);
  }
  if (filterStatus) {
    rows = rows.filter(r => (r.Outcome || '').toLowerCase().includes(filterStatus.toLowerCase()));
  }
  displayRows = sortRows(rows, sortKey, sortDir);
}

function renderSummary() {
  const el = document.getElementById('tasks-summary');
  if (!el) return;

  const total = allRows.length;
  const success = allRows.filter(r => /ok|success|complete|done/i.test(r.Outcome)).length;
  const failed = allRows.filter(r => /fail|error/i.test(r.Outcome)).length;
  const machines = new Set(allRows.map(r => r.Machine).filter(Boolean)).size;

  el.innerHTML = `
    <div class="stat-chip stat-info">
      <span class="stat-num">${total}</span>
      <span class="stat-label">Total Tasks</span>
    </div>
    <div class="stat-chip stat-success">
      <span class="stat-num">${success}</span>
      <span class="stat-label">Succeeded</span>
    </div>
    <div class="stat-chip stat-error">
      <span class="stat-num">${failed}</span>
      <span class="stat-label">Failed</span>
    </div>
    <div class="stat-chip stat-info">
      <span class="stat-num">${machines}</span>
      <span class="stat-label">Machines</span>
    </div>
  `;
}

function renderTable() {
  const tbody = document.querySelector('#tasks-table tbody');
  if (!tbody) return;

  const badge = document.querySelector('[data-tab="tasks"] .tab-badge');
  if (badge) badge.textContent = allRows.length;

  if (!displayRows.length) {
    tbody.innerHTML = `
      <tr><td colspan="7">
        <div class="empty-state">
          <div class="empty-icon">⚡</div>
          <div class="empty-msg">${allRows.length ? 'No rows match your filters.' : 'No remote task or QR activity data loaded.'}</div>
          <div class="empty-sub">${allRows.length ? '' : 'Load QRTask logs or RunControl output files to populate this panel.'}</div>
        </div>
      </td></tr>`;
    return;
  }

  tbody.innerHTML = displayRows.map(row => `
    <tr>
      <td class="mono">${sanitize(formatTimestamp(row.Timestamp))}</td>
      <td class="mono">${sanitize(row.Machine || '—')}</td>
      <td>${sanitize(row.TaskName || '—')}</td>
      <td class="mono">${sanitize(row.TaskId || '—')}</td>
      <td>${statusBadge(row.Outcome || '—')}</td>
      <td>${sanitize(row.Operator || '—')}</td>
      <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis" title="${sanitize(row.Notes)}">${sanitize(row.Notes || '—')}</td>
    </tr>
  `).join('');
}

export function getTasksHTML() {
  return `
    <div id="tasks-summary" class="summary-row"></div>
    <div class="panel-toolbar">
      <span class="panel-title">Remote Task / QR Activity</span>
      <div class="toolbar-sep"></div>
      <input class="search-box" id="tasks-search" placeholder="Search machine, task, outcome…" type="text">
      <select class="filter-select" id="tasks-status-filter">
        <option value="">All Outcomes</option>
        <option value="success">Success</option>
        <option value="fail">Failed</option>
        <option value="error">Error</option>
        <option value="complete">Complete</option>
      </select>
      <button class="icon-btn" id="tasks-export">⬇ Export CSV</button>
    </div>
    <div class="table-wrapper">
      <table id="tasks-table">
        <thead>
          <tr>
            <th data-col="Timestamp">Timestamp</th>
            <th data-col="Machine">Machine</th>
            <th data-col="TaskName">Task Name</th>
            <th data-col="TaskId">Task ID / QR</th>
            <th data-col="Outcome">Outcome</th>
            <th data-col="Operator">Operator</th>
            <th>Notes</th>
          </tr>
        </thead>
        <tbody></tbody>
      </table>
    </div>`;
}
