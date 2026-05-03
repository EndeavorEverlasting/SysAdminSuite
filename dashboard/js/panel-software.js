// panel-software.js — SysAdmin Suite Software Tracker panel
// Renders Config/sources.yaml data as a searchable, sortable table.
// Also accepts software_superset.csv (from Inventory-Software.ps1 / sas-populate-tracker.sh)
// to cross-reference catalog vs installed state per host, highlighting partial deployments,
// missing apps, and unmanaged software discovered on hosts but not yet in the catalog.

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
      <select id="sw-status-filter"
        style="padding:5px 8px;background:var(--bg3);border:1px solid var(--border);border-radius:5px;color:var(--text);font-size:12px;outline:none">
        <option value="">All statuses</option>
        <option value="installed">Installed (all hosts)</option>
        <option value="partial">Partial (some hosts)</option>
        <option value="missing">Missing (no hosts)</option>
        <option value="unmanaged">Unmanaged</option>
      </select>
      <button class="icon-btn" id="sw-export-gap" title="Export per-host gap report as CSV">📤 Gap Report</button>
      <button class="icon-btn" id="sw-copy-json" title="Copy all catalog apps as JSON">📋 JSON</button>
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
          <th class="sortable" data-col="_hostCount">Installed on <span class="sort-icon">↕</span></th>
          <th class="sortable" data-col="_installStatus">Install Status <span class="sort-icon">↕</span></th>
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
      <code>sas-list-apps.sh --json</code> into the dashboard to populate this panel.<br>
      For per-host gap analysis, drop <code>software_hosts.csv</code> or one or more
      <code>installed_software_&lt;HOST&gt;.csv</code> files produced by
      <code>Inventory-Software.ps1</code> (one row per app per host).
      <code>software_superset.csv</code> is deduplicated (one row per app) and gives only
      a summary view — drop <code>software_hosts.csv</code> for full host-level tracking.
    </div>
  </div>
