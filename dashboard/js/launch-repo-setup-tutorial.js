// launch-repo-setup-tutorial.js
// Opens the repo setup tutorial when launched with ?tutorial=setup and loads
// the browser-first software-deployment tutorial used by the main dashboard.
(function () {
  'use strict';

  function loadSoftwareDeploymentTutorial() {
    if (document.getElementById('sas-software-deployment-script')) return;
    const script = document.createElement('script');
    script.id = 'sas-software-deployment-script';
    script.src = 'js/software-deployment-tutorial.js';
    script.async = false;
    script.onerror = function () {
      const status = document.getElementById('repo-setup-hero-status');
      if (status) {
        status.textContent = 'Software Deployment tutorial could not load. Reload the dashboard.';
        status.classList.remove('hidden');
        status.classList.add('is-error');
      }
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
