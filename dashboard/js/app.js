// app.js — SysAdmin Suite Dashboard main controller

import { parseCSV, parseJSON, toast, sanitize } from './utils.js';
import { detectFileType, parseFileContent, mergeDataStore } from './parsers.js';
import { getPrinterHTML, initPrinterPanel, renderPrinterPanel } from './panel-printer.js';
import { getInventoryHTML, initInventoryPanel, renderInventoryPanel } from './panel-inventory.js';
import { getTasksHTML, initTasksPanel, renderTasksPanel } from './panel-tasks.js';
import { getNetworkHTML, initNetworkPanel, renderNetworkPanel } from './panel-network.js';
import { getSoftwareHTML, initSoftwarePanel, renderSoftwarePanel } from './panel-software.js';
import { initSoftwareTrackerTutorial } from './software-tracker-tutorial.js';
import { initRepoSetupTutorial } from './repo-setup-tutorial.js';
import {
  setSoftwareInstallPlan,
  clearSoftwareInstallPlan,
} from './software-tracker-state.js';
import { initTour, markPanelVisited, initPanelBadges } from './tour.js';
import { initRelayConnection, onRelayStatus, getRelayConnected, RELAY_PORT } from './relay-client.js'; // setRelayToken used via relay-client.js in panel-network.js
// Sample data is loaded via a plain <script> tag in index.html (not an ES module).
// Globals defined by that script: window._sasSampleStore(), window._sasSampleStatus()

// ── State ──────────────────────────────────────────────────────────────────
let store = {};
let loadedFiles = [];
let mode = 'log'; // 'log' | 'live'
let activeTab = 'network';

// Human-readable review section for evidence chips
const TYPE_SECTION_LABELS = {
  'preflight': 'Printer mapping',
  'results': 'Printer mapping',
  'printer-probe': 'Printer · Network',
  'machine-info': 'Hardware inventory',
  'ram-info': 'Hardware inventory',
  'monitor-info': 'Hardware inventory',
  'neuron-inventory': 'Hardware inventory',
  'workstation-identity': 'Network review',
  'network-preflight': 'Network review',
  'smb-recon': 'Network review',
  'naabu-reachability': 'Reachability evidence',
  'cybernet-target-manifest': 'Target manifest',
  'ad-registered-population': 'AD registered population',
  'remote-task': 'Remote tasks',
  'software-tracker': 'Software tracker',
  'software-tracker-install-plan': 'Software install plan',
  'software-superset': 'Software tracker',
  'status-json': 'Status',
};

// ── File-type → panel(s) mapping ───────────────────────────────────────────
// Each type maps to one or more panels it populates.
// printer-probe feeds buildPrinterRows AND buildProtocolRows (both panels get data).
// workstation-identity feeds buildProtocolRows only (not the Inventory panel).
const TYPE_TO_PANELS = {
  'results':             ['printer'],
  'preflight':           ['printer'],
  'printer-probe':       ['printer', 'network'],
  'machine-info':        ['inventory'],
  'ram-info':            ['inventory'],
  'monitor-info':        ['inventory'],
  'workstation-identity':['network'],
  'neuron-inventory':    ['inventory'],
  'remote-task':         ['tasks'],
  'network-preflight':   ['network'],
  'smb-recon':           ['network'],
  'naabu-reachability':  ['network'],
  'cybernet-target-manifest': ['inventory'],
  'ad-registered-population': ['inventory', 'network'],
  'software-tracker':    ['software'],
  'software-tracker-install-plan': ['software'],
  'software-superset':   ['software'],
};

// ── Bootstrap ──────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  buildLayout();
  initRepoSetupShell();
  initCybernetShell();
  initSoftwareTrackerShell();
  initTabs();
  initIngestion();
  initModeToggle();
  initLiveMode();
  initRepoSetupTutorial();
  initCybernetTutorial();
  initSoftwareTrackerTutorial();
  initPasteModal();
  initStatusFooter();
  initDropOverlay();
  initSampleDataBtn();
  initFolderWatch();

  initRelayConnection();
  onRelayStatus(_updateHeaderRelayBadge);

  initPrinterPanel();
  initInventoryPanel();
  initTasksPanel();
  initNetworkPanel();
  initSoftwarePanel();

  refreshAllPanels();
  updateCybernetReview();

  // Tour available via Advanced; do not auto-launch on Cybernet-first front door
  try { localStorage.setItem('sas_tour_v1_done', '1'); } catch (_) { /* ignore */ }
  initTour();
  _relocateTourButton();

  initPanelBadges();
});

// ── Layout ─────────────────────────────────────────────────────────────────
function buildLayout() {
  const printerEl = document.getElementById('panel-printer');
  const inventoryEl = document.getElementById('panel-inventory');
  const tasksEl = document.getElementById('panel-tasks');
  const networkEl = document.getElementById('panel-network');
  const softwareEl = document.getElementById('panel-software');

  if (printerEl) printerEl.innerHTML = getPrinterHTML();
  if (inventoryEl) inventoryEl.innerHTML = getInventoryHTML();
  if (tasksEl) tasksEl.innerHTML = getTasksHTML();
  if (networkEl) networkEl.innerHTML = getNetworkHTML();
  if (softwareEl) softwareEl.innerHTML = getSoftwareHTML();
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
  const content = document.getElementById('content');
  if (content) content.classList.remove('hidden');
}

