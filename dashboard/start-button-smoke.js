#!/usr/bin/env node
// dashboard/start-button-smoke.js — runtime exercise for the Cybernet Start button.
// Run: node dashboard/start-button-smoke.js
//
// Loads the real production bundle under a minimal DOM mock and proves that a
// press of Start never strands the user. Specifically it guards the exact field
// failure: "I clicked Start, the button disappeared, and nothing showed."
//
// Covered states:
//   1. Initial load  — wizard hidden, Start button labelled normally.
//   2. Manual click  — wizard becomes visibly open, Start transforms into a
//                      recovery control, hero status announces the open state.
//   3. Rogue inline display:none on the wizard (the original bug) — opening must
//      clear it so the wizard still shows.
//   4. ?tutorial=cybernet auto-start — routes through the same verified path.

import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));

let passed = 0;
let failed = 0;
function assert(ok, label, detail) {
  if (ok) { console.log(`PASS [start-button:${label}]`); passed++; }
  else { console.error(`FAIL [start-button:${label}]${detail ? ': ' + detail : ''}`); failed++; }
}

// ── Minimal DOM mock ────────────────────────────────────────────────────────
function makeClassList(el) {
  const set = new Set();
  return {
    add: (...c) => c.forEach(x => set.add(x)),
    remove: (...c) => c.forEach(x => set.delete(x)),
    contains: c => set.has(c),
    toggle: (c, force) => {
      const want = force === undefined ? !set.has(c) : !!force;
      if (want) set.add(c); else set.delete(c);
      return want;
    },
    _set: set,
  };
}

function makeEl(id) {
  const el = {
    _id: id || '',
    style: {},
    attributes: {},
    dataset: {},
    children: [],
    _listeners: {},
    textContent: '',
    value: '',
    disabled: false,
    innerHTML: '',
  };
  el.classList = makeClassList(el);
  el.setAttribute = (k, v) => { el.attributes[k] = String(v); };
  el.getAttribute = k => (k in el.attributes ? el.attributes[k] : null);
  el.removeAttribute = k => { delete el.attributes[k]; };
  el.addEventListener = (type, fn) => { (el._listeners[type] = el._listeners[type] || []).push(fn); };
  el.removeEventListener = () => {};
  el.dispatch = type => { (el._listeners[type] || []).forEach(fn => { try { fn({ target: el, preventDefault() {} }); } catch (_) {} }); };
  el.click = () => el.dispatch('click');
  el.scrollIntoView = () => {};
  el.focus = () => {};
  el.select = () => {};
  el.appendChild = c => { el.children.push(c); return c; };
  el.insertBefore = c => { el.children.unshift(c); return c; };
  el.removeChild = c => { el.children = el.children.filter(x => x !== c); };
  el.remove = () => {};
  el.querySelector = () => null;
  el.querySelectorAll = () => [];
  el.getClientRects = () => (isVisible(el) ? [{ width: 100, height: 50 }] : []);
  Object.defineProperty(el, 'offsetParent', { get: () => (isVisible(el) ? document.body : null) });
  Object.defineProperty(el, 'firstChild', { get: () => el.children[0] || null });
  return el;
}

function isVisible(el) {
  if (!el) return false;
  if (el.classList.contains('hidden')) return false;       // .hidden { display:none !important }
  if (el.style.display === 'none') return false;
  if (el.style.visibility === 'hidden') return false;
  return true;
}

const elements = new Map();
// Seed the ids that mirror index.html's initial state.
function seed(id, classes = []) {
  const el = makeEl(id);
  classes.forEach(c => el.classList.add(c));
  elements.set(id, el);
  return el;
}
const tutorial = seed('cybernet-tutorial', ['hidden']);
const startBtn = seed('hero-start-survey');
startBtn.textContent = 'Start Cybernet Survey';
seed('cybernet-hero-actions');
seed('cybernet-hero-status', ['hidden']);
seed('toast-container');

const document = {
  readyState: 'loading',
  _listeners: {},
  getElementById: id => {
    if (!elements.has(id)) elements.set(id, makeEl(id));
    return elements.get(id);
  },
  querySelector: () => null,
  querySelectorAll: () => [],
  createElement: tag => makeEl(`__created_${tag}`),
  addEventListener: (type, fn) => { (document._listeners[type] = document._listeners[type] || []).push(fn); },
  removeEventListener: () => {},
};
document.head = makeEl('__head');
document.body = makeEl('__body');
document.documentElement = makeEl('__html');

class MutationObserverMock { observe() {} disconnect() {} takeRecords() { return []; } }

