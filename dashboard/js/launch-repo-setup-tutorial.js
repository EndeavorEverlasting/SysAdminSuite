// launch-repo-setup-tutorial.js
// Opens the repo setup tutorial when launched with ?tutorial=setup and loads
// the browser-first software-deployment tutorial used by the main dashboard.
(function () {
  'use strict';

  function showLoadError(message) {
    const status = document.getElementById('repo-setup-hero-status');
    if (status) {
      status.textContent = message;
      status.classList.remove('hidden');
      status.classList.add('is-error');
    }
  }

  function loadSoftwareDeploymentInputInvalidation() {
    if (document.getElementById('sas-software-deployment-input-invalidation-script')) return;
    const guard = document.createElement('script');
    guard.id = 'sas-software-deployment-input-invalidation-script';
    guard.src = 'js/software-deployment-input-invalidation.js';
    guard.async = false;
    guard.onerror = function () {
      showLoadError('Software Deployment approval guard could not load. Live pilot progression is unavailable; reload the dashboard.');
    };
    document.head.appendChild(guard);
  }

  function loadSoftwareDeploymentTutorial() {
    if (document.getElementById('sas-software-deployment-script')) {
      loadSoftwareDeploymentInputInvalidation();
      return;
    }
    const script = document.createElement('script');
    script.id = 'sas-software-deployment-script';
    script.src = 'js/software-deployment-tutorial.js';
    script.async = false;
    script.onload = loadSoftwareDeploymentInputInvalidation;
    script.onerror = function () {
      showLoadError('Software Deployment tutorial could not load. Reload the dashboard.');
    };
    document.head.appendChild(script);
  }

  function shouldStart() {
    const params = new URLSearchParams(window.location.search || '');
    const tutorial = (params.get('tutorial') || '').toLowerCase();
    const start = (params.get('start') || '').toLowerCase();
    const hash = (window.location.hash || '').toLowerCase();
    return tutorial === 'setup' ||
      tutorial === 'repo-setup' ||
      start === 'setup' ||
      start === 'repo-setup' ||
      hash === '#repo-setup-tutorial' ||
      hash === '#start-repo-setup';
  }

  function startTutorial(attemptsRemaining) {
    if (!shouldStart()) return;
    if (window.__sasToolboxStatusPending && attemptsRemaining > 0) {
      window.setTimeout(function () { startTutorial(attemptsRemaining - 1); }, 100);
      return;
    }
    if (window.__sasToolboxActionNeeded) return;

    const startButton = document.getElementById('hero-start-setup');
    const tutorial = document.getElementById('repo-setup-tutorial');

    if (typeof window.startRepoSetupTutorial === 'function' && tutorial) {
      window.startRepoSetupTutorial({ source: 'query' });
      return;
    }

    if (startButton && tutorial) {
      startButton.click();
      window.setTimeout(function () {
        tutorial.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }, 50);
      return;
    }

    if (attemptsRemaining > 0) {
      window.setTimeout(function () { startTutorial(attemptsRemaining - 1); }, 100);
    }
  }

  function initialize() {
    loadSoftwareDeploymentTutorial();
    startTutorial(25);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
  } else {
    initialize();
  }
})();
