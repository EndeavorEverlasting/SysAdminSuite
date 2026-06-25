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
  ['not a dashboard import yet', 'no false manifest import claim'],
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

console.log(`\nShell: ${shellPassed} passed, ${shellFailed} failed`);
if (shellFailed > 0) process.exit(1);
