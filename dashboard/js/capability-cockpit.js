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


  // Operator journey annotations. IDs must resolve against the live canonical
  // registry; these descriptions are NOT alternate command/proof authorities.
  const adbStages = [
    { title: 'Prepare the Admin Box', description: 'Qualify approved host tooling before any device interaction.', ids: ['android-toolchain-adminbox', 'hh-cc-reader-adb-host-prepare'] },
    { title: 'Inspect the transport', description: 'Separate provider readiness, USB enumeration and reader authorization.', ids: ['android-provider', 'hh-cc-reader-adb-probe'] },
    { title: 'Capture read-only inventory', description: 'Collect Android properties only after exact-device authorization.', ids: ['hh-cc-reader-adb-inventory-capture'] },
    { title: 'Resolve the version domain', description: 'Classify labeled version evidence; do not substitute campaign targets.', ids: ['hh-cc-reader-version-domain-classify'] },
    { title: 'Evaluate baseline and recovery', description: 'Keep baseline, restoration eligibility and mutation authority separate.', ids: ['hh-cc-reader-firmware-roundtrip-evaluate'] },
    { title: 'Certify network ADB and revert', description: 'Exact target only, with mandatory USB restoration and listener cleanup.', ids: ['hh-cc-reader-adb-tcpip-certify'] },
    { title: 'Certify view-only display', description: 'Observe the reader display without input injection or remote control.', ids: ['hh-cc-reader-adb-remote-view-certify'] },
    { title: 'Evaluate the capability program', description: 'Orchestrate proven prerequisites while preserving attended and blocked gates.', ids: ['hh-cc-reader-adb-control-plane-evaluate', 'hh-cc-reader-capability-program-evaluate'] }
  ];

  function showAdbJourney() {
    const list = byId('adb-journey');
    if (!list) return;
    list.replaceChildren();
    if (!state.loaded) {
      setText('adb-status', 'ADB journey unavailable until the local host registry is verified.');
      return;
    }
    const indexed = new Map(state.capabilities.map(c => [c.id, c]));
    let registered = 0;
    let total = 0;
    const fragment = document.createDocumentFragment();
    for (const [index, stage] of adbStages.entries()) {
      const matches = stage.ids.map(id => indexed.get(id)).filter(Boolean);
      registered += matches.length;
      total += stage.ids.length;
      const item = create('li', 'adb-stage');
      const heading = create('div', 'adb-stage-heading');
      heading.append(create('span', 'adb-number', String(index + 1).padStart(2, '0')));
      const copy = create('div');
      copy.append(create('h3', '', stage.title), create('p', 'description', stage.description));
      heading.append(copy);
      item.append(heading);
      const statuses = create('dl', 'adb-proof');
      const row = (key, value) => {
        const pair = create('div', 'adb-proof-pair');
        pair.append(create('dt', '', key), create('dd', '', value));
        statuses.append(pair);
      };
      row('Registered', matches.length + ' / ' + stage.ids.length + ' mapped commands');
      const present = matches.filter(c => c.entrypoint_status === 'FILE_PRESENT').length;
      const unprobed = matches.filter(c => c.entrypoint_status === 'RUNTIME_DISPATCH_NOT_PROBED').length;
      row('Executable', 'NOT PROBED · ' + present + ' entrypoint file(s) present'
        + (unprobed ? ' · ' + unprobed + ' runtime dispatcher(s) not probed' : '')
        + ' · execution untested');
      const receipts = matches.filter(c => c.local_receipt_observed).length;
      const otherHomes = matches.filter(c => c.receipt_coverage !== 'SURVEY_OUTPUT_PATTERN').length;
      row('Evidence', receipts + ' local receipt(s)'
        + (otherHomes ? ' · ' + otherHomes + ' private home(s) not queried' : '')
        + ' · not live proof');
      row('Field outcome', 'Not verified by this read-only cockpit');
      item.append(statuses);
      const commands = create('ul', 'adb-command-list');
      for (const id of stage.ids) {
        const cap = indexed.get(id);
        const li = create('li', 'adb-command');
        li.append(create('span', '', cap ? id : id + ' · NOT REGISTERED'));
        if (cap) {
          const inspect = create('button', 'adb-inspect', 'Inspect');
          inspect.type = 'button';
          inspect.setAttribute('aria-label', 'Inspect registered command ' + id);
          inspect.addEventListener('click', () => {
            byId('search').value = id;
            byId('domain').value = '';
            byId('evidence').value = '';
            showCapabilities();
            byId('capabilities').scrollIntoView({ behavior: 'auto', block: 'start' });
          });
          li.append(inspect);
        }
        commands.append(li);
      }
      item.append(commands);
      fragment.append(item);
    }
    list.append(fragment);
    setText('adb-status', registered + ' of ' + total
      + ' mapped command references registered locally. Journey stages describe capabilities, not a mandatory run order. '
      + 'No executable, target operation or outcome is certified by this projection.');
  }

  function showCapabilities() {
    const list = byId('capabilities');
    const search = byId('search').value.trim().toLowerCase();
    const domain = byId('domain').value;
    const evidence = byId('evidence').value;
    const matching = state.capabilities.filter(c => {
      if (domain && c.domain !== domain) return false;
      if (evidence === 'receipt' && !c.local_receipt_observed) return false;
      if (evidence === 'none' && (c.local_receipt_observed || c.receipt_coverage !== 'SURVEY_OUTPUT_PATTERN')) return false;
      if (evidence === 'uncovered' && c.receipt_coverage === 'SURVEY_OUTPUT_PATTERN') return false;
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
      const evidenceTag = capability.receipt_coverage !== 'SURVEY_OUTPUT_PATTERN'
        ? 'Other private receipt home · not queried'
        : capability.local_receipt_observed
          ? 'Local receipt exists · outcome not certified'
          : 'No matching survey receipt observed';
      card.append(create('div', 'tag' + (capability.local_receipt_observed ? ' warn' : ''), evidenceTag));
      const detail = create('div', 'detail');
      const dl = create('dl');
      const rows = [
        ['Command', capability.command || 'Unknown'],
        ['Source present', capability.source_present ? 'Yes' : 'No / unverified'],
        ['Executable', capability.executable_availability || 'NOT_PROBED'],
        ['Field outcome', capability.real_world_outcome || 'NOT_VERIFIED'],
        ['Mutation class', capability.mutation_class || 'Unspecified'],
        ['Receipt coverage', capability.receipt_coverage === 'SURVEY_OUTPUT_PATTERN' ? 'Survey output pattern' : 'Other private home / not indexed'],
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
      setText('count-no-evidence', data.unobserved_supported_receipt_count);
      setText('count-uncovered', data.receipt_home_not_queried_count);
      showCapabilities();
      showAdbJourney();
    } catch (err) {
      // Do not use stale data as current host truth after an endpoint failure.
      state.capabilities = [];
      state.loaded = false;
      state.generatedAt = null;
      ['count-registered', 'count-entrypoints', 'count-receipts', 'count-no-evidence', 'count-uncovered']
        .forEach(id => setText(id, '—'));
      setText('status', 'Unable to verify local capabilities: ' + (err.message || 'unknown error')
        + '. Start the Windows SysAdminSuite DashboardHost on this Admin Box. '
        + 'The generic Python/static fallback does not certify local evidence.');
      showCapabilities();
      showAdbJourney();
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
