// tour.js — SysAdmin Suite Dashboard interactive tour
// No external dependencies. Stores completion in localStorage.

const TOUR_KEY = 'sas_tour_v1_done';

const STEPS = [
  {
    target: '#header',
    title: 'Welcome to SysAdmin Suite Dashboard',
    body:
      'This dashboard visualises output from SysAdminSuite scripts — printer mapping, ' +
      'hardware inventory, network scans, remote tasks, and software tracking. ' +
      "Let's walk through each section.",
    position: 'bottom',
  },
  {
    target: '#mode-toggle',
    title: 'Log Mode vs Live (Command-Gen) Mode',
    body:
      '<strong>Log Mode</strong> lets you drag-and-drop CSV / JSON / XLSX files produced ' +
      'by the suite scripts and visualise the results instantly.<br><br>' +
      '<strong>Live Mode</strong> accepts a list of hostnames and generates the exact ' +
      'probe commands to run on an admin Windows machine — copy, run, then drag the ' +
      'resulting CSVs back here.',
    position: 'bottom',
  },
  {
    target: '#panel-ingestion',
    title: 'Loading Data',
    body:
      'Drop <strong>CSV, JSON, XLSX, or TXT</strong> files onto the drop zone, or click ' +
      'it to browse. You can also use the <em>Paste / Type</em> button to paste raw CSV ' +
      'or JSON directly.<br><br>' +
      'The dashboard auto-detects file type by filename pattern ' +
      '(e.g. <code>Results.csv</code>, <code>network_preflight.csv</code>, ' +
      '<code>status.json</code>).',
    position: 'bottom',
  },
  {
    target: '[data-tab="printer"]',
    title: 'Printer Mapping Tab',
    body:
      'Shows the output of printer mapping runs — what queues are present, their status ' +
      '(<em>PresentNow</em>, <em>PresentBefore</em>, <em>Added</em>, <em>Removed</em>), ' +
      'and any preflight check results.<br><br>' +
      'Load a <code>Results.csv</code> or <code>Preflight.csv</code> from a ' +
      '<strong>Map-MachineWide</strong> run to populate this panel.',
    position: 'bottom',
    clickTarget: '[data-tab="printer"]',
  },
  {
    target: '[data-tab="inventory"]',
    title: 'Hardware Inventory Tab',
    body:
      'Displays machine identity data — serial numbers, IP addresses, MAC addresses, ' +
      'RAM DIMMs, and monitor details collected by the <strong>Get-MachineInfo</strong>, ' +
      '<strong>Get-RamInfo</strong>, and <strong>Get-MonitorInfo</strong> scripts.<br><br>' +
      'Load a <code>MachineInfo_Output.csv</code>, <code>RamInfo_Output.csv</code>, or ' +
      '<code>workstation_identity.csv</code> to see rows here.',
    position: 'bottom',
    clickTarget: '[data-tab="inventory"]',
  },
  {
    target: '[data-tab="tasks"]',
    title: 'Remote Tasks Tab',
    body:
      'Shows the run-control status and undo/redo history from controller and worker ' +
      'sessions.<br><br>' +
      'Load a <code>status.json</code> from a mapping run, or drag in a ' +
      '<code>QRTask</code> log file to see task output here.',
    position: 'bottom',
    clickTarget: '[data-tab="tasks"]',
  },
  {
    target: '[data-tab="network"]',
    title: 'Network & Protocol Trace Tab',
    body:
      'Visualises output from the network preflight and printer probe scripts — ' +
      'reachability, DNS resolution, and per-port TCP status for every target.<br><br>' +
      'Load a <code>network_preflight.csv</code> or <code>printer_probe.csv</code> ' +
      'produced by <code>sas-network-preflight.sh</code> or <code>sas-printer-probe.sh</code>.',
    position: 'bottom',
    clickTarget: '[data-tab="network"]',
  },
  {
    target: '[data-tab="software"]',
    title: 'Software Tracker Tab',
    body:
      'Cross-checks installed software against a known-good manifest from ' +
      '<code>sources.yaml</code>. Highlights apps that are missing, out of date, or ' +
      'present but not in the manifest.<br><br>' +
      'Load a <code>software_tracker.csv</code> or a merged superset CSV from an ' +
      '<strong>Inventory-Software</strong> run.',
    position: 'bottom',
    clickTarget: '[data-tab="software"]',
  },
  {
    target: '#status-footer',
    title: 'Status Footer',
    body:
      'When a run-control <code>status.json</code> is loaded the footer shows a live ' +
      'heartbeat dot, the current stage, and the last timestamp — so you can monitor a ' +
      'long mapping job without leaving this page.',
    position: 'top',
  },
];

