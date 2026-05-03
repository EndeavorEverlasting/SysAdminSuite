// parsers.js — file type detection and data normalization

import { parseCSV, parseJSON, pingToStep } from './utils.js';

/**
 * Detect the log type from filename and/or CSV headers.
 * Returns one of: 'preflight', 'results', 'workstation-identity',
 *   'printer-probe', 'network-preflight', 'machine-info', 'ram-info',
 *   'monitor-info', 'neuron-inventory', 'status-json', 'smb-recon', 'unknown'
 */
export function detectFileType(filename, content) {
  const fn = filename.toLowerCase();

  // JSON detection — check filename hints first, then probe content
  if (fn.endsWith('.json')) {
    if (fn.includes('status')) return 'status-json';
    if (fn.includes('neuron')) return 'neuron-inventory';
    if (fn.includes('runcontrol') || fn.includes('run_control') ||
        fn.includes('qrtask') || fn.includes('qr_task') ||
        fn.includes('invoke-techtask') || fn.includes('techtask') ||
        fn.includes('tasklog') || fn.includes('task_log')) return 'remote-task';
    // Probe raw content: if it contains task-event keys treat as task log
    if (typeof content === 'string') {
      const snip = content.slice(0, 400).toLowerCase();
      if (snip.includes('"taskname"') || snip.includes('"outcome"') ||
          snip.includes('"taskid"') || snip.includes('"events"')) return 'remote-task';
    }
    return 'status-json'; // fallback: attempt parse as status snapshot
  }

  // XLSX detection
  if (fn.endsWith('.xlsx') || fn.endsWith('.xls')) return 'xlsx';

  // CSV detection by filename — specific patterns before generic ones
  if (fn.includes('network_preflight') || fn.includes('network-preflight') || fn.includes('networkpreflight')) return 'network-preflight';
  if (fn.includes('workstation_identity') || fn.includes('workstation-identity')) return 'workstation-identity';
  if (fn.includes('printer_probe') || fn.includes('printer-probe')) return 'printer-probe';
  if (fn.includes('preflight')) return 'preflight';
  if (fn.includes('results')) return 'results';
  if (fn.includes('machineinfo') || fn.includes('machine_info') || fn.includes('machine-info')) return 'machine-info';
  if (fn.includes('raminfo') || fn.includes('ram_info') || fn.includes('ram-info')) return 'ram-info';
  if (fn.includes('monitorinfo') || fn.includes('monitor_info') || fn.includes('monitor-info')) return 'monitor-info';
  if (fn.includes('neuron')) return 'neuron-inventory';
  if (fn.includes('smb')) return 'smb-recon';
  if (fn.includes('qrtask') || fn.includes('qr_task') || fn.includes('invoke-techtask') || fn.includes('runtask')) return 'remote-task';
  if (fn.includes('runcontrol') || fn.includes('run_control')) return 'remote-task';
  if (fn.includes('wmi_identity') || fn.includes('wmi-identity')) return 'workstation-identity';

  // Detect by headers if content is provided
  if (typeof content === 'string' && content.includes(',')) {
    const firstLine = content.split('\n')[0].toLowerCase();
    if (firstLine.includes('snapshottime') && firstLine.includes('presentnow')) return 'preflight';
    if (firstLine.includes('driver') && firstLine.includes('port') && firstLine.includes('status')) return 'results';
    if (firstLine.includes('transportused') && firstLine.includes('identitystatus')) return 'workstation-identity';
    if (firstLine.includes('pingstatus') && firstLine.includes('mac') && firstLine.includes('serial') && firstLine.includes('source')) return 'printer-probe';
    if (firstLine.includes('portstatus') || (firstLine.includes('port') && firstLine.includes('pingstatus'))) return 'network-preflight';
    if (firstLine.includes('monitorserials') && firstLine.includes('hostname')) return 'machine-info';
    if (firstLine.includes('capacitygb') || firstLine.includes('memorytype')) return 'ram-info';
    if (firstLine.includes('displaynumber') || firstLine.includes('isprimary')) return 'monitor-info';
    if (firstLine.includes('targethost') && firstLine.includes('matchexpected')) return 'neuron-inventory';
    if (firstLine.includes('share') && firstLine.includes('liststatus')) return 'smb-recon';
    if (firstLine.includes('taskname') || firstLine.includes('taskid') || firstLine.includes('outcome')) return 'remote-task';
  }

  return 'unknown';
}

/**
 * Parse file content into structured data for each panel.
 * Returns { type, rows, meta }
 */
