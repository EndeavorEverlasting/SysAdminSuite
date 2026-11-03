/* SAS Capability Cockpit: read-only local projection; never invokes tool execution. */
(() => {
  'use strict';
  const state = {
    capabilities: [],
    loaded: false,
    generatedAt: null,
    sourceClassCounts: {},
    activity: null,
    runFeedStatus: 'NOT_CONNECTED',
    unsubscribeRuns: null
  };
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
  const sourceClassMeta = {
    SURVEY_OUTPUT_PATTERN: { meaning: 'Allowlisted survey/output pattern; may be read as sanitized metadata.', gate: 'QUERIED', gateClass: 'queried' },
    KNOWN_LOCALAPPDATA_NOT_QUERIED: { meaning: 'Known local AppData home named by the registry; not traversed.', gate: 'NOT QUERIED', gateClass: '' },
    TEMP_NOT_QUERIED: { meaning: 'Temporary workspace artifact; classified only.', gate: 'NOT QUERIED', gateClass: '' },
    CONSOLE_OR_CI_NOT_QUERIED: { meaning: 'Console or CI log outcome; not a local private receipt home.', gate: 'NOT QUERIED', gateClass: '' },
    BUILD_OUTPUT_NOT_PROBED: { meaning: 'Build/publish output directory; presence not probed here.', gate: 'NOT PROBED', gateClass: '' },
    APPROVED_RUNTIME_HOME_NOT_QUERIED: { meaning: 'Approved runtime evidence placeholder; not expanded.', gate: 'NOT QUERIED', gateClass: '' },
    OTHER_SOURCE_NOT_QUERIED: { meaning: 'Recognized path shape outside the survey reader; left unread.', gate: 'NOT QUERIED', gateClass: '' },
    NO_INDEXED_RECEIPT: { meaning: 'No indexed success-artifact path for this command.', gate: 'UNMAPPED', gateClass: 'gap' }
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
      const missing = matches.filter(c => c.entrypoint_status === 'FILE_MISSING').length;
      row('Executable', 'NOT PROBED · ' + present + ' entrypoint file(s) present'
        + (missing ? ' · ' + missing + ' entrypoint file(s) missing' : '')
        + (unprobed ? ' · ' + unprobed + ' runtime dispatcher(s) not probed' : '')
        + ' · execution untested');
      const receipts = matches.filter(c => c.local_receipt_observed).length;
      const otherHomes = matches.filter(c => c.receipt_coverage === 'OTHER_PRIVATE_RECEIPT_HOME_NOT_QUERIED').length;
      const unindexed = matches.filter(c => c.receipt_coverage === 'NO_INDEXED_RECEIPT').length;
      row('Evidence', receipts + ' local receipt(s)'
        + (otherHomes ? ' · ' + otherHomes + ' private home(s) not queried' : '')
        + (unindexed ? ' · ' + unindexed + ' without indexed receipt mapping' : '')
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
            const target = [...byId('capabilities').querySelectorAll('.cap h3')]
              .find(heading => heading.textContent === id);
            if (target) {
              target.tabIndex = -1;
              target.focus({ preventScroll: true });
              target.scrollIntoView({ behavior: 'auto', block: 'start' });
            }
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

  function renderActivity(projection) {
    state.activity = projection;
    const panel = byId('activity-panel');
    if (!panel || !projection) return;
    panel.dataset.class = projection.activity_class || 'UNKNOWN';
    setText('activity-class', (projection.feed_status || 'UNKNOWN') + ' · ' + (projection.activity_class || 'UNKNOWN')
      + ' · ' + (projection.conflation_guard || 'RECEIPT_HISTORY_IS_NOT_LIVE_ACTIVITY'));
    setText('activity-headline', projection.headline || 'Activity unavailable');
    setText('activity-detail', projection.detail || '');
    const active = projection.active_run;
    const terminal = projection.latest_terminal_run;
    const meta = active
      ? ('Active: ' + active.kind + ' / ' + active.state + (active.updatedAt ? ' · ' + formatTime(active.updatedAt) : ''))
      : terminal
        ? ('Terminal history: ' + terminal.kind + ' / ' + terminal.state + (terminal.endedAt ? ' · ' + formatTime(terminal.endedAt) : '')
          + ' · not running')
        : 'No run-control operation attached on this page';
    setText('activity-meta', meta);
  }

  async function refreshActivityFeed() {
    let projectCockpitActivity = null;
    try {
      const activityMod = await import('./capability-activity.js');
      projectCockpitActivity = activityMod.projectCockpitActivity;
      const runMod = await import('./run-control.js');
      const paint = () => {
        renderActivity(projectCockpitActivity({
          feedStatus: 'CONNECTED',
          activeRun: runMod.getActiveRun(),
          latestRun: runMod.getLatestRun()
        }));
      };
      state.runFeedStatus = 'CONNECTED';
      if (typeof runMod.subscribeRunEvents === 'function') {
        if (state.unsubscribeRuns) state.unsubscribeRuns();
        state.unsubscribeRuns = runMod.subscribeRunEvents(paint);
      }
      if (typeof runMod.initRunControl === 'function') runMod.initRunControl();
      paint();
    } catch (err) {
      state.runFeedStatus = 'NOT_CONNECTED';
      if (projectCockpitActivity) {
        renderActivity(projectCockpitActivity({ feedStatus: 'NOT_CONNECTED' }));
      } else {
        renderActivity({
          feed_status: 'NOT_CONNECTED',
          activity_class: 'NOT_CONNECTED',
          headline: 'Run feed not connected on this page',
          detail: 'Active operations cannot be certified here. Historical receipts below are not live activity or field outcomes.',
          active_run: null,
          latest_terminal_run: null,
          conflation_guard: 'RECEIPT_HISTORY_IS_NOT_LIVE_ACTIVITY'
        });
      }
    }
  }

  function coverageLabel(capability) {
    if (capability.receipt_coverage === 'NO_INDEXED_RECEIPT') return 'No indexed receipt mapping';
    if (capability.receipt_coverage !== 'SURVEY_OUTPUT_PATTERN') {
      return 'Private origin · not queried · ' + (capability.receipt_source_class || 'OTHER_SOURCE_NOT_QUERIED');
    }
    return capability.local_receipt_observed
      ? 'Local survey receipt exists · outcome not certified'
      : 'No matching survey receipt observed';
  }

  function showOriginLedger() {
    const host = byId('origin-rows');
    if (!host) return;
    host.replaceChildren();
    if (!state.loaded) {
      const empty = create('div', 'origin-row');
      empty.append(create('div', 'origin-meaning', 'Origin ledger unavailable until the local host registry is verified.'));
      host.append(empty);
      return;
    }
    const counts = state.sourceClassCounts || {};
    const keys = Object.keys(counts).sort((a, b) => (counts[b] - counts[a]) || a.localeCompare(b));
    const fragment = document.createDocumentFragment();
    for (const key of keys) {
      const meta = sourceClassMeta[key] || sourceClassMeta.OTHER_SOURCE_NOT_QUERIED;
      const row = create('div', 'origin-row');
      row.setAttribute('role', 'row');
      row.append(
        create('div', 'origin-count', counts[key]),
        create('div', 'origin-code', key),
        create('div', 'origin-meaning', meta.meaning),
        create('div', 'origin-gate' + (meta.gateClass ? ' ' + meta.gateClass : ''), meta.gate)
      );
      fragment.append(row);
    }
    if (!keys.length) fragment.append(create('div', 'origin-meaning', 'No source-family counts were returned.'));
    host.append(fragment);
  }

  function setSourceClasses() {
    const select = byId('source-class');
    if (!select) return;
    const previous = select.value;
    select.querySelectorAll('option:not(:first-child)').forEach(option => option.remove());
    const classes = [...new Set(state.capabilities.map(c => c.receipt_source_class).filter(Boolean))].sort();
    for (const name of classes) {
      const option = create('option', '', name);
      option.value = name;
      select.append(option);
    }
    if (classes.includes(previous)) select.value = previous;
  }

  function showCapabilities() {
    const list = byId('capabilities');
    const search = byId('search').value.trim().toLowerCase();
    const domain = byId('domain').value;
    const evidence = byId('evidence').value;
    const sourceClass = byId('source-class') ? byId('source-class').value : '';
    const matching = state.capabilities.filter(c => {
      if (domain && c.domain !== domain) return false;
      if (sourceClass && c.receipt_source_class !== sourceClass) return false;
      if (evidence === 'receipt' && !c.local_receipt_observed) return false;
      if (evidence === 'none' && (c.local_receipt_observed || c.receipt_coverage !== 'SURVEY_OUTPUT_PATTERN')) return false;
      if (evidence === 'uncovered' && c.receipt_coverage !== 'OTHER_PRIVATE_RECEIPT_HOME_NOT_QUERIED') return false;
      if (evidence === 'unmapped' && c.receipt_coverage !== 'NO_INDEXED_RECEIPT') return false;
      if (evidence === 'missing' && c.entrypoint_status !== 'FILE_MISSING') return false;
      return [c.id, c.domain, c.command, c.purpose, c.receipt_source_class].join(' ').toLowerCase().includes(search);
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
      card.append(create('div', 'tag' + (capability.local_receipt_observed ? ' warn' : ''), coverageLabel(capability)));
      const detail = create('div', 'detail');
      const dl = create('dl');
      const coverageText = capability.receipt_coverage === 'SURVEY_OUTPUT_PATTERN'
        ? 'Survey output pattern'
        : capability.receipt_coverage === 'NO_INDEXED_RECEIPT'
          ? 'No indexed receipt mapping'
          : 'Other private home · not queried';
      const rows = [
        ['Command', capability.command || 'Unknown'],
        ['Source present', capability.source_present ? 'Yes' : 'No / unverified'],
        ['Executable', capability.executable_availability || 'NOT_PROBED'],
        ['Field outcome', capability.real_world_outcome || 'NOT_VERIFIED'],
        ['Mutation class', capability.mutation_class || 'Unspecified'],
        ['Receipt coverage', coverageText],
        ['Origin class', capability.receipt_source_class || 'Unknown'],
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
      state.sourceClassCounts = data.receipt_source_class_counts || {};
      state.loaded = true;
      setDomains();
      setSourceClasses();
      setText('count-registered', data.registered_count);
      setText('count-entrypoints', data.entrypoint_present_count);
      setText('count-receipts', data.local_receipt_count);
      setText('count-no-evidence', data.unobserved_supported_receipt_count);
      setText('count-uncovered', data.receipt_home_not_queried_count);
      setText('count-unmapped', data.no_indexed_receipt_count);
      showOriginLedger();
      showCapabilities();
      showAdbJourney();
    } catch (err) {
      // Do not use stale data as current host truth after an endpoint failure.
      state.capabilities = [];
      state.loaded = false;
      state.generatedAt = null;
      state.sourceClassCounts = {};
      ['count-registered', 'count-entrypoints', 'count-receipts', 'count-no-evidence', 'count-uncovered', 'count-unmapped']
        .forEach(id => setText(id, '—'));
      setText('status', 'Unable to verify local capabilities: ' + (err.message || 'unknown error')
        + '. Start the Windows SysAdminSuite DashboardHost on this Admin Box. '
        + 'The generic Python/static fallback does not certify local evidence.');
      showOriginLedger();
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
    const sourceClass = byId('source-class');
    if (sourceClass) sourceClass.addEventListener('change', showCapabilities);
    byId('refresh').addEventListener('click', refresh);
    refreshActivityFeed();
    refresh();
  });
})();
