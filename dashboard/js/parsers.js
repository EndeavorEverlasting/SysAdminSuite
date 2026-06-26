// parsers.js — file type detection and data normalization

import { parseCSV, parseJSON, pingToStep } from './utils.js';

function isNaabuReachabilityObject(obj) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return false;
  const hasHost = !!(obj.host || obj.ip || obj.Host || obj.IP || obj.Ip);
  const port = obj.port ?? obj.Port;
  return hasHost && port !== undefined && port !== null && String(port).trim() !== '';
}

function contentLooksLikeNaabuReachability(content) {
  if (typeof content !== 'string') return false;
  const trimmed = content.trim();
  if (!trimmed) return false;
  const snip = trimmed.slice(0, 800).toLowerCase();
  if (!snip.includes('port') || (!snip.includes('host') && !snip.includes('ip'))) return false;

  try {
    const data = JSON.parse(trimmed);
    const items = Array.isArray(data) ? data : [data];
    return items.some(isNaabuReachabilityObject);
  } catch {
    for (const raw of trimmed.split('\n')) {
      const line = raw.trim();
      if (!line) continue;
      try {
        if (isNaabuReachabilityObject(JSON.parse(line))) return true;
      } catch { /* invalid JSONL line */ }
    }
  }
  return false;
}

/**
 * Detect the log type from filename and/or CSV headers.
 * Returns one of: 'preflight', 'results', 'workstation-identity',
 *   'printer-probe', 'network-preflight', 'machine-info', 'ram-info',
 *   'monitor-info', 'neuron-inventory', 'cybernet-target-manifest',
 *   'ad-registered-population', 'status-json', 'smb-recon', 'naabu-reachability', 'unknown'
 */
function csvBasename(filename) {
  const parts = filename.replace(/\\/g, '/').split('/');
  return parts[parts.length - 1].toLowerCase();
}

const CYBERNET_MANIFEST_FILENAMES = new Set([
  'cybernet_targets.csv',
  'cybernet-targets.csv',
  'targets_resolved.csv',
  'cybernet_targets_resolved.csv',
]);

function isCybernetManifestHeader(firstLine) {
  const h = firstLine.toLowerCase();

  // Reject inventory / evidence schemas (defense in depth; detectFileType routes most of these first)
  if (h.includes('monitorserials')) return false;
  if (h.includes('transportused') && h.includes('identitystatus')) return false;
  if (h.includes('targethost') && h.includes('matchexpected')) return false;
  if (h.includes('driver') && h.includes('port') && h.includes('status')) return false;
  if (h.includes('pingstatus') && (h.includes('port') || h.includes('mac'))) return false;
  if (h.includes('populationauthority') || h.includes('reconcilebucket')) return false;
  if (h.includes('displaynumber') || h.includes('isprimary')) return false;
  if (h.includes('capacitygb') || h.includes('memorytype')) return false;
  if (h.includes('observedhostname') || h.includes('observedserial')) return false;
  if (h.includes('lastseen') || h.includes('evidencesource')) return false;

  // Manifest-specific positive signals only — avoid broad hostname/serial/site inventory CSVs
  if (h.includes('identifiertype') && h.includes('devicetype')) return true;
  if (h.includes('dnshostname')) return true;
  if (h.includes('neuron')) return true;
  if (h.includes('workstation') && !h.includes('identitystatus')) return true;

  return false;
}

function normalizeCybernetHost(value) {
  const v = String(value || '').trim();
  if (!v) return '';
  return v.split('.')[0].toUpperCase();
}

function pickManifestField(row, names) {
  const lowered = {};
  for (const [k, v] of Object.entries(row)) {
    const key = String(k).replace(/^\uFEFF/, '').toLowerCase();
    lowered[key] = v;
  }
  for (const name of names) {
    const val = lowered[name.toLowerCase()];
    if (val != null && String(val).trim()) return String(val).trim();
  }
  return '';
}

function firstIpAddress(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  return raw.split(/[;,|\s]+/).map(s => s.trim()).find(Boolean) || '';
}