export function parseFileContent(type, content, filename) {
  switch (type) {
    case 'preflight': return parsePreflight(content);
    case 'results': return parseResults(content);
    case 'workstation-identity': return parseWorkstationIdentity(content);
    case 'printer-probe': return parsePrinterProbe(content);
    case 'network-preflight': return parseNetworkPreflight(content);
    case 'machine-info': return parseMachineInfo(content);
    case 'ram-info': return parseRamInfo(content);
    case 'monitor-info': return parseMonitorInfo(content);
    case 'neuron-inventory': return parseNeuronInventory(content);
    case 'smb-recon': return parseSmbRecon(content);
    case 'status-json': return parseStatusJson(content);
    case 'remote-task': return parseRemoteTask(content);
    default: return { type: 'unknown', rows: [], meta: {} };
  }
}

function parsePreflight(content) {
  const rows = parseCSV(content);
  return { type: 'preflight', rows, meta: { count: rows.length } };
}

function parseResults(content) {
  const rows = parseCSV(content);
  return { type: 'results', rows, meta: { count: rows.length } };
}

function parseWorkstationIdentity(content) {
  const rows = parseCSV(content);
  return { type: 'workstation-identity', rows, meta: { count: rows.length } };
}

function parsePrinterProbe(content) {
  const rows = parseCSV(content);
  return { type: 'printer-probe', rows, meta: { count: rows.length } };
}

function parseNetworkPreflight(content) {
  const rows = parseCSV(content);
  // Group by target so each target has all port statuses
  const byTarget = {};
  for (const row of rows) {
    const t = row.Target || row.target || '';
    if (!byTarget[t]) {
      byTarget[t] = {
        Target: t,
        ResolvedAddress: row.ResolvedAddress || row.resolvedaddress || '',
        PingStatus: row.PingStatus || row.pingstatus || '',
        Timestamp: row.Timestamp || row.timestamp || '',
        ports: {}
      };
    }
    const port = row.Port || row.port || '';
    const status = row.PortStatus || row.portstatus || '';
    if (port) byTarget[t].ports[port] = status;
  }
  const grouped = Object.values(byTarget);
  return { type: 'network-preflight', rows: grouped, rawRows: rows, meta: { count: grouped.length } };
}

function parseMachineInfo(content) {
  const rows = parseCSV(content);
  return { type: 'machine-info', rows, meta: { count: rows.length } };
}

function parseRamInfo(content) {
  const rows = parseCSV(content);
  // Group by hostname
  const byHost = {};
  for (const row of rows) {
    const h = row.HostName || row.Hostname || row.hostname || '';
    if (!byHost[h]) byHost[h] = [];
    byHost[h].push(row);
  }
  return { type: 'ram-info', rows, byHost, meta: { count: rows.length } };
}

function parseMonitorInfo(content) {
  const rows = parseCSV(content);
  return { type: 'monitor-info', rows, meta: { count: rows.length } };
}

function parseNeuronInventory(content) {
  // Could be JSON or CSV
  if (content.trim().startsWith('[') || content.trim().startsWith('{')) {
    const json = parseJSON(content);
    const arr = Array.isArray(json) ? json : (json ? [json] : []);
    return { type: 'neuron-inventory', rows: arr, meta: { count: arr.length } };
  }
  const rows = parseCSV(content);
  return { type: 'neuron-inventory', rows, meta: { count: rows.length } };
}

function parseSmbRecon(content) {
  const rows = parseCSV(content);
  return { type: 'smb-recon', rows, meta: { count: rows.length } };
}

function parseStatusJson(content) {
  const data = parseJSON(content);
  return { type: 'status-json', data, meta: {} };
}

function parseRemoteTask(content) {
  const trimmed = content.trim();

  // ── JSON path ────────────────────────────────────────────────────────────
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    let parsed;
    try { parsed = JSON.parse(trimmed); } catch { /* fall through to CSV */ }

    if (parsed !== undefined) {
      // Unwrap common RunControl / QRTask envelope keys
      let items = parsed;
      if (!Array.isArray(parsed)) {
        items =
          parsed.events    || parsed.Events     ||
          parsed.tasks     || parsed.Tasks      ||
          parsed.TaskEvents|| parsed.taskEvents ||
          parsed.Records   || parsed.records    ||
          parsed.Results   || parsed.results    ||
          (parsed.Data ? (Array.isArray(parsed.Data) ? parsed.Data : [parsed.Data]) : null) ||
          [parsed]; // single-object log
      }

      const rows = (Array.isArray(items) ? items : []).map(e => ({
        Timestamp:  e.Timestamp  || e.timestamp  || e.GeneratedAt || e.Date || e.date || e.StartTime || '',
        Machine:    e.ComputerName || e.Machine  || e.Target      || e.TargetMachine || e.HostName  || '',
        TaskName:   e.TaskName   || e.Name       || e.Task        || e.TechTask       || e.Action    || '',
        TaskId:     e.TaskId     || e.Id         || e.QRCode      || e.QrCode        || '',
        Outcome:    e.Outcome    || e.Status     || e.Result      || e.State         || '',
        Operator:   e.Operator   || e.User       || e.RunAs       || e.RunByUser     || '',
        Notes:      e.Notes      || e.ErrorMessage || e.Message   || e.Error         || '',
      }));
      return { type: 'remote-task', rows, meta: { count: rows.length, source: 'json' } };
    }
  }

  // ── CSV / TSV path ───────────────────────────────────────────────────────
  if (trimmed.includes(',') || trimmed.includes('\t')) {
    const rows = parseCSV(trimmed);
    return { type: 'remote-task', rows, meta: { count: rows.length, source: 'csv' } };
  }

  return { type: 'remote-task', rows: [], meta: { count: 0 } };
}

