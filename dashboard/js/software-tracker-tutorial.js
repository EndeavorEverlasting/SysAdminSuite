// software-tracker-tutorial.js — guarded install workflow wizard (dry-run → approve → execute)

import { sanitize, toast } from './utils.js';
import {
  SOFTWARE_TRACKER_PATHS,
  buildSoftwareTrackerDryRunCommand,
  buildSoftwareTrackerExecuteCommand,
} from './software-tracker-paths.js';
import {
  getSoftwareInstallPlan,
  getSoftwareSelection,
  setSoftwareSelection,
  setLiveRunApproved,
  summarizeInstallBlockers,
  isLiveRunApproved,
  canRunLiveInstall,
} from './software-tracker-state.js';

export const SOFTWARE_TRACKER_TUTORIAL_STEPS = [
  {
    title: 'Load Software Tracker',
    railLabel: 'Load tracker',
    body: 'When the network share is unavailable, use the local offline workbook stored in the repo. Do not hunt for a live server path during guest or segmented network work.',
    command: `# Offline workbook (gitignored local copy):\n${SOFTWARE_TRACKER_PATHS.offlineWorkbook}\n\n# Windows path example:\n${SOFTWARE_TRACKER_PATHS.offlineWorkbookWindows}`,
    checks: [
      'Copy the current Software Tracker workbook into logs/targets/software/ before you start.',
      'Expected filename pattern: Software Tracker M-D-YYYY.xlsx (example: Software Tracker 6-26-2026.xlsx).',
      'This file stays local and is never committed to git.',
    ],
    nextAction: 'Confirm the offline workbook exists at the path above, then click Next.',
    note: 'Canonical path is documented in Config/software-tracker.paths.json and docs/SOFTWARE_TRACKER_INSTALLS.md.',
    optional: false,
    hasCommand: false,
  },
  {
    title: 'Choose list or software',
    railLabel: 'Choose target',
    body: 'Limit the install plan to one named list or one application from the Directories sheet. Leave both blank to plan the whole catalog.',
    command: '# Use the selectors below, or add flags to the dry-run command:\n#   --list "workstation-baseline"\n#   --software "Google Chrome"',
    checks: [
      'List mode is best for site packages or baseline bundles.',
      'Software mode is best for one application at a time.',
      'You can change the selection and re-run Preview Install Plan anytime.',
    ],
    nextAction: 'Pick an optional list or software name using the fields below, then click Next.',
    note: 'Selection is optional. Blank means plan all rows in scope.',
    optional: false,
    hasCommand: false,
    showSelection: true,
  },
  {
    title: 'Dry-run preview',
    railLabel: 'Dry-run preview',
    body: 'Generate the install plan first. Nothing installs during dry-run. The command writes install-summary.json, install-summary.csv, and install-log.txt locally.',
    command: '', // filled dynamically
    checks: [
      'Dry-run is the default and required first step.',
      'No installer commands run without --execute.',
      'Reports land in survey/output/software-tracker-install/.',
    ],
    nextAction: 'Click Copy Command, run it on your admin machine, then load install-summary.json back into the dashboard.',
    note: `Primary action label: Preview Install Plan. Output: ${SOFTWARE_TRACKER_PATHS.reportJson}`,
    optional: false,
    hasCommand: true,
    commandKind: 'dry-run',
  },
  {
    title: 'Review blockers',
    railLabel: 'Review blockers',
    body: 'Load install-summary.json from the dry-run output. Review blocked URLs, EXEs missing silent args, folder paths needing manual review, and missing installers before any live run.',
    command: `# Load this file via Load Evidence or drop it on the dashboard:\n${SOFTWARE_TRACKER_PATHS.reportJson}`,
    checks: [
      'Blocked rows are expected safety outcomes, not parser failures.',
      'URLs are never opened or executed.',
      'Folder paths stay manual-review unless execute plus allow-discovered-folder-installs are both set.',
    ],
    nextAction: 'Drop install-summary.json, confirm the blocker summary below, then click Next.',
    note: 'Primary action label: Review Plan.',
    optional: false,
    hasCommand: false,
    showPlanSummary: true,
  },
  {
    title: 'Approve live run',
    railLabel: 'Approve live run',
    body: 'Live execution only runs after you review the dry-run plan and explicitly approve it. This step explains what guarded execute will do.',
    command: '# Check Approve Live Run below after you understand the planned mutations.',
    checks: [
      'Approve only after reviewing install-summary.json.',
      'Live run uses --execute and still respects blocked/manual-review rows.',
      'Relay is not required; copy and run the command on an admin workstation.',
    ],
    nextAction: 'Check Approve Live Run, then click Next.',
    note: 'Primary action label: Approve Live Run.',
    optional: false,
    hasCommand: false,
    showApproval: true,
  },
  {
    title: 'Run guarded execute',
    railLabel: 'Run execute',
    body: 'Copy the guarded execute command. It adds --execute only after approval. Folder-discovered installers also need --allow-discovered-folder-installs.',
    command: '',
    checks: [
      'Execute mode never runs blocked or manual-review rows.',
      'EXE installers require explicit silent arguments.',
      'Commands run as argv lists with shell=False in the Python tool.',
    ],
    nextAction: 'Click Copy Command, run it outside the dashboard, then load the updated install-summary.json.',
    note: 'Primary action label: Run Approved Installs.',
    optional: false,
    hasCommand: true,
    commandKind: 'execute',
    requiresApproval: true,
    showExecuteOptions: true,
  },
  {
    title: 'Save results',
    railLabel: 'Save results',
    body: 'Keep the JSON, CSV, and text reports for handoff. Re-run dry-run any time the workbook or selection changes.',
    command: `# Report locations:\n${SOFTWARE_TRACKER_PATHS.reportJson}\n${SOFTWARE_TRACKER_PATHS.reportCsv}\n${SOFTWARE_TRACKER_PATHS.reportText}`,
    checks: [
      'Do not commit live workbook files or field reports to git.',
      'Use Export Report in the Software panel for a quick CSV copy of the loaded plan.',
      'If results look wrong, use Back to dry-run and start over.',
    ],
    nextAction: 'Open the Software Tracker panel to export or review the final plan.',
    note: 'Primary action label: Export Report.',
    optional: false,
    hasCommand: false,
  },
];

