/* SAS Capability Cockpit: read-only local projection; never invokes tool execution. */
(() => {
  'use strict';
  const state = { capabilities: [], loaded: false, generatedAt: null };
  const byId = id => document.getElementById(id);
  const create = (tag, className, value) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (value !== undefined && value !== null) node.textContent = String(value);
    return node;
  };
  const setText = (id, value) => { const node = byId(id); if (node) node.textContent = String(value); };
  const formatTime = value => {
    if (!value || Number.isNaN(Date.parse(value))) return 'Not available';
    return new Date(value).toLocaleString();
  };

  function showCapabilities() {
    const list = byId('capabilities');
    const search = byId('search').value.trim().toLowerCase();
    const domain = byId('domain').value;
    const evidence = byId('evidence').value;
    const matching = state.capabilities.filter(c => {
      if (domain && c.domain !== domain) return false;
      if (evidence === 'receipt' && !c.local_receipt_observed) return false;
      if (evidence === 'none' && c.local_receipt_observed) return false;
      if (evidence === 'missing' && c.entrypoint_status !== 'FILE_MISSING') return false;
      return [c.id, c.domain, c.command, c.purpose].join(' ').toLowerCase().includes(search);
    });
    list.replaceChildren();
    const fragment = document.createDocumentFragment();
    for (const capability of matching) {
      const card = create('article', 'cap');
      const head = create('div', 'caphead');
      const titleGroup = create('div');
      titleGroup.append(create('div', 'domain', capability.domain));
      titleGroup.append(create('h3', '', capability.id));
      head.append(titleGroup);
      const pathStatus = capability.entrypoint_status === 'FILE_PRESENT'
        ? 'Entrypoint present'
        : capability.entrypoint_status === 'FILE_MISSING'
          ? 'Entrypoint missing'
          : 'Runtime not probed';
      head.append(create('span', 'tag ' + (capability.entrypoint_present ? 'ok' : 'warn'), pathStatus));
      card.append(head);
      card.append(create('p', 'description', capability.purpose || 'No purpose documented.'));
      const evidenceTag = capability.local_receipt_observed
        ? 'Local receipt exists · outcome not certified'
        : 'No local receipt observed';
      card.append(create('div', 'tag' + (capability.local_receipt_observed ? ' warn' : ''), evidenceTag));
      const detail = create('div', 'detail');
      const dl = create('dl');
      const rows = [
        ['Command', capability.command || 'Unknown'],
        ['Source present', capability.source_present ? 'Yes' : 'No / unverified'],
        ['Mutation class', capability.mutation_class || 'Unspecified'],
        ['Last receipt', formatTime(capability.last_receipt_at)],
        ['Typed state', capability.last_allowlisted_state || 'Not safely classified'],
        ['Proof ceiling', capability.proof_ceiling || 'Not established']
      ];
      for (const [key, value] of rows) {
        dl.append(create('dt', '', key), create('dd', '', value));
      }
      detail.append(dl);
      card.append(detail);
      fragment.append(card);
    }
    if (!matching.length) fragment.append(create('p', 'empty', state.loaded
      ? 'No capabilities match these filters.' : 'No verified local capability inventory is available.'));
    list.append(fragment);
    if (state.loaded) setText('status',
      matching.length + ' of ' + state.capabilities.length + ' commands shown · Local scan ' + formatTime(state.generatedAt)
      + ' · Refresh rereads the registry and private receipt metadata.');
  }

  function setDomains() {
    const select = byId('domain');
    const previous = select.value;
    select.querySelectorAll('option:not(:first-child)').forEach(option => option.remove());
    const domains = [...new Set(state.capabilities.map(c => c.domain))].sort();
    for (const domain of domains) {
      const option = create('option', '', domain);
      option.value = domain;
      select.append(option);
    }
    if (domains.includes(previous)) select.value = previous;
  }

  async function refresh() {
    const button = byId('refresh');
    button.disabled = true;
    setText('status', 'Reading the local SAS command registry and receipt metadata…');
    try {
      const res = await fetch('api/capabilities', { cache: 'no-store', credentials: 'same-origin' });
      if (!res.ok) throw new Error('Local endpoint HTTP ' + res.status);
      const data = await res.json();
      if (data.schema !== 'sas-capability-cockpit/v1'
          || data.registry_loaded !== true || !Array.isArray(data.capabilities))
        throw new Error('Local registry unavailable or unqualified response');
      state.capabilities = data.capabilities;
      state.generatedAt = data.generated_at;
      state.loaded = true;
      setDomains();
      setText('count-registered', data.registered_count);
      setText('count-entrypoints', data.entrypoint_present_count);
      setText('count-receipts', data.local_receipt_count);
      setText('count-no-evidence', data.registered_count - data.local_receipt_count);
      showCapabilities();
    } catch (err) {
      // Do not use stale data as current host truth after an endpoint failure.
      state.capabilities = [];
      state.loaded = false;
      state.generatedAt = null;
      ['count-registered', 'count-entrypoints', 'count-receipts', 'count-no-evidence']
        .forEach(id => setText(id, '—'));
      setText('status', 'Unable to verify local capabilities: ' + (err.message || 'unknown error')
        + '. Start the Windows SysAdminSuite DashboardHost on this Admin Box. '
        + 'The generic Python/static fallback does not certify local evidence.');
      showCapabilities();
    } finally {
      button.disabled = false;
    }
  }
  document.addEventListener('DOMContentLoaded', () => {
    byId('search').addEventListener('input', showCapabilities);
    byId('domain').addEventListener('change', showCapabilities);
    byId('evidence').addEventListener('change', showCapabilities);
    byId('refresh').addEventListener('click', refresh);
    refresh();
  });
})();
