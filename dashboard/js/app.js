// app.js — SysAdmin Suite Dashboard main controller

import { parseCSV, parseJSON, toast, sanitize } from './utils.js';
import { detectFileType, parseFileContent, mergeDataStore } from './parsers.js';
import { getPrinterHTML, initPrinterPanel, renderPrinterPanel } from './panel-printer.js';
import { getInventoryHTML, initInventoryPanel, renderInventoryPanel } from './panel-inventory.js';
import { getTasksHTML, initTasksPanel, renderTasksPanel } from './panel-tasks.js';
import { getNetworkHTML, initNetworkPanel, renderNetworkPanel } from './panel-network.js';

// ── State ──────────────────────────────────────────────────────────────────
let store = {};
let loadedFiles = [];
let mode = 'log'; // 'log' | 'live'
let activeTab = 'printer';

// ── Bootstrap ──────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  buildLayout();
  initTabs();
  initIngestion();
  initModeToggle();
  initLiveMode();
  initPasteModal();
  initStatusFooter();
  initDropOverlay();

  // Init panels
  initPrinterPanel();
  initInventoryPanel();
  initTasksPanel();
  initNetworkPanel();

  // Render empty state on all panels
  refreshAllPanels();
});

// ── Layout ─────────────────────────────────────────────────────────────────
function buildLayout() {
  const printerEl = document.getElementById('panel-printer');
  const inventoryEl = document.getElementById('panel-inventory');
  const tasksEl = document.getElementById('panel-tasks');
  const networkEl = document.getElementById('panel-network');

  if (printerEl) printerEl.innerHTML = getPrinterHTML();
  if (inventoryEl) inventoryEl.innerHTML = getInventoryHTML();
  if (tasksEl) tasksEl.innerHTML = getTasksHTML();
  if (networkEl) networkEl.innerHTML = getNetworkHTML();
}

// ── Tabs ────────────────────────────────────────────────────────────────────
function initTabs() {
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const tab = btn.dataset.tab;
      switchTab(tab);
    });
  });
}

function switchTab(tab) {
  activeTab = tab;
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
  document.querySelectorAll('.panel').forEach(p => p.classList.toggle('active', p.dataset.panel === tab));
}

// ── Mode Toggle ─────────────────────────────────────────────────────────────
function initModeToggle() {
  document.querySelectorAll('.mode-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      mode = btn.dataset.mode;
      document.querySelectorAll('.mode-btn').forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
      const logSection = document.getElementById('panel-ingestion');
      const liveSection = document.getElementById('live-controls');
      if (logSection) logSection.style.display = mode === 'log' ? '' : 'none';
      if (liveSection) liveSection.classList.toggle('active', mode === 'live');
    });
  });
}

// ── File Ingestion ──────────────────────────────────────────────────────────
function initIngestion() {
  const fileInput = document.getElementById('file-input');
  const dropZone = document.getElementById('drop-zone');

  if (fileInput) {
    fileInput.addEventListener('change', e => {
      handleFiles([...e.target.files]);
      fileInput.value = '';
    });
  }

  if (dropZone) {
    dropZone.addEventListener('click', () => fileInput?.click());
    dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.classList.add('dragover'); });
    dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragover'));
    dropZone.addEventListener('drop', e => {
      e.preventDefault();
      e.stopPropagation(); // prevent event bubbling to the body-level drop handler
      dropZone.classList.remove('dragover');
      if (document.getElementById('drop-overlay')) {
        document.getElementById('drop-overlay').classList.remove('active');
      }
      handleFiles([...e.dataTransfer.files]);
    });
  }

  const clearBtn = document.getElementById('clear-all-btn');
  if (clearBtn) clearBtn.addEventListener('click', clearAllData);
}

function initDropOverlay() {
  const overlay = document.getElementById('drop-overlay');
  document.body.addEventListener('dragover', e => {
    e.preventDefault();
    if (overlay) overlay.classList.add('active');
  });
  document.body.addEventListener('dragleave', e => {
    if (!e.relatedTarget || e.relatedTarget === document.body) {
      if (overlay) overlay.classList.remove('active');
    }
  });
  document.body.addEventListener('drop', e => {
    e.preventDefault();
    if (overlay) overlay.classList.remove('active');
    const files = [...(e.dataTransfer?.files || [])];
    if (files.length) handleFiles(files);
  });
}

async function handleFiles(files) {
  for (const file of files) {
    await processFile(file);
  }
}

