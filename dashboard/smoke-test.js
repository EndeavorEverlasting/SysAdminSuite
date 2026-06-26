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
  { file: 'cybernet_targets.sample.csv',           expectedType: 'cybernet-target-manifest', minRows: 2 },
  { file: 'ad_registered_normalized.csv',            expectedType: 'ad-registered-population', minRows: 1 },
  { file: 'ad_registered_population.sample.csv',    expectedType: 'ad-registered-population', minRows: 6 },
  { file: 'dns_infrastructure_classification.sample.csv', expectedType: 'survey-classification', minRows: 2 },
];

// ── Naabu reachability parser cases (synthetic samples only) ────────────────

const naabuCases = [
  { file: 'cybernet_naabu.sample.jsonl',          expectedType: 'naabu-reachability', minRows: 3 },
  { file: 'cybernet_naabu.sample.json',           expectedType: 'naabu-reachability', minRows: 3 },
  { file: 'cybernet_naabu.invalid.sample.jsonl',  expectedType: 'naabu-reachability', minRows: 1, minWarnings: 1 },
];

// Toolbox status fixtures include tool names such as "naabu"; filename hints
// must keep them on the toolbox parser path before generic reachability rules.
const toolboxStatusCases = [
  { file: 'toolbox-status-all-ok.json',             expectedType: 'toolbox-status', minRows: 1, actionNeeded: false },
  { file: 'toolbox-status-missing-naabu.json',      expectedType: 'toolbox-status', minRows: 1, actionNeeded: true },
  { file: 'toolbox-status-update-available.json',   expectedType: 'toolbox-status', minRows: 1, actionNeeded: true },
];

