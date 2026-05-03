// panel-software.js — SysAdmin Suite Software Tracker panel
// Renders Config/sources.yaml data as a searchable, sortable table.
// Data arrives as an array of app objects parsed from YAML (via sas-list-apps --json
// or drag-dropped sources.yaml parsed client-side).

import { sanitize, toast } from './utils.js';

// ── HTML skeleton ────────────────────────────────────────────────────────────
export function getSoftwareHTML() {
  return `
<div class="panel-section">
  <div class="section-header">
    <span class="section-title">📦 Software Tracker</span>
    <div class="section-controls" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
      <input type="text" id="sw-search" placeholder="Search apps…"
        style="padding:5px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:5px;color:var(--text);font-size:12px;font-family:var(--mono);outline:none;width:180px">
      <select id="sw-list-filter"
        style="padding:5px 8px;background:var(--bg3);border:1px solid var(--border);border-radius:5px;color:var(--text);font-size:12px;outline:none">
        <option value="">All lists</option>
      </select>
      <select id="sw-type-filter"
        style="padding:5px 8px;background:var(--bg3);border:1px solid var(--border);border-radius:5px;color:var(--text);font-size:12px;outline:none">
        <option value="">All types</option>
        <option value="msi">MSI</option>
        <option value="exe">EXE</option>
        <option value="zip">ZIP</option>
        <option value="msix">MSIX</option>
      </select>
      <label style="font-size:11px;color:var(--text-dim);display:flex;align-items:center;gap:4px;cursor:pointer">
        <input type="checkbox" id="sw-unmanaged-only" style="cursor:pointer">
        Unmanaged only
      </label>
      <button class="icon-btn" id="sw-copy-json" title="Copy all apps as JSON">📋 JSON</button>
    </div>
  </div>

  <div id="sw-stats" style="padding:6px 0 2px;font-size:11px;color:var(--text-muted)"></div>

  <div style="overflow-x:auto;margin-top:6px">
    <table class="data-table" id="sw-table">
      <thead>
        <tr>
          <th class="sortable" data-col="name">Name <span class="sort-icon">↕</span></th>
          <th class="sortable" data-col="source">Source <span class="sort-icon">↕</span></th>
          <th class="sortable" data-col="strategy">Strategy <span class="sort-icon">↕</span></th>
          <th class="sortable" data-col="version">Version <span class="sort-icon">↕</span></th>
          <th class="sortable" data-col="type">Type <span class="sort-icon">↕</span></th>
          <th class="sortable" data-col="detect_type">Detect <span class="sort-icon">↕</span></th>
          <th>Detect Value</th>
          <th class="sortable" data-col="unmanaged">Managed <span class="sort-icon">↕</span></th>
        </tr>
      </thead>
      <tbody id="sw-tbody"></tbody>
    </table>
  </div>

  <div id="sw-empty" class="empty-state" style="display:none">
    <div class="empty-icon">📦</div>
    <div class="empty-title">No software tracker data loaded</div>
    <div class="empty-desc">
      Drop <code>sources.yaml</code> or a JSON export from
      <code>sas-list-apps.sh --json</code> into the dashboard to populate this panel.
    </div>
  </div>
</div>
`;
}

// ── State ────────────────────────────────────────────────────────────────────
let _apps = [];
let _lists = {};
let _sortCol = 'name';
let _sortDir = 1; // 1 = asc, -1 = desc

// ── Init ─────────────────────────────────────────────────────────────────────
export function initSoftwarePanel() {
  const search = document.getElementById('sw-search');
  const listFilter = document.getElementById('sw-list-filter');
  const typeFilter = document.getElementById('sw-type-filter');
  const unmanagedOnly = document.getElementById('sw-unmanaged-only');
  const copyBtn = document.getElementById('sw-copy-json');

  if (search) search.addEventListener('input', renderTable);
  if (listFilter) listFilter.addEventListener('change', renderTable);
  if (typeFilter) typeFilter.addEventListener('change', renderTable);
  if (unmanagedOnly) unmanagedOnly.addEventListener('change', renderTable);

  if (copyBtn) {
    copyBtn.addEventListener('click', () => {
      const json = JSON.stringify(_apps, null, 2);
      navigator.clipboard?.writeText(json)
        .then(() => toast('Apps JSON copied!', 'success'))
        .catch(() => toast('Select and copy manually.', 'warning'));
    });
  }

  // Column sort
  document.querySelectorAll('#sw-table th.sortable').forEach(th => {
    th.style.cursor = 'pointer';
    th.addEventListener('click', () => {
      const col = th.dataset.col;
      if (_sortCol === col) {
        _sortDir *= -1;
      } else {
        _sortCol = col;
        _sortDir = 1;
      }
      document.querySelectorAll('#sw-table th .sort-icon').forEach(i => i.textContent = '↕');
      const icon = th.querySelector('.sort-icon');
      if (icon) icon.textContent = _sortDir === 1 ? '↑' : '↓';
      renderTable();
    });
  });
}

// ── Render ───────────────────────────────────────────────────────────────────
export function renderSoftwarePanel(store) {
  if (store.software) {
    _apps  = store.software.apps  || [];
    _lists = store.software.lists || {};
    populateListDropdown();
  }
  renderTable();
}

