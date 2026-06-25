// tour.js — SysAdmin Suite Dashboard interactive tour
// No external dependencies. Stores completion in localStorage.

const TOUR_KEY = 'sas_tour_v1_done';
const PANELS_VISITED_KEY = 'sas_panels_visited_v1';
const PANEL_NAMES = ['printer', 'inventory', 'tasks', 'network', 'software'];

const STEPS = [
  {
    target: '#header',
    title: 'Welcome to SysAdmin Suite Dashboard',
    body:
      'This dashboard guides Cybernet field surveys — find targets, verify network posture, ' +
      'collect identity evidence, and package results for review. ' +
      "Let's walk through the Cybernet-first workflow.",
    position: 'bottom',
  },
  {
    target: '#hero-start-survey',
    title: 'Start here',
    body:
      'Tap <strong>Start Cybernet Survey</strong> to open the step-by-step wizard. ' +
      'It walks you through target prep, network checks, identity evidence, reachability, ' +
      'and packaging — with copy-ready commands for each step.',
    position: 'bottom',
  },
  {
    target: '#cybernet-progress-rail',
    title: 'Survey progress',
    body:
      'The progress rail shows where you are in the five-step survey: ' +
      '<em>Targets</em> → <em>Network posture</em> → <em>Identity evidence</em> → ' +
      '<em>Reachability</em> → <em>Review package</em>. ' +
      'Labels update as you advance through the wizard.',
    position: 'bottom',
  },
  {
    target: '#drop-zone',
    title: 'Load evidence',
    body:
      'After running survey commands on an admin workstation, load the output here. ' +
      'Drop <strong>CSV, JSON, XLSX, or TXT</strong> files onto the drop zone, or click to browse. ' +
      'Use <em>Paste data</em> to paste raw CSV or JSON directly.<br><br>' +
      'You can also open this panel from <strong>Load Evidence</strong> on the hero.',
    position: 'bottom',
    reveal: () => {
      document.getElementById('evidence-loader')?.classList.remove('hidden');
    },
  },
  {
    target: '#cybernet-review',
    title: 'Review results',
    body:
      'Once recognized evidence is loaded, the review summary appears here — ' +
      'a consolidated readout of your Cybernet survey package. ' +
      'Use the link below to open detailed network evidence when you need more depth.',
    position: 'bottom',
    reveal: () => {
      document.getElementById('cybernet-review')?.classList.remove('hidden');
    },
  },
  {
    target: '#advanced-tools-toggle',
    title: 'Advanced tools',
    body:
      'When you need capabilities beyond the Cybernet wizard — reviewing raw evidence, ' +
      'generating survey commands, or opening detailed panels — use ' +
      '<strong>Advanced Tools</strong> in the header.',
    position: 'bottom',
  },
  {
    target: '#advanced-section',
    title: 'Details if needed',
    body:
      'Inside Advanced Tools you can switch between <strong>Review Evidence</strong> and ' +
      '<strong>Generate Survey Commands</strong>, import target lists, and open ' +
      '<em>Advanced Review Panels</em> for printer mapping, hardware inventory, ' +
      'remote tasks, network detail, and software tracking.',
    position: 'bottom',
    reveal: () => {
      document.getElementById('advanced-section')?.classList.remove('hidden');
      document.getElementById('advanced-tools-toggle')?.setAttribute('aria-expanded', 'true');
    },
  },
  {
    target: '#status-footer',
    title: 'Status footer',
    body:
      'When a run-control <code>status.json</code> is loaded the footer shows a live ' +
      'heartbeat dot, the current stage, and the last timestamp — so you can monitor a ' +
      'long mapping job without leaving this page.',
    position: 'top',
  },
  {
    target: '#sas-tour-launch-btn',
    title: "You're all set!",
    body:
      'That covers the Cybernet-first workflow on the SysAdmin Suite Dashboard.<br><br>' +
      'You can relaunch this tour from <strong>Interactive tour</strong> inside ' +
      '<strong>Advanced Tools</strong>, or by pressing ' +
      '<kbd style="background:#0d1420;color:#f6ad55;' +
      'padding:1px 6px;border-radius:3px;font-size:11.5px;border:1px solid #3a5080">?</kbd> ' +
      'anywhere on the page.',
    position: 'bottom',
    reveal: () => {
      document.getElementById('advanced-section')?.classList.remove('hidden');
      document.getElementById('advanced-tools-toggle')?.setAttribute('aria-expanded', 'true');
    },
  },
];

// ── State ────────────────────────────────────────────────────────────────────
let currentStep = 0;
let overlay = null;
let tooltip = null;
let activeHighlight = null;

// ── Panel Visit Tracking ──────────────────────────────────────────────────────
function _getVisited() {
  try {
    return JSON.parse(localStorage.getItem(PANELS_VISITED_KEY) || '{}');
  } catch (_) {
    return {};
  }
}

function _getUnvisitedCount() {
  const visited = _getVisited();
  return PANEL_NAMES.filter(p => !visited[p]).length;
}

function _updateTabIndicators() {
  const visited = _getVisited();
  PANEL_NAMES.forEach(panel => {
    const tab = document.querySelector(`.tab-btn[data-tab="${panel}"]`);
    if (!tab) return;
    let dot = tab.querySelector('.tab-new-dot');
    if (!visited[panel]) {
      if (!dot) {
        dot = document.createElement('span');
        dot.className = 'tab-new-dot';
        dot.title = 'Load data into this panel to explore it';
        tab.appendChild(dot);
      }
    } else {
      if (dot) dot.remove();
    }
  });
}

function _updateTourButtonBadge() {
  const btn = document.getElementById('sas-tour-launch-btn');
  if (!btn) return;
  const count = _getUnvisitedCount();
  let badge = btn.querySelector('.tour-unvisited-badge');
  if (count > 0) {
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'tour-unvisited-badge';
      btn.appendChild(badge);
    }
    badge.textContent = count;
  } else {
    if (badge) badge.remove();
  }
}

export function markPanelVisited(panelName) {
  if (!PANEL_NAMES.includes(panelName)) return;
  const visited = _getVisited();
  if (visited[panelName]) return;
  visited[panelName] = true;
  localStorage.setItem(PANELS_VISITED_KEY, JSON.stringify(visited));
  _updateTabIndicators();
  _updateTourButtonBadge();
}

export function initPanelBadges() {
  _updateTabIndicators();
  _updateTourButtonBadge();
}

// ── Public API ────────────────────────────────────────────────────────────────
export function initTour() {
  injectStyles();
  addTourButton();
  addKeyboardShortcut();
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
  btn.title = 'Take the interactive tour  [Shortcut: ?]';
  btn.textContent = '🗺 Tour';
  btn.addEventListener('click', startTour);
  headerSpacer.parentNode.insertBefore(btn, headerSpacer);
}

function addKeyboardShortcut() {
  document.addEventListener('keydown', function (e) {
    // Ignore when typing in an input, textarea, or contenteditable element
    const tag = (e.target && e.target.tagName) ? e.target.tagName.toUpperCase() : '';
    if (tag === 'INPUT' || tag === 'TEXTAREA' || e.target.isContentEditable) return;
    if (e.key === '?') {
      startTour();
    }
  });
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

  // Reveal hidden sections before measuring target geometry
  if (step.reveal) {
    step.reveal();
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

function _isZeroSizeRect(rect) {
  return !rect || (rect.width === 0 && rect.height === 0);
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
    if (_isZeroSizeRect(rect)) {
      tooltip.style.top = '50%';
      tooltip.style.left = '50%';
      tooltip.style.transform = 'translate(-50%, -50%)';
      return;
    }

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