async function processFile(file) {
  const name = file.name;
  const ext = name.split('.').pop().toLowerCase();

  try {
    let content;
    let parsedData;

    if (ext === 'xlsx' || ext === 'xls') {
      // Use SheetJS
      if (typeof XLSX === 'undefined') {
        toast('SheetJS library not available — try reloading or check network access.', 'warning');
        return;
      }
      const buffer = await file.arrayBuffer();
      const wb = XLSX.read(buffer, { type: 'array' });
      const ws = wb.Sheets[wb.SheetNames[0]];
      const csv = XLSX.utils.sheet_to_csv(ws);
      content = csv;
      // Strip XLSX extension so specific filename patterns (network_preflight, etc.) match
      const nameForDetect = name.replace(/\.(xlsx|xls)$/i, '.csv');
      const type = detectFileType(nameForDetect, csv);
      parsedData = parseFileContent(type, csv, nameForDetect);
    } else {
      content = await readFileAsText(file);
      const type = detectFileType(name, content);

      if (type === 'unknown') {
        toast(`Could not detect file type for "${name}". Try renaming it to match known patterns (e.g. Results.csv, workstation_identity.csv).`, 'warning');
      }
      parsedData = parseFileContent(type, content, name);
    }

    // Special handling for status JSON
    if (parsedData.type === 'status-json') {
      updateStatusFooter(parsedData.data);
      toast(`Loaded status.json`, 'success');
      addFileChip(name, 'ok', 'status-json', '', parsedData);
      return;
    }

    store = mergeDataStore(store, parsedData);
    refreshAllPanels();

    const count = parsedData.rows?.length ?? 0;
    addFileChip(name, count > 0 ? 'ok' : 'warn', parsedData.type, count, parsedData);
    toast(`Loaded "${name}" — ${count} rows (${parsedData.type})`, count > 0 ? 'success' : 'warning');

  } catch (err) {
    console.error('Error processing file:', name, err);
    toast(`Error loading "${name}": ${err.message}`, 'error');
    addFileChip(name, 'err', 'error', 0);
  }
}

function readFileAsText(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = e => resolve(e.target.result);
    reader.onerror = () => reject(new Error('File read error'));
    reader.readAsText(file);
  });
}

function rebuildStoreFromChips() {
  store = {};
  let latestStatus = null;
  for (const f of loadedFiles) {
    if (!f.parsedData) continue;
    if (f.parsedData.type === 'status-json') {
      latestStatus = f.parsedData.data; // keep last status-json remaining
    } else {
      store = mergeDataStore(store, f.parsedData);
    }
  }
  updateStatusFooter(latestStatus); // null clears footer if no status chip remains
  refreshAllPanels();
}

function addFileChip(name, status, type, countOrData, parsedData = null) {
  const container = document.getElementById('loaded-files');
  if (!container) return;

  const count = typeof countOrData === 'number' ? countOrData : '';
  const id = 'chip-' + Date.now() + '-' + Math.random().toString(36).slice(2);

  const iconMap = {
    'preflight': '📋', 'results': '✅', 'workstation-identity': '🖥️',
    'printer-probe': '🖨️', 'network-preflight': '📡', 'machine-info': '💻',
    'ram-info': '🧠', 'monitor-info': '🖥️', 'neuron-inventory': '🗂️',
    'smb-recon': '📂', 'status-json': '💚', 'remote-task': '⚡', 'unknown': '❓'
  };
  const icon = iconMap[type] || '📄';

  const chip = document.createElement('div');
  chip.className = `file-chip chip-${status}`;
  chip.id = id;
  chip.innerHTML = `
    <span class="chip-icon">${icon}</span>
    <span title="${sanitize(name)} (${type})">${sanitize(name.length > 24 ? name.slice(0, 22) + '…' : name)}${count !== '' ? ` (${count})` : ''}</span>
    <span class="chip-remove" data-id="${id}">×</span>
  `;

  chip.querySelector('.chip-remove').addEventListener('click', () => {
    chip.remove();
    loadedFiles = loadedFiles.filter(f => f.id !== id);
    rebuildStoreFromChips();
    toast(`Removed "${name}"`, 'info');
  });

  container.appendChild(chip);
  loadedFiles.push({ id, name, type, status, parsedData });
}

function clearAllData() {
  store = {};
  loadedFiles = [];
  document.getElementById('loaded-files').innerHTML = '';
  refreshAllPanels();
  updateStatusFooter(null);
  toast('All data cleared.', 'info');
}