function buildStepCommand(step) {
  const sel = getSoftwareSelection();
  if (step.commandKind === 'dry-run') {
    return buildSoftwareTrackerDryRunCommand(sel);
  }
  if (step.commandKind === 'execute') {
    const allowFolder = document.getElementById('sw-tutorial-allow-folder')?.checked
      || document.getElementById('sw-allow-folder')?.checked;
    return buildSoftwareTrackerExecuteCommand({ ...sel, allowFolder });
  }
  return step.command || '';
}

export function initSoftwareTrackerTutorial() {
  const root = document.getElementById('software-tracker-tutorial');
  if (!root) return;

  let idx = 0;
  let copiedThisStep = false;
  const title = document.getElementById('sw-step-title');
  const body = document.getElementById('sw-step-body');
  const kicker = document.getElementById('sw-step-kicker');
  const checks = document.getElementById('sw-step-checks');
  const command = document.getElementById('sw-step-command');
  const runner = document.getElementById('sw-command-runner');
  const note = document.getElementById('sw-step-note');
  const commandPanel = document.getElementById('sw-command-panel');
  const prev = document.getElementById('sw-prev');
  const next = document.getElementById('sw-next');
  const copy = document.getElementById('sw-copy');
  const progressRail = document.getElementById('software-tracker-progress-rail');
  const listInput = document.getElementById('sw-tutorial-list');
  const softwareInput = document.getElementById('sw-tutorial-software');
  const planSummary = document.getElementById('sw-tutorial-plan-summary');
  const approveBox = document.getElementById('sw-tutorial-approve-live');
  const selectionPanel = document.getElementById('sw-selection-panel');
  const approvalPanel = document.getElementById('sw-approval-panel');
  const executeOptionsPanel = document.getElementById('sw-execute-options-panel');
  const allowFolderTutorial = document.getElementById('sw-tutorial-allow-folder');

  function updateProgressRail() {
    progressRail?.querySelectorAll('li').forEach((li, i) => {
      li.classList.toggle('active', i === idx);
      li.classList.toggle('done', i < idx);
    });
  }

  function renderPlanSummary() {
    if (!planSummary) return;
    const plan = getSoftwareInstallPlan();
    if (!plan) {
      planSummary.textContent = 'No install-summary.json loaded yet. Run Preview Install Plan, then drop the JSON report here.';
      return;
    }
    const summary = summarizeInstallBlockers(plan);
    const lines = [
      `Total rows: ${summary.total}`,
      `Blocked: ${summary.blocked.length}`,
      `Manual review: ${summary.manual.length}`,
      `Dry-run / planned: ${summary.planned.length}`,
    ];
    if (summary.blocked.length) {
      lines.push('Blocked examples: ' + summary.blocked.slice(0, 3).map(i => `${i.software_name} (${i.reason})`).join('; '));
    }
    planSummary.textContent = lines.join(' · ');
  }

  function render() {
    const step = SOFTWARE_TRACKER_TUTORIAL_STEPS[idx];
    if (!step) return;
    copiedThisStep = false;

    kicker.textContent = `Step ${idx + 1} of ${SOFTWARE_TRACKER_TUTORIAL_STEPS.length} — ${step.railLabel}`;
    title.textContent = step.title;
    body.textContent = step.body;
    checks.innerHTML = step.checks.map(item => `<li>${sanitize(item)}</li>`).join('');

    selectionPanel?.classList.toggle('hidden', !step.showSelection);
    approvalPanel?.classList.toggle('hidden', !step.showApproval);
    executeOptionsPanel?.classList.toggle('hidden', !step.showExecuteOptions);
    planSummary?.classList.toggle('hidden', !step.showPlanSummary);
    if (step.showPlanSummary) renderPlanSummary();

    const cmdText = buildStepCommand(step);
    const hasCommand = !!(step.hasCommand && cmdText);
    commandPanel?.classList.toggle('hidden', !hasCommand && !step.command);
    if (command) command.value = hasCommand ? cmdText : (step.command || '');
    if (runner) runner.textContent = step.nextAction;
    if (note) note.textContent = step.note;

    prev.disabled = idx === 0;
    next.textContent = idx === SOFTWARE_TRACKER_TUTORIAL_STEPS.length - 1 ? 'Finish' : 'Next →';
    copy?.classList.toggle('hidden', !hasCommand);

    updateProgressRail();
  }

  function copyCommand() {
    const text = command?.value || '';
    if (!text) return;
    const write = navigator.clipboard?.writeText
      ? navigator.clipboard.writeText(text)
      : Promise.reject(new Error('clipboard unavailable'));
    write
      .then(() => {
        copiedThisStep = true;
        toast('Command copied.', 'success');
      })
      .catch(() => toast('Select and copy the command manually.', 'warning'));
  }

  listInput?.addEventListener('input', () => {
    setSoftwareSelection({ list: listInput.value.trim(), software: softwareInput?.value.trim() || '' });
    render();
  });
  softwareInput?.addEventListener('input', () => {
    setSoftwareSelection({ list: listInput?.value.trim() || '', software: softwareInput.value.trim() });
    render();
  });
  approveBox?.addEventListener('change', () => setLiveRunApproved(approveBox.checked));
  allowFolderTutorial?.addEventListener('change', () => render());
  window.addEventListener('sas-software-install-state', () => {
    if (approveBox) approveBox.checked = isLiveRunApproved();
    renderPlanSummary();
    render();
  });

  prev?.addEventListener('click', () => { if (idx > 0) { idx--; render(); } });
  next?.addEventListener('click', () => {
    const step = SOFTWARE_TRACKER_TUTORIAL_STEPS[idx];
    if (step.showApproval && !isLiveRunApproved()) {
      toast('Check Approve Live Run before continuing.', 'warning');
      return;
    }
    if (step.requiresApproval && !canRunLiveInstall() && !isLiveRunApproved()) {
      toast('Load a dry-run plan and approve live run first.', 'warning');
      return;
    }
    if (step.hasCommand && !copiedThisStep) {
      toast('Copy the command first, run it outside the dashboard, then continue.', 'warning');
      return;
    }
    if (step.showPlanSummary && !getSoftwareInstallPlan()) {
      toast('Load install-summary.json before continuing.', 'warning');
      return;
    }
    if (idx < SOFTWARE_TRACKER_TUTORIAL_STEPS.length - 1) {
      idx++;
      render();
    } else {
      document.getElementById('advanced-section')?.classList.remove('hidden');
      document.getElementById('content')?.classList.remove('hidden');
      document.querySelector('.tab-btn[data-tab="software"]')?.click();
      toast('Software Tracker install workflow complete.', 'success');
    }
  });
  copy?.addEventListener('click', copyCommand);

  window.__sasResetSoftwareTrackerWizard = () => { idx = 0; copiedThisStep = false; render(); };
  render();
}