export function detectFileType(filename, content) {
  const fn = filename.toLowerCase();

  // YAML detection — sources.yaml or sas-list-apps JSON output
  if (fn.endsWith('.yaml') || fn.endsWith('.yml')) {
    if (fn.includes('sources')) return 'software-tracker';
    return 'software-tracker'; // treat all YAML drops as tracker
  }

  // Naabu reachability JSON / JSONL — filename hint
  if ((fn.endsWith('.json') || fn.endsWith('.jsonl')) && fn.includes('naabu')) {
    return 'naabu-reachability';
  }

  // JSON detection — check filename hints first, then probe content
  if (fn.endsWith('.json')) {
    if (fn.includes('toolbox-status') || fn.includes('toolbox_status')) return 'toolbox-status';
    if (fn.includes('install-summary') || fn.includes('install_summary')) return 'software-tracker-install-plan';
    if (fn.includes('status')) return 'status-json';
    if (fn.includes('sources') || fn.includes('software') || fn.includes('apps')) return 'software-tracker';
    if (fn.includes('neuron')) return 'neuron-inventory';
    if (fn.includes('runcontrol') || fn.includes('run_control') ||
        fn.includes('qrtask') || fn.includes('qr_task') ||
        fn.includes('invoke-techtask') || fn.includes('techtask') ||
        fn.includes('tasklog') || fn.includes('task_log')) return 'remote-task';
    // Probe raw content: if it contains task-event keys treat as task log
    if (typeof content === 'string') {
      const snip = content.slice(0, 400).toLowerCase();
      if (snip.includes('"items"') && snip.includes('"summary"') && snip.includes('"status"')) {
        return 'software-tracker-install-plan';
      }
      if (snip.includes('"tools"') && snip.includes('"actionneeded"') && snip.includes('"repo"')) {
        return 'toolbox-status';
      }
      if (snip.includes('"taskname"') || snip.includes('"outcome"') ||
          snip.includes('"taskid"') || snip.includes('"events"')) return 'remote-task';
    }
    if (contentLooksLikeNaabuReachability(content)) return 'naabu-reachability';
    return 'status-json'; // fallback: attempt parse as status snapshot
  }

  if (fn.endsWith('.jsonl')) {
    if (contentLooksLikeNaabuReachability(content)) return 'naabu-reachability';
    return 'unknown';
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
  if (CYBERNET_MANIFEST_FILENAMES.has(csvBasename(filename))) return 'cybernet-target-manifest';
  if (fn.includes('neuron')) return 'neuron-inventory';
  if (fn.includes('smb')) return 'smb-recon';
  if (fn.includes('software_superset') || fn.includes('softwaresuperset') || fn.includes('software-superset')) return 'software-superset';
  if (fn.includes('software_hosts') || fn.includes('softwarehosts') || fn.includes('software-hosts')) return 'software-superset';
  if (fn.startsWith('installed_software_') || fn.includes('/installed_software_') || fn.includes('\\installed_software_')) return 'software-superset';
  if (fn.includes('qrtask') || fn.includes('qr_task') || fn.includes('invoke-techtask') || fn.includes('runtask')) return 'remote-task';
  if (fn.includes('runcontrol') || fn.includes('run_control')) return 'remote-task';
  if (fn.includes('ad_registered') || fn.includes('ad-registered') || fn.includes('ad_evidence') ||
      fn.includes('ad_only') || fn.includes('ad_disabled') || fn.includes('ad_stale') ||
      fn.includes('ad_missing_dns') || fn.includes('ad_duplicates') || fn.includes('evidence_only')) {
    return 'ad-registered-population';
  }
  if (fn.includes('dns_infrastructure_classification') || fn.includes('dns_infrastructure') ||
      fn.includes('cybernet_dns_resolution') || fn.includes('cybernet_master_presence')) {
    return 'survey-classification';
  }
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
    if (isCybernetManifestHeader(firstLine)) return 'cybernet-target-manifest';
    if (firstLine.includes('share') && firstLine.includes('liststatus')) return 'smb-recon';
    if (firstLine.includes('taskname') || firstLine.includes('taskid') || firstLine.includes('outcome')) return 'remote-task';
    if (firstLine.includes('publisher') && firstLine.includes('host') && firstLine.includes('name')) return 'software-superset';
    if (firstLine.includes('populationauthority') && firstLine.includes('reconcilebucket')) return 'ad-registered-population';
    if (firstLine.includes('populationauthority') && firstLine.includes('adstatus')) return 'ad-registered-population';
    if (firstLine.includes('reconcilebucket') && firstLine.includes('hostname')) return 'ad-registered-population';
    if (firstLine.includes('devicerole') && firstLine.includes('surveylane')) return 'survey-classification';
    if (firstLine.includes('devicerole') && firstLine.includes('countstowardcybernetpopulation')) return 'survey-classification';
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
    case 'cybernet-target-manifest': return parseCybernetTargetManifest(content);
    case 'smb-recon': return parseSmbRecon(content);
    case 'status-json': return parseStatusJson(content);
    case 'toolbox-status': return parseToolboxStatus(content, filename);
    case 'remote-task': return parseRemoteTask(content);
    case 'software-tracker': return parseSoftwareTracker(content, filename);
    case 'software-tracker-install-plan': return parseSoftwareTrackerInstallPlan(content, filename);
    case 'software-superset': return parseSoftwareSuperset(content);
    case 'naabu-reachability': return parseNaabuReachability(content, filename);
    case 'ad-registered-population': return parseAdRegisteredPopulation(content, filename);
    case 'survey-classification': return parseSurveyClassification(content, filename);
    default: return { type: 'unknown', rows: [], meta: {} };
  }
}