// ── Cybernet-first shell ─────────────────────────────────────────────────────
function initRepoSetupShell() {
  const startBtn = document.getElementById('hero-start-setup');
  const tutorial = document.getElementById('repo-setup-tutorial');
  const statusEl = document.getElementById('repo-setup-hero-status');

  const setHeroStatus = (msg, kind) => {
    if (!statusEl) return;
    statusEl.textContent = msg || '';
    statusEl.classList.remove('is-busy', 'is-open', 'is-error');
    if (kind) statusEl.classList.add(kind);
    statusEl.classList.toggle('hidden', !msg);
  };

  const tutorialIsVisible = () => {
    if (!tutorial) return false;
    if (tutorial.classList.contains('hidden')) return false;
    const cs = window.getComputedStyle(tutorial);
    return cs.display !== 'none' && cs.visibility !== 'hidden';
  };

  const startRepoSetupTutorial = (opts) => {
    const source = (opts && opts.source) || 'manual';
    if (!tutorial || !startBtn) {
      setHeroStatus('Could not open repo setup. Reload the dashboard or start Cybernet Survey directly.', 'is-error');
      toast('Repo setup tutorial is unavailable. Reload the dashboard.', 'error');
      return false;
    }

    setHeroStatus('Opening repo setup…', 'is-busy');
    tutorial.style.display = '';
    tutorial.classList.remove('hidden');
    if (typeof window.__sasResetRepoSetupWizard === 'function') {
      try { window.__sasResetRepoSetupWizard(); } catch (_) { /* non-fatal */ }
    }

    if (!tutorialIsVisible()) {
      tutorial.classList.add('hidden');
      setHeroStatus('Could not open repo setup. Try again or start Cybernet Survey.', 'is-error');
      toast('Could not open repo setup. Try again.', 'error');
      return false;
    }

    startBtn.textContent = 'Restart Repo Setup';
    startBtn.setAttribute('aria-label', 'Restart repo setup from step 1');
    setHeroStatus('Repo setup open below.', 'is-open');
    if (source !== 'silent') {
      window.setTimeout(() => {
        tutorial.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }, 30);
    }
    return true;
  };

  startBtn?.addEventListener('click', () => startRepoSetupTutorial({ source: 'manual' }));
  document.getElementById('hero-open-cybernet')?.addEventListener('click', () => {
    if (typeof window.startCybernetTutorial === 'function') window.startCybernetTutorial({ source: 'manual' });
    else document.getElementById('hero-start-survey')?.click();
  });
  window.startRepoSetupTutorial = startRepoSetupTutorial;
}

