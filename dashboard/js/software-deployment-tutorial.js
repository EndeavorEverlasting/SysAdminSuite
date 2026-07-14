// software-deployment-tutorial.js
// Browser-first guide for generated-executable dry run -> one authorized pilot.
(function (global) {
  'use strict';

  const DRY_RUN_COMMAND = [
    'pwsh -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\Invoke-SasSoftwareInstallE2E.ps1 `',
    '  -OutputRoot .\\survey\\output\\software-install-e2e'
  ].join('\n');

  function psQuote(value) {
    return `'${String(value || '').replace(/'/g, "''")}'`;
  }

  function parseArguments(value) {
    return String(value || '')
      .split(/\r?\n|,/)
      .map(item => item.trim())
      .filter(Boolean);
  }

  function validatePilot(input) {
    const errors = [];
    const target = String(input?.target || '').trim();
    const packageName = String(input?.packageName || '').trim();
    const installerPath = String(input?.installerPath || '').trim();
    const args = parseArguments(input?.installerArguments);
    const installMode = input?.installMode === 'CopyThenInstall' ? 'CopyThenInstall' : 'UncDirect';

    if (!target) errors.push('Enter one authorized pilot workstation.');
    else if (!/^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$/.test(target)) {
      errors.push('Use one hostname or FQDN only. Do not enter a list, spaces, commas, or wildcards.');
    }
    if (!packageName) errors.push('Enter the approved package display name.');
    if (!installerPath) errors.push('Enter the approved installer path relative to the configured source root.');
    else if (/^(?:[A-Za-z]:|[\\/])/.test(installerPath) || installerPath.split(/[\\/]+/).includes('..')) {
      errors.push('Installer path must be relative and must not contain parent traversal.');
    }
    if (!args.length) errors.push('Enter vendor-supported silent arguments, one per line or comma-separated.');

    return {
      valid: errors.length === 0,
      errors,
      value: { target, packageName, installerPath, installerArguments: args, installMode }
    };
  }

  function buildInstallCommand(input, live) {
    const result = validatePilot(input);
    if (!result.valid) return { ...result, command: '' };
    const item = result.value;
    const argList = item.installerArguments.map(psQuote).join(', ');
    const lines = [
      '.\\scripts\\Invoke-SasSoftwareInstall.ps1 `',
      `  -ComputerName ${psQuote(item.target)} \``,
      `  -PackageName ${psQuote(item.packageName)} \``,
      `  -InstallerRelativePath ${psQuote(item.installerPath)} \``,
      `  -InstallerArguments @(${argList}) \``,
      `  -InstallMode ${item.installMode} \``
    ];
    lines.push(live ? '  -AllowTargetMutation' : '  -WhatIf');
    return { ...result, command: lines.join('\n') };
  }

  function buildWhatIfCommand(input) {
    return buildInstallCommand(input, false);
  }

  function buildPilotCommand(input) {
    return buildInstallCommand(input, true);
  }

  const API = {
    DRY_RUN_COMMAND,
    parseArguments,
    validatePilot,
    buildWhatIfCommand,
    buildPilotCommand
  };
  global.__sasSoftwareDeploymentTutorialApi = API;

  if (typeof document === 'undefined') return;

  const STEPS = [
    {
      phase: 'Orientation',
      title: 'Understand the proof ladder',
      body: 'The dashboard guides the work, but it never installs software itself. First prove the complete installer chain against an isolated dummy target. Only then prepare one separately authorized pilot workstation.',
      checks: [
        'Fixture proof and live workstation proof are different evidence levels.',
        'The browser generates and explains commands; you run them from an approved admin session.',
        'The first live pilot stays limited to one workstation.'
      ],
      action: 'Review the sequence, then continue to the safe executable dry run.',
      mode: 'read'
    },
    {
      phase: 'Safe dry run',
      title: 'Run the generated dummy installer',
      body: 'This builds a temporary Windows executable from tracked C# source and sends it through the real SysAdminSuite software-install wrapper. It does not contact a package share or workstation.',
      checks: [
        'Expected proof class: fixture-software-install-executable-e2e.',
        'Expected delta: 3 added, 0 changed, 0 removed.',
        'The generated executable and evidence remain under ignored output paths.'
      ],
      action: 'Copy the command, run it at the repo root, then return to review the evidence.',
      mode: 'command',
      commandKind: 'dry-run'
    },
    {
      phase: 'Evidence gate',
      title: 'Review the dry-run evidence',
      body: 'Open survey\\output\\software-install-e2e and verify the result before any pilot preparation. A green command exit alone is not enough.',
      checks: [
        'software_install_e2e_result.json reports PASS.',
        'real_operator_wrapper_executed and real_installer_executable_executed are true.',
        'The package version is 1.0.0 and the exact delta is 3 / 0 / 0.',
        'Operator failures, cleanup failures, and repo-owned remnants are all zero.'
      ],
      action: 'Check the acknowledgement only after you inspect the generated JSON, matrix, installer log, and operator summary.',
      mode: 'fixture-review'
    },
    {
      phase: 'Pilot preparation',
      title: 'Enter one approved pilot',
      body: 'Use one authorized hostname, one approved package, the path relative to the configured source root, and vendor-supported silent arguments. The dashboard rejects lists and unsafe paths.',
      checks: [
        'Record the installer SHA-256, signature, publisher, and version separately.',
        'Use UncDirect when the target can read the approved share.',
        'Use CopyThenInstall only when temporary staging is approved and necessary.'
      ],
      action: 'Complete every field. These values generate both the WhatIf plan and the later pilot command.',
      mode: 'pilot-input'
    },
    {
      phase: 'Request review',
      title: 'Generate the WhatIf plan',
      body: 'The WhatIf command validates the request and writes local planning evidence. It does not open a remote session, read the package share, copy a payload, or start an installer.',
      checks: [
        'Confirm the target is exactly the approved pilot.',
        'Confirm package name, relative path, arguments, and mode.',
        'Review software_install_events.jsonl, software_install_summary.json, and operator_handoff.txt.'
      ],
      action: 'Copy and run the WhatIf command, inspect the newest software_install run folder, then acknowledge that it matches the approved request.',
      mode: 'command-review',
      commandKind: 'what-if'
    },
    {
      phase: 'Mutation approval',
      title: 'Approve one confirmation-enabled pilot',
      body: 'Live mutation remains blocked until every approval gate is checked. This tutorial never removes the PowerShell confirmation prompt from the first pilot.',
      checks: [
        'The dry-run fixture passed and its evidence was reviewed.',
        'The WhatIf plan matches the authorized target and package.',
        'Package evidence and silent arguments are approved.',
        'The maintenance window and post-install checks are ready.'
      ],
      action: 'Check every approval. If any statement is uncertain, stop and correct the request instead of proceeding.',
      mode: 'approval'
    },
    {
      phase: 'Pilot execution',
      title: 'Run the guarded pilot',
      body: 'This command adds AllowTargetMutation but keeps confirmation enabled. Read the prompt and verify the same target, package, arguments, source, mode, and change window before confirming.',
      checks: [
        'Do not add a second target while the first is running.',
        'Do not bypass the confirmation prompt on the first pilot.',
        'A process launch or exit code alone is not deployment proof.'
      ],
      action: 'Copy the command, run it in the approved admin context, and return with the operator evidence and observed package behavior.',
      mode: 'command',
      commandKind: 'pilot'
    },
    {
      phase: 'Decision',
      title: 'Review results and decide',
      body: 'Expand only after the operator evidence, cleanup, installed state, required reboot, application readiness, and intended behavior all agree. Otherwise stop and preserve the evidence.',
      checks: [
        'completed_count = 1 and failed_count = 0.',
        'cleanup_failure_count = 0 and repo_artifact_remaining_count = 0.',
        'Installer exit code is approved and package-specific detection passes.',
        'Required reboot, launch readiness, and intended behavior were actually observed.'
      ],
      action: 'Stop for uncertainty, unexpected interaction, security blocking, wrong version, cleanup failure, target remnants, or contradictory evidence.',
      mode: 'decision'
    }
  ];

  function injectStyles() {
    if (document.getElementById('sas-software-deployment-styles')) return;
    const style = document.createElement('style');
    style.id = 'sas-software-deployment-styles';
    style.textContent = `
      .sas-deploy-hero { border-color: rgba(90, 200, 250, .38); background: linear-gradient(135deg, rgba(20,82,120,.22), rgba(26,40,65,.88)); }
      .sas-deploy-hero-inner { position: relative; }
      .sas-deploy-badge { display:inline-flex; align-items:center; gap:6px; padding:4px 9px; border-radius:999px; background:rgba(90,200,250,.14); border:1px solid rgba(90,200,250,.35); color:#9cddff; font-size:11px; font-weight:700; letter-spacing:.04em; text-transform:uppercase; margin-bottom:8px; }
      .sas-deploy-subtitle { max-width:760px; }
      .sas-deploy-tutorial { border:1px solid rgba(90,200,250,.3); }
      .sas-deploy-phase { display:inline-flex; padding:4px 8px; border-radius:5px; background:rgba(90,200,250,.12); color:#9cddff; font-size:10px; font-weight:700; letter-spacing:.08em; text-transform:uppercase; margin-bottom:8px; }
      .sas-deploy-action { margin-top:14px; padding:10px 12px; border-left:3px solid #5ac8fa; background:rgba(90,200,250,.08); border-radius:4px; }
      .sas-deploy-inputs, .sas-deploy-gate, .sas-deploy-decision { margin-top:14px; padding:14px; border:1px solid rgba(148,163,184,.22); border-radius:8px; background:rgba(15,23,42,.45); }
      .sas-deploy-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:12px; }
      .sas-deploy-grid label { display:flex; flex-direction:column; gap:5px; font-size:11px; color:var(--text-dim); }
      .sas-deploy-grid label.sas-deploy-wide { grid-column:1/-1; }
      .sas-deploy-grid input, .sas-deploy-grid textarea, .sas-deploy-grid select { width:100%; box-sizing:border-box; padding:8px 9px; color:var(--text); background:var(--bg3); border:1px solid var(--border); border-radius:5px; font:12px var(--mono); }
      .sas-deploy-grid textarea { min-height:70px; resize:vertical; }
      .sas-deploy-gate label { display:flex; align-items:flex-start; gap:8px; margin:8px 0; line-height:1.4; }
      .sas-deploy-gate input { margin-top:2px; }
      .sas-deploy-errors { color:#fca5a5; margin:9px 0 0; font-size:11px; white-space:pre-line; }
      .sas-deploy-command { min-height:170px; }
      .sas-deploy-command-meta { display:flex; justify-content:space-between; gap:10px; align-items:center; margin-bottom:8px; }
      .sas-deploy-proof { font-size:10px; color:var(--text-muted); }
      .sas-deploy-flash { min-height:18px; margin:8px 0 0; font-size:11px; color:#9cddff; }
      .sas-deploy-decision-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:12px; }
      .sas-deploy-decision-card { padding:12px; border-radius:7px; border:1px solid rgba(148,163,184,.24); }
      .sas-deploy-decision-card h4 { margin:0 0 7px; }
      .sas-deploy-decision-card ul { margin:0; padding-left:18px; }
      .sas-deploy-expand { background:rgba(34,197,94,.08); border-color:rgba(34,197,94,.28); }
      .sas-deploy-stop { background:rgba(239,68,68,.08); border-color:rgba(239,68,68,.28); }
      .sas-deploy-progress-rail { grid-template-columns:repeat(8,minmax(0,1fr)); }
      @media (max-width:760px) { .sas-deploy-grid, .sas-deploy-decision-grid { grid-template-columns:1fr; } .sas-deploy-progress-rail { grid-template-columns:repeat(4,minmax(0,1fr)); } }
    `;
    document.head.appendChild(style);
  }

  function injectUi() {
    if (document.getElementById('software-deployment-hero')) return true;
    const anchor = document.getElementById('software-tracker-hero');
    if (!anchor || !anchor.parentNode) return false;

    const wrapper = document.createElement('div');
    wrapper.innerHTML = `
      <section id="software-deployment-hero" class="workflow-hero sas-deploy-hero" aria-label="Software Deployment">
        <div class="software-tracker-hero-inner sas-deploy-hero-inner">
          <span class="sas-deploy-badge">Primary deployment interface</span>
          <h2>Software Deployment</h2>
          <p class="software-tracker-hero-subtitle sas-deploy-subtitle">Prove the generated dummy installer, prepare one authorized pilot, review the WhatIf plan, run with confirmation, and verify evidence before expansion.</p>
          <ol class="workflow-progress-rail sas-deploy-progress-rail" id="software-deployment-progress-rail" aria-label="Software deployment tutorial progress">
            ${STEPS.map((step, index) => `<li data-step="${index}">${step.phase}</li>`).join('')}
          </ol>
          <div class="software-tracker-hero-actions">
            <button class="btn-primary" id="hero-start-deployment" type="button">Start Software Deployment</button>
            <button class="btn-secondary" id="hero-deployment-dry-run" type="button">Jump to Safe Dry Run</button>
          </div>
          <p id="software-deployment-hero-status" class="software-tracker-hero-status hidden" role="status" aria-live="polite"></p>
        </div>
      </section>
      <section id="software-deployment-tutorial" class="workflow-tutorial sas-deploy-tutorial hidden" aria-label="Software deployment wizard">
        <div class="workflow-exit-bar"><button class="workflow-exit-btn" id="software-deployment-exit" type="button">← Back to dashboard</button></div>
        <div class="workflow-step-kicker" id="software-deployment-step-kicker">Step 1 of ${STEPS.length}</div>
        <div class="workflow-step-card">
          <div class="workflow-step-content">
            <span class="sas-deploy-phase" id="software-deployment-phase"></span>
            <h3 id="software-deployment-step-title"></h3>
            <p id="software-deployment-step-body"></p>
            <ul id="software-deployment-step-checks"></ul>
            <p class="sas-deploy-action" id="software-deployment-step-action"></p>
            <div id="software-deployment-pilot-inputs" class="sas-deploy-inputs hidden">
              <div class="sas-deploy-grid">
                <label>Pilot workstation<input id="software-deployment-target" autocomplete="off" placeholder="AUTHORIZED-HOST"></label>
                <label>Package display name<input id="software-deployment-package" autocomplete="off" placeholder="Approved package name"></label>
                <label class="sas-deploy-wide">Installer path relative to approved root<input id="software-deployment-path" autocomplete="off" placeholder="packages\\Vendor\\Package\\setup.exe"></label>
                <label class="sas-deploy-wide">Silent arguments, one per line or comma-separated<textarea id="software-deployment-args" spellcheck="false" placeholder="/quiet&#10;/norestart"></textarea></label>
                <label>Install mode<select id="software-deployment-mode"><option value="UncDirect">UncDirect (preferred)</option><option value="CopyThenInstall">CopyThenInstall (temporary staging)</option></select></label>
              </div>
              <p id="software-deployment-input-errors" class="sas-deploy-errors" role="alert"></p>
            </div>
            <div id="software-deployment-fixture-gate" class="sas-deploy-gate hidden">
              <label><input type="checkbox" id="software-deployment-fixture-reviewed"> I reviewed PASS, real wrapper execution, real generated executable execution, the exact 3 / 0 / 0 delta, and zero failures or remnants.</label>
            </div>
            <div id="software-deployment-plan-gate" class="sas-deploy-gate hidden">
              <label><input type="checkbox" id="software-deployment-plan-reviewed"> I ran WhatIf and reviewed the newest local software_install summary, events, and handoff. They match this one authorized target and package.</label>
            </div>
            <div id="software-deployment-approval-gate" class="sas-deploy-gate hidden">
              <label><input type="checkbox" data-deploy-approval> The workstation and maintenance window are authorized.</label>
              <label><input type="checkbox" data-deploy-approval> Hash, signature, publisher, version, and silent arguments were independently reviewed.</label>
              <label><input type="checkbox" data-deploy-approval> The fixture dry run and WhatIf plan passed their evidence gates.</label>
              <label><input type="checkbox" data-deploy-approval> Post-install detection, reboot, launch, and business-behavior checks are ready.</label>
            </div>
            <div id="software-deployment-decision" class="sas-deploy-decision hidden">
              <div class="sas-deploy-decision-grid">
                <div class="sas-deploy-decision-card sas-deploy-expand"><h4>Expand only when</h4><ul><li>1 completed, 0 failed</li><li>0 cleanup failures or remnants</li><li>Version and detection pass</li><li>Required reboot and behavior are observed</li></ul></div>
                <div class="sas-deploy-decision-card sas-deploy-stop"><h4>Stop when</h4><ul><li>Package evidence or arguments are uncertain</li><li>Security blocks or unexpected interaction occurs</li><li>Version, behavior, cleanup, or evidence is wrong</li><li>Results are incomplete or contradictory</li></ul></div>
              </div>
            </div>
          </div>
          <div class="workflow-command-panel" id="software-deployment-command-panel">
            <div class="sas-deploy-command-meta"><div class="command-panel-title">Command to run outside the dashboard</div><span class="sas-deploy-proof" id="software-deployment-proof-label"></span></div>
            <div class="command-panel-runner">Run only from an approved admin session at the repo root. The web interface guides and validates the request; it never executes the installer.</div>
            <textarea class="sas-deploy-command" id="software-deployment-command" readonly spellcheck="false"></textarea>
            <div class="command-panel-note" id="software-deployment-command-note"></div>
            <div class="sas-deploy-flash" id="software-deployment-flash" role="status" aria-live="polite"></div>
          </div>
        </div>
        <div class="workflow-tutorial-nav">
          <button class="btn-secondary" id="software-deployment-prev" type="button">← Previous Step</button>
          <button class="btn-secondary" id="software-deployment-copy" type="button">Copy Command</button>
          <button class="btn-primary" id="software-deployment-next" type="button">Next →</button>
        </div>
      </section>
    `;

    const hero = wrapper.firstElementChild;
    const tutorial = hero.nextElementSibling;
    anchor.parentNode.insertBefore(hero, anchor);
    anchor.parentNode.insertBefore(tutorial, anchor);

    const repoActions = document.getElementById('repo-setup-hero-actions');
    if (repoActions && !document.getElementById('hero-open-deployment')) {
      const button = document.createElement('button');
      button.className = 'btn-secondary';
      button.id = 'hero-open-deployment';
      button.type = 'button';
      button.textContent = 'Open Software Deployment';
      repoActions.appendChild(button);
    }
    return true;
  }

  function init() {
    injectStyles();
    if (!injectUi()) return;

    let index = 0;
    let copiedStep = -1;
    const hero = document.getElementById('software-deployment-hero');
    const tutorial = document.getElementById('software-deployment-tutorial');
    const status = document.getElementById('software-deployment-hero-status');
    const kicker = document.getElementById('software-deployment-step-kicker');
    const phase = document.getElementById('software-deployment-phase');
    const title = document.getElementById('software-deployment-step-title');
    const body = document.getElementById('software-deployment-step-body');
    const checks = document.getElementById('software-deployment-step-checks');
    const action = document.getElementById('software-deployment-step-action');
    const command = document.getElementById('software-deployment-command');
    const commandPanel = document.getElementById('software-deployment-command-panel');
    const commandNote = document.getElementById('software-deployment-command-note');
    const proofLabel = document.getElementById('software-deployment-proof-label');
    const flash = document.getElementById('software-deployment-flash');
    const prev = document.getElementById('software-deployment-prev');
    const next = document.getElementById('software-deployment-next');
    const copy = document.getElementById('software-deployment-copy');
    const inputs = document.getElementById('software-deployment-pilot-inputs');
    const fixtureGate = document.getElementById('software-deployment-fixture-gate');
    const planGate = document.getElementById('software-deployment-plan-gate');
    const approvalGate = document.getElementById('software-deployment-approval-gate');
    const decision = document.getElementById('software-deployment-decision');
    const errors = document.getElementById('software-deployment-input-errors');

    function pilotInput() {
      return {
        target: document.getElementById('software-deployment-target')?.value,
        packageName: document.getElementById('software-deployment-package')?.value,
        installerPath: document.getElementById('software-deployment-path')?.value,
        installerArguments: document.getElementById('software-deployment-args')?.value,
        installMode: document.getElementById('software-deployment-mode')?.value
      };
    }

    function commandFor(step) {
      if (step.commandKind === 'dry-run') return { valid: true, command: DRY_RUN_COMMAND };
      if (step.commandKind === 'what-if') return buildWhatIfCommand(pilotInput());
      if (step.commandKind === 'pilot') return buildPilotCommand(pilotInput());
      return { valid: true, command: '' };
    }

    function setStatus(message, kind) {
      if (!status) return;
      status.textContent = message || '';
      status.classList.remove('is-busy', 'is-open', 'is-error');
      if (kind) status.classList.add(kind);
      status.classList.toggle('hidden', !message);
    }

    function showFlash(message) {
      if (!flash) return;
      flash.textContent = message || '';
    }

    function updateRail() {
      document.querySelectorAll('#software-deployment-progress-rail li').forEach((item, itemIndex) => {
        item.classList.toggle('active', itemIndex === index);
        item.classList.toggle('done', itemIndex < index);
      });
    }

    function render() {
      const step = STEPS[index];
      if (!step) return;
      const result = commandFor(step);
      kicker.textContent = `Step ${index + 1} of ${STEPS.length} — ${step.phase}`;
      phase.textContent = step.phase;
      title.textContent = step.title;
      body.textContent = step.body;
      checks.innerHTML = step.checks.map(item => `<li>${item}</li>`).join('');
      action.textContent = step.action;
      command.value = result.command || '# No command on this step. Complete the review or input gate on the left.';
      commandPanel.classList.toggle('hidden', step.mode === 'decision');
      copy.classList.toggle('hidden', !step.commandKind);
      inputs.classList.toggle('hidden', !['pilot-input', 'command-review', 'approval', 'command'].includes(step.mode) || index < 3);
      fixtureGate.classList.toggle('hidden', step.mode !== 'fixture-review');
      planGate.classList.toggle('hidden', step.mode !== 'command-review');
      approvalGate.classList.toggle('hidden', step.mode !== 'approval');
      decision.classList.toggle('hidden', step.mode !== 'decision');
      errors.textContent = result.valid ? '' : result.errors.join('\n');
      proofLabel.textContent = index < 3 ? 'Fixture proof' : (index < 7 ? 'One-pilot preparation' : 'Observed proof required');
      commandNote.textContent = step.commandKind === 'pilot'
        ? 'Confirmation remains enabled. The generated command intentionally does not include a confirmation bypass.'
        : step.commandKind === 'what-if'
          ? 'WhatIf writes local planning evidence only; it does not contact the share or target.'
          : step.commandKind === 'dry-run'
            ? 'Expected result: PASS, exact 3 / 0 / 0 delta, and no live target proof.'
            : 'Complete the left-side gate before continuing.';
      prev.disabled = index === 0;
      next.textContent = index === STEPS.length - 1 ? 'Finish' : 'Next →';
      showFlash('');
      updateRail();
    }

    function openTutorial(startIndex) {
      index = Number.isInteger(startIndex) ? Math.max(0, Math.min(STEPS.length - 1, startIndex)) : 0;
      copiedStep = -1;
      tutorial.classList.remove('hidden');
      document.getElementById('hero-start-deployment').textContent = 'Restart Software Deployment';
      setStatus('Software deployment tutorial open below.', 'is-open');
      render();
      window.setTimeout(() => tutorial.scrollIntoView({ behavior: 'smooth', block: 'start' }), 30);
    }

    function closeTutorial() {
      tutorial.classList.add('hidden');
      document.getElementById('hero-start-deployment').textContent = 'Start Software Deployment';
      setStatus('', '');
      hero.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    function currentGatePasses() {
      const step = STEPS[index];
      if (step.commandKind) {
        const result = commandFor(step);
        errors.textContent = result.valid ? '' : result.errors.join('\n');
        if (!result.valid) return false;
        if (copiedStep !== index) {
          showFlash('Copy and run this command before continuing.');
          return false;
        }
      }
      if (step.mode === 'fixture-review' && !document.getElementById('software-deployment-fixture-reviewed')?.checked) {
        showFlash('Review the fixture evidence and check the acknowledgement before continuing.');
        return false;
      }
      if (step.mode === 'pilot-input') {
        const result = validatePilot(pilotInput());
        errors.textContent = result.valid ? '' : result.errors.join('\n');
        if (!result.valid) return false;
      }
      if (step.mode === 'command-review' && !document.getElementById('software-deployment-plan-reviewed')?.checked) {
        showFlash('Run and review WhatIf, then check the acknowledgement.');
        return false;
      }
      if (step.mode === 'approval') {
        const boxes = Array.from(document.querySelectorAll('[data-deploy-approval]'));
        if (!boxes.length || boxes.some(box => !box.checked)) {
          showFlash('Every live-pilot approval must be checked. Stop if any statement is uncertain.');
          return false;
        }
      }
      return true;
    }

    function copyCommand() {
      const result = commandFor(STEPS[index]);
      if (!result.valid || !result.command) {
        errors.textContent = (result.errors || ['Complete the required fields first.']).join('\n');
        return;
      }
      const fallback = () => {
        command.focus();
        command.select();
        return document.execCommand && document.execCommand('copy');
      };
      const promise = navigator.clipboard?.writeText
        ? navigator.clipboard.writeText(result.command)
        : Promise.resolve(fallback());
      promise.then(() => {
        copiedStep = index;
        showFlash('Command copied. Run it outside the dashboard, then return for the next gate.');
      }).catch(() => showFlash('Clipboard access is blocked. Select and copy the command manually.'));
    }

    document.getElementById('hero-start-deployment')?.addEventListener('click', () => openTutorial(0));
    document.getElementById('hero-deployment-dry-run')?.addEventListener('click', () => openTutorial(1));
    document.getElementById('hero-open-deployment')?.addEventListener('click', () => openTutorial(0));
    document.getElementById('software-deployment-exit')?.addEventListener('click', closeTutorial);
    prev?.addEventListener('click', () => { if (index > 0) { index -= 1; render(); } });
    next?.addEventListener('click', () => {
      if (!currentGatePasses()) return;
      if (index < STEPS.length - 1) {
        index += 1;
        render();
      } else {
        closeTutorial();
        setStatus('Tutorial complete. Keep the evidence and expand only after explicit approval.', 'is-open');
      }
    });
    copy?.addEventListener('click', copyCommand);
    ['software-deployment-target', 'software-deployment-package', 'software-deployment-path', 'software-deployment-args', 'software-deployment-mode']
      .forEach(id => document.getElementById(id)?.addEventListener('input', render));

    global.startSoftwareDeploymentTutorial = function (options) {
      openTutorial(options?.startAtDryRun ? 1 : 0);
      return true;
    };

    const params = new URLSearchParams(global.location?.search || '');
    const requested = String(params.get('tutorial') || params.get('start') || '').toLowerCase();
    const hash = String(global.location?.hash || '').toLowerCase();
    if (['software-deployment', 'deployment', 'software-install'].includes(requested) || hash === '#software-deployment-tutorial') {
      global.setTimeout(() => openTutorial(requested === 'software-install' ? 1 : 0), 60);
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})(typeof window !== 'undefined' ? window : globalThis);
