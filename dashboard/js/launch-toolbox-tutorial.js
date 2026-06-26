// launch-toolbox-tutorial.js
// Fetches toolbox-status.json and auto-opens the toolbox wizard when action is needed.
(function () {
  'use strict';

  var pollTimer = null;
  window.__sasToolboxStatusPending = true;
  window.__sasToolboxActionNeeded = false;

  function shouldStartSetup() {
    var params = new URLSearchParams(window.location.search || '');
    var tutorial = (params.get('tutorial') || '').toLowerCase();
    var start = (params.get('start') || '').toLowerCase();
    var hash = (window.location.hash || '').toLowerCase();
    return tutorial === 'setup' || tutorial === 'repo-setup' ||
      start === 'setup' || start === 'repo-setup' ||
      hash === '#repo-setup-tutorial' || hash === '#start-repo-setup';
  }

  function shouldStartToolbox() {
    var params = new URLSearchParams(window.location.search || '');
    var tutorial = (params.get('tutorial') || '').toLowerCase();
    var start = (params.get('start') || '').toLowerCase();
    var hash = (window.location.hash || '').toLowerCase();
    return tutorial === 'toolbox' || start === 'toolbox' ||
      hash === '#toolbox-tutorial' || hash === '#start-toolbox';
  }

  function applyStatus(status) {
    if (typeof window.__sasRenderToolboxChecklist === 'function') {
      window.__sasRenderToolboxChecklist(status);
    }
    if (typeof window.__sasUpdateToolboxBanner === 'function') {
      window.__sasUpdateToolboxBanner(status);
    }
    if (typeof window.__sasApplyToolboxStatus === 'function') {
      window.__sasApplyToolboxStatus(status);
    }
  }

  function fetchStatus() {
    return fetch('toolbox-status.json?ts=' + Date.now())
      .then(function (res) {
        if (!res.ok) throw new Error('status unavailable');
        return res.json();
      });
  }

  function startRepoSetupWhenReady(attemptsRemaining) {
    if (!shouldStartSetup()) return;
    if (typeof window.startRepoSetupTutorial === 'function') {
      window.startRepoSetupTutorial({ source: 'query' });
      return;
    }
    if (attemptsRemaining > 0) {
      window.setTimeout(function () { startRepoSetupWhenReady(attemptsRemaining - 1); }, 100);
    }
  }

  function startToolboxWhenReady(status, attemptsRemaining) {
    if (typeof window.startToolboxTutorial === 'function') {
      applyStatus(status);
      window.startToolboxTutorial({ source: 'status', status: status });
      return;
    }
    if (attemptsRemaining > 0) {
      window.setTimeout(function () { startToolboxWhenReady(status, attemptsRemaining - 1); }, 100);
    }
  }

  function handleStatus(status) {
    applyStatus(status);
    window.__sasLastToolboxStatus = status;
    window.__sasFetchedToolboxStatus = status;
    window.__sasToolboxStatusPending = false;
    window.__sasToolboxActionNeeded = !!status.actionNeeded;

    if (shouldStartToolbox()) {
      startToolboxWhenReady(status, 25);
      return;
    }

    if (status.actionNeeded) {
      startToolboxWhenReady(status, 25);
      return;
    }

    if (shouldStartSetup()) {
      startRepoSetupWhenReady(25);
    }
  }

  function loadAndRoute() {
    fetchStatus()
      .then(handleStatus)
      .catch(function () {
        window.__sasToolboxStatusPending = false;
        window.__sasToolboxActionNeeded = false;
        if (shouldStartToolbox()) {
          startToolboxWhenReady({ tools: [], actionNeeded: false }, 25);
        } else if (shouldStartSetup()) {
          startRepoSetupWhenReady(25);
        }
      });
  }

  window.__sasReloadToolboxStatus = function () {
    fetchStatus()
      .then(function (status) {
        applyStatus(status);
        window.__sasLastToolboxStatus = status;
        window.__sasFetchedToolboxStatus = status;
        toastIfNeeded(status);
      })
      .catch(function () {
        window.location.reload();
      });
  };

  function toastIfNeeded(status) {
    if (status.actionNeeded) return;
    if (window.toast) window.toast('Toolbox re-check complete — all clear.', 'success');
  }

  function bindBanner() {
    var banner = document.getElementById('toolbox-status-banner');
    banner?.addEventListener('click', function () {
      if (window.__sasLastToolboxStatus && typeof window.startToolboxTutorial === 'function') {
        window.startToolboxTutorial({ source: 'banner', status: window.__sasLastToolboxStatus });
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      bindBanner();
      loadAndRoute();
    });
  } else {
    bindBanner();
    loadAndRoute();
  }
})();
