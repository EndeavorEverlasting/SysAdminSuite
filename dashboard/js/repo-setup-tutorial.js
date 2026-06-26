// repo-setup-tutorial.js — dashboard front-door tutorial for clone/update/open.

import { sanitize, toast } from './utils.js';

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
    const hasCommand = !!step.hasCommand;
    kicker.textContent = `Step ${idx + 1} of ${REPO_SETUP_TUTORIAL_STEPS.length} — ${step.railLabel}`;
    title.textContent = step.title;
    body.textContent = step.body;
    checks.innerHTML = step.checks.map(item => `<li>${sanitize(item)}</li>`).join('');
    commandPanel?.classList.toggle('hidden', !hasCommand);
    if (command) command.value = hasCommand ? step.command : '';
    if (runner) runner.textContent = step.nextAction || 'Read the step, then click Next.';
    if (note) note.textContent = step.note || '';
    if (prev) prev.disabled = idx === 0;
    if (next) next.textContent = step.finalAction ? 'Finish setup' : hasCommand ? 'Next after cloning →' : 'Next →';
    copy?.classList.toggle('hidden', !hasCommand);
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
        toast('Repo setup command copied.', 'success');
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
    const hasCommand = !!step?.hasCommand;
    if (hasCommand && step.requireCopy && !copiedThisStep) {
      toast('Copy the clone command first, or continue only if the repo already exists.', 'warning');
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