/**
 * Merge multiple parsed data objects into unified store for each panel.
 */
export function mergeDataStore(existing, incoming) {
  const store = { ...existing };

  const { type, rows, data, byHost, rawRows } = incoming;

  switch (type) {
    case 'preflight':
      store.preflight = (store.preflight || []).concat(rows);
      break;
    case 'results':
      store.results = (store.results || []).concat(rows);
      break;
    case 'workstation-identity':
      store.workstationIdentity = (store.workstationIdentity || []).concat(rows);
      break;
    case 'printer-probe':
      store.printerProbe = (store.printerProbe || []).concat(rows);
      break;
    case 'network-preflight':
      store.networkPreflight = (store.networkPreflight || []).concat(rows);
      store.networkPreflightRaw = (store.networkPreflightRaw || []).concat(rawRows || []);
      break;
    case 'machine-info':
      store.machineInfo = (store.machineInfo || []).concat(rows);
      break;
    case 'ram-info':
      store.ramInfo = (store.ramInfo || []).concat(rows);
      // Merge byHost
      store.ramByHost = store.ramByHost || {};
      for (const [h, sticks] of Object.entries(byHost || {})) {
        store.ramByHost[h] = (store.ramByHost[h] || []).concat(sticks);
      }
      break;
    case 'monitor-info':
      store.monitorInfo = (store.monitorInfo || []).concat(rows);
      break;
    case 'neuron-inventory':
      store.neuronInventory = (store.neuronInventory || []).concat(rows);
      break;
    case 'smb-recon':
      store.smbRecon = (store.smbRecon || []).concat(rows);
      break;
    case 'status-json':
      store.statusJson = data;
      break;
    case 'remote-task':
      store.remoteTasks = (store.remoteTasks || []).concat(rows);
      break;
  }

  return store;
}

/**
 * Build unified inventory rows by merging machine-info, neuron-inventory,
 * ram-info, and monitor-info by hostname.
 */
