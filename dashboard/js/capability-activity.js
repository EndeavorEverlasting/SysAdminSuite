/* Capability cockpit activity projection.
 * Source of truth for live runs remains dashboard/js/run-control.js.
 * Receipt history must never be promoted to an active operation.
 */

const ACTIVE_STATES = new Set(['requested', 'approved', 'starting', 'running', 'waiting', 'stopping']);
const TERMINAL_STATES = new Set(['stopped', 'completed', 'failed', 'skipped', 'aborted', 'disconnected']);

function sanitizeRun(run) {
  if (!run || typeof run !== 'object') return null;
  return {
    runId: String(run.runId || ''),
    kind: String(run.kind || 'run').slice(0, 80),
    state: String(run.state || 'unknown').slice(0, 32),
    summary: String(run.summary || '').slice(0, 240),
    updatedAt: run.updatedAt ? String(run.updatedAt) : null,
    endedAt: run.endedAt ? String(run.endedAt) : null,
    source: String(run.source || 'unknown').slice(0, 32)
  };
}

/**
 * @param {{ feedStatus: string, activeRun?: object|null, latestRun?: object|null }} input
 * @returns {object} privacy-safe activity projection for the capability cockpit
 */
export function projectCockpitActivity(input = {}) {
  const feedStatus = String(input.feedStatus || 'NOT_CONNECTED');
  const guard = 'RECEIPT_HISTORY_IS_NOT_LIVE_ACTIVITY';

  if (feedStatus !== 'CONNECTED') {
    return {
      feed_status: feedStatus === 'UNKNOWN' ? 'UNKNOWN' : 'NOT_CONNECTED',
      activity_class: feedStatus === 'UNKNOWN' ? 'UNKNOWN' : 'NOT_CONNECTED',
      headline: feedStatus === 'UNKNOWN'
        ? 'Run-feed status unknown'
        : 'Run feed not connected on this page',
      detail: 'Active operations cannot be certified here. Historical receipts below are not live activity or field outcomes.',
      active_run: null,
      latest_terminal_run: null,
      conflation_guard: guard
    };
  }

  const active = sanitizeRun(input.activeRun);
  if (active && ACTIVE_STATES.has(active.state)) {
    return {
      feed_status: 'CONNECTED',
      activity_class: 'ACTIVE',
      headline: `${active.kind} is ${active.state}`,
      detail: active.summary || 'Dashboard run-control reports an active operation. This is independent of receipt history.',
      active_run: active,
      latest_terminal_run: null,
      conflation_guard: guard
    };
  }

  const latest = sanitizeRun(input.latestRun);
  if (latest && TERMINAL_STATES.has(latest.state)) {
    return {
      feed_status: 'CONNECTED',
      activity_class: latest.state === 'disconnected' ? 'DISCONNECTED' : 'HISTORICAL_TERMINAL',
      headline: `${latest.kind} ended as ${latest.state}`,
      detail: 'This is terminal run-control history on the connected feed, not proof that work is running and not a field outcome.',
      active_run: null,
      latest_terminal_run: latest,
      conflation_guard: guard
    };
  }

  return {
    feed_status: 'CONNECTED',
    activity_class: 'UNKNOWN',
    headline: 'No active dashboard run observed',
    detail: 'The run feed is connected, but no current or terminal run is available on this page. Do not infer activity from receipt timestamps.',
    active_run: null,
    latest_terminal_run: null,
    conflation_guard: guard
  };
}

export const COCKPIT_ACTIVITY_ACTIVE_STATES = ACTIVE_STATES;
export const COCKPIT_ACTIVITY_TERMINAL_STATES = TERMINAL_STATES;
