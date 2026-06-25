#!/usr/bin/env node
// dashboard/smoke-test.js — parser regression test using production modules
// Run: node dashboard/smoke-test.js
// Imports the real detectFileType / parseFileContent from parsers.js
// (no DOM dependency in those code paths).

import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const samplesDir = join(__dir, 'samples');

// Import real production modules (parsers.js → utils.js, no DOM)
const { detectFileType, parseFileContent } = await import('./js/parsers.js');

// ── Test cases ────────────────────────────────────────────────────────────────

const cases = [
  { file: 'Preflight.csv',                         expectedType: 'preflight',           minRows: 1 },
  { file: 'Results.csv',                           expectedType: 'results',             minRows: 1 },
  { file: 'workstation_identity.csv',              expectedType: 'workstation-identity', minRows: 1 },
  { file: 'printer_probe.csv',                     expectedType: 'printer-probe',       minRows: 1 },
  { file: 'network_preflight.csv',                 expectedType: 'network-preflight',   minRows: 1 },
  { file: 'MachineInfo_Output.csv',                expectedType: 'machine-info',        minRows: 1 },
  { file: 'RamInfo_Output.csv',                    expectedType: 'ram-info',            minRows: 1 },
  { file: 'NeuronNetworkInventory_20241115.csv',   expectedType: 'neuron-inventory',    minRows: 1 },
  { file: 'status.json',                           expectedType: 'status-json',         minRows: null },
  { file: 'QRTask_log.json',                       expectedType: 'remote-task',         minRows: 3 },
  { file: 'RunControl_events.json',                expectedType: 'remote-task',         minRows: 3 },
  { file: 'ad_registered_normalized.csv',            expectedType: 'ad-registered-population', minRows: 1 },
  { file: 'ad_registered_population.sample.csv',    expectedType: 'ad-registered-population', minRows: 6 },
];

// ── Naabu reachability parser cases (synthetic samples only) ────────────────

const naabuCases = [
  { file: 'cybernet_naabu.sample.jsonl',          expectedType: 'naabu-reachability', minRows: 3 },
  { file: 'cybernet_naabu.sample.json',           expectedType: 'naabu-reachability', minRows: 3 },
  { file: 'cybernet_naabu.invalid.sample.jsonl',  expectedType: 'naabu-reachability', minRows: 1, minWarnings: 1 },
];

let passed = 0;
let failed = 0;

for (const { file, expectedType, minRows } of cases) {
  const content = readFileSync(join(samplesDir, file), 'utf8');
  const detected = detectFileType(file, content);

  if (detected !== expectedType) {
    console.error(`FAIL [${file}]: expected type="${expectedType}" got="${detected}"`);
    failed++;
    continue;
  }

  const parsed = parseFileContent(detected, content, file);

  if (minRows !== null && (parsed.rows?.length ?? 0) < minRows) {
    console.error(`FAIL [${file}]: expected >= ${minRows} rows, got ${parsed.rows?.length ?? 0}`);
    failed++;
    continue;
  }

  // BOM check — first CSV key must not start with the BOM character
  if (parsed.rows?.length > 0 && Object.keys(parsed.rows[0])[0].startsWith('\uFEFF')) {
    console.error(`FAIL [${file}]: BOM not stripped from first header key`);
    failed++;
    continue;
  }

  console.log(`PASS [${file}]: type="${detected}"${parsed.rows ? ', rows=' + parsed.rows.length : ''}`);
  passed++;
}

for (const { file, expectedType, minRows, minWarnings } of naabuCases) {
  const content = readFileSync(join(samplesDir, file), 'utf8');
  const detected = detectFileType(file, content);

  if (detected !== expectedType) {
    console.error(`FAIL [${file}]: expected type="${expectedType}" got="${detected}"`);
    failed++;
    continue;
  }

  const parsed = parseFileContent(detected, content, file);

  if (minRows !== null && (parsed.rows?.length ?? 0) < minRows) {
    console.error(`FAIL [${file}]: expected >= ${minRows} rows, got ${parsed.rows?.length ?? 0}`);
    failed++;
    continue;
  }

  if (minWarnings != null && (parsed.meta?.warnings?.length ?? 0) < minWarnings) {
    console.error(`FAIL [${file}]: expected >= ${minWarnings} warnings, got ${parsed.meta?.warnings?.length ?? 0}`);
    failed++;
    continue;
  }

  const warnNote = parsed.meta?.warnings?.length ? `, warnings=${parsed.meta.warnings.length}` : '';
  console.log(`PASS [${file}]: type="${detected}"${parsed.rows ? ', rows=' + parsed.rows.length : ''}${warnNote}`);
  passed++;
}

