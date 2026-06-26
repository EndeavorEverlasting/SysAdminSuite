// toolbox-tutorial.js — dynamic glowing wizard for missing/outdated toolbox tools.

import { sanitize, toast } from './utils.js';

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
      note: 'Re-run START-HERE-SysAdminSuite-Dashboard.bat after installing tools to refresh this checklist.',
      hasCommand: false,
      finalAction: true
    });
  } else {
    steps[steps.length - 1].finalAction = true;
  }
  return steps;
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

  let steps = [];
  let idx = 0;
  let copiedThisStep = false;

  const title = document.getElementById('toolbox-step-title');
  const body = document.getElementById('toolbox-step-body');
  const kicker = document.getElementById('toolbox-step-kicker');
  const checks = document.getElementById('toolbox-step-checks');
  const command = document.getElementById('toolbox-step-command');
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

  function render() {
    const step = steps[idx];
    if (!step) return;
    copiedThisStep = false;
    const hasCommand = !!step.hasCommand;
    kicker.textContent = `Step ${idx + 1} of ${steps.length} — ${step.railLabel}`;
    title.textContent = step.title;
    body.textContent = step.body;
    checks.innerHTML = step.checks.map(item => `<li>${sanitize(item)}</li>`).join('');
    commandPanel?.classList.toggle('hidden', !hasCommand);
    if (command) command.value = hasCommand ? step.command : '';
    if (runner) runner.textContent = step.nextAction || 'Read the step, then click Next.';
    if (note) note.textContent = step.note || '';
    if (prev) prev.disabled = idx === 0;
    if (next) next.textContent = step.finalAction ? 'Finish toolbox check' : hasCommand ? 'Next after fix →' : 'Next →';
    copy?.classList.toggle('hidden', !hasCommand);
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
        toast('Toolbox fix command copied.', 'success');
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
    const hasCommand = !!step?.hasCommand;
    if (hasCommand && !copiedThisStep) {
      toast('Copy the fix command first, or continue only if the tool is already fixed.', 'warning');
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
    render();
  };

  window.__sasResetToolboxWizard = () => {
    idx = 0;
    copiedThisStep = false;
    render();
  };

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
  const count = status?.summary?.needsAction ?? 0;
  if (status?.actionNeeded && count > 0) {
    banner.textContent = `${count} toolbox item${count === 1 ? '' : 's'} need attention — click to open the guided fix wizard`;
    banner.classList.remove('hidden');
    banner.classList.add('sas-guide-glow');
  } else {
    banner.classList.add('hidden');
    banner.classList.remove('sas-guide-glow');
  }
}
