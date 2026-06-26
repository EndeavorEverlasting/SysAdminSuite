// repo-setup-tutorial.js — dashboard front-door tutorial for clone/update/open.

import { sanitize, toast } from './utils.js';
import { applyCommandHelp, resolveRunMode } from './wizard-command-help.js';

export const REPO_SETUP_TUTORIAL_STEPS = [
  {
    title: 'Get SysAdminSuite',
    railLabel: 'Get repo',
    body: 'Start by getting one clean copy of SysAdminSuite. Pick a parent folder such as Desktop or dev, then clone into it. Do not create a SysAdminSuite folder first.',
    command: 'git clone https://github.com/EndeavorEverlasting/SysAdminSuite.git',
    checks: [
      'The command creates the SysAdminSuite folder for you.',
      'Avoid the common nested path: SysAdminSuite\\SysAdminSuite.',
      'No Git available? Use the approved field release package instead of a raw source clone.'
    ],
    nextAction: 'Copy this only if you need to clone. After the folder exists, open it and click Next.',
    explain: 'Clones one clean SysAdminSuite copy from GitHub into the folder you are currently in.',
    explainParts: [
      { part: 'git clone', meaning: 'Asks Git to download a repository into a new folder.' },
      { part: 'GitHub URL', meaning: 'The approved SysAdminSuite source repository.' },
      { part: 'Next', meaning: 'Only advances after you have run or skipped the clone yourself.' },
    ],
    note: 'Source clones are for IT/developer machines. Field PCs without the .NET SDK should use the field release ZIP.',
    hasCommand: true
  },
  {
    title: 'Open the dashboard',
    railLabel: 'Open dashboard',
    body: 'Open the SysAdminSuite folder and double-click the dashboard launcher. The launcher starts the local dashboard host and opens this browser page.',
    command: 'START-HERE-SysAdminSuite-Dashboard.bat',
    checks: [
      'Run it from the repo root, not from a subfolder.',
      'First launch may take a minute while the dashboard app is prepared.',
      'If the machine cannot build the app, ask for the packaged field release or IT preparation.'
    ],
    nextAction: 'Find the launcher at the top of the repo and double-click it. Then click Next.',
    explain: 'Points you to the documented double-click launcher; the dashboard does not start it from this browser page.',
    explainParts: [
      { part: 'START-HERE-SysAdminSuite-Dashboard.bat', meaning: 'The field-user dashboard launcher at the repo root.' },
      { part: 'Double-click', meaning: 'Run it from Windows Explorer, not from the Next button.' },
      { part: 'Next', meaning: 'Moves to the update guidance after you have opened the dashboard path.' },
    ],
    note: 'The .cmd shortcuts are aliases, but the .bat launcher is the documented front door.',
    hasCommand: false
  },
  {
    title: 'Update safely',
    railLabel: 'Update safely',
    body: 'Updates are opt-in. If a newer clean main or field package is available, the launcher asks before applying it. Nothing should silently update underneath a technician.',
    command: '# Source clone rule: approve first, then fast-forward clean main only.\n# ZIP / field package rule: approve first, then apply a checksum-verified package.',
    checks: [
      'Source clones update only from clean main with a fast-forward.',
      'Field packages update only from a checksum-verified package.',
      'Never use reset, branch deletion, or silent updates as the field path.'
    ],
    nextAction: 'Read this once. If the launcher asks to update, approve only when you are ready.',
    explain: 'Summarizes the safe update rules so technicians know updates are approval-gated.',
    explainParts: [
      { part: 'Source clone rule', meaning: 'Only fast-forward a clean main branch after approval.' },
      { part: 'ZIP / field package rule', meaning: 'Only apply a checksum-verified package after approval.' },
      { part: 'Nothing to run', meaning: 'This step is doctrine text, not a command.' },
    ],
    note: 'Approved update flow is documented in docs/APPROVED_UPDATE_FLOW.md.',
    hasCommand: false
  },
  {
    title: 'Pick the workflow',
    railLabel: 'Pick workflow',
    body: 'Now choose what you came here to do. Cybernet Survey teaches target loading, network posture, identity evidence, optional reachability, and where results appear.',
    command: '# Click Start Cybernet Survey for Cybernet field work.\n# Click Start Software Tracker Install only for the guarded install workflow.',
    checks: [
      'Use Cybernet Survey for Cybernet / Neuron target work.',
      'Use Software Tracker Install for dry-run install planning and guarded execute.',
      'Use Load Evidence when you already have output files to review.'
    ],
    nextAction: 'Click Next to finish setup, then choose the workflow button the dashboard highlights.',
    explain: 'Helps you choose the correct front-door workflow after setup is complete.',
    explainParts: [
      { part: 'Cybernet Survey', meaning: 'Use for Cybernet / Neuron target and evidence workflows.' },
      { part: 'Software Tracker Install', meaning: 'Use for dry-run install planning and guarded execution.' },
      { part: 'Load Evidence', meaning: 'Use when output files already exist and need review.' },
    ],
    note: 'Most Cybernet field work starts with Start Cybernet Survey.',
    hasCommand: false
  },
  {
    title: 'Ready for Cybernet Survey',
    railLabel: 'Ready',
    body: 'Setup is done. The next tutorial teaches the Cybernet survey from start to finish: start, load targets, run checks, finish, and review results.',
    command: '# No command here. Click Open Cybernet Survey below.',
    checks: [
      'You know where the repo lives.',
      'You know which launcher opens the dashboard.',
      'You know updates require approval before changes are applied.'
    ],
    nextAction: 'Click Open Cybernet Survey to start the field survey tutorial.',
    explain: 'Confirms setup is done and hands you to the Cybernet tutorial button.',
    explainParts: [
      { part: 'Ready', meaning: 'You know where the repo and launcher are.' },
      { part: 'Open Cybernet Survey', meaning: 'Starts the survey tutorial from the dashboard.' },
      { part: 'No command', meaning: 'There is nothing to copy or run on this final setup step.' },
    ],
    note: 'The Cybernet tutorial is separate so setup does not get mixed with field survey work.',
    hasCommand: false,
    finalAction: true
  }
];