// ── Paste Modal ─────────────────────────────────────────────────────────────
function initPasteModal() {
  const pasteBtn = document.getElementById('paste-btn');
  const modal = document.getElementById('paste-modal');
  const closeBtn = document.getElementById('paste-modal-close');
  const cancelBtn = document.getElementById('paste-cancel');
  const submitBtn = document.getElementById('paste-submit');
  const textarea = document.getElementById('paste-textarea');
  const fileNameInput = document.getElementById('paste-filename');

  if (!modal) return;

  pasteBtn?.addEventListener('click', () => modal.classList.remove('hidden'));
  closeBtn?.addEventListener('click', () => modal.classList.add('hidden'));
  cancelBtn?.addEventListener('click', () => modal.classList.add('hidden'));

  modal.addEventListener('click', e => {
    if (e.target === modal) modal.classList.add('hidden');
  });

  submitBtn?.addEventListener('click', () => {
    const content = textarea?.value?.trim();
    const fname = fileNameInput?.value?.trim() || 'pasted-data.csv';
    if (!content) { toast('Nothing to import.', 'warning'); return; }

    const type = detectFileType(fname, content);
    const parsedData = parseFileContent(type, content, fname);

    if (parsedData.type === 'status-json') {
      updateStatusFooter(parsedData.data);
      addFileChip(fname, 'ok', 'status-json', '', parsedData);
      toast(`Imported status.json`, 'success');
    } else {
      store = mergeDataStore(store, parsedData);
      refreshAllPanels();
      const count = parsedData.rows?.length ?? 0;
      addFileChip(fname, count > 0 ? 'ok' : 'warn', parsedData.type, count, parsedData);
      toast(`Imported "${fname}" — ${count} rows (${parsedData.type})`, count > 0 ? 'success' : 'warning');
    }

    if (textarea) textarea.value = '';
    modal.classList.add('hidden');
  });
}

// ── Live Mode ────────────────────────────────────────────────────────────────
function initLiveMode() {
  const startBtn = document.getElementById('live-start');
  const targetsInput = document.getElementById('live-targets');
  const fileInput = document.getElementById('live-file-input');
  const liveFileBtn = document.getElementById('live-file-btn');

  liveFileBtn?.addEventListener('click', () => fileInput?.click());
  fileInput?.addEventListener('change', async e => {
    const file = e.target.files[0];
    if (!file) return;
    const text = await file.text();
    const targets = text.split('\n')
      .map(l => l.split(',')[0].trim())
      .filter(l => l && !l.startsWith('#'));
    if (targetsInput) targetsInput.value = targets.join(', ');
    fileInput.value = '';
  });

  startBtn?.addEventListener('click', () => showLiveCommands());
}

/**
 * Live mode: generate a full protocol probe command suite for each target.
 * We do not attempt browser-side network probes (CORS/security restrictions
 * prevent DNS, ping, TCP, WMI, SNMP, SSH from a browser context).
 * Instead we generate Bash and PowerShell one-liners the operator can copy
 * and run from an admin machine, then load the resulting CSV output back.
 */
