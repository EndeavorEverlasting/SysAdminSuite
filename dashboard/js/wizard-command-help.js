// wizard-command-help.js — shared command-panel clarity for dashboard wizards.

import { sanitize } from './utils.js';

const RUN_MODE_COPY = {
  run: {
    label: 'RUN IT YOURSELF',
    className: 'is-run',
    runner: 'Copy this command, run it outside the dashboard, then return here. Next never runs commands.',
    empty: '',
    next: 'I ran it — Next →',
  },
  read: {
    label: 'NOTHING TO RUN',
    className: 'is-read',
    runner: 'This is reference text only. Nothing runs in the dashboard; read it, then click Next.',
    empty: 'This step shows reference text so you know what to look for. There is no command to run.',
    next: 'Next →',
  },
  none: {
    label: 'JUST CLICK NEXT',
    className: 'is-none',
    runner: 'There is no command for this step. Click Next when you are ready.',
    empty: 'No outside action is required for this step. The right panel stays visible so the wizard always explains what is happening.',
    next: 'Next →',
  },
};

function isCommentOnly(text) {
  const lines = String(text || '').split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  return lines.length > 0 && lines.every(line => line.startsWith('#'));
}

function normalizeParts(step) {
  if (Array.isArray(step.explainParts) && step.explainParts.length > 0) {
    return step.explainParts;
  }
  const parts = [];
  if (step.command) {
    parts.push({ part: 'Command/action', meaning: 'The exact text shown in the command box. Copy it only when the badge says RUN IT YOURSELF.' });
  }
  if (step.nextAction) {
    parts.push({ part: 'Next action', meaning: step.nextAction });
  }
  if (Array.isArray(step.checks) && step.checks.length > 0) {
    parts.push({ part: 'Checklist', meaning: step.checks[0] });
  }
  return parts;
}

export function resolveRunMode(step = {}) {
  const command = String(step.command || '').trim();
  if (step.hasCommand === true && command) return 'run';
  if (isCommentOnly(command)) return 'read';
  return 'none';
}

export function applyCommandHelp(els, step = {}, runMode = resolveRunMode(step), options = {}) {
  const copy = RUN_MODE_COPY[runMode] || RUN_MODE_COPY.none;
  const commandText = String(step.command || '');
  const hasRunnableCommand = runMode === 'run';

  els.panel?.classList.remove('hidden');

  if (els.mode) {
    els.mode.className = `command-run-mode ${copy.className}`;
    els.mode.textContent = copy.label;
  }

  if (els.command) {
    els.command.value = runMode === 'none' ? '' : commandText;
    els.command.classList.toggle('hidden', runMode === 'none');
  }

  if (els.runner) {
    els.runner.textContent = step.runnerText || copy.runner;
  }

  if (els.note) {
    els.note.textContent = step.note || '';
  }

  if (els.explain) {
    els.explain.textContent = step.explain || step.body || step.nextAction || copy.empty || copy.runner;
  }

  if (els.parts) {
    const parts = normalizeParts(step);
    els.parts.innerHTML = parts.map(item => {
      const part = typeof item === 'string' ? item : item.part;
      const meaning = typeof item === 'string' ? '' : item.meaning;
      return `<li><strong>${sanitize(part || 'Step detail')}</strong>${meaning ? `: ${sanitize(meaning)}` : ''}</li>`;
    }).join('');
    els.details?.classList.toggle('hidden', parts.length === 0);
  }

  if (els.empty) {
    els.empty.textContent = step.emptyText || copy.empty;
    els.empty.classList.toggle('hidden', runMode !== 'none' && runMode !== 'read');
  }

  if (els.copy) {
    els.copy.classList.toggle('hidden', !hasRunnableCommand);
  }

  if (els.next) {
    els.next.textContent = options.finalLabel || copy.next;
  }

  return { hasRunnableCommand, runMode };
}
