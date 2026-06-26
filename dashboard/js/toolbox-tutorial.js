// toolbox-tutorial.js — dynamic glowing wizard for missing/outdated toolbox tools.

import { sanitize, toast } from './utils.js';
import { applyCommandHelp, resolveRunMode } from './wizard-command-help.js';

const ACTION_STATUSES = new Set(['missing', 'outdated', 'blocked', 'available', 'manual_review']);

function buildStepsFromStatus(status) {
  if (!status || !Array.isArray(status.tools)) return [];

  const failing = status.tools.filter(t => ACTION_STATUSES.has(t.status));
  const steps = failing.map(tool => ({
    toolId: tool.id,
    title: tool.displayName || tool.id,
    railLabel: tool.displayName || tool.id,
    body: describeIssue(tool),
    command: tool.nextAction || '',
    checks: buildChecks(tool),
    nextAction: tool.nextAction || 'Follow the step guidance, then click Next.',
    explain: describeAction(tool),
    explainParts: buildExplainParts(tool),
    note: tool.installDoc ? `See ${tool.installDoc} for full guidance.` : '',
    hasCommand: !!(tool.nextAction && tool.nextAction.startsWith('bash ')),
    finalAction: false
  }));

  if (steps.length === 0) {
    steps.push({
      toolId: 'all_clear',
      title: 'Toolbox ready',
      railLabel: 'Ready',
      body: 'Every required tool the dashboard probed looks good. You can continue with Repo Setup or Cybernet Survey.',
      command: '',
      checks: ['Required runtimes and host are present.', 'Workflow tools you need can be installed from the steps above when missing.'],
      nextAction: 'Click Finish to continue.',
      explain: 'The toolbox found no required fix steps, so there is no outside command to run.',
      explainParts: [
        { part: 'Toolbox ready', meaning: 'Required dashboard and workflow tools look usable from the last probe.' },
        { part: 'Finish', meaning: 'Closes this wizard and lets you continue with Repo Setup or Cybernet Survey.' },
      ],
      note: 'Re-run START-HERE-SysAdminSuite-Dashboard.bat after installing tools to refresh this checklist.',
      hasCommand: false,
      finalAction: true
    });
  } else {
    steps[steps.length - 1].finalAction = true;
  }
  return steps;
}

function describeAction(tool) {
  if (tool.nextAction?.startsWith('bash ')) {
    return `Runs the approved SysAdminSuite ensure script for ${tool.displayName || tool.id} outside the dashboard.`;
  }
  if (tool.nextAction) {
    return `Shows the manual action for ${tool.displayName || tool.id}; the browser will not perform it.`;
  }
  return `Explains why ${tool.displayName || tool.id} needs attention and what to review next.`;
}

function buildExplainParts(tool) {
  const parts = [];
  if (tool.nextAction?.startsWith('bash ')) {
    const [shell, script, ...rest] = tool.nextAction.split(/\s+/);
    parts.push({ part: shell, meaning: 'Runs the command in Bash on Windows.' });
    if (script) parts.push({ part: script, meaning: 'The SysAdminSuite helper script to run yourself.' });
    if (rest.length) parts.push({ part: rest.join(' '), meaning: 'Flags or arguments passed to the helper script.' });
  } else if (tool.nextAction) {
    parts.push({ part: 'Manual action', meaning: tool.nextAction });
  }
  if (tool.pinnedVersion) parts.push({ part: 'Pinned version', meaning: `Expected version: ${tool.pinnedVersion}.` });
  if (tool.installDoc) parts.push({ part: 'Install doc', meaning: `Full guidance lives in ${tool.installDoc}.` });
  if (!parts.length) parts.push({ part: 'Review', meaning: 'Read the status and continue when you know the next action.' });
  return parts;
}