function populateListDropdown() {
  const sel = document.getElementById('sw-list-filter');
  if (!sel) return;
  const current = sel.value;
  // Clear existing dynamic options (keep "All lists")
  while (sel.options.length > 1) sel.remove(1);
  Object.keys(_lists).forEach(name => {
    const opt = document.createElement('option');
    opt.value = name;
    opt.textContent = `${name} (${_lists[name].length})`;
    sel.appendChild(opt);
  });
  if (current && sel.querySelector(`option[value="${current}"]`)) {
    sel.value = current;
  }
}

function getFiltered() {
  const q = (document.getElementById('sw-search')?.value || '').toLowerCase();
  const listFilter = document.getElementById('sw-list-filter')?.value || '';
  const typeFilter = document.getElementById('sw-type-filter')?.value || '';
  const unmanagedOnly = document.getElementById('sw-unmanaged-only')?.checked || false;

  let filtered = [..._apps];

  if (listFilter && _lists[listFilter]) {
    const wanted = new Set(_lists[listFilter].map(n => n.toLowerCase()));
    filtered = filtered.filter(a => wanted.has((a.name || '').toLowerCase()));
  }

  if (typeFilter) {
    filtered = filtered.filter(a => (a.type || '').toLowerCase() === typeFilter);
  }

  if (unmanagedOnly) {
    filtered = filtered.filter(a => a.unmanaged === true || a.unmanaged === 'true');
  }

  if (q) {
    filtered = filtered.filter(a =>
      (a.name || '').toLowerCase().includes(q) ||
      (a.detect_value || '').toLowerCase().includes(q) ||
      (a.repo || '').toLowerCase().includes(q)
    );
  }

  // Sort
  filtered.sort((a, b) => {
    const av = String(a[_sortCol] || '').toLowerCase();
    const bv = String(b[_sortCol] || '').toLowerCase();
    if (_sortCol === 'unmanaged') {
      // unmanaged:true sorts last when ascending
      const au = a.unmanaged === true || a.unmanaged === 'true' ? 1 : 0;
      const bu = b.unmanaged === true || b.unmanaged === 'true' ? 1 : 0;
      return (au - bu) * _sortDir;
    }
    return av < bv ? -_sortDir : av > bv ? _sortDir : 0;
  });

  return filtered;
}

function renderTable() {
  const tbody = document.getElementById('sw-tbody');
  const empty = document.getElementById('sw-empty');
  const stats = document.getElementById('sw-stats');

  if (!tbody) return;

  if (_apps.length === 0) {
    tbody.innerHTML = '';
    if (empty) empty.style.display = '';
    if (stats) stats.textContent = '';
    return;
  }

  if (empty) empty.style.display = 'none';

  const filtered = getFiltered();
  const unmanagedCount = filtered.filter(a => a.unmanaged === true || a.unmanaged === 'true').length;

  if (stats) {
    stats.textContent = `${filtered.length} of ${_apps.length} app(s)` +
      (unmanagedCount ? ` — ${unmanagedCount} unmanaged` : '');
  }

  if (filtered.length === 0) {
    tbody.innerHTML = `<tr><td colspan="8" style="text-align:center;color:var(--text-muted);padding:20px">No apps match the current filters.</td></tr>`;
    return;
  }

  tbody.innerHTML = filtered.map(a => {
    const unmanaged = a.unmanaged === true || a.unmanaged === 'true';
    const rowClass = unmanaged ? 'style="background:rgba(245,158,11,0.06)"' : '';
    const managedBadge = unmanaged
      ? `<span style="color:var(--warning);font-weight:600">⚠ Unmanaged</span>`
      : `<span style="color:var(--success)">✓ Managed</span>`;
    const stratBadge = a.strategy === 'latest'
      ? `<span class="badge badge-info">latest</span>`
      : `<span class="badge badge-muted">pinned</span>`;
    const sourceBadge = a.source === 'github'
      ? `<span class="badge badge-purple">GitHub</span>`
      : `<span class="badge badge-blue">URL</span>`;
    const typeBadge = a.type
      ? `<code style="font-size:10px">${sanitize(a.type.toUpperCase())}</code>`
      : '';
    const detectVal = a.detect_value ? sanitize(
      a.detect_value.length > 48
        ? a.detect_value.slice(0, 46) + '…'
        : a.detect_value
    ) : '<span style="color:var(--text-muted)">—</span>';
    const ver = a.version
      ? sanitize(a.version)
      : '<span style="color:var(--text-muted)">latest</span>';

    return `<tr ${rowClass}>
      <td style="font-weight:500">${sanitize(a.name || '')}</td>
      <td>${sourceBadge}</td>
      <td>${stratBadge}</td>
      <td style="font-family:var(--mono);font-size:11px">${ver}</td>
      <td>${typeBadge}</td>
      <td style="font-size:11px;color:var(--text-dim)">${sanitize(a.detect_type || '—')}</td>
      <td style="font-family:var(--mono);font-size:10px;max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${sanitize(a.detect_value || '')}">${detectVal}</td>
      <td>${managedBadge}</td>
    </tr>`;
  }).join('');
}
