// tutorial-polish.js — loaded after bundle.js to correct PR 46 tutorial UI details.
(function () {
  'use strict';

  const $ = id => document.getElementById(id);

  function polishStep() {
    const title = ($('cybernet-step-title')?.textContent || '').toLowerCase();
    const command = $('cybernet-step-command');
    const note = $('cybernet-step-note');
    const body = $('cybernet-step-body');
    const checks = $('cybernet-step-checks');

    if (command && (title.includes('posture') || title.includes('identity'))) {
      command.value = command.value.replace(/--file\s+/g, '--targets-file ');
    }

    if (title.includes('normalize') && note) {
      note.textContent = 'This output is a handoff artifact for the rest of the suite. It is not currently a dashboard import artifact.';
    }

    if (title.includes('load, review')) {
      if (body) body.textContent = 'Drag only dashboard-recognized evidence CSVs into this dashboard, then review before classifying the result.';
      if (command) {
        command.value = command.value
          .split('\n')
          .filter(line => !line.includes('cybernet_targets.csv'))
          .join('\n') + '\n\n# Review the normalized manifest separately until dashboard parsing is added for it.';
      }
      if (checks) {
        checks.innerHTML = [
          'Classify environment blocks separately from product defects.',
          'Keep smoke-test evidence separate from feature validation.',
          'Do not treat the normalized manifest as a dashboard import until a parser is added for that schema.'
        ].map(text => `<li>${text}</li>`).join('');
      }
      if (note) note.textContent = 'The dashboard is a review surface. It does not perform browser-side probing or ingest the normalized manifest yet.';
    }

    const stepper = $('cybernet-stepper');
    stepper?.removeAttribute('role');
    stepper?.querySelectorAll('.cybernet-step-pill').forEach(button => {
      button.removeAttribute('role');
      button.removeAttribute('aria-selected');
      button.setAttribute('aria-pressed', button.classList.contains('active') ? 'true' : 'false');
      if (button.classList.contains('active')) button.setAttribute('aria-current', 'step');
      else button.removeAttribute('aria-current');
    });
  }

  function guardCopyButton() {
    const copy = $('cybernet-tutorial-copy');
    const command = $('cybernet-step-command');
    if (!copy || !command) return;

    copy.addEventListener('click', event => {
      event.preventDefault();
      event.stopImmediatePropagation();
      const note = $('cybernet-step-note');
      const original = note?.textContent || '';
      const text = command.value || '';
      const writer = navigator.clipboard && typeof navigator.clipboard.writeText === 'function'
        ? navigator.clipboard.writeText(text)
        : new Promise((resolve, reject) => {
            command.focus();
            command.select();
            try { document.execCommand('copy') ? resolve() : reject(new Error('copy unavailable')); }
            catch (err) { reject(err); }
          });
      writer.then(() => { if (note) note.textContent = 'Command copied.'; })
        .catch(() => { if (note) note.textContent = `${original} Select the command text and copy it manually if clipboard access is blocked.`; })
        .finally(() => window.setTimeout(() => { if (note) note.textContent = original; }, 2200));
    }, true);
  }

  function patchIntro() {
    const intro = $('cybernet-tutorial')?.querySelector('.cybernet-tutorial-head p');
    if (intro) intro.textContent = 'Click through a safe command workflow: prepare a list, prove path posture, collect identity evidence, then review CSV output locally.';
  }

  document.addEventListener('DOMContentLoaded', () => {
    patchIntro();
    guardCopyButton();
    ['cybernet-stepper', 'cybernet-prev', 'cybernet-next', 'cybernet-tutorial-start'].forEach(id => {
      $(id)?.addEventListener('click', () => window.setTimeout(polishStep, 0), true);
    });
    window.setTimeout(polishStep, 0);
  });
}());
