#!/usr/bin/env node
'use strict';
/*
 * Offline contract for cockpit activity vs receipt-history separation.
 * Run from any cwd: node dashboard/test_capability_activity.js
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const root = path.resolve(__dirname);
const html = fs.readFileSync(path.join(root, 'capabilities.html'), 'utf8');
const cockpit = fs.readFileSync(path.join(root, 'js', 'capability-cockpit.js'), 'utf8');
const activityUrl = pathToFileURL(path.join(root, 'js', 'capability-activity.js')).href;

(async () => {
  const { projectCockpitActivity } = await import(activityUrl);

  const absent = projectCockpitActivity({ feedStatus: 'NOT_CONNECTED' });
  assert.equal(absent.activity_class, 'NOT_CONNECTED');
  assert.equal(absent.active_run, null);
  assert.equal(absent.conflation_guard, 'RECEIPT_HISTORY_IS_NOT_LIVE_ACTIVITY');

  const unknownFeed = projectCockpitActivity({ feedStatus: 'UNKNOWN' });
  assert.equal(unknownFeed.activity_class, 'UNKNOWN');

  const active = projectCockpitActivity({
    feedStatus: 'CONNECTED',
    activeRun: {
      runId: 'r1',
      kind: 'Network probe',
      state: 'running',
      summary: '2 target(s)',
      source: 'relay-server',
      updatedAt: '2026-11-03T12:00:00Z'
    }
  });
  assert.equal(active.activity_class, 'ACTIVE');
  assert.equal(active.active_run.state, 'running');
  assert.equal(active.latest_terminal_run, null);

  const terminal = projectCockpitActivity({
    feedStatus: 'CONNECTED',
    latestRun: {
      runId: 'r2',
      kind: 'Network probe',
      state: 'completed',
      summary: 'finished',
      source: 'ui',
      endedAt: '2026-11-03T12:05:00Z'
    }
  });
  assert.equal(terminal.activity_class, 'HISTORICAL_TERMINAL');
  assert.equal(terminal.active_run, null);
  assert.equal(terminal.latest_terminal_run.state, 'completed');

  const disconnected = projectCockpitActivity({
    feedStatus: 'CONNECTED',
    latestRun: { runId: 'r3', kind: 'Network probe', state: 'disconnected', summary: 'lost' }
  });
  assert.equal(disconnected.activity_class, 'DISCONNECTED');

  const idle = projectCockpitActivity({ feedStatus: 'CONNECTED' });
  assert.equal(idle.activity_class, 'UNKNOWN');
  assert.match(idle.detail, /Do not infer activity from receipt timestamps/);

  for (const id of ['activity-panel', 'activity-headline', 'activity-detail', 'activity-class']) {
    assert.ok(html.includes('id="' + id + '"'), 'missing activity UI anchor: ' + id);
  }
  assert.match(cockpit, /projectCockpitActivity/, 'cockpit must consume the activity projector');
  assert.match(cockpit, /RECEIPT_HISTORY_IS_NOT_LIVE_ACTIVITY/, 'conflation guard must remain visible');
  assert.match(cockpit, /NOT_CONNECTED/, 'absent run feed must fail closed');
  assert.ok(!cockpit.includes('innerHTML'), 'no untrusted HTML injection for activity copy');
  assert.ok(!html.includes('last_receipt_at') || html.includes('Historical receipts'),
    'activity copy must keep receipt history conceptually separate');

  console.log('Capability activity contract PASS: NOT_CONNECTED/UNKNOWN/ACTIVE/HISTORICAL_TERMINAL/DISCONNECTED');
})().catch(err => {
  console.error(err);
  process.exit(1);
});
