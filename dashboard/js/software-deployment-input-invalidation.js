// software-deployment-input-invalidation.js
// Revokes copied/reviewed/approved state whenever any pilot-defining input changes.
(function (global) {
  'use strict';

  const INPUT_IDS = [
    'software-deployment-target',
    'software-deployment-package',
    'software-deployment-path',
    'software-deployment-args',
    'software-deployment-mode'
  ];

  function invalidateReviewState(state) {
    const currentRevision = Number.isInteger(state?.inputRevision) ? state.inputRevision : 0;
    const approvals = Array.isArray(state?.approvals) ? state.approvals : [];
    return {
      inputRevision: currentRevision + 1,
      copiedRevision: -1,
      planReviewed: false,
      approvals: approvals.map(() => false)
    };
  }

  global.__sasSoftwareDeploymentInputInvalidationApi = {
    INPUT_IDS: INPUT_IDS.slice(),
    invalidateReviewState
  };

  if (typeof document === 'undefined') return;

  function activeStepIndex() {
    const active = document.querySelector('#software-deployment-progress-rail li.active');
    const value = Number(active?.dataset?.step);
    return Number.isInteger(value) ? value : -1;
  }

  function pilotInput() {
    return {
      target: document.getElementById('software-deployment-target')?.value,
      packageName: document.getElementById('software-deployment-package')?.value,
      installerPath: document.getElementById('software-deployment-path')?.value,
      installerArguments: document.getElementById('software-deployment-args')?.value,
      installMode: document.getElementById('software-deployment-mode')?.value
    };
  }

  function showFlash(message) {
    const flash = document.getElementById('software-deployment-flash');
    if (flash) flash.textContent = message || '';
  }

  function planReviewed() {
    return Boolean(document.getElementById('software-deployment-plan-reviewed')?.checked);
  }

  function approvalBoxes() {
    return Array.from(document.querySelectorAll('[data-deploy-approval]'));
  }

  function readRevision(tutorial, name, fallback) {
    const value = Number(tutorial.dataset[name]);
    return Number.isInteger(value) ? value : fallback;
  }

  function resetReviewedState(tutorial) {
    const approvals = approvalBoxes();
    const state = invalidateReviewState({
      inputRevision: readRevision(tutorial, 'sasInputRevision', 0),
      approvals: approvals.map(box => Boolean(box.checked))
    });

    tutorial.dataset.sasInputRevision = String(state.inputRevision);
    tutorial.dataset.sasCopiedRevision = String(state.copiedRevision);

    const plan = document.getElementById('software-deployment-plan-reviewed');
    if (plan) plan.checked = state.planReviewed;
    approvals.forEach((box, index) => { box.checked = state.approvals[index]; });
  }

  function markCurrentCommandCopied(tutorial) {
    const step = activeStepIndex();
    if (step < 4) return;

    const validator = global.__sasSoftwareDeploymentTutorialApi?.validatePilot;
    if (typeof validator !== 'function' || !validator(pilotInput()).valid) return;

    tutorial.dataset.sasCopiedRevision = tutorial.dataset.sasInputRevision || '0';
  }

  function requestMatchesCopiedRevision(tutorial) {
    return readRevision(tutorial, 'sasInputRevision', 0) ===
      readRevision(tutorial, 'sasCopiedRevision', -1);
  }

  function blockStaleProgress(event, tutorial) {
    const step = activeStepIndex();
    if (step < 4) return;

    if (!requestMatchesCopiedRevision(tutorial)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      showFlash('Pilot inputs changed. Return to the WhatIf step, copy and review the updated plan, then approve the live pilot again.');
      return;
    }

    if (step >= 5) {
      const approvals = approvalBoxes();
      if (!planReviewed() || !approvals.length || approvals.some(box => !box.checked)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        showFlash('The reviewed WhatIf acknowledgement and every live-pilot approval must match the current inputs.');
      }
    }
  }

  function bind() {
    const tutorial = document.getElementById('software-deployment-tutorial');
    const copy = document.getElementById('software-deployment-copy');
    const next = document.getElementById('software-deployment-next');
    if (!tutorial || !copy || !next) return false;

    if (tutorial.dataset.sasInputInvalidationBound === 'true') return true;
    tutorial.dataset.sasInputInvalidationBound = 'true';
    tutorial.dataset.sasInputRevision = tutorial.dataset.sasInputRevision || '0';
    tutorial.dataset.sasCopiedRevision = tutorial.dataset.sasCopiedRevision || '-1';

    INPUT_IDS.forEach(id => {
      const field = document.getElementById(id);
      if (!field) return;
      const invalidate = function () {
        resetReviewedState(tutorial);
        showFlash('Pilot inputs changed. The copied command, WhatIf acknowledgement, and live approvals were revoked.');
      };
      field.addEventListener('input', invalidate);
      field.addEventListener('change', invalidate);
    });

    copy.addEventListener('click', function () {
      global.setTimeout(function () { markCurrentCommandCopied(tutorial); }, 0);
    });
    next.addEventListener('click', function (event) {
      blockStaleProgress(event, tutorial);
    }, true);
    return true;
  }

  function initialize(attemptsRemaining) {
    if (bind()) return;
    if (attemptsRemaining > 0) {
      global.setTimeout(function () { initialize(attemptsRemaining - 1); }, 50);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { initialize(40); });
  } else {
    initialize(40);
  }
})(typeof window !== 'undefined' ? window : globalThis);