export function buildInventoryRows(store) {
  // Keys are always uppercase for case-insensitive host matching.
  // HostName (display value) is preserved from the first source that provides it.
  const hostMap = {};

  const addHost = (rawName, data) => {
    const key = rawName.toUpperCase();
    if (!hostMap[key]) hostMap[key] = { HostName: rawName }; // preserve original casing
    else if (rawName && hostMap[key].HostName === key && rawName !== key) {
      hostMap[key].HostName = rawName; // upgrade from uppercase placeholder to real casing
    }
    Object.assign(hostMap[key], data);
  };

  for (const row of (store.machineInfo || [])) {
    const h = row.HostName || row.Hostname || '';
    if (!h) continue;
    addHost(h, {
      Serial: row.Serial || '',
      IPAddress: row.IPAddress || '',
      MACAddress: row.MACAddress || '',
      MonitorSerials: row.MonitorSerials || '',
      Status: row.Status || '',
      _machineInfo: row
    });
  }

  for (const row of (store.neuronInventory || [])) {
    const h = row.TargetHost || row.HostName || row.Hostname || '';
    if (!h) continue;
    const key = h.toUpperCase();
    addHost(h, {
      IPAddress: row.IPAddress || hostMap[key]?.IPAddress || '',
      MACAddress: row.MACAddress || row.PrimaryMAC || hostMap[key]?.MACAddress || '',
      Serial: row.SerialNumber || row.SystemSerialNumber || hostMap[key]?.Serial || '',
      Model: row.Model || '',
      Manufacturer: row.Manufacturer || '',
      Site: row.Site || '',
      Room: row.Room || '',
      Status: row.Status || hostMap[key]?.Status || '',
      _neuron: row
    });
  }

  // Enrich with monitor-info (case-insensitive key)
  const monitorsByHost = {};
  for (const row of (store.monitorInfo || [])) {
    const h = (row.HostName || row.Hostname || row.ComputerName || '').toUpperCase();
    if (!h) continue;
    if (!monitorsByHost[h]) monitorsByHost[h] = [];
    monitorsByHost[h].push(row);
  }
  for (const [key, monitors] of Object.entries(monitorsByHost)) {
    const serials = monitors.map(m => m.Serial || '').filter(Boolean);
    const models = monitors.map(m => m.Model || '').filter(Boolean);
    const displayName = monitors[0]?.HostName || monitors[0]?.ComputerName || key;
    addHost(displayName, {
      MonitorSerials: hostMap[key]?.MonitorSerials || serials.join(';'),
      MonitorModels: models.join(';'),
      _monitors: monitors
    });
  }

  // Enrich with RAM summary (case-insensitive key)
  for (const [h, sticks] of Object.entries(store.ramByHost || {})) {
    const totalGB = sticks.reduce((s, r) => s + parseFloat(r.CapacityGB || 0), 0);
    const speed = sticks[0]?.ConfiguredClockSpeed || sticks[0]?.Speed || '';
    const type = sticks[0]?.MemoryType || '';
    const displayName = sticks[0]?.HostName || sticks[0]?.Hostname || h;
    addHost(displayName, {
      RAMTotal: totalGB.toFixed(1) + ' GB',
      RAMSpeed: speed ? speed + ' MHz' : '',
      RAMType: type,
      RAMSticks: sticks.length,
      _ramSticks: sticks
    });
  }

  return Object.values(hostMap).sort((a, b) => (a.HostName || '').localeCompare(b.HostName || ''));
}

/**
 * Build printer mapping rows by merging preflight + results + printer-probe.
 */
export function buildPrinterRows(store) {
  const rows = [];

  // Results.csv is the most complete
  for (const row of (store.results || [])) {
    rows.push({
      ComputerName: row.ComputerName || '',
      Target: row.Target || '',
      Type: row.Type || '',
      Driver: row.Driver || '',
      Port: row.Port || '',
      Status: row.Status || '',
      Timestamp: row.Timestamp || '',
      Source: 'Results.csv'
    });
  }

  // Add preflight rows not already covered
  const resultTargets = new Set(rows.map(r => r.ComputerName + '|' + r.Target));
  for (const row of (store.preflight || [])) {
    const key = (row.ComputerName || '') + '|' + (row.Target || '');
    if (!resultTargets.has(key)) {
      rows.push({
        ComputerName: row.ComputerName || '',
        Target: row.Target || '',
        Type: row.Type || '',
        Driver: '',
        Port: '',
        Status: row.PresentNow === 'True' || row.PresentNow === 'true' ? 'PresentNow' : (row.InDesired === 'True' ? 'Planned' : 'NotPresent'),
        Timestamp: row.SnapshotTime || '',
        PreflightNotes: row.Notes || '',
        Source: 'Preflight.csv'
      });
    }
  }

  // Add printer probe data
  for (const row of (store.printerProbe || [])) {
    rows.push({
      ComputerName: row.Target || '',
      Target: row.Target || '',
      Type: 'PRINTER',
      Driver: '',
      Port: row.ResolvedAddress || '',
      Status: row.PingStatus || '',
      MAC: row.MAC || '',
      Serial: row.Serial || '',
      ProbeSource: row.Source || '',
      Timestamp: row.Timestamp || '',
      Notes: row.Notes || '',
      Source: 'printer-probe'
    });
  }

  return rows;
}

/**
 * Build protocol trace rows from workstation identity + network preflight + smb recon.
 */