function normalizeNaabuRow(item, sourceFile) {
  const host = String(item.host || item.Host || '').trim();
  const ip = String(item.ip || item.IP || item.Ip || '').trim();
  const portRaw = item.port ?? item.Port;
  const port = portRaw !== undefined && portRaw !== null ? String(portRaw).trim() : '';
  const reachRaw = item.reachability ?? item.Reachability ?? 'open';
  return {
    host: host || ip,
    ip: ip || host,
    port,
    protocol: String(item.protocol || item.Protocol || 'tcp').trim() || 'tcp',
    timestamp: String(item.timestamp || item.Timestamp || item.time || '').trim(),
    tls: !!(item.tls ?? item.TLS),
    service: String(item.service || item.Service || '').trim(),
    sourceFile: sourceFile || '',
    reachability: String(reachRaw).trim().toLowerCase() || 'open',
  };
}

function parseNaabuReachability(content, filename) {
  const warnings = [];
  const rows = [];
  const sourceFile = filename || '';
  const trimmed = (content || '').replace(/^\uFEFF/, '').trim();

  if (!trimmed) {
    return { type: 'naabu-reachability', rows, meta: { count: 0, warnings } };
  }

  const ingestItem = (item, lineNo) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      if (lineNo != null) warnings.push(`Line ${lineNo}: not a JSON object`);
      return;
    }
    if (!isNaabuReachabilityObject(item)) {
      if (lineNo != null) warnings.push(`Line ${lineNo}: missing host/ip or port`);
      return;
    }
    rows.push(normalizeNaabuRow(item, sourceFile));
  };

  try {
    const data = JSON.parse(trimmed);
    const items = Array.isArray(data) ? data : [data];
    items.forEach((item, i) => ingestItem(item, items.length > 1 ? i + 1 : null));
  } catch {
    trimmed.split('\n').forEach((raw, idx) => {
      const line = raw.trim();
      if (!line) return;
      try {
        ingestItem(JSON.parse(line), idx + 1);
      } catch {
        warnings.push(`Line ${idx + 1}: invalid JSON`);
      }
    });
  }

  return { type: 'naabu-reachability', rows, meta: { count: rows.length, warnings } };
}

/**
 * Parse survey classification CSVs (DNS resolution, subnet dns-list, merged evidence).
 */
function parseSurveyClassification(content, filename) {
  const rows = parseCSV(content);
  const normalized = rows.map(r => ({
    hostName: r.HostName || r.hostname || r.Target || '',
    deviceRole: r.DeviceRole || r.devicerole || '',
    surveyLane: r.SurveyLane || r.surveylane || '',
    identifierType: r.IdentifierType || r.identifiertype || '',
    countsToward: r.CountsTowardCybernetPopulation || r.countstowardcybernetpopulation || '',
    roleSignals: r.RoleSignals || r.rolesignals || '',
    nextAction: r.NextAction || r.nextaction || '',
    overallStatus: r.OverallStatus || r.overallstatus || r.Status || '',
    sourceFile: filename || '',
  }));
  return { type: 'survey-classification', rows: normalized, meta: { count: normalized.length } };
}

/**
 * Parse AD registered population reconcile CSVs.
 */