</div>
`;
}

// ── State ────────────────────────────────────────────────────────────────────
let _apps = [];                 // catalog apps from sources.yaml
let _lists = {};                // named lists from sources.yaml
let _inventory = [];            // rows from software_superset.csv {Name, Host, ...}
let _inventoryIndex = {};       // lowerName -> Set<host>
let _hostUniverse = new Set();  // all unique hosts seen in inventory
let _inventoryOnlyApps = [];    // apps seen in inventory but absent from catalog
let _sortCol = 'name';
let _sortDir = 1; // 1 = asc, -1 = desc

// ── Init ─────────────────────────────────────────────────────────────────────
export function initSoftwarePanel() {
  const search       = document.getElementById('sw-search');
  const listFilter   = document.getElementById('sw-list-filter');
  const typeFilter   = document.getElementById('sw-type-filter');
  const statusFilter = document.getElementById('sw-status-filter');
  const copyBtn      = document.getElementById('sw-copy-json');
  const exportBtn    = document.getElementById('sw-export-gap');

  if (search)       search.addEventListener('input', renderTable);
  if (listFilter)   listFilter.addEventListener('change', renderTable);
  if (typeFilter)   typeFilter.addEventListener('change', renderTable);
  if (statusFilter) statusFilter.addEventListener('change', renderTable);

  if (copyBtn) {
    copyBtn.addEventListener('click', () => {
      const json = JSON.stringify(_apps, null, 2);
      navigator.clipboard?.writeText(json)
        .then(() => toast('Apps JSON copied!', 'success'))
        .catch(() => toast('Select and copy manually.', 'warning'));
    });
  }

  if (exportBtn) {
    exportBtn.addEventListener('click', exportGapReport);
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
  _apps      = store.software?.apps  || [];
  _lists     = store.software?.lists || {};
  _inventory = store.softwareInventory || [];

  // Warn when the inventory looks deduplicated (one unique host per app on average),
  // which happens when software_superset.csv (not software_hosts.csv) is dropped.
  if (_inventory.length > 0) {
    const uniqueHosts = new Set(_inventory.map(r => (r.Host || r.host || '').trim()).filter(Boolean));
    const uniqueNames = new Set(_inventory.map(r => (r.Name || r.name || '').trim().toLowerCase()).filter(Boolean));
    // If every app appears on exactly one host, it's very likely a deduplicated superset
    const avgHostsPerApp = uniqueNames.size > 0 ? _inventory.length / uniqueNames.size : 0;
    if (uniqueHosts.size <= 1 && uniqueNames.size > 4 && Math.round(avgHostsPerApp) <= 1) {
      toast(
        'Inventory looks deduplicated (software_superset.csv). Drop software_hosts.csv for accurate per-host gap analysis.',
        'warning'
      );
    }
  }

  // Build host universe and per-name index from inventory rows
  _inventoryIndex = {};
  _hostUniverse   = new Set();
  for (const row of _inventory) {
    const name = (row.Name || row.name || '').trim().toLowerCase();
    const host = (row.Host || row.host || '').trim();
    if (host) _hostUniverse.add(host);
    if (!name) continue;
    if (!_inventoryIndex[name]) _inventoryIndex[name] = new Set();
    if (host) _inventoryIndex[name].add(host);
  }

  // Build inventory-only apps: names found in inventory but not in catalog
  const catalogNames = new Set(_apps.map(a => (a.name || '').toLowerCase()));
  const seenInventoryOnly = new Set();
  _inventoryOnlyApps = [];
  for (const row of _inventory) {
    const name = (row.Name || row.name || '').trim();
    const lower = name.toLowerCase();
    if (!lower || catalogNames.has(lower) || seenInventoryOnly.has(lower)) continue;
    seenInventoryOnly.add(lower);
    _inventoryOnlyApps.push({
      name,
      source:        '—',
      strategy:      '—',
      version:       row.Version || row.version || '',
      type:          '—',
      detect_type:   row.DetectType  || row.detect_type  || '',
      detect_value:  row.DetectValue || row.detect_value || '',
      unmanaged:     true,
      _inventoryOnly: true,
    });
  }

  populateListDropdown();
  renderTable();
}

function populateListDropdown() {
  const sel = document.getElementById('sw-list-filter');
  if (!sel) return;
  const current = sel.value;
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

// ── Install-status helpers ────────────────────────────────────────────────────
// Returns: 'installed' | 'partial' | 'missing' | 'unmanaged' | null
function getInstallStatus(app) {
  const unmanaged = app.unmanaged === true || app.unmanaged === 'true';

  if (_inventory.length === 0) {
    return unmanaged ? 'unmanaged' : null;
  }

  const key = (app.name || '').toLowerCase();
  const installedOn = _inventoryIndex[key];
  const installedCount = installedOn ? installedOn.size : 0;
  const totalHosts = _hostUniverse.size;

  if (unmanaged) {
    // Unmanaged catalog entries: also surface partial/missing if inventory loaded
    // but keep 'unmanaged' as primary status
    return 'unmanaged';
  }

  if (installedCount === 0)              return 'missing';
  if (installedCount >= totalHosts)     return 'installed';
  return 'partial';
}

function getHostCount(app) {
  const key = (app.name || '').toLowerCase();
  return _inventoryIndex[key] ? _inventoryIndex[key].size : 0;
}

// ── Filtering & sorting ───────────────────────────────────────────────────────
function getFiltered() {
  const q            = (document.getElementById('sw-search')?.value || '').toLowerCase();
  const listFilter   = document.getElementById('sw-list-filter')?.value || '';
  const typeFilter   = document.getElementById('sw-type-filter')?.value || '';
  const statusFilter = document.getElementById('sw-status-filter')?.value || '';

  // Merge catalog apps with inventory-only apps
  let filtered = [..._apps, ..._inventoryOnlyApps];

  if (listFilter && _lists[listFilter]) {
    const wanted = new Set(_lists[listFilter].map(n => n.toLowerCase()));
    // Inventory-only apps are never in a named list — always exclude them when filtering by list
    filtered = filtered.filter(a =>
      !a._inventoryOnly && wanted.has((a.name || '').toLowerCase())
    );
  }

  if (typeFilter) {
    filtered = filtered.filter(a => (a.type || '').toLowerCase() === typeFilter);
  }

  if (statusFilter) {
    filtered = filtered.filter(a => getInstallStatus(a) === statusFilter);
  }

  if (q) {
    filtered = filtered.filter(a =>
      (a.name || '').toLowerCase().includes(q) ||
      (a.detect_value || '').toLowerCase().includes(q) ||
      (a.repo || '').toLowerCase().includes(q)
    );
  }

  // Sort
  const statusOrder = { installed: 0, partial: 1, missing: 2, unmanaged: 3 };

  filtered.sort((a, b) => {
    if (_sortCol === 'unmanaged') {
      const au = a.unmanaged === true || a.unmanaged === 'true' ? 1 : 0;
      const bu = b.unmanaged === true || b.unmanaged === 'true' ? 1 : 0;
      return (au - bu) * _sortDir;
    }
    if (_sortCol === '_hostCount') {
      return (getHostCount(a) - getHostCount(b)) * _sortDir;
    }
    if (_sortCol === '_installStatus') {
      const as = getInstallStatus(a) || 'zzz';
      const bs = getInstallStatus(b) || 'zzz';
      const ai = statusOrder[as] ?? 9;
      const bi = statusOrder[bs] ?? 9;
      return (ai - bi) * _sortDir;
    }
    const av = String(a[_sortCol] || '').toLowerCase();
    const bv = String(b[_sortCol] || '').toLowerCase();
    return av < bv ? -_sortDir : av > bv ? _sortDir : 0;
  });

  return filtered;
}

function renderTable() {
  const tbody = document.getElementById('sw-tbody');
  const empty = document.getElementById('sw-empty');
  const stats = document.getElementById('sw-stats');

  if (!tbody) return;

  const hasData = _apps.length > 0 || _inventoryOnlyApps.length > 0;

  if (!hasData) {
    tbody.innerHTML = '';
    if (empty) empty.style.display = '';
    if (stats) stats.textContent = '';
    return;
  }

  if (empty) empty.style.display = 'none';

  const filtered = getFiltered();
  const hasInventory = _inventory.length > 0;
  const N = _hostUniverse.size;

  // Stats
  if (stats) {
    const allApps = [..._apps, ..._inventoryOnlyApps];
    const installedCount = allApps.filter(a => getInstallStatus(a) === 'installed').length;
    const partialCount   = allApps.filter(a => getInstallStatus(a) === 'partial').length;
    const missingCount   = allApps.filter(a => getInstallStatus(a) === 'missing').length;
    const unmanagedCount = allApps.filter(a => getInstallStatus(a) === 'unmanaged').length;

    let txt = `${filtered.length} of ${allApps.length} app(s)`;
    if (hasInventory) {
      txt += ` — ${installedCount} installed, ${partialCount} partial, ${missingCount} missing, ${unmanagedCount} unmanaged`;
      txt += ` (${N} host${N !== 1 ? 's' : ''} surveyed)`;
    } else if (unmanagedCount) {
      txt += ` — ${unmanagedCount} unmanaged`;
    }
    stats.textContent = txt;
  }

  if (filtered.length === 0) {
    tbody.innerHTML = `<tr><td colspan="10" style="text-align:center;color:var(--text-muted);padding:20px">No apps match the current filters.</td></tr>`;
    return;
  }

  tbody.innerHTML = filtered.map(a => {
    const unmanaged     = a.unmanaged === true || a.unmanaged === 'true';
    const installStatus = getInstallStatus(a);
    const hostCount     = getHostCount(a);
    const isInvOnly     = !!a._inventoryOnly;

    // Row highlight
    let rowStyle = '';
    if (installStatus === 'missing')  rowStyle = 'style="background:rgba(239,68,68,0.05)"';
    else if (installStatus === 'partial')   rowStyle = 'style="background:rgba(251,191,36,0.06)"';
    else if (installStatus === 'unmanaged') rowStyle = 'style="background:rgba(245,158,11,0.06)"';

    // Managed badge
    const managedBadge = isInvOnly
      ? `<span style="color:var(--text-muted)">— inventory only</span>`
      : unmanaged
        ? `<span style="color:var(--warning);font-weight:600">⚠ Unmanaged</span>`
        : `<span style="color:var(--success)">✓ Managed</span>`;

    // Source / strategy / type badges (blank for inventory-only)
    const stratBadge = a.strategy === 'latest'
      ? `<span class="badge badge-info">latest</span>`
      : a.strategy === '—' ? '<span style="color:var(--text-muted)">—</span>'
      : `<span class="badge badge-muted">pinned</span>`;

    const sourceBadge = a.source === 'github'
      ? `<span class="badge badge-purple">GitHub</span>`
      : a.source === 'url'
        ? `<span class="badge badge-blue">URL</span>`
        : `<span style="color:var(--text-muted)">—</span>`;

    const typeBadge = a.type && a.type !== '—'
      ? `<code style="font-size:10px">${sanitize(a.type.toUpperCase())}</code>`
      : '<span style="color:var(--text-muted)">—</span>';

    const detectVal = a.detect_value ? sanitize(
      a.detect_value.length > 48
        ? a.detect_value.slice(0, 46) + '…'
        : a.detect_value
    ) : '<span style="color:var(--text-muted)">—</span>';

    const ver = a.version && a.version !== '—'
      ? sanitize(a.version)
      : '<span style="color:var(--text-muted)">latest</span>';

    // Install status badge + host count cell
    let hostCell   = '<span style="color:var(--text-muted)">—</span>';
    let statusBadge = '<span style="color:var(--text-muted)">—</span>';

    if (hasInventory || installStatus === 'unmanaged') {
      const hosts = [...(_inventoryIndex[(a.name || '').toLowerCase()] || [])].sort();
      const hostTitle = hosts.join(', ');

      if (installStatus === 'installed') {
        hostCell    = `<span title="${sanitize(hostTitle)}" style="color:var(--success);font-weight:600;cursor:default">${hostCount} / ${N}</span>`;
        statusBadge = `<span class="badge" style="background:rgba(34,197,94,0.18);color:var(--success);border:1px solid rgba(34,197,94,0.35)">✓ Installed</span>`;
      } else if (installStatus === 'partial') {
        hostCell    = `<span title="${sanitize(hostTitle)}" style="color:#fbbf24;font-weight:600;cursor:default">${hostCount} / ${N}</span>`;
        statusBadge = `<span class="badge" style="background:rgba(251,191,36,0.18);color:#fbbf24;border:1px solid rgba(251,191,36,0.35)">⚡ Partial</span>`;
      } else if (installStatus === 'missing') {
        hostCell    = `<span style="color:var(--text-muted)">0 / ${N}</span>`;
        statusBadge = `<span class="badge" style="background:rgba(239,68,68,0.15);color:#f87171;border:1px solid rgba(239,68,68,0.3)">✗ Missing</span>`;
      } else if (installStatus === 'unmanaged') {
        if (_inventory.length > 0) {
          hostCell = hostCount > 0
            ? `<span title="${sanitize(hostTitle)}" style="color:var(--warning);cursor:default">${hostCount} / ${N}</span>`
            : `<span style="color:var(--text-muted)">0 / ${N}</span>`;
        }
        statusBadge = isInvOnly
          ? `<span class="badge" style="background:rgba(245,158,11,0.15);color:var(--warning);border:1px solid rgba(245,158,11,0.3)">⚠ Not in catalog</span>`
          : `<span class="badge" style="background:rgba(245,158,11,0.15);color:var(--warning);border:1px solid rgba(245,158,11,0.3)">⚠ Unmanaged</span>`;
      }
    }

    return `<tr ${rowStyle}>
      <td style="font-weight:500">${sanitize(a.name || '')}</td>
      <td>${sourceBadge}</td>
      <td>${stratBadge}</td>
      <td style="font-family:var(--mono);font-size:11px">${ver}</td>
      <td>${typeBadge}</td>
      <td style="font-size:11px;color:var(--text-dim)">${sanitize(a.detect_type || '—')}</td>
      <td style="font-family:var(--mono);font-size:10px;max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${sanitize(a.detect_value || '')}">${detectVal}</td>
      <td>${managedBadge}</td>
      <td style="text-align:center">${hostCell}</td>
      <td>${statusBadge}</td>
    </tr>`;
  }).join('');
}

// ── Gap Report Export ─────────────────────────────────────────────────────────
// Emits one row per (app × host) combination, making per-host gaps actionable.
// Inventory-only apps (not in catalog) are included with status "unmanaged".
function exportGapReport() {
  const hasInventory = _inventory.length > 0;

  if (_apps.length === 0 && _inventoryOnlyApps.length === 0) {
    toast('No software catalog or inventory loaded.', 'warning');
    return;
  }
  if (!hasInventory) {
    toast('No inventory loaded — drop software_superset.csv to generate a host-level gap report.', 'warning');
    return;
  }

  const escapeCell = v => {
    const s = String(v ?? '');
    return s.includes(',') || s.includes('"') || s.includes('\n')
      ? `"${s.replace(/"/g, '""')}"` : s;
  };

  const headers = [
    'AppName', 'Host', 'GapStatus',
    'CatalogVersion', 'InstalledVersion', 'Publisher',
    'Source', 'Strategy', 'Managed', 'DetectType', 'DetectValue'
  ];

  const gapRows = [];
  const hosts = [..._hostUniverse].sort();

  // Catalog apps × all surveyed hosts
  for (const app of _apps) {
    const key = (app.name || '').toLowerCase();
    const installedOn = _inventoryIndex[key] || new Set();
    const managed = (app.unmanaged === true || app.unmanaged === 'true') ? 'No' : 'Yes';

    for (const host of hosts) {
      let gapStatus;
      if (app.unmanaged === true || app.unmanaged === 'true') {
        gapStatus = installedOn.has(host) ? 'unmanaged-installed' : 'unmanaged-absent';
      } else {
        gapStatus = installedOn.has(host) ? 'installed' : 'missing';
      }

      // Look up the inventory row for this specific host to get installed version/publisher
      const invRow = _inventory.find(r =>
        (r.Name || r.name || '').trim().toLowerCase() === key &&
        (r.Host || r.host || '').trim() === host
      );

      gapRows.push([
        app.name || '',
        host,
        gapStatus,
        app.version || '',
        invRow?.Version || invRow?.version || '',
        invRow?.Publisher || invRow?.publisher || '',
        app.source || '',
        app.strategy || '',
        managed,
        app.detect_type || '',
        app.detect_value || ''
      ].map(escapeCell).join(','));
    }
  }

  // Inventory-only apps × hosts where they were observed
  for (const app of _inventoryOnlyApps) {
    const key = (app.name || '').toLowerCase();
    const installedOn = _inventoryIndex[key] || new Set();

    for (const host of hosts) {
      if (!installedOn.has(host)) continue; // only emit rows where it was actually found
      const invRow = _inventory.find(r =>
        (r.Name || r.name || '').trim().toLowerCase() === key &&
        (r.Host || r.host || '').trim() === host
      );
      gapRows.push([
        app.name || '',
        host,
        'unmanaged',
        '',
        invRow?.Version || invRow?.version || '',
        invRow?.Publisher || invRow?.publisher || '',
        '', '', 'No',
        invRow?.DetectType || invRow?.detect_type || '',
        invRow?.DetectValue || invRow?.detect_value || ''
      ].map(escapeCell).join(','));
    }
  }

  const csv = [headers.join(','), ...gapRows].join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `software_gap_report_${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);

  const missingRows   = gapRows.filter(r => r.includes(',missing,')).length;
  const unmanagedRows = gapRows.filter(r => /,unmanaged[^,]*,/.test(r)).length;
  toast(`Gap report exported — ${missingRows} missing and ${unmanagedRows} unmanaged host-app gaps.`, 'success');
}
