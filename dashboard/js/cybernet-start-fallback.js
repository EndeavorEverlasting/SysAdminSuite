// Defensive fallback for the Cybernet survey start button.
(function () {
  'use strict';

  function openSurvey() {
    var tutorial = document.getElementById('cybernet-tutorial');
    var actions = document.getElementById('cybernet-hero-actions');
    var overlay = document.getElementById('drop-overlay');
    if (overlay) overlay.classList.remove('active');
    if (tutorial) {
      tutorial.style.display = '';
      tutorial.classList.remove('hidden');
      tutorial.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    if (actions) actions.classList.add('hidden');
  }

  function init() {
    var start = document.getElementById('hero-start-survey');
    if (!start) return;
    start.addEventListener('click', function (event) {
      event.preventDefault();
      openSurvey();
    }, true);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
}());