function parseAdRegisteredPopulation(content, filename) {
  const rows = parseCSV(content);
  const normalized = rows.map(r => ({
    HostName:        r.HostName        || r.hostname        || r.ComputerName || '',
    DNSHostName:     r.DNSHostName     || r.dnshostname     || r.FQDN         || '',
    ADStatus:        r.ADStatus        || r.adstatus        || '',
    Enabled:         r.Enabled         || r.enabled         || '',
    OperatingSystem: r.OperatingSystem || r.operatingsystem || r.OS           || '',
    LastLogonDate:   r.LastLogonDate   || r.lastlogondate   || '',
    Description:     r.Description     || r.description     || '',
    ReconcileBucket: r.ReconcileBucket || r.reconcilebucket || r.Bucket       || '',
    PopulationAuthority: r.PopulationAuthority || r.populationauthority || 'ad_registered',
    MatchStatus:     r.MatchStatus     || r.matchstatus     || '',
    EvidenceSerial:  r.EvidenceSerial  || r.evidenceserial  || r.Serial       || '',
    EvidenceSource:  r.EvidenceSource  || r.evidencesource  || r.Source       || '',
    Reachability:    r.Reachability    || r.reachability    || '',
    ProbeStatus:     r.ProbeStatus     || r.probestatus     || '',
    Reason:          r.Reason          || r.reason          || '',
    _sourceFile:     filename || '',
  })).filter(r => r.HostName);
  const buckets = {};
  for (const row of normalized) {
    const b = row.ReconcileBucket || 'registered';
    buckets[b] = (buckets[b] || 0) + 1;
  }
  return { type: 'ad-registered-population', rows: normalized, meta: { count: normalized.length, buckets } };
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

/**
 * Parse Cybernet target manifest CSV (sas-survey-targets output or resolved manifests).
 * Distinct from network-preflight, workstation-identity, and AD population exports.
 */
function parseCybernetTargetManifest(content) {
  const rawRows = parseCSV(content);
  const rows = rawRows.map(row => {
    const identifierType = pickManifestField(row, ['IdentifierType', 'Identifier Type']);
    const identifier = pickManifestField(row, ['Identifier', 'Target', 'KnownIdentifier']);
    let hostname = pickManifestField(row, [
      'HostName', 'Hostname', 'Host', 'ComputerName', 'Computer', 'Name',
    ]);
    if (!hostname && identifierType.toLowerCase() === 'hostname') hostname = identifier;

    const dnsHostName = pickManifestField(row, ['DNSHostName', 'DNS Host Name', 'FQDN']);
    const ipAddress = firstIpAddress(pickManifestField(row, [
      'IPAddress', 'IP Address', 'IPAddresses', 'IP', 'ResolvedAddress',
    ]));
    const serial = pickManifestField(row, [
      'Serial', 'SerialNumber', 'Serial Number', 'ServiceTag', 'AssetSerial',
    ]);
    const site = pickManifestField(row, ['Site']);
    const location = pickManifestField(row, ['Location', 'Room']);
    const neuron = pickManifestField(row, [
      'Neuron', 'Neuron Hostname', 'NeuronHostName', 'Neuron Host',
    ]);
    const workstation = pickManifestField(row, ['Workstation', 'Workstation Hostname']);
    const mac = pickManifestField(row, [
      'MAC', 'MACAddress', 'MacAddress', 'Mac', 'EthernetMAC', 'WifiMAC',
    ]);
    const normalizedHost = normalizeCybernetHost(hostname || dnsHostName);

    return {
      type: 'cybernet-target-manifest',
      sourceType: 'cybernet-target-manifest',
      hostname,
      normalizedHost,
      dnsHostName,
      ipAddress,
      serial,
      site,
      location,
      neuron,
      workstation,
      mac,
      identifierType,
    };
  }).filter(r =>
    r.hostname || r.dnsHostName || r.ipAddress || r.serial || r.mac || r.neuron || r.workstation
  );

  return {
    type: 'cybernet-target-manifest',
    rows,
    meta: {
      count: rows.length,
      withSerial: rows.filter(r => r.serial).length,
      withIp: rows.filter(r => r.ipAddress).length,
      missingDnsHost: rows.filter(r => !r.hostname && !r.dnsHostName).length,
    },
  };
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
 * Parse software_superset.csv (from Inventory-Software.ps1 or sas-populate-tracker.sh --from-host).
 * Expected columns: Name, Version, Publisher, DetectType, DetectValue, Host, Timestamp
 */
function parseSoftwareSuperset(content) {
  const rows = parseCSV(content);
  // Normalize column names (case-insensitive)
  const normalized = rows.map(r => ({
    Name:        r.Name        || r.name        || '',
    Version:     r.Version     || r.version     || '',
    Publisher:   r.Publisher   || r.publisher   || '',
    DetectType:  r.DetectType  || r.detect_type || r.detecttype  || 'regkey',
    DetectValue: r.DetectValue || r.detect_value|| r.detectvalue || '',
    Host:        r.Host        || r.host        || r.ComputerName|| r.computername || '',
    Timestamp:   r.Timestamp   || r.timestamp   || '',
  })).filter(r => r.Name);
  return { type: 'software-superset', rows: normalized, meta: { count: normalized.length } };
}

function parseSoftwareTrackerInstallPlan(content, filename) {
  let parsed;
  try {
    parsed = typeof content === 'string' ? JSON.parse(content) : content;
  } catch (err) {
    return { type: 'software-tracker-install-plan', rows: [], data: { items: [], summary: {} }, meta: { error: err.message, filename } };
  }
  const items = Array.isArray(parsed?.items) ? parsed.items : [];
  const summary = parsed?.summary && typeof parsed.summary === 'object' ? parsed.summary : {};
  return {
    type: 'software-tracker-install-plan',
    rows: items,
    data: { items, summary },
    meta: { count: items.length, filename },
  };
}

function parseToolboxStatus(content, filename) {
  let parsed;
  try {
    parsed = typeof content === 'string' ? JSON.parse(content) : content;
  } catch (err) {
    return { type: 'toolbox-status', rows: [], data: { tools: [], actionNeeded: false }, meta: { error: err.message, filename } };
  }
  const tools = Array.isArray(parsed?.tools) ? parsed.tools : [];
  return {
    type: 'toolbox-status',
    rows: tools,
    data: parsed,
    meta: { count: tools.length, filename },
  };
}

/**
 * Parse sources.yaml or sas-list-apps.sh --json output into the software tracker store.
 * Accepts:
 *   - YAML text (Config/sources.yaml format)
 *   - JSON array of app objects (sas-list-apps.sh --json output)
 *   - JSON object with { apps: [...], lists: {...} }
 */
function parseSoftwareTracker(content, filename) {
  const trimmed = content.trim();

  // ── JSON path ────────────────────────────────────────────────────────────
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    let parsed;
    try { parsed = JSON.parse(trimmed); } catch { /* fall through to YAML */ }
    if (parsed !== undefined) {
      if (Array.isArray(parsed)) {
        return { type: 'software-tracker', rows: parsed, data: { apps: parsed, lists: {} }, meta: { count: parsed.length } };
      }
      if (parsed.apps || parsed.lists) {
        return { type: 'software-tracker', rows: parsed.apps || [], data: parsed, meta: { count: (parsed.apps || []).length } };
      }
    }
  }

  // ── YAML path — minimal parser matching the flat sources.yaml structure ──
  const apps = [];
  const lists = {};
  const lines = trimmed.split('\n');
  let i = 0;
  const n = lines.length;

  function stripComment(s) {
    let inSq = false;
    let result = '';
    for (const ch of s) {
      if (ch === "'" && !inSq) { inSq = true; result += ch; continue; }
      if (ch === "'" && inSq)  { inSq = false; result += ch; continue; }
      if (ch === '#' && !inSq) break;
      result += ch;
    }
    return result.trimEnd();
  }

  function unquote(s) {
    s = (s || '').trim();
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) return s.slice(1, -1);
    return s;
  }

  function indentOf(line) { return line.length - line.trimStart().length; }

  while (i < n) {
    const raw = lines[i];
    const line = stripComment(raw);
    const stripped = line.trimStart();
    if (!stripped || stripped.startsWith('#')) { i++; continue; }
    const ind = indentOf(raw);

    if (ind === 0 && stripped.includes(':')) {
      const key = stripped.split(':')[0].trim();

      if (key === 'apps') {
        i++;
        while (i < n) {
          const raw2 = lines[i];
          const s2 = stripComment(raw2).trimStart();
          if (!s2 || s2.startsWith('#')) { i++; continue; }
          const ind2 = indentOf(raw2);
          if (ind2 === 0 && !s2.startsWith('-')) break;
          if (s2.startsWith('- ') && ind2 === 2) {
            const app = {};
            const rest = s2.slice(2).trim();
            if (rest.includes(':')) {
              const [k, ...vs] = rest.split(':');
              app[k.trim()] = unquote(vs.join(':'));
            }
            i++;
            while (i < n) {
              const raw3 = lines[i];
              const s3 = stripComment(raw3).trimStart();
              if (!s3 || s3.startsWith('#')) { i++; continue; }
              const ind3 = indentOf(raw3);
              if (ind3 <= 2 && ind3 !== 4) break;
              if (s3.includes(':')) {
                const [k, ...vs] = s3.split(':');
                app[k.trim()] = unquote(vs.join(':'));
              }
              i++;
            }
            apps.push(app);
          } else { i++; }
        }
        continue;
      }

      if (key === 'lists') {
        i++;
        let curList = null;
        while (i < n) {
          const raw2 = lines[i];
          const s2 = stripComment(raw2).trimStart();
          if (!s2 || s2.startsWith('#')) { i++; continue; }
          const ind2 = indentOf(raw2);
          if (ind2 === 0 && !s2.startsWith('-')) break;
          if (ind2 === 2 && s2.includes(':') && !s2.startsWith('-')) {
            curList = s2.replace(/:.*/, '').trim();
            lists[curList] = [];
            i++; continue;
          }
          if (ind2 === 4 && s2.startsWith('- ') && curList) {
            lists[curList].push(s2.slice(2).trim().replace(/^['"]|['"]$/g, ''));
            i++; continue;
          }
          i++;
        }
        continue;
      }
    }
    i++;
  }

  return {
    type: 'software-tracker',
    rows: apps,
    data: { apps, lists },
    meta: { count: apps.length }
  };
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
    case 'cybernet-target-manifest':
      store.cybernetTargetManifest = (store.cybernetTargetManifest || []).concat(rows);
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
    case 'software-tracker': {
      const existingApps = (store.software?.apps || []);
      const existingNames = new Set(existingApps.map(a => (a.name || '').toLowerCase()));
      const newApps = (incoming.data?.apps || rows || []).filter(
        a => !existingNames.has((a.name || '').toLowerCase())
      );
      const mergedLists = Object.assign({}, store.software?.lists || {}, incoming.data?.lists || {});
      store.software = {
        apps: [...existingApps, ...newApps],
        lists: mergedLists
      };
      break;
    }
    case 'software-superset':
      store.softwareInventory = (store.softwareInventory || []).concat(rows);
      break;
    case 'software-tracker-install-plan':
      store.softwareInstallPlan = data;
      break;
    case 'naabu-reachability':
      store.naabuReachability = (store.naabuReachability || []).concat(rows);
      break;
    case 'ad-registered-population':
      store.adRegisteredPopulation = (store.adRegisteredPopulation || []).concat(rows);
      break;
    case 'survey-classification':
      store.surveyClassification = (store.surveyClassification || []).concat(rows);
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

  for (const row of (store.adRegisteredPopulation || [])) {
    const h = row.HostName || '';
    if (!h) continue;
    const key = h.toUpperCase();
    addHost(h, {
      Status: row.ReconcileBucket || row.ADStatus || hostMap[key]?.Status || '',
      Site: row.PopulationAuthority || 'ad_registered',
      Serial: row.EvidenceSerial || hostMap[key]?.Serial || '',
      _adPopulation: row
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

  // Naabu reachability — merge open ports only; never set identity fields from reachability alone
  for (const row of (store.naabuReachability || [])) {
    const t = row.host || row.ip || '';
    if (!t) continue;
    if (!hostMap[t]) {
      hostMap[t] = { Target: t, ports: {}, steps: {} };
    }
    const port = String(row.port || '').trim();
    if (!port) continue;
    const reach = (row.reachability || 'open').toLowerCase();
    hostMap[t].ports[port] = reach === 'open' ? 'Open' : reach;
  }

  for (const row of (store.adRegisteredPopulation || [])) {
    const t = row.HostName || '';
    if (!t) continue;
    if (!hostMap[t]) {
      hostMap[t] = {
        Target: t,
        ResolvedAddress: row.DNSHostName || '',
        ports: {},
        steps: {}
      };
    }
    hostMap[t].ADStatus = row.ADStatus || '';
    hostMap[t].ReconcileBucket = row.ReconcileBucket || '';
    hostMap[t].PopulationAuthority = row.PopulationAuthority || 'ad_registered';
    if (row.Reachability) {
      hostMap[t].steps.Ping = (row.Reachability || '').toLowerCase().includes('reach') ? 'success' : 'failed';
    }
    if (row.EvidenceSerial) hostMap[t].ObservedSerial = row.EvidenceSerial;
    hostMap[t].Notes = [row.Reason, row.EvidenceSource, row.ProbeStatus].filter(Boolean).join(' | ');
  }

  return Object.values(hostMap).sort((a, b) => (a.Target || '').localeCompare(b.Target || ''));
}
