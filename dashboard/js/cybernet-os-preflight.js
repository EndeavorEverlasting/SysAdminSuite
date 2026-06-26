// cybernet-os-preflight.js - PowerShell-first field command patcher.
// The durable field path is repo-local PowerShell. Bash transport remains an advanced/developer lane,
// but this Cybernet tutorial must not send Northwell field techs there.
(function () {
  'use strict';

  const PREFLIGHT_DOC = 'docs/FIELD_NETWORK_PREFLIGHT.md';

  const COMMANDS = {
    loadTargets: String.raw`Run in Windows PowerShell

Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1`,

    networkPreflight: String.raw`Run in Windows PowerShell

Set-Location <SysAdminSuite repo root>
.\survey\sas-network-preflight.ps1 -TargetFile .\targets\local\approved_targets.csv -Ports 135,445,3389,9100`,

    identityEvidence: String.raw`Run in Windows PowerShell

# Identity evidence is separate from network preflight.
# Load an approved workstation_identity.csv only after an approved identity collection path produces it.
# Network preflight output belongs under .\survey\output\network_preflight\ and can be loaded now.`,

    optionalReachability: String.raw`Run in Windows PowerShell

# Optional reachability beyond sas-network-preflight.ps1 is advanced scope.
# Use the runbook first, then only run additional reachability tooling against an approved target file.
Get-Content .\docs\FIELD_NETWORK_PREFLIGHT.md | Select-Object -First 40`,

    finish: String.raw`Run in Windows PowerShell

# Load Evidence in the dashboard accepts the generated network preflight CSV:
# .\survey\output\network_preflight\network_preflight_<timestamp>.csv
# Also load approved workstation_identity.csv or reachability JSON only when those files already exist.`
  };

  const PATCHES = {
    'Load your targets': {
      body: 'Select an approved target source. Place exported CSVs or target text files under targets/local/ or logs/targets/. Run the preflight script with no target file to list candidates and stop safely.',
      command: COMMANDS.loadTargets,
      checks: [
        'Use approved target files from targets/local/ or logs/targets/.',
        'survey/input is normalized staging only after an approved normalization step.',
        'Do not type demo hostnames manually for live work.',
        'Do not use CMD for this block. Do not paste non-PowerShell syntax.'
      ],
      note: 'This lists candidate target files and stops. Select the approved file before probing.',
      explain: 'Runs the PowerShell entrypoint in safe selection mode so the operator can choose a codified target file.',
      explainParts: [
        ['Set-Location', 'Move to the SysAdminSuite repo root before running the script.'],
        ['sas-network-preflight.ps1', 'Lists approved candidate files when no target file is supplied.'],
        ['targets/local and logs/targets', 'Preferred ignored live intake roots.']
      ]
    },
    'Check network posture': {
      body: 'Run the repo PowerShell preflight against the selected approved target file. It performs read-only DNS, ping, and selected TCP port checks from the admin machine.',
      command: COMMANDS.networkPreflight,
      checks: [
        'Run in Windows PowerShell.',
        'Use targets/local/ or logs/targets/ for live intake.',
        'Use survey/input/ only for normalized staging from a prior approved step.',
        'Output is generated under survey/output/network_preflight/.',
        'The script prints stage progress, [n/total], percent complete, and the final CSV path.'
      ],
      note: 'After it finishes, load the generated network_preflight CSV from survey/output/network_preflight/.',
      explain: 'Runs read-only network posture checks against a bounded target file and writes local ignored CSV evidence.',
      explainParts: [
        ['-TargetFile', 'Explicit approved .txt or .csv target file.'],
        ['-Ports', 'Selected TCP ports to check.'],
        ['survey/output/network_preflight', 'Generated local output folder.']
      ]
    },
    'Collect identity evidence': {
      body: 'Identity evidence is not created by the network preflight script. Load an approved workstation identity CSV only when a separate approved identity collection path produced it.',
      command: COMMANDS.identityEvidence,
      checks: [
        'Do not treat ping or open ports as serial identity proof.',
        'Load workstation_identity.csv only when it came from an approved identity path.',
        'Keep network_preflight as reachability and posture evidence only.'
      ],
      note: 'Skip this step unless approved identity evidence already exists.',
      explain: 'Separates reachability posture from identity collection so serial proof does not get invented from network checks.',
      explainParts: [
        ['network_preflight', 'Reachability and posture evidence.'],
        ['workstation_identity', 'Separate identity evidence, when approved and available.'],
        ['approved identity path', 'WMI/CIM, SCCM, MDM, tracker, AD/CMDB, or operator-approved evidence.']
      ]
    },
    'Optional reachability check': {
      body: 'The PowerShell preflight already checks selected ports against the approved target file. Additional reachability tooling is advanced scope and must stay bounded to the same approved population.',
      command: COMMANDS.optionalReachability,
      checks: [
        'Do not broaden scope beyond the selected approved target file.',
        'Do not use broad subnet scans from this field tutorial.',
        'Generated reachability evidence belongs in logs/nmap/ or survey/output/.',
        'Read the field preflight runbook before adding optional reachability evidence.'
      ],
      note: 'Optional means optional. No extra probe is required when network_preflight is enough.',
      explain: 'Keeps optional reachability separate from the default PowerShell preflight path.',
      explainParts: [
        ['FIELD_NETWORK_PREFLIGHT.md', 'Runbook for the durable field path.'],
        ['approved target file', 'The only population that may be checked.'],
        ['logs/nmap or survey/output', 'Generated local evidence folders.']
      ]
    },
    'Finish and review results': {
      body: 'Load the generated evidence files back into the dashboard. The expected network preflight output is under survey/output/network_preflight/.',
      command: COMMANDS.finish,
      checks: [
        'Load network_preflight_<timestamp>.csv from survey/output/network_preflight/.',
        'Load identity or reachability evidence only when separately approved and generated.',
        'Do not load live source workbooks as proof of reachability.',
        'Do not commit generated outputs.'
      ],
      note: 'Use Load Evidence for the generated CSV. Source files stay local and ignored.',
      explain: 'Closes the loop by loading generated local evidence, not source target files, into the dashboard.',
      explainParts: [
        ['Load Evidence', 'Dashboard import area for generated CSV/JSON outputs.'],
        ['network_preflight CSV', 'The generated result of this PowerShell preflight.'],
        ['source target files', 'Inputs only, not evidence proof.']
      ]
    }
  };

  function escapeHtml(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function ensureFieldRuleCard(root) {
    if (!root || document.getElementById('cybernet-os-preflight')) return;
    const card = document.createElement('div');
    card.id = 'cybernet-os-preflight';
    card.className = 'cybernet-os-preflight';
    card.innerHTML = `
      <div class="cybernet-os-title">Field shell rule</div>
      <div class="cybernet-os-note" id="cybernet-os-note">
        Run field preflight in Windows PowerShell. Use approved target files from targets/local/ or logs/targets/. See ${escapeHtml(PREFLIGHT_DOC)}.
      </div>
    `;
    const stepCard = root.querySelector('.cybernet-step-card');
    root.insertBefore(card, stepCard || root.firstChild);

    const style = document.createElement('style');
    style.textContent = `
      .cybernet-os-preflight { margin: 12px 0; padding: 12px; border: 1px solid var(--border); border-radius: 10px; background: var(--bg2); display: grid; gap: 8px; }
      .cybernet-os-title { color: var(--accent); font-weight: 700; font-size: 13px; }
      .cybernet-os-note { color: var(--text-muted); font-size: 12px; line-height: 1.4; }
    `;
    document.head.appendChild(style);
  }

  function renderList(el, items) {
    if (!el || !Array.isArray(items)) return;
    el.innerHTML = items.map(item => `<li>${escapeHtml(item)}</li>`).join('');
  }

  function renderExplainParts(el, parts) {
    if (!el || !Array.isArray(parts)) return;
    el.innerHTML = parts
      .map(([part, meaning]) => `<li><code>${escapeHtml(part)}</code> - ${escapeHtml(meaning)}</li>`)
      .join('');
  }

  function patchCurrentStep() {
    const titleEl = document.getElementById('cybernet-step-title');
    if (!titleEl) return;

    const title = titleEl.textContent.trim();
    const patch = PATCHES[title];
    const cardEl = document.getElementById('cybernet-os-preflight');
    if (cardEl) cardEl.classList.toggle('hidden', !patch);
    if (!patch) return;

    const bodyEl = document.getElementById('cybernet-step-body');
    const commandEl = document.getElementById('cybernet-step-command');
    const noteEl = document.getElementById('cybernet-step-note');
    const checksEl = document.getElementById('cybernet-step-checks');
    const modeEl = document.getElementById('cybernet-command-mode');
    const explainEl = document.getElementById('cybernet-command-explain');
    const explainPartsEl = document.getElementById('cybernet-command-explain-parts');

    if (bodyEl) bodyEl.textContent = patch.body;
    if (commandEl) commandEl.value = patch.command;
    if (noteEl) noteEl.textContent = patch.note;
    if (modeEl) modeEl.textContent = 'Run in Windows PowerShell';
    if (explainEl) explainEl.textContent = patch.explain;
    renderList(checksEl, patch.checks);
    renderExplainParts(explainPartsEl, patch.explainParts);
  }

  function init() {
    const root = document.getElementById('cybernet-tutorial');
    if (!root) return;
    ensureFieldRuleCard(root);
    patchCurrentStep();
    root.addEventListener('click', () => setTimeout(patchCurrentStep, 0));
    const observer = new MutationObserver(() => patchCurrentStep());
    const titleEl = document.getElementById('cybernet-step-title');
    if (titleEl) observer.observe(titleEl, { childList: true, characterData: true, subtree: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
}());
