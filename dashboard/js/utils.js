// utils.js — shared utilities for SAS Dashboard

/**
 * RFC-4180-compliant CSV parser.
 * Handles: UTF-8 BOM, CRLF/LF/CR line endings, quoted fields with embedded
 * commas, escaped double-quotes (""), and multiline quoted fields.
 */
export function parseCSV(text) {
  // Strip UTF-8 BOM (\uFEFF) that Excel/PowerShell often prepend
  const src = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const records = tokenizeCSV(src);
  if (records.length === 0) return [];

  const headers = records[0].map(h => h.trim());
  const rows = [];
  for (let i = 1; i < records.length; i++) {
    const vals = records[i];
    // skip completely blank records
    if (vals.length === 0 || (vals.length === 1 && vals[0].trim() === '')) continue;
    const row = {};
    headers.forEach((h, idx) => { row[h] = (vals[idx] ?? '').trim(); });
    rows.push(row);
  }
  return rows;
}

/** Tokenize full CSV text into an array of records (each record = array of fields). */
function tokenizeCSV(src) {
  const records = [];
  let cur = '';
  let inQuotes = false;
  let fields = [];
  let i = 0;

  const flush = () => { fields.push(cur); cur = ''; };
  const commit = () => { flush(); records.push(fields); fields = []; };

  while (i < src.length) {
    const ch = src[i];
    if (inQuotes) {
      if (ch === '"') {
        if (src[i + 1] === '"') { cur += '"'; i += 2; continue; } // escaped quote
        inQuotes = false; i++; continue;
      }
      cur += ch; i++; continue; // embedded newlines / commas inside quotes
    }
    if (ch === '"') { inQuotes = true; i++; continue; }
    if (ch === ',') { flush(); i++; continue; }
    if (ch === '\n') { commit(); i++; continue; }
    cur += ch; i++;
  }
  commit(); // flush final field/record
  return records;
}

export function parseJSON(text) {
  try { return JSON.parse(text); } catch { return null; }
}

export function sanitize(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function escapeCSV(val) {
  const s = String(val ?? '');
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

export function exportToCSV(rows, filename) {
  if (!rows.length) return;
  const headers = Object.keys(rows[0]);
  const lines = [headers.map(escapeCSV).join(',')];
  for (const row of rows) {
    lines.push(headers.map(h => escapeCSV(row[h] ?? '')).join(','));
  }
  const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * Classify a PingStatus value into a step result string.
 * Negative states are checked FIRST so that values like 'Unreachable' or
 * 'UnreachableOrBlocked' are never matched by the 'reachable' substring.
 * Exported here so all panels share the same logic.
 */
export function pingToStep(pingStatus) {
  const s = (pingStatus || '').toLowerCase().trim();
  if (!s) return 'skipped';
  if (s.includes('noping') || s.includes('unreachable') || s.includes('offline') ||
      s.includes('blocked') || s.includes('timeout') || s.includes('error') ||
      s === 'failed' || s.includes('icmpfail')) return 'failed';
  if (s.includes('reachable')) return 'success';
  return 'skipped';
}

export function statusBadge(status) {
  const s = (status || '').toLowerCase();
  // Check failure states FIRST — 'unreachable' must not match the 'reachable' success pattern
  if (/fail|error|denied|miss|offline|unreachable|blocked|noping|no$/i.test(s)) {
    return `<span class="badge badge-error">${sanitize(status)}</span>`;
  }
  if (/ok|success|mapped|added|complete|reachable|identity.?collected|yes/i.test(s)) {
    return `<span class="badge badge-success">${sanitize(status)}</span>`;
  }
  if (/warn|plan|present|partial|pending|notchecked|unknown/i.test(s)) {
    return `<span class="badge badge-warning">${sanitize(status)}</span>`;
  }
  if (/removed|prune/i.test(s)) {
    return `<span class="badge badge-error">${sanitize(status)}</span>`;
  }
  if (/skip|not.?attempt/i.test(s)) {
    return `<span class="badge badge-muted">${sanitize(status)}</span>`;
  }
  return `<span class="badge badge-muted">${sanitize(status)}</span>`;
}

export function formatTimestamp(ts) {
  if (!ts) return '—';
  const d = new Date(ts);
  if (isNaN(d)) return ts;
  return d.toLocaleString();
}

export function toast(msg, type = 'info', duration = 3500) {
  const container = document.getElementById('toast-container');
  if (!container) return;
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = msg;
  container.appendChild(el);
  setTimeout(() => el.remove(), duration);
}

export function sortRows(rows, key, dir) {
  return [...rows].sort((a, b) => {
    const av = (a[key] ?? '').toString().toLowerCase();
    const bv = (b[key] ?? '').toString().toLowerCase();
    const cmp = av.localeCompare(bv, undefined, { numeric: true });
    return dir === 'asc' ? cmp : -cmp;
  });
}

export function filterRows(rows, searchKeys, query) {
  if (!query) return rows;
  const q = query.toLowerCase();
  return rows.filter(row =>
    searchKeys.some(k => (row[k] || '').toString().toLowerCase().includes(q))
  );
}

export function makeSortable(tableEl, onSort) {
  tableEl.querySelectorAll('th[data-col]').forEach(th => {
    th.innerHTML += '<span class="sort-icon"></span>';
    th.addEventListener('click', () => {
      const col = th.dataset.col;
      const cur = th.classList.contains('sorted-asc') ? 'asc' :
                  th.classList.contains('sorted-desc') ? 'desc' : '';
      tableEl.querySelectorAll('th').forEach(t => t.classList.remove('sorted-asc', 'sorted-desc'));
      const dir = cur === 'asc' ? 'desc' : 'asc';
      th.classList.add(`sorted-${dir}`);
      onSort(col, dir);
    });
  });
}

export function el(tag, attrs = {}, children = []) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v;
    else if (k === 'style') Object.assign(e.style, v);
    else e.setAttribute(k, v);
  }
  for (const c of children) {
    if (typeof c === 'string') e.appendChild(document.createTextNode(c));
    else if (c) e.appendChild(c);
  }
  return e;
}

export function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}