function describeIssue(tool) {
  const pinned = tool.pinnedVersion ? ` (pinned: ${tool.pinnedVersion})` : '';
  switch (tool.status) {
    case 'missing':
      return `${tool.displayName} was not found on this machine${pinned}. Install or ensure it before continuing.`;
    case 'outdated':
      return `${tool.displayName} is present but outdated${pinned}. Found: ${tool.version || 'unknown'}. Update to the pinned version.`;
    case 'blocked':
      return `${tool.displayName} could not be verified due to a policy or environment block.`;
    case 'available':
      return 'A SysAdminSuite update is available. Approve it in the launcher before continuing field work.';
    case 'manual_review':
      return 'The repo update check needs manual review. Continue with the current copy or review docs/APPROVED_UPDATE_FLOW.md.';
    default:
      return `${tool.displayName} needs attention (${tool.status}).`;
  }
}

function buildChecks(tool) {
  const checks = [];
  if (tool.tier === 'required') checks.push('Required for the dashboard host and launcher.');
  if (tool.tier === 'workflow') checks.push('Needed for Cybernet / Neuron survey workflows.');
  if (tool.pinnedVersion) checks.push(`Pinned target: ${tool.pinnedVersion}.`);
  if (tool.path) checks.push(`Detected path: ${tool.path}.`);
  if (tool.nextAction) checks.push(`Fix: ${tool.nextAction}`);
  if (!checks.length) checks.push('Follow the command or action for this tool.');
  return checks;
}