function showLiveCommands() {
  const targetsInput = document.getElementById('live-targets');
  const raw = targetsInput?.value || '';
  const targets = raw.split(/[,\n\s]+/).map(t => t.trim()).filter(Boolean);

  if (!targets.length) {
    toast('Enter at least one target hostname or IP.', 'warning');
    return;
  }

  // Sanitize targets to valid hostname/IP characters only (letters, digits, dots,
  // hyphens, colons, underscores). This prevents any shell metacharacter injection.
  const safeTargets = targets.map(t => t.replace(/[^a-zA-Z0-9.\-:_]/g, '')).filter(Boolean);
  if (safeTargets.length !== targets.length) {
    toast('Some targets contained unsafe characters and were sanitized.', 'warning');
  }
  if (safeTargets.length === 0) {
    toast('No valid targets remain after sanitization. Use hostname or IP format.', 'warning');
    return;
  }

  // Build shell-safe target list using printf instead of heredoc.
  // printf '%s\n' 'target' is injection-free regardless of target content
  // because each target is enclosed in single quotes and single-quote chars
  // cannot appear in sanitized targets (stripped above).
  const printfLines = safeTargets.map(t => `printf '%s\\n' '${t}'`).join(' >> /tmp/sas-live/targets.txt\n') + ' >> /tmp/sas-live/targets.txt';

  // targetLines is used in the PowerShell here-string (@'...'@).
  // PS single-quote here-strings do not expand variables, so this is safe.
  const targetLines = safeTargets.join('\n');

  const bashCmds = `#!/usr/bin/env bash
# SysAdmin Suite — Network preflight + identity probe
# Generated by dashboard Live Mode for ${targets.length} target(s)
# Run from a Bash-capable admin host with suite scripts available.

mkdir -p /tmp/sas-live
# Build targets file — one printf call per target (no heredoc, injection-free)
: > /tmp/sas-live/targets.txt
${printfLines}

# 1. Network preflight (DNS, ping, TCP ports)
bash bash/transport/sas-network-preflight.sh \\
  --targets-file /tmp/sas-live/targets.txt \\
  --output /tmp/sas-live/network_preflight.csv --pass-thru

# 2. Workstation identity (DNS, ARP, optional SSH/WMI)
bash bash/transport/sas-workstation-identity.sh \\
  --targets-file /tmp/sas-live/targets.txt \\
  --output /tmp/sas-live/workstation_identity.csv --pass-thru

# 3. Printer probe (SNMP, HTTP, 9100/ZPL, ARP)
bash bash/transport/sas-printer-probe.sh \\
  --targets-file /tmp/sas-live/targets.txt \\
  --output /tmp/sas-live/printer_probe.csv --pass-thru

# Drag the output files from /tmp/sas-live/ back into the dashboard drop zone.`;

  const psCmds = `# SysAdmin Suite — Hardware inventory + printer mapping
# Generated by dashboard Live Mode for ${targets.length} target(s)
# Run from Windows PowerShell as administrator with suite scripts available.

# Write targets list safely (here-string — no PS expansion of content)
@'
${targetLines}
'@ | Set-Content C:\\Temp\\live-targets.txt

# Hardware inventory (WMI: serial, MAC, IP, monitors, serial numbers)
.\\GetInfo\\Get-MachineInfo.ps1 -ListPath C:\\Temp\\live-targets.txt

# RAM inventory
.\\GetInfo\\Get-RamInfo.ps1 -ListPath C:\\Temp\\live-targets.txt

# Printer mapping snapshot (read-only preflight)
.\\mapping\\Workers\\Map-MachineWide.ps1 -ListOnly -Preflight

# Drag the resulting CSV files back into the dashboard drop zone.`;

  const linuxCmds = `#!/usr/bin/env bash
# Linux native one-liners — quick reachability check, no suite scripts needed
# Run from any Linux host on the same network.

mkdir -p /tmp/sas-live
# Build targets file — one printf call per target (no heredoc, injection-free)
: > /tmp/sas-live/targets.txt
${printfLines}

while IFS= read -r T; do
  [[ -z "\$T" ]] && continue
  echo "=== \$T ==="
  dig +short "\$T" 2>/dev/null | head -1 || echo "  DNS: no result"
  ping -c1 -W1 "\$T" &>/dev/null && echo "  Ping: reachable" || echo "  Ping: failed"
  for PORT in 135 139 445 515 631 9100 3389; do
    nc -zw1 "\$T" \$PORT 2>/dev/null && echo "  TCP/\$PORT: open" || echo "  TCP/\$PORT: closed"
  done
  arp "\$T" 2>/dev/null | grep -v incomplete || echo "  ARP: no entry"
  echo ""
done < /tmp/sas-live/targets.txt`;

  showCommandModal(targets.length, bashCmds, psCmds, linuxCmds);
}