// ── State ────────────────────────────────────────────────────────────────────
let currentStep = 0;
let overlay = null;
let tooltip = null;
let activeHighlight = null;

// ── Public API ────────────────────────────────────────────────────────────────
export function initTour() {
  injectStyles();
  addTourButton();
  if (!localStorage.getItem(TOUR_KEY)) {
    // Small delay so the rest of the UI finishes rendering
    setTimeout(startTour, 800);
  }
}

export function startTour() {
  currentStep = 0;
  ensureElements();
  showStep(currentStep);
}

// ── DOM creation ──────────────────────────────────────────────────────────────
function ensureElements() {
  if (overlay) return;

  overlay = document.createElement('div');
  overlay.id = 'sas-tour-overlay';
  document.body.appendChild(overlay);

  tooltip = document.createElement('div');
  tooltip.id = 'sas-tour-tooltip';
  tooltip.innerHTML = `
    <div id="sas-tour-header">
      <span id="sas-tour-counter"></span>
      <button id="sas-tour-close" title="Close tour">✕</button>
    </div>
    <div id="sas-tour-title"></div>
    <div id="sas-tour-body"></div>
    <div id="sas-tour-footer">
      <button id="sas-tour-prev">← Back</button>
      <button id="sas-tour-skip">Skip tour</button>
      <button id="sas-tour-next">Next →</button>
    </div>`;
  document.body.appendChild(tooltip);

  document.getElementById('sas-tour-close').addEventListener('click', endTour);
  document.getElementById('sas-tour-skip').addEventListener('click', endTour);
  document.getElementById('sas-tour-prev').addEventListener('click', () => {
    if (currentStep > 0) { currentStep--; showStep(currentStep); }
  });
  document.getElementById('sas-tour-next').addEventListener('click', () => {
    if (currentStep < STEPS.length - 1) { currentStep++; showStep(currentStep); }
    else finishTour();
  });
}

function addTourButton() {
  const headerSpacer = document.querySelector('.header-spacer');
  if (!headerSpacer) return;
  const btn = document.createElement('button');
  btn.id = 'sas-tour-launch-btn';
  btn.className = 'icon-btn';
  btn.title = 'Take the interactive tour';
  btn.textContent = '🗺 Tour';
  btn.addEventListener('click', startTour);
  headerSpacer.parentNode.insertBefore(btn, headerSpacer);
}