export function initToolboxTutorial() {
  const root = document.getElementById('toolbox-tutorial');
  if (!root) return;

  let steps = buildStepsFromStatus({ tools: [], actionNeeded: false });
  let idx = 0;
  let copiedThisStep = false;

  const title = document.getElementById('toolbox-step-title');
  const body = document.getElementById('toolbox-step-body');
  const kicker = document.getElementById('toolbox-step-kicker');
  const checks = document.getElementById('toolbox-step-checks');
  const command = document.getElementById('toolbox-step-command');
  const commandMode = document.getElementById('toolbox-command-mode');
  const explain = document.getElementById('toolbox-command-explain');
  const explainDetails = document.getElementById('toolbox-command-explain-details');
  const explainParts = document.getElementById('toolbox-command-explain-parts');
  const commandEmpty = document.getElementById('toolbox-command-empty');
  const runner = document.getElementById('toolbox-command-runner');
  const note = document.getElementById('toolbox-step-note');
  const commandPanel = document.getElementById('toolbox-command-panel');
  const prev = document.getElementById('toolbox-prev');
  const next = document.getElementById('toolbox-next');
  const copy = document.getElementById('toolbox-copy');
  const recheck = document.getElementById('toolbox-recheck');
  const footer = document.getElementById('toolbox-wizard-footer');
  const progressRail = document.getElementById('toolbox-progress-rail');

  function highlightChecklistRow(toolId) {
    document.querySelectorAll('.toolbox-checklist-row').forEach(row => {
      row.classList.toggle('needs-action', row.dataset.toolId === toolId);
      row.classList.toggle('sas-guide-glow', row.dataset.toolId === toolId);
    });
  }

  function updateGuideState(hasCommand) {
    const finalStep = idx === steps.length - 1;
    copy?.classList.toggle('sas-guide-glow', hasCommand && !copiedThisStep);
    next?.classList.toggle('sas-guide-glow', (hasCommand && copiedThisStep) || (!hasCommand && !finalStep));
    recheck?.classList.toggle('sas-guide-glow', finalStep && steps.length > 0 && steps[steps.length - 1].toolId !== 'all_clear');
    commandPanel?.classList.toggle('sas-guide-panel', hasCommand && !copiedThisStep);
  }

  function updateProgressRail() {
    progressRail?.querySelectorAll('li').forEach((li, i) => {
      li.classList.toggle('active', i === idx);
      li.classList.toggle('done', i < idx);
    });
  }

  function rebuildProgressRail() {
    if (!progressRail) return;
    progressRail.innerHTML = steps.map((step, i) =>
      `<li data-step="${i}" data-tool-id="${sanitize(step.toolId || '')}">${sanitize(step.railLabel || step.title)}</li>`
    ).join('');
  }

  function render() {
    const step = steps[idx];
    if (!step) return;
    copiedThisStep = false;
    const runMode = resolveRunMode(step);
    const hasCommand = runMode === 'run';
    kicker.textContent = `Step ${idx + 1} of ${steps.length} — ${step.railLabel}`;
    title.textContent = step.title;
    body.textContent = step.body;
    checks.innerHTML = step.checks.map(item => `<li>${sanitize(item)}</li>`).join('');
    applyCommandHelp({
      panel: commandPanel, command, mode: commandMode, runner, note, explain,
      details: explainDetails, parts: explainParts, empty: commandEmpty, copy, next,
    }, step, runMode, { finalLabel: step.finalAction ? 'Finish toolbox check' : '' });
    if (prev) prev.disabled = idx === 0;
    footer?.classList.toggle('hidden', !step.finalAction);
    highlightChecklistRow(step.toolId);
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
        toast('Command copied. Run it outside the dashboard, then come back for Next.', 'success');
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

  function recheckStatus() {
    if (typeof window.__sasReloadToolboxStatus === 'function') {
      window.__sasReloadToolboxStatus();
    } else {
      window.location.reload();
    }
  }

  prev?.addEventListener('click', () => { if (idx > 0) { idx--; render(); } });
  next?.addEventListener('click', () => {
    const step = steps[idx];
    const hasCommand = resolveRunMode(step) === 'run';
    if (hasCommand && !copiedThisStep) {
      toast('Copy and run the command outside the dashboard first, or continue only if the tool is already fixed.', 'warning');
      return;
    }
    if (idx < steps.length - 1) {
      idx++;
      render();
    } else {
      toast('Toolbox check complete.', 'success');
      render();
    }
  });
  copy?.addEventListener('click', copyCommand);
  recheck?.addEventListener('click', recheckStatus);

  window.__sasApplyToolboxStatus = (status) => {
    steps = buildStepsFromStatus(status);
    idx = 0;
    copiedThisStep = false;
    rebuildProgressRail();
    renderToolboxChecklist(status);
    updateToolboxBanner(status);
    window.dispatchEvent(new CustomEvent('sas-toolbox-status', { detail: status }));
    render();
  };

  window.__sasResetToolboxWizard = () => {
    idx = 0;
    copiedThisStep = false;
    rebuildProgressRail();
    render();
  };

  rebuildProgressRail();
  render();
}

export function renderToolboxChecklist(status) {
  const panel = document.getElementById('toolbox-checklist');
  if (!panel || !status?.tools) return;

  const rows = status.tools.map(tool => {
    const chipClass = tool.status === 'ok' || tool.status === 'not_applicable' ? 'ok' : 'warn';
    const label = tool.status === 'not_applicable' ? 'n/a' : tool.status;
    return `<div class="toolbox-checklist-row" data-tool-id="${sanitize(tool.id)}">
      <span class="toolbox-checklist-name">${sanitize(tool.displayName || tool.id)}</span>
      <span class="toolbox-checklist-chip ${chipClass}">${sanitize(label)}</span>
    </div>`;
  }).join('');
  panel.innerHTML = rows;
}

export function updateToolboxBanner(status) {
  const banner = document.getElementById('toolbox-status-banner');
  if (!banner) return;
  const count = status?.summary?.needsAction ??
    (status?.tools || []).filter(tool => ACTION_STATUSES.has(tool.status)).length;
  if (status?.actionNeeded && count > 0) {
    banner.textContent = `${count} toolbox item${count === 1 ? '' : 's'} need attention — click to open the guided fix wizard`;
    banner.classList.remove('hidden');
    banner.classList.add('sas-guide-glow');
  } else {
    banner.classList.add('hidden');
    banner.classList.remove('sas-guide-glow');
  }
}

window.__sasRenderToolboxChecklist = renderToolboxChecklist;
window.__sasUpdateToolboxBanner = updateToolboxBanner;