function showCommandModal(targetCount, bashCmds, psCmds, linuxCmds) {
  const existing = document.getElementById('live-cmd-modal');
  if (existing) existing.remove();

  const section = (id, label, height = '160px') => `
    <div>
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">
        <span style="font-size:11px;font-weight:600;color:var(--text-dim)">${label}</span>
        <button class="icon-btn copy-cmd-btn" data-target="${id}" style="font-size:11px">📋 Copy</button>
      </div>
      <textarea readonly id="${id}" style="width:100%;height:${height};padding:10px;background:var(--bg3);border:1px solid var(--border);border-radius:6px;color:var(--text);font-family:var(--mono);font-size:10px;resize:vertical"></textarea>
    </div>`;

  const modal = document.createElement('div');
  modal.id = 'live-cmd-modal';
  modal.className = 'modal-backdrop';
  modal.innerHTML = `
    <div class="modal" style="width:740px;max-width:98vw">
      <div class="modal-header">
        <span class="modal-title">⚡ Live Mode — Probe Commands for ${targetCount} Target(s)</span>
        <p class="modal-subtitle">Copy and run these commands on a machine with network access to your targets. When complete, drag the generated CSV files back into the dashboard drop zone to populate all panels.</p>
        <button class="modal-close" id="live-cmd-close">×</button>
      </div>
      <div class="modal-body" style="gap:14px">
        <div style="padding:8px 12px;background:rgba(245,158,11,0.1);border:1px solid rgba(245,158,11,0.3);border-radius:6px;font-size:11px;color:var(--warning)">
          ⚠ Browser security prevents direct network probing from a web page.
          Copy the commands below, run them from an admin machine, then drag the resulting CSV files back into the dashboard.
        </div>
        ${section('bash-cmds', '1 — BASH  (primary — suite scripts)', '170px')}
        ${section('ps-cmds',   '2 — POWERSHELL  (Windows WMI / printer mapping)', '150px')}
        ${section('linux-cmds','3 — LINUX NATIVE  (quick check — no suite required)', '150px')}
        <div style="font-size:11px;color:var(--text-muted)">
          Load back: network_preflight.csv · workstation_identity.csv · printer_probe.csv · MachineInfo_Output.csv · RamInfo_Output.csv
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn-secondary" id="live-cmd-dismiss">Close</button>
      </div>
    </div>`;

  document.body.appendChild(modal);

  modal.querySelector('#bash-cmds').value = bashCmds;
  modal.querySelector('#ps-cmds').value = psCmds;
  modal.querySelector('#linux-cmds').value = linuxCmds;

  const cmdMap = { 'bash-cmds': bashCmds, 'ps-cmds': psCmds, 'linux-cmds': linuxCmds };
  const labelMap = { 'bash-cmds': 'Bash', 'ps-cmds': 'PowerShell', 'linux-cmds': 'Linux' };

  modal.querySelectorAll('.copy-cmd-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const id = btn.dataset.target;
      navigator.clipboard?.writeText(cmdMap[id])
        .then(() => toast(`${labelMap[id]} commands copied!`, 'success'))
        .catch(() => toast('Select and copy the text manually.', 'warning'));
    });
  });

  const closeModal = () => modal.remove();
  modal.querySelector('#live-cmd-close').addEventListener('click', closeModal);
  modal.querySelector('#live-cmd-dismiss').addEventListener('click', closeModal);
  modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });
}

// ── Status Footer ────────────────────────────────────────────────────────────
function initStatusFooter() {
  updateStatusFooter(null);
}

function updateStatusFooter(data) {
  const dot = document.getElementById('status-dot');
  const text = document.getElementById('status-text');
  const stage = document.getElementById('status-stage');
  const ts = document.getElementById('status-ts');
  const computer = document.getElementById('status-computer');

  if (!data) {
    if (dot) dot.className = 'status-dot';
    if (text) text.textContent = 'No run-control status loaded';
    if (stage) stage.textContent = '';
    if (ts) ts.textContent = '';
    if (computer) computer.textContent = '';
    return;
  }

  const state = data.State || data.state || 'Unknown';
  const stageVal = data.Stage || data.stage || '';
  const msg = data.Message || data.message || '';
  const comp = data.Data?.ComputerName || data.ComputerName || '';
  const timestamp = data.GeneratedAt || data.generatedAt || data.Timestamp || data.timestamp || new Date().toISOString();

  if (dot) dot.className = `status-dot ${state.toLowerCase()}`;
  if (text) text.textContent = `${state}${msg ? ' — ' + msg : ''}`;
  if (stage) stage.textContent = stageVal ? `[${stageVal}]` : '';
  if (ts) ts.textContent = new Date(timestamp).toLocaleTimeString();
  if (computer) computer.textContent = comp;

  // Auto-poll if status.json is accessible (dropped file provides data)
}

// ── Panel Refresh ────────────────────────────────────────────────────────────
function refreshAllPanels() {
  try { renderPrinterPanel(store); } catch(e) { console.warn('Printer panel error:', e); }
  try { renderInventoryPanel(store); } catch(e) { console.warn('Inventory panel error:', e); }
  try { renderTasksPanel(store); } catch(e) { console.warn('Tasks panel error:', e); }
  try { renderNetworkPanel(store); } catch(e) { console.warn('Network panel error:', e); }
}

// Expose for debug
window._sasStore = () => store;