// ── Step rendering ────────────────────────────────────────────────────────────
function showStep(index) {
  const step = STEPS[index];
  if (!step) return;

  // Optionally click a tab to navigate to the right panel before highlighting
  if (step.clickTarget) {
    const clickEl = document.querySelector(step.clickTarget);
    if (clickEl) clickEl.click();
  }

  // Highlight target element
  clearHighlight();
  const targetEl = document.querySelector(step.target);
  if (targetEl) {
    targetEl.classList.add('sas-tour-highlighted');
    activeHighlight = targetEl;
    targetEl.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  // Update tooltip content
  document.getElementById('sas-tour-counter').textContent =
    `Step ${index + 1} of ${STEPS.length}`;
  document.getElementById('sas-tour-title').textContent = step.title;
  document.getElementById('sas-tour-body').innerHTML = step.body;

  // Navigation button state
  const prevBtn = document.getElementById('sas-tour-prev');
  const nextBtn = document.getElementById('sas-tour-next');
  const skipBtn = document.getElementById('sas-tour-skip');
  prevBtn.disabled = index === 0;
  const isLast = index === STEPS.length - 1;
  nextBtn.textContent = isLast ? 'Finish ✓' : 'Next →';
  skipBtn.style.display = isLast ? 'none' : '';

  // Show overlay + tooltip
  overlay.classList.add('active');
  tooltip.classList.add('active');

  // Position tooltip relative to the target element
  positionTooltip(targetEl, step.position || 'bottom');
}

function positionTooltip(targetEl, position) {
  tooltip.style.left = '';
  tooltip.style.top = '';
  tooltip.style.bottom = '';
  tooltip.style.transform = '';

  if (!targetEl) {
    // Centered fallback
    tooltip.style.top = '50%';
    tooltip.style.left = '50%';
    tooltip.style.transform = 'translate(-50%, -50%)';
    return;
  }

  // Wait one frame for the tooltip to be visible so we can read its size
  requestAnimationFrame(() => {
    const rect = targetEl.getBoundingClientRect();
    const tw = tooltip.offsetWidth || 340;
    const th = tooltip.offsetHeight || 220;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const GAP = 14;

    let left = rect.left + rect.width / 2 - tw / 2;
    let top;

    if (position === 'top') {
      top = rect.top - th - GAP + window.scrollY;
    } else {
      top = rect.bottom + GAP + window.scrollY;
    }

    // Clamp horizontally
    left = Math.max(12, Math.min(left, vw - tw - 12));
    // Clamp vertically
    top = Math.max(window.scrollY + 12, top);
    if (top + th > window.scrollY + vh - 12) {
      top = rect.top + window.scrollY - th - GAP;
    }

    tooltip.style.left = `${left}px`;
    tooltip.style.top = `${top}px`;
    tooltip.style.transform = '';
  });
}

function clearHighlight() {
  if (activeHighlight) {
    activeHighlight.classList.remove('sas-tour-highlighted');
    activeHighlight = null;
  }
}

function endTour() {
  // Mark complete whether the user Skips, Closes, or Finishes — prevents
  // auto-re-launch on every subsequent visit.
  localStorage.setItem(TOUR_KEY, '1');
  clearHighlight();
  if (overlay) overlay.classList.remove('active');
  if (tooltip) tooltip.classList.remove('active');
}

function finishTour() {
  endTour();
}

// ── Styles ────────────────────────────────────────────────────────────────────
function injectStyles() {
  if (document.getElementById('sas-tour-styles')) return;
  const style = document.createElement('style');
  style.id = 'sas-tour-styles';
  style.textContent = `
    #sas-tour-overlay {
      display: none;
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,.45);
      z-index: 8000;
      pointer-events: none;
    }
    #sas-tour-overlay.active { display: block; }

    #sas-tour-tooltip {
      display: none;
      position: absolute;
      z-index: 8100;
      width: 360px;
      max-width: calc(100vw - 24px);
      background: #1a2236;
      border: 1px solid #3a5080;
      border-radius: 10px;
      box-shadow: 0 8px 32px rgba(0,0,0,.6);
      color: #d8e6f8;
      font-family: 'Segoe UI', system-ui, sans-serif;
      font-size: 13px;
      line-height: 1.55;
    }
    #sas-tour-tooltip.active { display: block; }

    #sas-tour-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 10px 14px 0;
    }
    #sas-tour-counter {
      font-size: 11px;
      color: #6b8ab0;
      font-weight: 600;
      letter-spacing: .04em;
      text-transform: uppercase;
    }
    #sas-tour-close {
      background: none;
      border: none;
      color: #6b8ab0;
      font-size: 15px;
      cursor: pointer;
      line-height: 1;
      padding: 0 2px;
    }
    #sas-tour-close:hover { color: #d8e6f8; }

    #sas-tour-title {
      font-size: 15px;
      font-weight: 700;
      color: #90cdf4;
      padding: 6px 14px 2px;
    }
    #sas-tour-body {
      padding: 6px 14px 14px;
      color: #b8ccdf;
      font-size: 12.5px;
    }
    #sas-tour-body code {
      background: #0d1420;
      color: #f6ad55;
      padding: 1px 5px;
      border-radius: 3px;
      font-size: 11.5px;
    }
    #sas-tour-body strong { color: #d8e6f8; }
    #sas-tour-body em { color: #9ae6b4; font-style: normal; font-weight: 600; }

    #sas-tour-footer {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 10px 14px 12px;
      border-top: 1px solid #2d4060;
    }
    #sas-tour-footer button {
      border: none;
      border-radius: 6px;
      padding: 6px 14px;
      font-size: 12px;
      font-weight: 600;
      cursor: pointer;
      transition: opacity .15s;
    }
    #sas-tour-prev {
      background: #253550;
      color: #90cdf4;
    }
    #sas-tour-prev:disabled {
      opacity: .35;
      cursor: default;
    }
    #sas-tour-skip {
      background: transparent;
      color: #6b8ab0;
      margin-right: auto;
      padding-left: 4px;
      font-weight: 400;
    }
    #sas-tour-skip:hover { color: #d8e6f8; }
    #sas-tour-next {
      background: #2b6cb0;
      color: #fff;
      margin-left: auto;
    }
    #sas-tour-next:hover { opacity: .85; }

    .sas-tour-highlighted {
      outline: 3px solid #4299e1 !important;
      outline-offset: 3px;
      border-radius: 6px;
      position: relative;
      z-index: 8050;
      box-shadow: 0 0 0 6px rgba(66,153,225,.18);
    }

    #sas-tour-launch-btn {
      margin-right: 6px;
    }
  `;
  document.head.appendChild(style);
}
