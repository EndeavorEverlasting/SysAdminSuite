// software-tracker-state.js — shared install workflow state for tutorial + panel rail

let _installPlan = null;
let _liveApproved = false;
let _selection = { list: '', software: '' };

export function getSoftwareInstallPlan() {
  return _installPlan;
}

export function setSoftwareInstallPlan(plan) {
  _installPlan = plan;
  _liveApproved = false;
  window.dispatchEvent(new CustomEvent('sas-software-install-state'));
}

export function clearSoftwareInstallPlan() {
  _installPlan = null;
  _liveApproved = false;
  window.dispatchEvent(new CustomEvent('sas-software-install-state'));
}

export function isLiveRunApproved() {
  return _liveApproved;
}

export function setLiveRunApproved(value) {
  _liveApproved = Boolean(value);
  window.dispatchEvent(new CustomEvent('sas-software-install-state'));
}

export function getSoftwareSelection() {
  return { ..._selection };
}

export function setSoftwareSelection({ list, software } = {}) {
  _selection = {
    list: list ?? _selection.list,
    software: software ?? _selection.software,
  };
  window.dispatchEvent(new CustomEvent('sas-software-install-state'));
}

export function summarizeInstallBlockers(plan) {
  const items = plan?.items || [];
  const counts = {};
  for (const item of items) {
    counts[item.status] = (counts[item.status] || 0) + 1;
  }
  return {
    total: items.length,
    counts,
    blocked: items.filter(i => i.status === 'Blocked'),
    manual: items.filter(i => i.status === 'ManualReview'),
    planned: items.filter(i => i.status === 'Planned' || i.status === 'DryRun'),
  };
}

export function canRunLiveInstall() {
  if (!_installPlan) return false;
  if (!_liveApproved) return false;
  return (_installPlan.items || []).some(item => item.status === 'Planned' || item.status === 'DryRun');
}

export function liveRunDisabledReason() {
  if (!_installPlan) return 'Run Preview Install Plan first, then load install-summary.json.';
  if (!_liveApproved) return 'Check Approve Live Run after reviewing blockers.';
  if (!canRunLiveInstall()) return 'No planned install rows are ready for guarded execute.';
  return '';
}