export function initRepoSetupTutorial() {
  const root = document.getElementById('repo-setup-tutorial');
  if (!root) return;

  let idx = 0;
  let copiedThisStep = false;
  const title = document.getElementById('repo-setup-step-title');
  const body = document.getElementById('repo-setup-step-body');
  const kicker = document.getElementById('repo-setup-step-kicker');
  const checks = document.getElementById('repo-setup-step-checks');
  const command = document.getElementById('repo-setup-step-command');
  const commandMode = document.getElementById('repo-setup-command-mode');
  const explain = document.getElementById('repo-setup-command-explain');
  const explainDetails = document.getElementById('repo-setup-command-explain-details');
  const explainParts = document.getElementById('repo-setup-command-explain-parts');
  const commandEmpty = document.getElementById('repo-setup-command-empty');
  const runner = document.getElementById('repo-setup-command-runner');
  const note = document.getElementById('repo-setup-step-note');
  const commandPanel = document.getElementById('repo-setup-command-panel');
  const prev = document.getElementById('repo-setup-prev');
  const next = document.getElementById('repo-setup-next');
  const copy = document.getElementById('repo-setup-copy');
  const footer = document.getElementById('repo-setup-wizard-footer');
  const openCybernet = document.getElementById('repo-setup-open-cybernet');
  const cybernetStart = document.getElementById('hero-start-survey');
  const progressRail = document.getElementById('repo-setup-progress-rail');

  function updateProgressRail() {
    progressRail?.querySelectorAll('li').forEach((li, i) => {
      li.classList.toggle('active', i === idx);
      li.classList.toggle('done', i < idx);
    });
  }

  function updateGuideState(hasCommand) {
    const finalStep = idx === REPO_SETUP_TUTORIAL_STEPS.length - 1;
    copy?.classList.toggle('sas-guide-glow', hasCommand && !copiedThisStep);
    next?.classList.toggle('sas-guide-glow', (hasCommand && copiedThisStep) || (!hasCommand && !finalStep));
    openCybernet?.classList.toggle('sas-guide-glow', finalStep);
    cybernetStart?.classList.toggle('sas-guide-glow', finalStep);
    commandPanel?.classList.toggle('sas-guide-panel', hasCommand && !copiedThisStep);
  }

  function render() {
    const step = REPO_SETUP_TUTORIAL_STEPS[idx];
    if (!step) return;
    copiedThisStep = false;
    const runMode = resolveRunMode(step);
    const hasCommand = runMode === 'run';
    kicker.textContent = `Step ${idx + 1} of ${REPO_SETUP_TUTORIAL_STEPS.length} — ${step.railLabel}`;
    title.textContent = step.title;
    body.textContent = step.body;
    checks.innerHTML = step.checks.map(item => `<li>${sanitize(item)}</li>`).join('');
    applyCommandHelp({
      panel: commandPanel, command, mode: commandMode, runner, note, explain,
      details: explainDetails, parts: explainParts, empty: commandEmpty, copy, next,
    }, step, runMode, { finalLabel: step.finalAction ? 'Finish setup' : '' });
    if (prev) prev.disabled = idx === 0;
    footer?.classList.toggle('hidden', !step.finalAction);
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

  function openCybernetSurvey() {
    cybernetStart?.classList.remove('sas-guide-glow');
    openCybernet?.classList.remove('sas-guide-glow');
    if (typeof window.startCybernetTutorial === 'function') {
      window.startCybernetTutorial({ source: 'manual' });
    } else {
      cybernetStart?.click();
    }
  }

  prev?.addEventListener('click', () => { if (idx > 0) { idx--; render(); } });
  next?.addEventListener('click', () => {
    const step = REPO_SETUP_TUTORIAL_STEPS[idx];
    const hasCommand = resolveRunMode(step) === 'run';
    if (hasCommand && step.requireCopy && !copiedThisStep) {
      toast('Copy and run the command outside the dashboard first, or continue only if the repo already exists.', 'warning');
      return;
    }
    if (idx < REPO_SETUP_TUTORIAL_STEPS.length - 1) {
      idx++;
      render();
    } else {
      toast('Repo setup complete — choose Cybernet Survey when ready.', 'success');
      document.getElementById('cybernet-hero')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      render();
    }
  });
  copy?.addEventListener('click', copyCommand);
  openCybernet?.addEventListener('click', openCybernetSurvey);

  window.__sasResetRepoSetupWizard = () => { idx = 0; copiedThisStep = false; render(); };

  render();
}
