// repo-freshness.js — local clone freshness warning banner

export function initRepoFreshnessBanner() {
  if (typeof fetch !== 'function') return;

  fetch('repo-freshness.json', { cache: 'no-store' })
    .then(response => (response.ok ? response.json() : null))
    .then(state => {
      if (!shouldShowFreshnessWarning(state)) return;
      renderRepoFreshnessBanner(state);
    })
    .catch(() => {
      // Missing or unreadable local state should not block dashboard use.
    });
}

function shouldShowFreshnessWarning(state) {
  return Boolean(state && state.updateAvailable && Number(state.behind || 0) > 0);
}

function renderRepoFreshnessBanner(state) {
  const app = document.getElementById('app');
  const header = document.getElementById('header');
  if (!app || !header || document.getElementById('repo-freshness-banner')) return;

  const behind = Number(state.behind || 0);
  const banner = document.createElement('section');
  banner.id = 'repo-freshness-banner';
  banner.className = 'repo-freshness-banner';
  banner.setAttribute('role', 'alert');
  banner.setAttribute('aria-live', 'polite');

  const copy = document.createElement('div');
  copy.className = 'repo-freshness-copy';

  const title = document.createElement('strong');
  title.textContent = 'Local copy is behind the latest main';

  const body = document.createElement('span');
  body.textContent = `origin/main has ${behind} newer commit${behind === 1 ? '' : 's'} than this local main. Double-click START-HERE-SysAdminSuite-Dashboard.bat and approve the update before field work, or update with git pull --ff-only origin main after fixing any manual-review blocker.`;

  copy.append(title, body);
  banner.appendChild(copy);

  if (state.manualReviewReason) {
    const detail = document.createElement('div');
    detail.className = 'repo-freshness-detail';
    detail.textContent = `Manual review: ${state.manualReviewReason}`;
    banner.appendChild(detail);
  }

  app.insertBefore(banner, header.nextSibling);
}