const storage = new Map();
const localStorage = {
  getItem: k => (storage.has(k) ? storage.get(k) : null),
  setItem: (k, v) => storage.set(k, String(v)),
  removeItem: k => storage.delete(k),
};

const navigator = { clipboard: { writeText: () => Promise.resolve() }, userAgent: 'node-smoke' };

const window = {
  location: { search: '', hash: '', href: 'http://127.0.0.1:5000/dashboard/' },
  setTimeout: (fn) => { try { fn(); } catch (_) {} return 0; }, // run synchronously for the test
  clearTimeout: () => {},
  addEventListener: () => {},
  removeEventListener: () => {},
  matchMedia: () => ({ matches: false, addEventListener() {}, addListener() {} }),
  getComputedStyle: el => ({
    display: isVisible(el) ? 'block' : 'none',
    visibility: el && el.style && el.style.visibility === 'hidden' ? 'hidden' : 'visible',
  }),
  MutationObserver: MutationObserverMock,
  WebSocket: function () { return { addEventListener() {}, close() {}, send() {} }; },
  EventSource: function () { return { addEventListener() {}, close() {} }; },
  fetch: () => Promise.reject(new Error('no network in smoke test')),
  navigator,
  localStorage,
};
window.window = window;

function runScript(relPath) {
  const src = readFileSync(join(__dir, relPath), 'utf8');
  const fn = new Function(
    'window', 'document', 'navigator', 'localStorage', 'getComputedStyle',
    'MutationObserver', 'location', 'setTimeout', 'clearTimeout', 'URLSearchParams',
    'WebSocket', 'EventSource', 'fetch',
    src
  );
  fn(
    window, document, navigator, localStorage, window.getComputedStyle,
    MutationObserverMock, window.location, window.setTimeout, window.clearTimeout, URLSearchParams,
    window.WebSocket, window.EventSource, window.fetch
  );
}

function fireDomReady() {
  document.readyState = 'complete';
  // Later init functions (panels, relay) may touch APIs we do not mock and log
  // tolerated errors; the start-button wiring (initCybernetShell) runs first and
  // is what we test. Silence that expected noise so CI logs stay clean.
  const realError = console.error;
  const realWarn = console.warn;
  console.error = () => {};
  console.warn = () => {};
  try {
    (document._listeners.DOMContentLoaded || []).forEach(fn => {
      try { fn(); } catch (_) { /* tolerated */ }
    });
  } finally {
    console.error = realError;
    console.warn = realWarn;
  }
}

// ── Run the real bundle ─────────────────────────────────────────────────────
runScript('js/bundle.js');
fireDomReady();

// State 1: initial load — wizard hidden, Start labelled normally.
assert(!isVisible(tutorial), 'initial-wizard-hidden', 'wizard should start hidden');
assert(startBtn.textContent === 'Start Cybernet Survey', 'initial-start-label', `was "${startBtn.textContent}"`);
assert(typeof window.startCybernetTutorial === 'function', 'transition-exposed', 'window.startCybernetTutorial missing');

// State 3 (the original bug): a rogue inline display:none must not survive open.
tutorial.style.display = 'none';
startBtn.click();

// State 2: after click — wizard visibly open, Start transformed, status announced.
assert(isVisible(tutorial), 'click-opens-wizard', 'wizard still hidden after Start click');
assert(!tutorial.classList.contains('hidden'), 'click-removes-hidden-class', 'hidden class still present');
assert(startBtn.textContent !== 'Start Cybernet Survey' && /restart/i.test(startBtn.textContent),
  'click-transforms-start', `Start did not become a recovery control (was "${startBtn.textContent}")`);
const statusEl = document.getElementById('cybernet-hero-status');
assert(isVisible(statusEl) && /open/i.test(statusEl.textContent), 'click-shows-status',
  `hero status not shown (was "${statusEl.textContent}")`);
assert(document.getElementById('cybernet-hero-actions') && isVisible(document.getElementById('cybernet-hero-actions')),
  'hero-actions-not-stranded', 'hero actions were hidden, stranding the user');

// State 4: ?tutorial=cybernet auto-start uses the same verified path.
// Reset the wizard to the closed state, then drive the auto-launch helper.
tutorial.classList.add('hidden');
tutorial.style.display = 'none';
startBtn.textContent = 'Start Cybernet Survey';
window.location.search = '?tutorial=cybernet';
document.readyState = 'complete';
runScript('js/launch-cybernet-tutorial.js');
assert(isVisible(tutorial), 'auto-start-opens-wizard', 'auto-start left the wizard hidden');
assert(/restart/i.test(startBtn.textContent), 'auto-start-transforms-start',
  `auto-start did not transform Start (was "${startBtn.textContent}")`);

console.log(`\nStart button: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