function initCybernetShell() {
  const startBtn = document.getElementById('hero-start-survey');
  const tutorial = document.getElementById('cybernet-tutorial');
  const statusEl = document.getElementById('cybernet-hero-status');

  const setHeroStatus = (msg, kind) => {
    if (!statusEl) return;
    statusEl.textContent = msg || '';
    statusEl.classList.remove('is-busy', 'is-open', 'is-error');
    if (kind) statusEl.classList.add(kind);
    statusEl.classList.toggle('hidden', !msg);
  };

  // Effective visibility check: catches a none from the class, an inline style,
  // or a rule set by another script (e.g. the OS-preflight helper).
  const tutorialIsVisible = () => {
    if (!tutorial) return false;
    if (tutorial.classList.contains('hidden')) return false;
    const cs = window.getComputedStyle(tutorial);
    return cs.display !== 'none' && cs.visibility !== 'hidden';
  };

  // Explicit, verified state transition. A press of Start must always leave the
  // user in a visible state: tutorial open, or a clear recovery message — never a
  // vanished button with nothing showing.
  const startCybernetTutorial = (opts) => {
    const source = (opts && opts.source) || 'manual';
    if (!tutorial || !startBtn) {
      setHeroStatus('Could not open the tutorial. Reload the dashboard or use Load Evidence.', 'is-error');
      toast('Survey tutorial is unavailable. Reload the dashboard.', 'error');
      return false;
    }

    setHeroStatus('Opening tutorial…', 'is-busy');

    // Show the wizard. Clear any inline display another script may have set so a
    // stale inline none cannot silently keep the wizard hidden.
    tutorial.style.display = '';
    tutorial.classList.remove('hidden');
    if (typeof window.__sasResetCybernetWizard === 'function') {
      try { window.__sasResetCybernetWizard(); } catch (_) { /* non-fatal */ }
    }

    // Verify the wizard is actually visible before transforming the hero. If it
    // is not, restore the obvious action instead of stranding the user.
    if (!tutorialIsVisible()) {
      tutorial.classList.add('hidden');
      setHeroStatus('Could not open the tutorial. Try again or use Load Evidence.', 'is-error');
      toast('Could not open the survey tutorial. Try again or load evidence.', 'error');
      return false;
    }

    // Keep the hero action visible and turn it into a recovery control rather
    // than hiding the only obvious button.
    startBtn.textContent = 'Restart Cybernet Survey';
    startBtn.setAttribute('aria-label', 'Restart the Cybernet survey from step 1');
    setHeroStatus('Tutorial open below.', 'is-open');
    if (source !== 'silent') {
      window.setTimeout(() => {
        tutorial.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }, 30);
    }
    return true;
  };

  startBtn?.addEventListener('click', () => startCybernetTutorial({ source: 'manual' }));

  // Expose the same verified transition for the ?tutorial=cybernet auto-launch
  // path so it cannot diverge from the manual click behavior.
  window.startCybernetTutorial = startCybernetTutorial;

  const openEvidence = () => {
    document.getElementById('evidence-loader')?.classList.remove('hidden');
    document.getElementById('evidence-loader')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  document.getElementById('hero-load-evidence')?.addEventListener('click', openEvidence);
  document.getElementById('cybernet-load-evidence-end')?.addEventListener('click', openEvidence);

  document.getElementById('advanced-tools-toggle')?.addEventListener('click', () => {
    const section = document.getElementById('advanced-section');
    const open = section?.classList.contains('hidden');
    if (open) openAdvancedSection(true);
    else closeAdvancedSection();
  });

  document.getElementById('review-open-network')?.addEventListener('click', () => {
    openAdvancedSection(true);
    switchTab('network');
  });
}

function initSoftwareTrackerShell() {
  const startBtn = document.getElementById('hero-start-install');
  const tutorial = document.getElementById('software-tracker-tutorial');
  const statusEl = document.getElementById('software-tracker-hero-status');

  const setHeroStatus = (msg, kind) => {
    if (!statusEl) return;
    statusEl.textContent = msg || '';
    statusEl.classList.remove('is-busy', 'is-open', 'is-error');
    if (kind) statusEl.classList.add(kind);
    statusEl.classList.toggle('hidden', !msg);
  };

  const tutorialIsVisible = () => {
    if (!tutorial) return false;
    if (tutorial.classList.contains('hidden')) return false;
    const cs = window.getComputedStyle(tutorial);
    return cs.display !== 'none' && cs.visibility !== 'hidden';
  };

  const startSoftwareTrackerTutorial = (opts) => {
    const source = (opts && opts.source) || 'manual';
    if (!tutorial || !startBtn) {
      setHeroStatus('Could not open the install tutorial. Reload the dashboard or use Load Evidence.', 'is-error');
      toast('Software Tracker tutorial is unavailable. Reload the dashboard.', 'error');
      return false;
    }

    setHeroStatus('Opening install workflow…', 'is-busy');
    tutorial.style.display = '';
    tutorial.classList.remove('hidden');
    if (typeof window.__sasResetSoftwareTrackerWizard === 'function') {
      try { window.__sasResetSoftwareTrackerWizard(); } catch (_) { /* non-fatal */ }
    }

    if (!tutorialIsVisible()) {
      tutorial.classList.add('hidden');
      setHeroStatus('Could not open the tutorial. Try again or use Load Evidence.', 'is-error');
      toast('Could not open the Software Tracker tutorial. Try again or load evidence.', 'error');
      return false;
    }

    startBtn.textContent = 'Restart Software Tracker Install';
    startBtn.setAttribute('aria-label', 'Restart the Software Tracker install workflow from step 1');
    setHeroStatus('Install workflow open below.', 'is-open');
    if (source !== 'silent') {
      window.setTimeout(() => {
        tutorial.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }, 30);
    }
    return true;
  };

  startBtn?.addEventListener('click', () => startSoftwareTrackerTutorial({ source: 'manual' }));
  window.startSoftwareTrackerTutorial = startSoftwareTrackerTutorial;

  document.getElementById('hero-start-install-evidence')?.addEventListener('click', () => {
    document.getElementById('evidence-loader')?.classList.remove('hidden');
    document.getElementById('evidence-loader')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
}

function openAdvancedSection(scroll) {
  const section = document.getElementById('advanced-section');
  section?.classList.remove('hidden');
  document.getElementById('advanced-tools-toggle')?.setAttribute('aria-expanded', 'true');
  switchTab('network');
  if (scroll) section?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function closeAdvancedSection() {
  document.getElementById('advanced-section')?.classList.add('hidden');
  document.getElementById('advanced-tools-toggle')?.setAttribute('aria-expanded', 'false');
  document.getElementById('content')?.classList.add('hidden');
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
}

function _relocateTourButton() {
  const tourBtn = document.getElementById('sas-tour-launch-btn');
  const advancedHead = document.querySelector('.advanced-section-head');
  if (tourBtn && advancedHead && !advancedHead.contains(tourBtn)) {
    tourBtn.textContent = 'Interactive tour';
    tourBtn.className = 'paste-btn';
    advancedHead.appendChild(tourBtn);
  }
}

// ── Mode Toggle ─────────────────────────────────────────────────────────────
function initModeToggle() {
  document.querySelectorAll('.mode-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      mode = btn.dataset.mode;
      document.querySelectorAll('.mode-btn').forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
      const liveSection = document.getElementById('live-controls');
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
  if (files.length) document.getElementById('evidence-loader')?.classList.remove('hidden');
  // Spreadsheets can take a moment to parse — keep the tech company with Harold.
  const hasHeavy = files.some(f => /\.(xlsx|xls)$/i.test(f.name));
  if (hasHeavy) window.SASHarold?.show('Reading your spreadsheet… hang tight.');
  try {
    for (const file of files) {
      await processFile(file);
    }
  } finally {
    if (hasHeavy) window.SASHarold?.hide();
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

    if (parsedData.type === 'software-tracker-install-plan') {
      setSoftwareInstallPlan(parsedData.data);
      store = mergeDataStore(store, parsedData);
      refreshAllPanels();
      const count = parsedData.data?.items?.length ?? 0;
      addFileChip(name, count > 0 ? 'ok' : 'warn', parsedData.type, count, parsedData);
      toast(`Loaded install plan — ${count} row(s). Review blockers before live run.`, count > 0 ? 'success' : 'warning');
      updateSoftwareBadge();
      markPanelVisited('software');
      switchTab('software');
      document.getElementById('evidence-loader')?.classList.remove('hidden');
      return;
    }

    store = mergeDataStore(store, parsedData);
    refreshAllPanels();

    const count = parsedData.rows?.length ?? (parsedData.type === 'software-tracker' ? (parsedData.data?.apps?.length ?? 0) : 0);
    addFileChip(name, count > 0 ? 'ok' : 'warn', parsedData.type, count, parsedData);
    toast(`Loaded "${name}" — ${count} entries (${parsedData.type})`, count > 0 ? 'success' : 'warning');
    updateSoftwareBadge();

    const panels = TYPE_TO_PANELS[parsedData.type];
    if (panels && count > 0) panels.forEach(markPanelVisited);

    document.getElementById('evidence-loader')?.classList.remove('hidden');
    updateCybernetReview();

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

function rebuildInstallPlanFromChips() {
  let latest = null;
  for (const f of loadedFiles) {
    if (f.parsedData?.type === 'software-tracker-install-plan') {
      latest = f.parsedData.data;
    }
  }
  if (latest) setSoftwareInstallPlan(latest);
  else clearSoftwareInstallPlan();
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
  rebuildInstallPlanFromChips();
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
    'smb-recon': '📂', 'status-json': '💚', 'remote-task': '⚡',
    'naabu-reachability': '🔌',
    'ad-registered-population': '🏢',
    'software-tracker': '📦', 'software-tracker-install-plan': '📋',
    'cybernet-target-manifest': '🎯', 'unknown': '❓'
  };
  const icon = iconMap[type] || '📄';

  const sectionLabel = TYPE_SECTION_LABELS[type] || 'Review';
  const typeLabel = type === 'unknown' ? 'unknown format' : type;

  const chip = document.createElement('div');
  chip.className = `file-chip chip-${status}`;
  chip.id = id;
  chip.innerHTML = `
    <span class="chip-icon">${icon}</span>
    <span class="chip-meta">
      <span class="chip-name" title="${sanitize(name)}">${sanitize(name.length > 28 ? name.slice(0, 26) + '…' : name)}</span>
      <span class="chip-type">${sanitize(sectionLabel)} · ${sanitize(typeLabel)}${count !== '' ? ` · ${count} rows` : ''}</span>
    </span>
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

function clearAllData(silent = false) {
  store = {};
  loadedFiles = [];
  document.getElementById('loaded-files').innerHTML = '';
  refreshAllPanels();
  updateStatusFooter(null);
  updateCybernetReview();
  if (!silent) toast('All evidence cleared.', 'info');
}

// ── Demo / Sample Data ────────────────────────────────────────────────────
function initSampleDataBtn() {
  const btn = document.getElementById('demo-btn');
  if (btn) btn.addEventListener('click', loadSampleData);
}

function loadSampleData() {
  if (typeof window._sasSampleStore !== 'function') {
    toast('Sample data not available — sample-data.js may not have loaded.', 'error');
    return;
  }
  clearAllData(true);
  store = window._sasSampleStore();
  refreshAllPanels();
  updateStatusFooter(window._sasSampleStatus());
  updateSoftwareBadge();

  // Build parsedData objects that match mergeDataStore's expected shape so that
  // removing a sample chip triggers a correct store rebuild via rebuildStoreFromChips.
  const chips = [
    {
      name: 'sample-results.csv',
      type: 'results',
      parsedData: { type: 'results', rows: store.results || [] }
    },
    {
      name: 'sample-preflight.csv',
      type: 'preflight',
      parsedData: { type: 'preflight', rows: store.preflight || [] }
    },
    {
      name: 'sample-printer_probe.csv',
      type: 'printer-probe',
      parsedData: { type: 'printer-probe', rows: store.printerProbe || [] }
    },
    {
      name: 'sample-machine_info.csv',
      type: 'machine-info',
      parsedData: { type: 'machine-info', rows: store.machineInfo || [] }
    },
    {
      name: 'sample-ram_info.csv',
      type: 'ram-info',
      parsedData: { type: 'ram-info', rows: store.ramInfo || [], byHost: store.ramByHost || {} }
    },
    {
      name: 'sample-monitor_info.csv',
      type: 'monitor-info',
      parsedData: { type: 'monitor-info', rows: store.monitorInfo || [] }
    },
    {
      name: 'sample-QRTask_log.json',
      type: 'remote-task',
      parsedData: { type: 'remote-task', rows: store.remoteTasks || [] }
    },
    {
      name: 'sample-network_preflight.csv',
      type: 'network-preflight',
      parsedData: { type: 'network-preflight', rows: store.networkPreflight || [], rawRows: [] }
    },
    {
      name: 'sample-workstation_identity.csv',
      type: 'workstation-identity',
      parsedData: { type: 'workstation-identity', rows: store.workstationIdentity || [] }
    },
    {
      name: 'sample-sources.yaml',
      type: 'software-tracker',
      parsedData: { type: 'software-tracker', rows: store.software?.apps || [], data: store.software || {} }
    },
    {
      name: 'software_hosts.csv',
      type: 'software-superset',
      parsedData: { type: 'software-superset', rows: store.softwareInventory || [] }
    },
  ];

  for (const { name, type, parsedData } of chips) {
    const count = parsedData.rows?.length ?? 0;
    if (count > 0) addFileChip(name, 'ok', type, count, parsedData);
  }

  toast('Sample data loaded — all panels populated with demo data.', 'success');
  document.getElementById('evidence-loader')?.classList.remove('hidden');

  // Mark all data panels as visited since sample data populates every panel
  ['printer', 'inventory', 'tasks', 'network', 'software'].forEach(markPanelVisited);
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
      const pastePanels = TYPE_TO_PANELS[parsedData.type];
      if (pastePanels && count > 0) pastePanels.forEach(markPanelVisited);
      document.getElementById('evidence-loader')?.classList.remove('hidden');
      updateCybernetReview();
    }

    if (textarea) textarea.value = '';
    modal.classList.add('hidden');
  });
}



// ── Cybernet Survey Wizard ───────────────────────────────────────────────────
const CYBERNET_TUTORIAL_STEPS = [
  {
    title: 'Start the Cybernet survey',
    railLabel: 'Start',
    body: 'This tutorial teaches the field survey from beginning to end. You will load approved targets, run read-only checks from an admin machine, bring the files back, and review the dashboard results.',
    command: '',
    checks: [
      'The dashboard does not run probes by itself.',
      'You copy commands when the tutorial gives them, run them on an admin machine, then load the output files back here.',
      'Use approved target sources only; do not broaden the survey from guessed hosts.'
    ],
    nextAction: 'Read this, then click Next to load or prepare your targets.',
    note: 'Start here for Cybernet field work. Repo setup is a separate tutorial above.',
    optional: false
  },
  {
    title: 'Load your targets',
    railLabel: 'Load targets',
    body: 'Make the list of Cybernet computers you are allowed to check. Put one computer name or IP address on each line. This creates the target file used by the next checks.',
    command: "mkdir -p /tmp/sas-cybernet\nprintf '%s\\n' 'WMH300OPR001' 'WMH300OPR002' > /tmp/sas-cybernet/targets.txt",
    checks: [
      'Use only computer names, IPv4 addresses, or IPv6 addresses.',
      'Do not paste passwords, usernames, tickets, or notes into this file.',
      'AD registered population is the source of registered Cybernet population; the target list is not proof by itself.',
      'If the list came from another source, you can normalize with ./survey/sas-survey-targets.sh --device-type Cybernet --file /tmp/sas-cybernet/targets.txt (output is not dashboard-importable yet).'
    ],
    nextAction: 'Copy this local setup command, run it on your admin machine, then come back and click Next.',
    note: 'This step only creates a local targets file. It does not touch target devices.',
    optional: false
  },
  {
    title: 'Check network posture',
    railLabel: 'Network posture',
    body: 'Now check whether your admin machine can see the targets at all. This catches guest Wi-Fi, wrong VLAN, DNS, SMB, and RPC problems before anyone blames the tool.',
    command: 'bash bash/transport/sas-network-preflight.sh \\\n  --targets-file /tmp/sas-cybernet/targets.txt \\\n  --ports 135,445,3389,9100 \\\n  --output /tmp/sas-cybernet/network_preflight.csv --pass-thru',
    checks: [
      'If internal names do not resolve, the machine is probably not on the right network path.',
      'If SMB/445 and RPC/135 fail for every target, treat that as a network posture problem first.',
      'Classify guest-network blocking separately from product defects.'
    ],
    nextAction: 'Run the matching command outside the dashboard. When it finishes, drop network_preflight.csv into Load Evidence.',
    note: 'Load network_preflight.csv via Load Evidence after the command finishes.',
    optional: false
  },
  {
    title: 'Collect identity evidence',
    railLabel: 'Identity evidence',
    body: 'Collect read-only identity clues from each target. The command records what it can safely observe, such as DNS, ping status, MAC hints, and transport notes.',
    command: 'bash bash/transport/sas-workstation-identity.sh \\\n  --targets-file /tmp/sas-cybernet/targets.txt \\\n  --output /tmp/sas-cybernet/workstation_identity.csv --pass-thru',
    checks: [
      'Hostname, MAC, serial, and IP are separate clues; do not mix them together.',
      'Do not use reachability alone as Cybernet identity proof.',
      'Keep unknown or partial rows; they are useful triage evidence.'
    ],
    nextAction: 'Run the matching command outside the dashboard. When it finishes, drop workstation_identity.csv into Load Evidence.',
    note: 'Load workstation_identity.csv back via Load Evidence for searchable protocol evidence.',
    optional: false
  },
  {
    title: 'Optional reachability check',
    railLabel: 'Reachability',
    body: 'This is an extra confirmation pass for approved targets. Use it only when you need low-noise survey discipline for port evidence after the posture and identity checks.',
    command: 'mkdir -p logs/targets logs/nmap\ncp /tmp/sas-cybernet/targets.txt logs/targets/cybernet_confirm_hosts.txt\nbash survey/sas-run-naabu-pipeline.sh --site cybernet \\\n  --profile keyports_cybernet_json \\\n  --list logs/targets/cybernet_confirm_hosts.txt \\\n  --out logs/nmap/cybernet_naabu.json',
    checks: [
      'Profile: keyports_cybernet_json (-ec -silent -json).',
      'Naabu/Nmap output is reachability validation only.',
      'Doctrine: docs/LOW_NOISE_SURVEY_DOCTRINE.md — local evidence only, no target-side writes.',
      'This step is optional. Skip it when the earlier evidence is enough.'
    ],
    nextAction: 'Run this only if the target list is approved for reachability confirmation, then load cybernet_naabu.json as optional evidence.',
    note: 'Advanced: keyports_cybernet_json · output logs/nmap/cybernet_naabu.json',
    optional: true
  },
  {
    title: 'Finish and review results',
    railLabel: 'Review results',
    body: 'Bring the files back to this dashboard. Drop the CSV or JSON outputs into Load Evidence, then read Review Results for the survey summary and next action.',
    command: '# Use Load Evidence in the dashboard for:\n# /tmp/sas-cybernet/network_preflight.csv\n# /tmp/sas-cybernet/workstation_identity.csv\n# logs/nmap/cybernet_naabu.json (optional)\n# survey/output/cybernet_*_targets.csv (manifest, not evidence)',
    checks: [
      'Load Evidence is where files go in.',
      'Review Results is where the Cybernet summary appears after evidence is loaded.',
      'Open network evidence details when you need row-level DNS, ping, protocol, or reachability detail.',
      'Classify environment blocks separately from product defects.',
      'Treat manifest rows as target lists, not reachability or identity proof.'
    ],
    nextAction: 'Click Load resulting evidence, drop the files into the highlighted box, then read Review Results.',
    note: 'Click Load resulting evidence below, or use Load Evidence on the hero card.',
    optional: false
  }
];

function initCybernetTutorial() {
  const root = document.getElementById('cybernet-tutorial');
  if (!root) return;

  let idx = 0;
  let copiedThisStep = false;
  const title = document.getElementById('cybernet-step-title');
  const body = document.getElementById('cybernet-step-body');
  const kicker = document.getElementById('cybernet-step-kicker');
  const checks = document.getElementById('cybernet-step-checks');
  const command = document.getElementById('cybernet-step-command');
  const runner = document.getElementById('cybernet-command-runner');
  const note = document.getElementById('cybernet-step-note');
  const commandPanel = document.getElementById('cybernet-command-panel');
  const prev = document.getElementById('cybernet-prev');
  const next = document.getElementById('cybernet-next');
  const copy = document.getElementById('cybernet-copy');
  const wizardFooter = document.getElementById('cybernet-wizard-footer');
  const loadEvidenceEnd = document.getElementById('cybernet-load-evidence-end');
  const dropZone = document.getElementById('drop-zone');
  const progressRail = document.getElementById('cybernet-progress-rail');

  function updateProgressRail() {
    progressRail?.querySelectorAll('li').forEach((li, i) => {
      li.classList.toggle('active', i === idx);
      li.classList.toggle('done', i < idx);
    });
  }

  function updateGuideState(hasCommand) {
    const finalStep = idx === CYBERNET_TUTORIAL_STEPS.length - 1;
    copy?.classList.toggle('sas-guide-glow', hasCommand && !copiedThisStep);
    next?.classList.toggle('sas-guide-glow', (hasCommand && copiedThisStep) || (!hasCommand && !finalStep));
    loadEvidenceEnd?.classList.toggle('sas-guide-glow', finalStep);
    dropZone?.classList.toggle('sas-guide-drop', finalStep);
    commandPanel?.classList.toggle('sas-guide-panel', hasCommand && !copiedThisStep);
  }

  function render() {
    const step = CYBERNET_TUTORIAL_STEPS[idx];
    if (!step) return;
    copiedThisStep = false;
    kicker.textContent = `Step ${idx + 1} of ${CYBERNET_TUTORIAL_STEPS.length} — ${step.railLabel}`;
    title.textContent = step.title + (step.optional ? ' (optional)' : '');
    body.textContent = step.body;
    checks.innerHTML = step.checks.map(item => `<li>${sanitize(item)}</li>`).join('');
    const hasCommand = !!(step.command && !step.command.startsWith('# Use Load Evidence'));
    if (commandPanel) commandPanel.classList.toggle('hidden', !hasCommand);
    if (command) command.value = hasCommand ? step.command : '';
    if (runner) runner.textContent = step.nextAction || 'Copy the command, run it outside the dashboard, then load the output file here.';
    if (note) note.textContent = step.note;
    prev.disabled = idx === 0;
    next.textContent = idx === CYBERNET_TUTORIAL_STEPS.length - 1 ? 'Finish: Load Evidence' : hasCommand ? 'Next after running it →' : 'Next →';
    copy?.classList.toggle('hidden', !hasCommand);
    wizardFooter?.classList.toggle('hidden', idx !== CYBERNET_TUTORIAL_STEPS.length - 1);
    updateProgressRail();
    updateGuideState(hasCommand);
  }

  function copyCommand() {
    const text = command?.value || '';
    if (!text) return;
    const originalNote = note?.textContent || '';
    const write = navigator.clipboard && typeof navigator.clipboard.writeText === 'function'
      ? navigator.clipboard.writeText(text)
      : new Promise((resolve, reject) => {
          command.focus();
          command.select();
          try { document.execCommand('copy') ? resolve() : reject(new Error('copy unavailable')); }
          catch (err) { reject(err); }
        });
    write
      .then(() => {
        copiedThisStep = true;
        toast('Command copied.', 'success');
        if (note) note.textContent = 'Command copied.';
        updateGuideState(true);
      })
      .catch(() => {
        toast('Select and copy the command manually.', 'warning');
        if (note) note.textContent = `${originalNote} Select the command text and copy it manually if clipboard access is blocked.`;
      })
      .finally(() => {
        if (note) window.setTimeout(() => { if (note.textContent === 'Command copied.') note.textContent = originalNote; }, 2200);
      });
  }

  prev?.addEventListener('click', () => { if (idx > 0) { idx--; render(); } });
  next?.addEventListener('click', () => {
    const step = CYBERNET_TUTORIAL_STEPS[idx];
    const hasCommand = !!(step?.command && !step?.command.startsWith('# Use Load Evidence'));
    if (hasCommand && !copiedThisStep && !step.optional) {
      toast('Copy the command first, run it outside the dashboard, then come back for Next.', 'warning');
      return;
    }
    if (idx < CYBERNET_TUTORIAL_STEPS.length - 1) {
      idx++;
      render();
    } else {
      document.getElementById('evidence-loader')?.classList.remove('hidden');
      document.getElementById('evidence-loader')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      toast('Survey steps complete — load your evidence files.', 'success');
    }
  });
  copy?.addEventListener('click', copyCommand);

  // Allow the hero "Restart Cybernet Survey" control to reset to step 1.
  window.__sasResetCybernetWizard = () => { idx = 0; copiedThisStep = false; render(); };

  render();
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

# 4. Cybernet reachability (low-noise naabu — AD-derived list, local evidence only)
# Doctrine: docs/LOW_NOISE_SURVEY_DOCTRINE.md — -ec -silent, no target-side writes
mkdir -p logs/targets logs/nmap
cp /tmp/sas-live/targets.txt logs/targets/live_confirm_hosts.txt
bash survey/sas-run-naabu-pipeline.sh --site live \\
  --profile keyports_cybernet_json \\
  --list logs/targets/live_confirm_hosts.txt \\
  --out logs/nmap/live_naabu.json
# Optional silent pipeline into local cybernet-detect enrichment:
# bash survey/sas-run-naabu-pipeline.sh --site live --profile keyports_cybernet_pipe \\
#   --list logs/targets/live_confirm_hosts.txt --pipe-followup

# Drag the output files from /tmp/sas-live/ and logs/nmap/ back into the dashboard drop zone.`;

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

# Naabu handoff string (record-only — Bash pipeline above is the field path)
# Import-Module .\\modules\\CybernetSurvey\\CybernetSurvey.psm1
# New-CybernetScannerCommand -TargetFile C:\\Temp\\live-targets.txt -SurveyOutDir C:\\Temp\\sas-live

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
        <span class="modal-title">Generate Survey Commands — ${targetCount} Target(s)</span>
        <p class="modal-subtitle">Copy and run these commands on a machine with network access to your targets. When complete, use Load Evidence to import the resulting files.</p>
        <button class="modal-close" id="live-cmd-close">×</button>
      </div>
      <div class="modal-body" style="gap:14px">
        <div style="padding:8px 12px;background:rgba(245,158,11,0.1);border:1px solid rgba(245,158,11,0.3);border-radius:6px;font-size:11px;color:var(--warning)">
          ⚠ Browser security prevents direct network probing from a web page.
          Copy the commands below, run them from an admin machine, then drag the resulting CSV files back into the dashboard.
        </div>
        ${section('bash-cmds', '1 — BASH  (primary — suite scripts + optional low-noise reachability)', '220px')}
        ${section('ps-cmds',   '2 — POWERSHELL  (Windows WMI / printer mapping)', '150px')}
        ${section('linux-cmds','3 — LINUX NATIVE  (quick check — no suite required)', '150px')}
        <div style="font-size:11px;color:var(--text-muted)">
          Load back via Load Evidence: network_preflight.csv · workstation_identity.csv · printer_probe.csv · logs/nmap/*_naabu.json<br>
          Optional reachability profile: <code>keyports_cybernet_json</code> · Doctrine: <code>docs/LOW_NOISE_SURVEY_DOCTRINE.md</code>
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

// ── Folder Watch (File System Access API) ────────────────────────────────────
const WATCH_SUPPORTED = typeof window !== 'undefined' && 'showDirectoryPicker' in window;
const WATCH_INTERVAL_MS = 3000;
let watchDirHandle = null;
let watchIntervalId = null;
let watchedFileMap = {}; // filename → lastModified timestamp
let watchScanInProgress = false;

function initFolderWatch() {
  const btn = document.getElementById('watch-folder-btn');
  const stopBtn = document.getElementById('watch-stop-btn');
  const unsupportedMsg = document.getElementById('watch-unsupported-msg');

  if (!WATCH_SUPPORTED) {
    if (btn) {
      btn.disabled = true;
      btn.title = 'Folder watching requires Chrome or Edge 86+.';
      btn.classList.add('watch-unsupported');
    }
    if (unsupportedMsg) unsupportedMsg.style.display = '';
    return;
  }

  if (btn) btn.addEventListener('click', startFolderWatch);
  if (stopBtn) stopBtn.addEventListener('click', stopFolderWatch);
}

async function startFolderWatch() {
  if (!WATCH_SUPPORTED) {
    toast('Folder watching requires Chrome or Edge 86+.', 'warning');
    return;
  }

  try {
    watchDirHandle = await window.showDirectoryPicker({ mode: 'read' });
  } catch (err) {
    if (err.name !== 'AbortError') {
      toast('Could not open folder: ' + err.message, 'error');
    }
    return;
  }

  watchedFileMap = {};
  _updateWatchIndicator();

  // Initial scan
  await _scanWatchedFolder(true);

  // Start polling
  if (watchIntervalId) clearInterval(watchIntervalId);
  watchIntervalId = setInterval(() => _scanWatchedFolder(false), WATCH_INTERVAL_MS);

  toast('Now watching folder: ' + watchDirHandle.name, 'success');
}

function stopFolderWatch() {
  if (watchIntervalId) {
    clearInterval(watchIntervalId);
    watchIntervalId = null;
  }
  watchDirHandle = null;
  watchedFileMap = {};
  _updateWatchIndicator();
  toast('Folder watch stopped.', 'info');
}

// Remove all chips that were loaded from a given filename and rebuild store.
// Called before re-processing a modified file so data is replaced, not doubled.
function _removeWatchedFileChips(filename) {
  const toRemove = loadedFiles.filter(f => f.name === filename);
  if (!toRemove.length) return;
  toRemove.forEach(f => {
    const el = document.getElementById(f.id);
    if (el) el.remove();
  });
  loadedFiles = loadedFiles.filter(f => f.name !== filename);
  rebuildStoreFromChips();
}

async function _scanWatchedFolder(isInitial) {
  if (!watchDirHandle) return;
  if (watchScanInProgress) return; // prevent overlapping scans
  watchScanInProgress = true;

  try {
    let newCount = 0;
    for await (const [name, handle] of watchDirHandle.entries()) {
      if (handle.kind !== 'file') continue;
      const ext = name.split('.').pop().toLowerCase();
      if (!['csv', 'json', 'xlsx', 'xls', 'txt'].includes(ext)) continue;

      const file = await handle.getFile();
      const lastMod = file.lastModified;

      if (!watchedFileMap[name]) {
        // New file — process, then record timestamp only on success
        newCount++;
        await processFile(file);
        watchedFileMap[name] = lastMod;
      } else if (watchedFileMap[name] < lastMod) {
        // Modified file — remove old chips/data first, then re-process
        newCount++;
        _removeWatchedFileChips(name);
        await processFile(file);
        watchedFileMap[name] = lastMod;
      }
    }

    _updateWatchIndicator();

    if (newCount > 0 && !isInitial) {
      toast('Watch: loaded ' + newCount + ' new/updated file' + (newCount !== 1 ? 's' : ''), 'success');
    }
  } catch (err) {
    console.warn('Folder watch scan error:', err);
    if (err.name === 'NotAllowedError' || err.name === 'SecurityError') {
      stopFolderWatch();
      toast('Folder watch permission lost — watch stopped.', 'warning');
    }
  } finally {
    watchScanInProgress = false;
  }
}

function _updateWatchIndicator() {
  const indicator = document.getElementById('watch-indicator');
  const btn = document.getElementById('watch-folder-btn');
  const stopBtn = document.getElementById('watch-stop-btn');

  const watching = !!watchDirHandle;
  // Count chips that were loaded from the watched folder (by matching filename)
  const watchedNames = Object.keys(watchedFileMap);
  const fileCount = loadedFiles.filter(f => watchedNames.includes(f.name)).length;

  if (indicator) {
    if (watching) {
      // Build indicator safely — use textContent for user-controlled folder name
      indicator.innerHTML = '';
      const dot = document.createElement('span');
      dot.className = 'watch-dot';
      const label = document.createElement('span');
      label.className = 'watch-label';
      const strong = document.createElement('strong');
      strong.textContent = watchDirHandle.name;
      label.appendChild(document.createTextNode('Watching '));
      label.appendChild(strong);
      label.appendChild(document.createTextNode(' \u2014 ' + fileCount + ' file' + (fileCount !== 1 ? 's' : '') + ' loaded'));
      indicator.appendChild(dot);
      indicator.appendChild(label);
      indicator.style.display = '';
    } else {
      indicator.innerHTML = '';
      indicator.style.display = 'none';
    }
  }

  if (btn) btn.style.display = watching ? 'none' : '';
  if (stopBtn) stopBtn.style.display = watching ? '' : 'none';
}

// ── Relay header badge ────────────────────────────────────────────────────────
function _updateHeaderRelayBadge() {
  const badge = document.getElementById('header-relay-badge');
  if (!badge) return;
  const connected = getRelayConnected();
  badge.className = 'header-relay-badge ' + (connected ? 'relay-connected' : 'relay-disconnected');
  badge.title = connected
    ? `Relay connected — ws://localhost:${RELAY_PORT} — open Network panel to run live probes`
    : `Relay offline — run: python3 dashboard/relay.py`;
  badge.textContent = connected ? '⚡ Relay' : '○ Relay';
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
  try { renderSoftwarePanel(store); } catch(e) { console.warn('Software panel error:', e); }
  updateCybernetReview();
  updateCybernetManifestSummary();
  updateCybernetAdPopulationSummary();
}

function _countUniqueTargets(rows, field = 'Target') {
  const set = new Set();
  for (const row of rows || []) {
    const t = row[field] || row.target || row.HostName || row.hostname;
    if (t) set.add(String(t).trim());
  }
  return set.size;
}

function _detectGuestNetworkWarning() {
  const rows = store.networkPreflight || [];
  if (!rows.length) return null;
  const byTarget = new Map();
  for (const row of rows) {
    const t = row.Target || row.target;
    if (!t) continue;
    if (!byTarget.has(t)) byTarget.set(t, false);
    const ping = String(row.PingStatus || row.pingstatus || '').toLowerCase();
    if (ping.includes('reach')) byTarget.set(t, true);
  }
  if (!byTarget.size) return null;
  const allDown = [...byTarget.values()].every(v => !v);
  return allDown ? 'All preflight targets appear unreachable — check guest network or wrong segment before blaming the product.' : null;
}

function updateCybernetReview() {
  const section = document.getElementById('cybernet-review');
  const body = document.getElementById('cybernet-review-body');
  if (!section || !body) return;

  const preflightRows = store.networkPreflight?.length || 0;
  const identityRows = store.workstationIdentity?.length || 0;
  const targetCount = Math.max(_countUniqueTargets(store.networkPreflight), _countUniqueTargets(store.workstationIdentity));
  const reachRows = store.naabuReachability || [];
  const reachabilityCount = reachRows.length;
  const openPortsCount = reachRows.filter(r => {
    const rv = (r.reachability || 'open').toLowerCase();
    return rv === 'open' || rv === '';
  }).length;
  const hasEvidence = preflightRows > 0 || identityRows > 0 || reachabilityCount > 0 ||
    loadedFiles.some(f => f.type === 'network-preflight' || f.type === 'workstation-identity' || f.type === 'naabu-reachability');

  if (!hasEvidence) {
    section.classList.add('hidden');
    return;
  }

  section.classList.remove('hidden');
  const guestWarn = _detectGuestNetworkWarning();
  let nextAction = 'Review the summary, then open network evidence details if you need row-level triage.';
  if (!preflightRows) nextAction = 'Load network_preflight.csv to prove network posture.';
  else if (!identityRows) nextAction = 'Load workstation_identity.csv for identity evidence.';
  else if (guestWarn) nextAction = 'Fix network posture (segment/VPN) before running more probes.';

  body.innerHTML = `
    <ul class="cybernet-review-stats">
      <li><strong>Targets in evidence:</strong> ${targetCount || '—'}</li>
      <li><strong>Preflight rows:</strong> ${preflightRows}</li>
      <li><strong>Identity rows:</strong> ${identityRows}</li>
      <li><strong>Open ports observed:</strong> ${reachabilityCount > 0 ? openPortsCount : '—'}</li>
      <li><strong>Reachability rows:</strong> ${reachabilityCount > 0 ? reachabilityCount : '—'}</li>
    </ul>
    ${guestWarn ? `<p class="cybernet-review-warn">⚠ ${sanitize(guestWarn)}</p>` : ''}
    <p class="cybernet-review-next"><strong>Next:</strong> ${sanitize(nextAction)}</p>
  `;
}

function updateCybernetManifestSummary() {
  const root = document.getElementById('cybernet-manifest-summary');
  const stats = document.getElementById('cybernet-manifest-stats');
  if (!root || !stats) return;

  const rows = store.cybernetTargetManifest || [];
  if (!rows.length) {
    root.style.display = 'none';
    stats.textContent = '';
    return;
  }

  const withHostname = rows.filter(r => r.hostname || r.dnsHostName).length;
  const withSerial = rows.filter(r => r.serial).length;
  const withMac = rows.filter(r => r.mac).length;
  const missingDnsHost = rows.filter(r => !r.hostname && !r.dnsHostName).length;
  const missingSerial = rows.filter(r => !r.serial).length;

  stats.innerHTML = [
    `<span><strong>${rows.length}</strong> manifest rows</span>`,
    `<span><strong>${withHostname}</strong> with hostname/DNS</span>`,
    `<span><strong>${withSerial}</strong> with serial</span>`,
    `<span><strong>${withMac}</strong> with MAC</span>`,
    `<span><strong>${missingDnsHost}</strong> missing hostname/DNS</span>`,
    `<span><strong>${missingSerial}</strong> missing serial</span>`,
  ].join(' · ');
  root.style.display = '';
}

function updateCybernetAdPopulationSummary() {
  const root = document.getElementById('cybernet-ad-population-summary');
  const stats = document.getElementById('cybernet-ad-population-stats');
  if (!root || !stats) return;

  const rows = store.adRegisteredPopulation || [];
  if (!rows.length) {
    root.classList.add('hidden');
    stats.textContent = '';
    return;
  }

  const enabled = rows.filter(r => {
    const bucket = (r.ReconcileBucket || '').toLowerCase();
    const en = String(r.Enabled ?? '').toLowerCase();
    return bucket !== 'disabled' && en !== 'false' && bucket !== 'ad_disabled';
  }).length;
  const disabled = rows.filter(r => {
    const bucket = (r.ReconcileBucket || '').toLowerCase();
    const en = String(r.Enabled ?? '').toLowerCase();
    return bucket === 'disabled' || bucket === 'ad_disabled' || en === 'false';
  }).length;
  const stale = rows.filter(r => (r.ReconcileBucket || '').toLowerCase() === 'stale').length;
  const missingDns = rows.filter(r => !(r.DNSHostName || r.dnsHostName)).length;
  const hostCounts = new Map();
  for (const r of rows) {
    const h = (r.HostName || '').toUpperCase();
    if (h) hostCounts.set(h, (hostCounts.get(h) || 0) + 1);
  }
  const duplicates = [...hostCounts.values()].filter(n => n > 1).length;
  const matchedManifest = rows.filter(r => (r.ReconcileBucket || '').toLowerCase() === 'matched').length;
  const adOnly = rows.filter(r => (r.ReconcileBucket || '').toLowerCase() === 'ad_only').length;

  stats.innerHTML = [
    `<span><strong>${rows.length}</strong> registered computer accounts</span>`,
    `<span><strong>${enabled}</strong> enabled candidates</span>`,
    `<span><strong>${disabled}</strong> disabled</span>`,
    `<span><strong>${stale}</strong> stale</span>`,
    `<span><strong>${missingDns}</strong> missing DNS</span>`,
    `<span><strong>${duplicates}</strong> duplicate names</span>`,
    `<span><strong>${matchedManifest}</strong> matched manifest</span>`,
    `<span><strong>${adOnly}</strong> AD-only</span>`,
  ].join(' · ');
  root.classList.remove('hidden');
}

// Update software tab badge when store changes
function updateSoftwareBadge() {
  const btn = document.querySelector('.tab-btn[data-tab="software"] .tab-badge');
  if (btn && store.software) {
    btn.textContent = (store.software.apps || []).length;
  }
}

// Expose for debug
window._sasStore = () => store;
