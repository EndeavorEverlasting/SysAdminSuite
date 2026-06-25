// launch-cybernet-tutorial.js
// Opens the existing dashboard tutorial when launched with ?tutorial=cybernet.
(function () {
  'use strict';

  function shouldStart() {
    const params = new URLSearchParams(window.location.search || '');
    const hash = (window.location.hash || '').toLowerCase();
    return (params.get('tutorial') || '').toLowerCase() === 'cybernet' ||
      (params.get('start') || '').toLowerCase() === 'cybernet' ||
      hash === '#cybernet-tutorial' ||
      hash === '#start-cybernet-survey';
  }

  function startTutorial(attemptsRemaining) {
    if (!shouldStart()) return;

    const startButton = document.getElementById('hero-start-survey');
    const tutorial = document.getElementById('cybernet-tutorial');

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

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { startTutorial(25); });
  } else {
    startTutorial(25);
  }
})();