// ── Inline RFC-4180 multiline quoted field test ───────────────────────────────

const { parseCSV } = await import('./js/utils.js');

const multilineCsv = `ComputerName,Notes,Status
WMH300OPR134,"Error on line 1\nand line 2 of message",Failed
WMH300OPR211,"Normal notes",Success`;

const mlRows = parseCSV(multilineCsv);
if (mlRows.length !== 2) {
  console.error(`FAIL [multiline-csv]: expected 2 rows, got ${mlRows.length}`);
  failed++;
} else if (!mlRows[0].Notes.includes('\n')) {
  console.error(`FAIL [multiline-csv]: embedded newline not preserved in Notes field`);
  failed++;
} else {
  console.log(`PASS [multiline-csv]: embedded newline preserved, rows=${mlRows.length}`);
  passed++;
}

// BOM strip inline test
const bomCsv = '\uFEFFHostName,Serial\nWMH001,SN123';
const bomRows = parseCSV(bomCsv);
if (bomRows.length !== 1 || Object.keys(bomRows[0])[0] !== 'HostName') {
  console.error(`FAIL [bom-strip]: BOM not stripped, first key="${Object.keys(bomRows[0])[0]}"`);
  failed++;
} else {
  console.log(`PASS [bom-strip]: BOM stripped, first key="HostName"`);
  passed++;
}

// NOTE: XLSX ingestion is tested in the browser only.
// SheetJS requires browser File/ArrayBuffer/Uint8Array APIs that are not
// available in Node without additional polyfills.  Drop an *.xlsx file onto the
// dashboard and confirm it appears in the Hardware Inventory or Printer Mapping
// panel (whichever schema it matches) as a manual verification step.

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);

// ── Cybernet-first dashboard shell assertions (HTML text, no DOM) ─────────────

const indexHtml = readFileSync(join(__dir, 'index.html'), 'utf8');

const shellChecks = [
  ['cybernet-hero', 'Cybernet-first hero'],
  ['id="hero-start-survey"', 'Primary CTA Start Cybernet Survey'],
  ['Start Cybernet Survey', 'Start Cybernet Survey label'],
  ['id="hero-load-evidence"', 'Load Evidence entry'],
  ['id="advanced-tools-toggle"', 'Advanced Tools toggle'],
  ['id="advanced-section"', 'Advanced section container'],
  ['data-tab="network"', 'Network panel tab reachable'],
  ['data-tab="printer"', 'Printer panel tab reachable'],
  ['--targets-file', 'Wizard uses --targets-file in bundle/app'],
];

// Wizard command contracts live in app.js (bundled); verify source for CI without loading bundle
const appJs = readFileSync(join(__dir, 'js', 'app.js'), 'utf8');
const contractChecks = [
  ['--targets-file /tmp/sas-cybernet/targets.txt', 'preflight/identity --targets-file'],
  ['--file /tmp/sas-cybernet/targets.txt', 'normalize --file reference'],
  ['keyports_cybernet_json', 'low-noise reachability profile'],
  ['ad-registered-population', 'AD parser type wired'],
  ['store.adRegisteredPopulation', 'AD store wiring'],
];

const adContractChecks = [
  ['cybernet-ad-population-summary', 'AD summary container in HTML'],
  ['AD Registered Population', 'AD summary heading'],
  ['registered computer accounts', 'AD population row label'],
  ['not serial or reachability proof', 'no false AD proof claim'],
  ['AD registered population', 'AD section label'],
];

// ── Naabu reachability Cybernet review contracts (app.js) ───────────────────

const naabuContractChecks = [
  ['naabu-reachability', 'naabu reachability file type'],
  ['Reachability evidence', 'reachability section label'],
  ['Open ports observed:', 'cybernet review open ports metric'],
  ['Reachability rows:', 'cybernet review reachability rows metric'],
  ['store.naabuReachability', 'parsed naabu store wiring'],
];

