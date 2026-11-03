'use strict';
/*
 * Offline contract for the cockpit's curated ADB journey.
 * Static stages are presentation annotations, never a second executable registry.
 * Run from any cwd: node dashboard/test_capability_cockpit_adb.js
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const script = fs.readFileSync(path.join(__dirname, 'js', 'capability-cockpit.js'), 'utf8');
const html = fs.readFileSync(path.join(__dirname, 'capabilities.html'), 'utf8');
const commands = JSON.parse(fs.readFileSync(
  path.join(root, 'harness', 'api', 'harness-command-registry.json'), 'utf8'
)).commands;
const start = script.indexOf('const adbStages = [');
const end = script.indexOf('\n  ];', start);
assert.ok(start >= 0 && end > start, 'ADB journey must have a bounded stage declaration');
const literal = script.slice(start + 'const adbStages = '.length, end + '\n  ]'.length);
const stages = vm.runInNewContext('(' + literal + ')');
assert.equal(stages.length, 8, 'eight operator-facing stages have been reviewed');
const known = new Set(commands.map(row => row.id));
const expectedStages = [
  ['android-toolchain-adminbox', 'hh-cc-reader-adb-host-prepare'],
  ['android-provider', 'hh-cc-reader-adb-probe'],
  ['hh-cc-reader-adb-inventory-capture'],
  ['hh-cc-reader-version-domain-classify'],
  ['hh-cc-reader-firmware-roundtrip-evaluate'],
  ['hh-cc-reader-adb-tcpip-certify'],
  ['hh-cc-reader-adb-remote-view-certify'],
  ['hh-cc-reader-adb-control-plane-evaluate', 'hh-cc-reader-capability-program-evaluate']
];
assert.deepEqual(stages.map(stage => Array.from(stage.ids)), expectedStages,
  'each exact registered command must stay in its reviewed operator journey stage');
function validateStages(rows) {
  const ids = [];
  for (const stage of rows) {
    assert.ok(stage.title && stage.description && stage.ids.length, 'all stages need accessible copy and command IDs');
    for (const id of stage.ids) {
      assert.ok(known.has(id), 'never advertise unregistered command: ' + id);
      assert.ok(!ids.includes(id), 'command mapped to more than one stage: ' + id);
      ids.push(id);
    }
  }
  return ids;
}
const boundIds = validateStages(stages);
assert.equal(boundIds.length, 11, 'the reviewed ADB journey must cover all 11 distinct commands');
assert.throws(() => validateStages([{ title: 'Invented', description: 'No source', ids: ['phantom-command'] }]),
  /unregistered command/, 'a phantom command must fail the contract');
for (const id of ['adb-suite', 'adb-suite-title', 'adb-journey', 'adb-status', 'capabilities']) {
  assert.ok(html.includes('id="' + id + '"'), 'missing accessible UI anchor: ' + id);
}
for (const label of ['Registered', 'Executable', 'Evidence', 'Field outcome']) {
  assert.ok(script.includes("row('" + label + "'"), 'orthogonal proof dimension missing: ' + label);
}
assert.match(script, /execution untested/, 'entrypoint file is not executable proof');
assert.match(script, /NOT PROBED/, 'runtime qualification must be explicit');
assert.match(script, /receipt_coverage === 'NO_INDEXED_RECEIPT'/,
  'unmapped evidence must not be treated as an unqueried private home');
assert.match(script, /entrypoint_status === 'FILE_MISSING'/,
  'missing entrypoint files need a visible count');
assert.match(script, /target\.focus\(/,
  'Inspect must focus the requested command heading');
assert.match(script, /Not verified by this read-only cockpit/, 'historical receipt is not field acceptance');
assert.match(script, /textContent = String\(value\)/, 'use text nodes, not untrusted HTML');
assert.match(script, /showAdbJourney\(\);\s*\} catch/, 'successful refresh must render ADB stages');
assert.match(script, /showAdbJourney\(\);\s*\} finally/, 'failed refresh must clear ADB stages');
assert.ok(!script.includes('innerHTML'), 'no arbitrary markup from receipt/registry data');
assert.ok(!script.includes('adb connect') && !script.includes('adb shell'),
  'the browser must not execute or teach target mutation');
console.log('ADB journey contract PASS: ' + stages.length + ' stages / ' + boundIds.length
  + ' unique canonical commands / four separate proof dimensions');