// Generic filenames whose headers resemble manifest columns but must NOT classify as manifest
const manifestNegativeCases = [
  { file: 'machine_info_negative_manifest.sample.csv',      expectedType: 'machine-info' },
  { file: 'workstation_identity_negative_manifest.sample.csv', expectedType: 'workstation-identity' },
  { file: 'broad_inventory_negative_manifest.sample.csv',   expectedType: 'unknown' },
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

for (const { file, expectedType, minRows, actionNeeded } of toolboxStatusCases) {
  const content = readFileSync(join(samplesDir, file), 'utf8');
  const detected = detectFileType(file, content);

  if (detected !== expectedType) {
    console.error(`FAIL [${file}]: expected type="${expectedType}" got="${detected}"`);
    failed++;
    continue;
  }

  const parsed = parseFileContent(detected, content, file);

  if ((parsed.rows?.length ?? 0) < minRows) {
    console.error(`FAIL [${file}]: expected >= ${minRows} tools, got ${parsed.rows?.length ?? 0}`);
    failed++;
    continue;
  }

  if (parsed.data?.actionNeeded !== actionNeeded) {
    console.error(`FAIL [${file}]: expected actionNeeded=${actionNeeded} got=${parsed.data?.actionNeeded}`);
    failed++;
    continue;
  }

  console.log(`PASS [${file}]: type="${detected}", tools=${parsed.rows.length}, actionNeeded=${parsed.data.actionNeeded}`);
  passed++;
}

for (const { file, expectedType } of manifestNegativeCases) {
  const content = readFileSync(join(samplesDir, file), 'utf8');
  const detected = detectFileType(file, content);

  if (detected === 'cybernet-target-manifest') {
    console.error(`FAIL [${file}]: must NOT classify as cybernet-target-manifest`);
    failed++;
    continue;
  }

  if (detected !== expectedType) {
    console.error(`FAIL [${file}]: expected type="${expectedType}" got="${detected}" (not manifest)`);
    failed++;
    continue;
  }

  console.log(`PASS [${file}]: not manifest, type="${detected}"`);
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

// Survey classification: parser fields and buckets must stay visible for drill-down
{
  const content = readFileSync(join(samplesDir, 'dns_infrastructure_classification.sample.csv'), 'utf8');
  const parsed = parseFileContent('survey-classification', content, 'dns_infrastructure_classification.sample.csv');
  const appSourceForBuckets = readFileSync(join(__dir, 'js', 'app.js'), 'utf8');
  const bucketStart = appSourceForBuckets.indexOf('function _classificationRole');
  const bucketEnd = appSourceForBuckets.indexOf('function humanizeClassificationWhy');
  const infra = parsed.rows.filter(r => (r.deviceRole || '').startsWith('infrastructure_'));
  const targets = parsed.rows.filter(r => (r.countsToward || '').toLowerCase() === 'yes');
  const withReason = parsed.rows.filter(r => r.roleSignals && r.nextAction);
  let buckets = null;
  if (bucketStart >= 0 && bucketEnd > bucketStart) {
    const bucketSource = appSourceForBuckets.slice(bucketStart, bucketEnd);
    ({ bucketClassificationRows: buckets } = new Function(`${bucketSource}; return { bucketClassificationRows };`)());
    buckets = buckets(parsed.rows);
  }
  const needsReviewHosts = new Set((buckets?.needsReview || []).map(r => r.hostName));
  const expectedNeedsReviewHosts = [
    'SYN-NO-HOST-001',
    'SYN-NO-DNS-001',
    'SYN-REVIEW-ONLY-001',
    'SYN-DISCOVERY-ONLY-001',
    'SYN-INFRA-UNKNOWN-001',
  ];
  if (infra.length < 1) {
    console.error('FAIL [classification]: expected at least one infrastructure row');
    failed++;
  } else if (targets.length < 1) {
    console.error('FAIL [classification]: expected at least one Cybernet target row');
    failed++;
  } else if (!buckets) {
    console.error('FAIL [classification]: could not load bucketClassificationRows from app.js');
    failed++;
  } else if (!expectedNeedsReviewHosts.every(host => needsReviewHosts.has(host))) {
    console.error('FAIL [classification]: expected all synthetic review triggers in needsReview bucket');
    failed++;
  } else if (needsReviewHosts.has('WTS001OPR001')) {
    console.error('FAIL [classification]: resolved target row should not require review');
    failed++;
  } else if (withReason.length !== parsed.rows.length) {
    console.error('FAIL [classification]: every row should carry roleSignals and nextAction');
    failed++;
  } else if (!parsed.rows.some(r => r.sourceFile === 'synthetic_list_dns.txt')) {
    console.error('FAIL [classification]: row-level SourceFile column should be preserved');
    failed++;
  } else {
    console.log('PASS [classification]: targets, infrastructure, needs-review buckets, and reasons parsed');
    passed++;
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);

// ── Cybernet-first dashboard shell assertions (HTML text, no DOM) ─────────────

const indexHtml = readFileSync(join(__dir, 'index.html'), 'utf8');

const shellChecks = [
  ['toolbox-status-banner', 'Toolbox status banner'],
  ['toolbox-hero', 'Toolbox hero'],
  ['id="hero-start-toolbox"', 'Primary CTA Start Toolbox Check'],
  ['id="toolbox-checklist"', 'Toolbox checklist'],
  ['id="toolbox-tutorial"', 'Toolbox tutorial container'],
  ['id="toolbox-command-mode"', 'Toolbox command mode badge'],
  ['id="toolbox-command-explain"', 'Toolbox command explainer'],
  ['id="toolbox-command-explain-details"', 'Toolbox command details'],
  ['repo-setup-hero', 'Repo Setup hero'],
  ['id="hero-start-setup"', 'Primary CTA Start Repo Setup'],
  ['id="repo-setup-tutorial"', 'Repo Setup tutorial container'],
  ['id="repo-setup-command-mode"', 'Repo Setup command mode badge'],
  ['id="repo-setup-command-explain"', 'Repo Setup command explainer'],
  ['id="repo-setup-command-explain-details"', 'Repo Setup command details'],
  ['id="hero-open-cybernet"', 'Repo setup handoff to Cybernet'],
  ['cybernet-hero', 'Cybernet-first hero'],
  ['id="cybernet-command-mode"', 'Cybernet command mode badge'],
  ['id="cybernet-command-explain"', 'Cybernet command explainer'],
  ['id="cybernet-command-explain-details"', 'Cybernet command details'],
  ['software-tracker-hero', 'Software Tracker install hero'],
  ['id="hero-start-install"', 'Primary CTA Start Software Tracker Install'],
  ['id="sw-command-mode"', 'Software Tracker command mode badge'],
  ['id="sw-command-explain"', 'Software Tracker command explainer'],
  ['id="sw-command-explain-details"', 'Software Tracker command details'],
  ['wizard-run-note', 'Manual Next never runs clarifier'],
  ['workflow-tutorial', 'Shared workflow tutorial CSS class'],
  ['Start', 'Cybernet Start rail label'],
  ['Load targets', 'Cybernet Load targets rail label'],
  ['Review results', 'Cybernet Review results rail label'],
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
  ['initToolboxTutorial', 'Toolbox tutorial init'],
  ['initToolboxShell', 'Toolbox hero shell'],
  ['window.startToolboxTutorial', 'Toolbox transition exposed'],
  ['toolbox-status', 'Toolbox parser type wired'],
  ['__sasFetchedToolboxStatus', 'Toolbox fetched status preserved'],
  ['initRepoSetupTutorial', 'Repo Setup tutorial init'],
  ['initRepoSetupShell', 'Repo Setup hero shell'],
  ['window.startRepoSetupTutorial', 'Repo Setup transition exposed'],
  ['software-tracker-install-plan', 'install plan parser type wired'],
  ['setSoftwareInstallPlan', 'install plan state wiring'],
  ['initSoftwareTrackerTutorial', 'Software Tracker tutorial init'],
  ['initSoftwareTrackerShell', 'Software Tracker hero shell'],
  ['--targets-file /tmp/sas-cybernet/targets.txt', 'preflight/identity --targets-file'],
  ['--file /tmp/sas-cybernet/targets.txt', 'normalize --file reference'],
  ['keyports_cybernet_json', 'low-noise reachability profile'],
  ['cybernet-target-manifest', 'manifest parser type wired'],
  ['store.cybernetTargetManifest', 'manifest store wiring'],
  ['ad-registered-population', 'AD parser type wired'],
  ['store.adRegisteredPopulation', 'AD store wiring'],
  ['bucketClassificationRows', 'classification bucket helper'],
  ['humanizeClassificationWhy', 'classification why helper'],
  ['cybernet-classification-drilldown', 'classification drilldown container'],
  ['Network / AP', 'classification network AP section'],
  ['Needs Review', 'classification needs-review section'],
];

// ── Naabu reachability Cybernet review contracts (app.js) ───────────────────

const naabuContractChecks = [
  ['naabu-reachability', 'naabu reachability file type'],
  ['Reachability evidence', 'reachability section label'],
  ['Open ports observed:', 'cybernet review open ports metric'],
  ['Reachability rows:', 'cybernet review reachability rows metric'],
  ['store.naabuReachability', 'parsed naabu store wiring'],
];

const panelSoftwareJs = readFileSync(join(__dir, 'js', 'panel-software.js'), 'utf8');

const softwareInstallChecks = [
  ['Preview Install Plan', 'Preview Install Plan workflow label'],
  ['Run Approved Installs', 'Run Approved Installs workflow label'],
  ['SOFTWARE_TRACKER_PATHS.offlineWorkbook', 'offline workbook path in panel'],
];

let shellPassed = 0;
let shellFailed = 0;

for (const [needle, label] of softwareInstallChecks) {
  if (!panelSoftwareJs.includes(needle)) {
    console.error(`FAIL [software-install:${label}]: missing "${needle}"`);
    shellFailed++;
  } else {
    console.log(`PASS [software-install:${label}]`);
    shellPassed++;
  }
}

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

const manifestContractChecks = [
  ['cybernet-manifest-summary', 'manifest summary container in HTML'],
  ['manifest rows', 'manifest summary row count label'],
  ['missing hostname/DNS', 'manifest missing hostname metric'],
  ['Target manifest', 'manifest section label'],
];

for (const [needle, label] of manifestContractChecks) {
  const src = needle === 'cybernet-manifest-summary' ? indexHtml : appJs;
  if (!src.includes(needle)) {
    console.error(`FAIL [manifest-contract:${label}]: missing "${needle}"`);
    shellFailed++;
  } else {
    console.log(`PASS [manifest-contract:${label}]`);
    shellPassed++;
  }
}

const adContractChecks = [
  ['cybernet-ad-population-summary', 'AD summary container in HTML'],
  ['AD Registered Population', 'AD summary heading'],
  ['registered computer accounts', 'AD population row label'],
  ['not serial or reachability proof', 'no false AD proof claim'],
  ['ad_registered_normalized.csv / AD bucket CSVs', 'AD supported format hint'],
  ['AD registered population', 'AD section label'],
  ['sample-ad_registered_normalized.csv', 'AD sample chip wiring'],
  ['AD is the registered-device roster; network probes are attendance', 'AD roster vs attendance review copy'],
];

for (const [needle, label] of adContractChecks) {
  const src = (needle === 'cybernet-ad-population-summary' || needle === 'AD Registered Population' || needle === 'not serial or reachability proof' || needle === 'ad_registered_normalized.csv / AD bucket CSVs')
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

// Dashboard map tour targets
for (const needle of ['#repo-setup-hero', '#hero-start-survey', '#cybernet-review', '#advanced-tools-toggle']) {
  tourAssert(tourJs.includes(`target: '${needle}'`), `dashboard-map-target:${needle}`);
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

// ── Start-button visible-failure contracts ───────────────────────────────────
// Source-level guards that a press of Start can never strand the user. The full
// runtime behavior is exercised by dashboard/start-button-smoke.js.

const bundleJs = readFileSync(join(__dir, 'js', 'bundle.js'), 'utf8');
const preflightJs = readFileSync(join(__dir, 'js', 'cybernet-os-preflight.js'), 'utf8');
const launchJs = readFileSync(join(__dir, 'js', 'launch-cybernet-tutorial.js'), 'utf8');
const launchSetupJs = readFileSync(join(__dir, 'js', 'launch-repo-setup-tutorial.js'), 'utf8');
const launchToolboxJs = readFileSync(join(__dir, 'js', 'launch-toolbox-tutorial.js'), 'utf8');

let startPassed = 0;
let startFailed = 0;
function startAssert(ok, label, detail) {
  if (ok) { console.log(`PASS [start-button:${label}]`); startPassed++; }
  else { console.error(`FAIL [start-button:${label}]${detail ? ': ' + detail : ''}`); startFailed++; }
}

startAssert(indexHtml.includes('id="cybernet-hero-status"'), 'hero-status-in-html', 'missing cybernet-hero-status');
startAssert(indexHtml.includes('id="repo-setup-hero-status"'), 'setup-hero-status-in-html', 'missing repo-setup-hero-status');
startAssert(appJs.includes('startCybernetTutorial'), 'explicit-transition', 'app.js missing startCybernetTutorial');
startAssert(appJs.includes('window.startCybernetTutorial'), 'transition-exposed', 'app.js does not expose startCybernetTutorial');
startAssert(appJs.includes('startRepoSetupTutorial'), 'setup-explicit-transition', 'app.js missing startRepoSetupTutorial');
startAssert(appJs.includes('window.startRepoSetupTutorial'), 'setup-transition-exposed', 'app.js does not expose startRepoSetupTutorial');
startAssert(appJs.includes('getComputedStyle'), 'verifies-visibility', 'app.js does not verify tutorial visibility');
startAssert(appJs.includes("tutorial.style.display = ''"), 'clears-inline-none', 'app.js does not clear a stale inline display:none');
startAssert(/Restart Cybernet Survey/.test(appJs), 'recovery-control', 'app.js missing Restart recovery control');
startAssert(appJs.includes('cybernet-hero-status'), 'drives-status', 'app.js does not drive the hero status');
// Guard the old strand pattern: Start must not simply hide the hero actions.
startAssert(!/cybernet-hero-actions'\)\?\.classList\.add\('hidden'\)/.test(appJs), 'no-strand-pattern',
  'app.js still hides cybernet-hero-actions on Start');
startAssert(!preflightJs.includes('syncTutorialVisibility'), 'preflight-not-gating-wizard',
  'cybernet-os-preflight.js still forces the wizard hidden');
startAssert(launchJs.includes('window.startCybernetTutorial'), 'auto-start-uses-transition',
  'launch-cybernet-tutorial.js does not use the verified transition');
startAssert(launchSetupJs.includes('window.startRepoSetupTutorial'), 'setup-auto-start-uses-transition',
  'launch-repo-setup-tutorial.js does not use the verified transition');
startAssert(launchSetupJs.includes("tutorial === 'setup'"), 'setup-query-supported',
  'launch-repo-setup-tutorial.js does not support ?tutorial=setup');
startAssert(launchToolboxJs.includes('toolbox-status.json?ts='), 'toolbox-fetches-status',
  'launch-toolbox-tutorial.js does not fetch toolbox-status.json');
startAssert(launchToolboxJs.includes('__sasToolboxActionNeeded'), 'toolbox-first-flag',
  'launch-toolbox-tutorial.js does not set the toolbox-first flag');
startAssert(launchSetupJs.includes('__sasToolboxActionNeeded'), 'setup-defers-to-toolbox',
  'repo setup launcher does not defer when toolbox action is needed');
startAssert(bundleJs.includes('initToolboxTutorial'), 'bundle-toolbox-tutorial',
  'bundle.js is stale — missing Toolbox tutorial; rebuild with: node dashboard/build-bundle.js');
startAssert(bundleJs.includes('initSoftwareTrackerTutorial'), 'bundle-software-tutorial',
  'bundle.js is stale — missing Software Tracker tutorial; rebuild with: node dashboard/build-bundle.js');
startAssert(bundleJs.includes('initRepoSetupTutorial'), 'bundle-repo-setup-tutorial',
  'bundle.js is stale — missing Repo Setup tutorial; rebuild with: node dashboard/build-bundle.js');
startAssert(bundleJs.includes('applyCommandHelp'), 'bundle-command-help',
  'bundle.js is stale — missing shared wizard command helper; rebuild with: node dashboard/build-bundle.js');
startAssert(bundleJs.includes('startCybernetTutorial'), 'bundle-not-stale',
  'bundle.js is stale — rebuild with: node dashboard/build-bundle.js');

console.log(`\nStart button: ${startPassed} passed, ${startFailed} failed`);
if (startFailed > 0) process.exit(1);

// ── Persistent Back/Exit + real Stop contracts ───────────────────────────────
// Source-level guards that every wizard has a state-independent exit and that
// the live probe Stop is a real relay cancellation, not a UI-only teardown.

const relayClientJs = readFileSync(join(__dir, 'js', 'relay-client.js'), 'utf8');
const runControlJs = readFileSync(join(__dir, 'js', 'run-control.js'), 'utf8');
const panelNetworkJs = readFileSync(join(__dir, 'js', 'panel-network.js'), 'utf8');
const relayPy = readFileSync(join(__dir, 'relay.py'), 'utf8');

let bsPassed = 0;
let bsFailed = 0;
function bsAssert(ok, label, detail) {
  if (ok) { console.log(`PASS [back-stop:${label}]`); bsPassed++; }
  else { console.error(`FAIL [back-stop:${label}]${detail ? ': ' + detail : ''}`); bsFailed++; }
}

// Persistent Back/Exit control on every wizard (independent of step index).
for (const id of ['cybernet-exit', 'repo-setup-exit', 'toolbox-exit', 'sw-exit']) {
  bsAssert(indexHtml.includes(`id="${id}"`), `exit-control:${id}`, `index.html missing #${id}`);
}
bsAssert(indexHtml.includes('Back to dashboard'), 'exit-label', 'no "Back to dashboard" control in index.html');
// Step Back is renamed so exit and previous-step are not the same overloaded button.
bsAssert(indexHtml.includes('Previous Step'), 'step-back-renamed', 'step Back not renamed to Previous Step');
bsAssert(appJs.includes('closeWorkflowTutorial'), 'close-helper', 'app.js missing closeWorkflowTutorial');
bsAssert(bundleJs.includes('closeWorkflowTutorial'), 'close-helper-bundled',
  'bundle.js stale — missing closeWorkflowTutorial; rebuild with: node dashboard/build-bundle.js');

// Real Stop: client sends probe_cancel; relay honors it; panel has a Stop button.
bsAssert(indexHtml.includes('id="run-control-banner"'), 'global-run-banner',
  'index.html missing persistent global Run Control banner');
bsAssert(indexHtml.includes('id="run-control-stop"'), 'global-run-stop',
  'index.html missing global Run Control Stop button');
bsAssert(runControlJs.includes('RunRequested') && runControlJs.includes('StopAcknowledged'),
  'run-control-lifecycle-events', 'run-control.js missing lifecycle event reducer');
bsAssert(runControlJs.includes('CommandGenerated') && runControlJs.includes('AwaitingExternalResults'),
  'run-control-command-gen-events', 'run-control.js missing command-generation lifecycle events');
bsAssert(runControlJs.includes('isRunStoppable'), 'run-control-stoppable-helper',
  'run-control.js missing external-only stoppable guard');
bsAssert(appJs.includes('_startCommandGenerationRun') && appJs.includes('CommandCopied'),
  'app-command-gen-lifecycle', 'app.js does not emit command-generation lifecycle events');
bsAssert(runControlJs.includes('Buttons express intent'), 'intent-vs-truth-doctrine',
  'run-control.js missing intent-vs-truth doctrine comment');
bsAssert(relayClientJs.includes('StopSent') && relayClientJs.includes('StopAcknowledged'),
  'client-stop-lifecycle', 'relay-client.js does not emit StopSent/StopAcknowledged lifecycle events');
bsAssert(relayClientJs.includes('probe_cancel'), 'client-sends-cancel',
  'relay-client.js does not send a probe_cancel (UI-only Stop is a defect)');
bsAssert(relayClientJs.includes('probeId'), 'client-probe-id', 'relay-client.js missing probeId');
bsAssert(relayPy.includes('probe_cancel'), 'relay-handles-cancel', 'relay.py does not handle probe_cancel');
bsAssert(relayPy.includes('cancel_event'), 'relay-cancel-event', 'relay.py has no cancellation token');
bsAssert(/def run_probe/.test(relayPy), 'relay-run-probe', 'relay.py missing run_probe orchestrator');
bsAssert(indexHtml.includes('id="net-stop-probe-btn"') || panelNetworkJs.includes('net-stop-probe-btn'),
  'panel-stop-button', 'no persistent Stop button on the network panel');
bsAssert(panelNetworkJs.includes('requestStop') && panelNetworkJs.includes('createRun'),
  'panel-uses-run-control', 'panel-network.js still lacks central Run Control integration');
bsAssert(panelNetworkJs.includes('subscribeRunEvents') && panelNetworkJs.includes('_probeStatusFromRun'),
  'panel-listens-lifecycle', 'panel-network.js does not derive probe status from lifecycle events');
bsAssert(panelNetworkJs.includes('Partial results preserved'), 'partial-results-msg',
  'panel-network.js does not report preserved partial results');
bsAssert(bundleJs.includes('net-stop-probe-btn'), 'panel-stop-bundled',
  'bundle.js stale — missing panel Stop button; rebuild with: node dashboard/build-bundle.js');
bsAssert(bundleJs.includes('initRunControl') && bundleJs.includes('run-control-banner'),
  'run-control-bundled', 'bundle.js stale — missing Run Control lifecycle layer');
// Command-gen fallback must tell the user how to stop a copied command.
bsAssert(appJs.includes('Ctrl+C'), 'cmdgen-ctrl-c', 'command-gen modal missing Ctrl+C stop guidance');

console.log(`\nBack/Stop controls: ${bsPassed} passed, ${bsFailed} failed`);
if (bsFailed > 0) process.exit(1);