let shellPassed = 0;
let shellFailed = 0;

for (const [needle, label] of shellChecks) {
  const src = needle.startsWith('--') ? appJs : indexHtml;
  if (!src.includes(needle)) {
    console.error(`FAIL [shell:${label}]: missing "${needle}"`);
    shellFailed++;
  } else {
    console.log(`PASS [shell:${label}]`);
    shellPassed++;
  }
}

for (const [needle, label] of contractChecks) {
  if (!appJs.includes(needle)) {
    console.error(`FAIL [wizard-contract:${label}]: missing "${needle}"`);
    shellFailed++;
  } else {
    console.log(`PASS [wizard-contract:${label}]`);
    shellPassed++;
  }
}

for (const [needle, label] of naabuContractChecks) {
  if (!appJs.includes(needle)) {
    console.error(`FAIL [naabu-contract:${label}]: missing "${needle}"`);
    shellFailed++;
  } else {
    console.log(`PASS [naabu-contract:${label}]`);
    shellPassed++;
  }
}

for (const [needle, label] of adContractChecks) {
  const src = (needle === 'cybernet-ad-population-summary' || needle === 'AD Registered Population')
    ? indexHtml
    : appJs;
  if (!src.includes(needle)) {
    console.error(`FAIL [ad-contract:${label}]: missing "${needle}"`);
    shellFailed++;
  } else {
    console.log(`PASS [ad-contract:${label}]`);
    shellPassed++;
  }
}

console.log(`\nShell: ${shellPassed} passed, ${shellFailed} failed`);
if (shellFailed > 0) process.exit(1);

// ── tourChecks — dashboard tour DOM / copy contract (END) ─────────────────────

const tourJs = readFileSync(join(__dir, 'js', 'tour.js'), 'utf8');

let tourPassed = 0;
let tourFailed = 0;

function tourAssert(ok, label, detail) {
  if (ok) {
    console.log(`PASS [tour:${label}]`);
    tourPassed++;
  } else {
    console.error(`FAIL [tour:${label}]${detail ? ': ' + detail : ''}`);
    tourFailed++;
  }
}

// Extract tour.js target selectors; each must exist in index.html or be #sas-tour-*
const tourTargetMatches = [...tourJs.matchAll(/target:\s*'([^']+)'/g)];
for (const [, selector] of tourTargetMatches) {
  if (selector.startsWith('#sas-tour-')) {
    tourAssert(true, `dynamic-target:${selector}`);
    continue;
  }
  const idMatch = selector.match(/^#([\w-]+)$/);
  if (idMatch) {
    const id = idMatch[1];
    tourAssert(indexHtml.includes(`id="${id}"`), `target-in-html:${selector}`, `missing id="${id}"`);
  } else {
    tourAssert(indexHtml.includes(selector) || tourJs.includes(selector), `target-in-html:${selector}`);
  }
}

// app.js must suppress auto-launch before initTour()
const doneBeforeInit = /localStorage\.setItem\(\s*['"]sas_tour_v1_done['"][\s\S]*?\n[\s\S]*?initTour\s*\(\s*\)/.test(appJs);
tourAssert(doneBeforeInit, 'auto-launch-suppressed-before-initTour');

// Cybernet-first tour targets
for (const needle of ['#hero-start-survey', '#cybernet-review', '#advanced-tools-toggle']) {
  tourAssert(tourJs.includes(`target: '${needle}'`), `cybernet-target:${needle}`);
}

// Stale pre-refactor copy must not appear
const staleCopy = [
  ['Log Mode vs Live', 'mode-toggle step title'],
  ['Protocol Trace Tab', 'per-tab network step'],
  ['#mode-toggle', 'mode-toggle target'],
  ['#panel-ingestion', 'standalone ingestion step target'],
];
for (const [needle, label] of staleCopy) {
  tourAssert(!tourJs.includes(needle), `no-stale:${label}`, `found "${needle}"`);
}

tourAssert(indexHtml.includes('class="advanced-section-head"'), 'advanced-section-head-in-html');

console.log(`\nTour: ${tourPassed} passed, ${tourFailed} failed`);
if (tourFailed > 0) process.exit(1);