export function buildProtocolRows(store) {
  const hostMap = {};

  // Network preflight - has per-port status
  for (const row of (store.networkPreflight || [])) {
    const t = row.Target || '';
    if (!hostMap[t]) {
      hostMap[t] = {
        Target: t,
        ResolvedAddress: row.ResolvedAddress || '',
        PingStatus: row.PingStatus || '',
        Timestamp: row.Timestamp || '',
        ports: {},
        steps: {}
      };
    }
    hostMap[t].ResolvedAddress = row.ResolvedAddress || hostMap[t].ResolvedAddress || '';
    hostMap[t].PingStatus = row.PingStatus || hostMap[t].PingStatus || '';
    Object.assign(hostMap[t].ports, row.ports || {});
    hostMap[t].steps.DNS = hostMap[t].ResolvedAddress ? 'success' : 'failed';
    hostMap[t].steps.Ping = pingToStep(hostMap[t].PingStatus);
  }

  // Workstation identity - adds SSH, WMI, ARP, TransportUsed, IdentityStatus
  for (const row of (store.workstationIdentity || [])) {
    const t = row.Target || '';
    if (!hostMap[t]) {
      hostMap[t] = { Target: t, ports: {}, steps: {} };
    }
    hostMap[t].ResolvedAddress = row.ResolvedAddress || hostMap[t].ResolvedAddress || '';
    hostMap[t].DnsName = row.DnsName || '';
    hostMap[t].PingStatus = row.PingStatus || '';
    hostMap[t].ObservedHostName = row.ObservedHostName || '';
    hostMap[t].ObservedSerial = row.ObservedSerial || '';
    hostMap[t].ObservedMACs = row.ObservedMACs || '';
    hostMap[t].TransportUsed = row.TransportUsed || '';
    hostMap[t].IdentityStatus = row.IdentityStatus || '';
    hostMap[t].Notes = row.Notes || '';
    hostMap[t].Timestamp = row.Timestamp || hostMap[t].Timestamp || '';

    // Populate steps from TransportUsed
    const transport = (row.TransportUsed || '').toUpperCase();
    hostMap[t].steps.DNS = row.ResolvedAddress ? 'success' : 'failed';
    hostMap[t].steps.Ping = pingToStep(row.PingStatus);
    hostMap[t].steps.ARP = transport.includes('ARP') ? 'success' : 'skipped';
    hostMap[t].steps.SSH = transport.includes('SSH') ? 'success' :
                           (row.Notes || '').toLowerCase().includes('ssh') ? 'failed' : 'skipped';
    hostMap[t].steps.WMI = transport.includes('WMI') ? 'success' :
                           (row.Notes || '').toLowerCase().includes('wmi') ? 'failed' : 'skipped';
  }

  // SMB recon
  for (const row of (store.smbRecon || [])) {
    const t = row.Target || '';
    if (!hostMap[t]) hostMap[t] = { Target: t, ports: {}, steps: {} };
    hostMap[t].steps.SMB = (row.Reachable || '').toLowerCase() === 'yes' ? 'success' :
                            (row.ListStatus || '').toLowerCase().includes('missing') ? 'partial' : 'failed';
    hostMap[t].SmbRecon = row.ReconStatus || '';
  }

  // Printer probe — enriches targets with SNMP, HTTP, 9100/ZPL, ARP step results
  for (const row of (store.printerProbe || [])) {
    const t = row.Target || '';
    if (!t) continue;
    if (!hostMap[t]) {
      hostMap[t] = {
        Target: t,
        ResolvedAddress: row.ResolvedAddress || '',
        Timestamp: row.Timestamp || '',
        ports: {},
        steps: {}
      };
    }
    // Populate ping/DNS from probe columns (don't overwrite if already set)
    hostMap[t].PingStatus = hostMap[t].PingStatus || row.PingStatus || '';
    if (!hostMap[t].steps.Ping) {
      hostMap[t].steps.Ping = pingToStep(hostMap[t].PingStatus);
    }
    if (!hostMap[t].steps.DNS) {
      hostMap[t].steps.DNS = (row.ResolvedAddress || hostMap[t].ResolvedAddress) ? 'success' : 'skipped';
    }
    hostMap[t].MAC = row.MAC || hostMap[t].MAC || '';
    hostMap[t].Serial = row.Serial || hostMap[t].Serial || '';
    hostMap[t].PrinterProbeNotes = row.Notes || '';

    // Parse Source field for protocol steps used
    const src = (row.Source || '').toLowerCase();
    if (src.includes('snmp')) hostMap[t].steps.SNMP = 'success';
    if (src.includes('http')) hostMap[t].steps.HTTP = 'success';
    if (src.includes('9100') || src.includes('zpl') || src.includes('raw')) {
      hostMap[t].ports['9100'] = 'Open';
      hostMap[t].steps['9100'] = 'success';
    }
    if (src.includes('arp')) hostMap[t].steps.ARP = 'success';
    if (src.includes('wmi')) hostMap[t].steps.WMI = 'success';
    if (src.includes('ssh')) hostMap[t].steps.SSH = 'success';
    // Mark missing MAC/Serial as partial if ping succeeded but source is sparse
    if (hostMap[t].steps.Ping === 'success' && !row.MAC && !row.Serial) {
      if (!hostMap[t].steps.SNMP) hostMap[t].steps.SNMP = 'failed';
    }
  }

  return Object.values(hostMap).sort((a, b) => (a.Target || '').localeCompare(b.Target || ''));
}
