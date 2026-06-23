// panel-qr-standalone.js - standalone QR payload builder for the SysAdminSuite dashboard
// Loaded after bundle.js so the feature can be reviewed without disturbing the existing bundle pipeline.
// Northwell posture: Bash-first for new work. PowerShell entries are preserved as legacy typed payloads only.

(function () {
  'use strict';

  const QR_MAX_PAYLOAD = 2000;
  const TARGET_DIR_STANDARD = 'SysAdminSuite/dashboard/targets';
  const QR_LOCAL_LIB = 'js/vendor/qrcode.min.js';
  const QR_CDN_LIB = 'https://cdn.jsdelivr.net/npm/qrcode@1.5.4/build/qrcode.min.js';

  let selectedTargets = [];
  let directoryHandle = null;
  let targetFiles = [];
  let lastPayload = '';
  let qrLibraryLoadStarted = false;

  const TEMPLATES = [
    {
      id: 'bash-network-preflight',
      label: 'Bash - network preflight from targets',
      platform: 'bash',
      category: 'Network',
      needsTargets: true,
      help: 'Preferred Northwell path. Builds a target file and calls sas-network-preflight.sh from the repo root.',
      build: ctx => `#!/usr/bin/env bash
# SysAdminSuite QR payload - network preflight
# Preferred Northwell path: Bash-first. Run from repo root.

set -euo pipefail
mkdir -p /tmp/sas-qr
: > /tmp/sas-qr/targets.txt
${ctx.bashTargetBlock}

bash bash/transport/sas-network-preflight.sh \\
  --targets-file /tmp/sas-qr/targets.txt \\
  --output /tmp/sas-qr/network_preflight.csv \\
  --pass-thru

echo "Done. Drag /tmp/sas-qr/network_preflight.csv back into the dashboard."`
    },
    {
      id: 'bash-workstation-identity',
      label: 'Bash - workstation identity from targets',
      platform: 'bash',
      category: 'Inventory',
      needsTargets: true,
      help: 'Preferred Northwell path. Produces workstation identity output from selected hostnames or IPs.',
      build: ctx => `#!/usr/bin/env bash
# SysAdminSuite QR payload - workstation identity
# Preferred Northwell path: Bash-first. Run from repo root.

set -euo pipefail
mkdir -p /tmp/sas-qr
: > /tmp/sas-qr/targets.txt
${ctx.bashTargetBlock}

bash bash/transport/sas-workstation-identity.sh \\
  --targets-file /tmp/sas-qr/targets.txt \\
  --output /tmp/sas-qr/workstation_identity.csv \\
  --pass-thru

echo "Done. Drag /tmp/sas-qr/workstation_identity.csv back into the dashboard."`
    },
    {
      id: 'bash-printer-probe',
      label: 'Bash - printer probe from targets',
      platform: 'bash',
      category: 'Printer',
      needsTargets: true,
      help: 'Preferred Northwell path. Probes printer targets and writes printer_probe.csv.',
      build: ctx => `#!/usr/bin/env bash
# SysAdminSuite QR payload - printer probe
# Preferred Northwell path: Bash-first. Run from repo root.

set -euo pipefail
mkdir -p /tmp/sas-qr
: > /tmp/sas-qr/targets.txt
${ctx.bashTargetBlock}

bash bash/transport/sas-printer-probe.sh \\
  --targets-file /tmp/sas-qr/targets.txt \\
  --output /tmp/sas-qr/printer_probe.csv \\
  --pass-thru

echo "Done. Drag /tmp/sas-qr/printer_probe.csv back into the dashboard."`
    },
    {
      id: 'bash-nmap-ad-derived',
      label: 'Bash - Nmap validation from AD-derived targets',
      platform: 'bash',
      category: 'Network',
      needsTargets: true,
      help: 'Reachability validation only. AD defines the registered population; Nmap only proves what answers today.',
      build: ctx => `#!/usr/bin/env bash
# SysAdminSuite QR payload - Nmap validation
# AD registered objects first. Nmap reachability second.

set -euo pipefail
mkdir -p /tmp/sas-qr
: > /tmp/sas-qr/targets.txt
${ctx.bashTargetBlock}

nmap -sn -iL /tmp/sas-qr/targets.txt -oA /tmp/sas-qr/nmap_ad_reachability
nmap -Pn -p 135,139,445,3389,5985 --script smb-os-discovery \\
  -iL /tmp/sas-qr/targets.txt \\
  -oA /tmp/sas-qr/nmap_ad_identity

echo "Done. Review /tmp/sas-qr/nmap_ad_reachability.* and nmap_ad_identity.*"`
    },
    {
      id: 'ps-ad-registered',
      label: 'PowerShell legacy - export AD registered devices by prefix',
      platform: 'powershell-legacy',
      category: 'AD',
      needsTargets: false,
      help: 'Typed interactive PowerShell only. Exports registered AD objects, including offline devices.',
      build: ctx => `$out="$env:USERPROFILE\\Desktop"
$f="${ctx.psFilter}"
$p="DNSHostName","Enabled","LastLogonDate","OperatingSystem","Description","CanonicalName","whenCreated","whenChanged"
Get-ADComputer -Filter $f -Properties $p |
Select Name,DNSHostName,Enabled,LastLogonDate,OperatingSystem,Description,CanonicalName,whenCreated,whenChanged |
Export-Csv "$out\\AD_Registered_Objects.csv" -NoTypeInformation`
    },
    {
      id: 'ps-ad-stale',
      label: 'PowerShell legacy - export stale AD devices',
      platform: 'powershell-legacy',
      category: 'AD',
      needsTargets: false,
      help: 'Typed interactive PowerShell only. Finds registered objects with no recent logon date.',
      build: ctx => `$out="$env:USERPROFILE\\Desktop"
$f="${ctx.psFilter}"
$p="DNSHostName","Enabled","LastLogonDate","OperatingSystem","Description","CanonicalName","whenCreated","whenChanged"
$d=(Get-Date).AddDays(-30)
Get-ADComputer -Filter $f -Properties $p |
Where {$_.LastLogonDate -lt $d -or $_.LastLogonDate -eq $null} |
Select Name,DNSHostName,Enabled,LastLogonDate,OperatingSystem,Description,CanonicalName,whenCreated,whenChanged |
Sort LastLogonDate |
Export-Csv "$out\\AD_Stale_30Days.csv" -NoTypeInformation`
    },
    {
      id: 'ps-ad-missing-dns',
      label: 'PowerShell legacy - export AD devices missing DNSHostName',
      platform: 'powershell-legacy',
      category: 'AD',
      needsTargets: false,
      help: 'Typed interactive PowerShell only. Finds registered objects that may not resolve cleanly.',
      build: ctx => `$out="$env:USERPROFILE\\Desktop"
$f="${ctx.psFilter}"
$p="DNSHostName","Enabled","LastLogonDate","OperatingSystem","Description","CanonicalName","whenCreated","whenChanged"
Get-ADComputer -Filter $f -Properties $p |
Where {!$_.DNSHostName} |
Select Name,DNSHostName,Enabled,LastLogonDate,OperatingSystem,Description,CanonicalName,whenCreated,whenChanged |
Export-Csv "$out\\AD_Missing_DNSHostName.csv" -NoTypeInformation`
    },
    {
      id: 'ps-ad-hostnames',
      label: 'PowerShell legacy - export AD DNS hostnames for Nmap',
      platform: 'powershell-legacy',
      category: 'AD',
      needsTargets: false,
      help: 'Typed interactive PowerShell only. Produces a hostname list for later Nmap validation.',
      build: ctx => `$out="$env:USERPROFILE\\Desktop"
$f="${ctx.psFilter}"
Get-ADComputer -Filter $f -Properties DNSHostName |
Where DNSHostName |
Select -Expand DNSHostName |
Sort -Unique |
Set-Content "$out\\AD_Target_Hostnames.txt"`
    },
    {
      id: 'ps-ad-dns-resolve',
      label: 'PowerShell legacy - resolve selected hostnames to IPs',
      platform: 'powershell-legacy',
      category: 'AD',
      needsTargets: true,
      help: 'Typed interactive PowerShell only. Resolves selected hostnames and exports a CSV.',
      build: ctx => `$out="$env:USERPROFILE\\Desktop"
${ctx.psTargetBlock}
Get-Content "$out\\SAS_QR_Targets.txt" |
ForEach {
  try {
    [pscustomobject]@{Host=$_;IP=(Resolve-DnsName $_ -Type A -ErrorAction Stop | Select -First 1 -Expand IPAddress)}
  } catch {
    [pscustomobject]@{Host=$_;IP=$null}
  }
} | Export-Csv "$out\\AD_Target_DNS_Resolution.csv" -NoTypeInformation`
    },
    {
      id: 'ps-cim-serials',
      label: 'PowerShell legacy - live CIM serial sweep from targets',
      platform: 'powershell-legacy',
      category: 'Hardware',
      needsTargets: true,
      help: 'Typed interactive PowerShell only. Live endpoint query. Offline devices and blocked CIM return denied/unreachable.',
      build: ctx => `$out="$env:USERPROFILE\\Desktop"
${ctx.psTargetBlock}
Get-Content "$out\\SAS_QR_Targets.txt" |
ForEach {
  try {
    Get-CimInstance -ComputerName $_ -Class Win32_BIOS -ErrorAction Stop | Select PSComputerName,SerialNumber
  } catch {
    [pscustomobject]@{PSComputerName=$_;SerialNumber="UNREACHABLE_OR_DENIED"}
  }
} | Export-Csv "$out\\Live_CIM_Serials.csv" -NoTypeInformation`
    },
    {
      id: 'custom',
      label: 'Custom payload - paste/type exact text',
      platform: 'custom',
      category: 'Custom',
      needsTargets: false,
      help: 'Use for approved one-liners, target notes, asset IDs, or other plain text payloads.',
      build: ctx => ctx.customText.trim()
    }
  ];

  function boot() {
    injectCss();
    injectQrTab();
    ensureQrLibrary();
    renderQrPanel();
    bindEvents();
    refreshHelpAndPayload();
  }

  function injectQrTab() {
    const tabs = document.getElementById('tabs');
    const content = document.getElementById('content');
    if (!tabs || !content || document.querySelector('[data-tab="qr"]')) return;

    const btn = document.createElement('button');
    btn.className = 'tab-btn';
    btn.dataset.tab = 'qr';
    btn.innerHTML = '▣ QR Builder<span class="tab-badge">' + TEMPLATES.length + '</span>';

    const networkTab = tabs.querySelector('[data-tab="network"]');
    tabs.insertBefore(btn, networkTab || null);

    const panel = document.createElement('div');
    panel.className = 'panel';
    panel.dataset.panel = 'qr';
    panel.id = 'panel-qr';

    const networkPanel = content.querySelector('[data-panel="network"]');
    content.insertBefore(panel, networkPanel || null);

    btn.addEventListener('click', function () {
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === 'qr'));
      document.querySelectorAll('.panel').forEach(p => p.classList.toggle('active', p.dataset.panel === 'qr'));
    });
  }

  function renderQrPanel() {
    const panel = document.getElementById('panel-qr');
    if (!panel) return;

    panel.innerHTML = `
      <div class="summary-row">
        <div class="stat-chip stat-success"><span class="stat-num">Bash</span><span class="stat-label">Preferred</span></div>
        <div class="stat-chip stat-warning"><span class="stat-num">PS</span><span class="stat-label">Legacy typed payloads</span></div>
        <div class="stat-chip stat-info"><span class="stat-num">${TEMPLATES.length}</span><span class="stat-label">Use cases</span></div>
      </div>

      <div class="panel-toolbar">
        <span class="panel-title">QR Payload Builder</span>
        <div class="toolbar-sep"></div>
        <button class="icon-btn" id="qr-copy-payload">📋 Copy Payload</button>
        <button class="icon-btn" id="qr-download-payload">⬇ Payload TXT</button>
        <button class="icon-btn" id="qr-show-large">▣ Show Large QR</button>
      </div>

      <div class="qr-grid">
        <section class="qr-card">
          <h3>1. Choose cmdlet / use case</h3>
          <label class="qr-label" for="qr-template-select">Desired payload</label>
          <select class="filter-select qr-full" id="qr-template-select">
            ${TEMPLATES.map(t => '<option value="' + esc(t.id) + '">' + esc(t.label) + '</option>').join('')}
          </select>
          <div class="qr-help" id="qr-template-help"></div>

          <label class="qr-label" for="qr-prefixes">AD name prefixes, comma separated</label>
          <input class="qr-input" id="qr-prefixes" value="CYB*,*CYBER*,WNH*,WMH*" spellcheck="false">

          <label class="qr-label" for="qr-custom-text">Custom payload text</label>
          <textarea class="qr-textarea" id="qr-custom-text" placeholder="Used only when Custom payload is selected."></textarea>
        </section>

        <section class="qr-card">
          <h3>2. Pick targets from directory</h3>
          <div class="qr-dir-note">Technician target-list directory: <code>${esc(TARGET_DIR_STANDARD)}</code></div>
          <p class="qr-muted">Put <code>.txt</code> or <code>.csv</code> target lists there. Browser security requires manual folder selection.</p>
          <div class="qr-row">
            <button class="btn-secondary" id="qr-choose-dir">📁 Choose Target Directory</button>
            <button class="btn-secondary" id="qr-clear-targets">Clear Targets</button>
          </div>
          <label class="qr-label" for="qr-target-file">Target file in chosen directory</label>
          <select class="filter-select qr-full" id="qr-target-file" disabled><option>No target directory selected</option></select>
          <label class="qr-label" for="qr-targets">Targets loaded into payload</label>
          <textarea class="qr-textarea qr-targets" id="qr-targets" placeholder="Hostnames or IPs, one per line. You can paste directly here too."></textarea>
          <div class="qr-target-count" id="qr-target-count">0 targets loaded</div>
        </section>

        <section class="qr-card qr-preview-card">
          <h3>3. Preview exact payload</h3>
          <div class="qr-warn" id="qr-warn"></div>
          <textarea class="qr-preview" id="qr-payload-preview" readonly></textarea>
        </section>

        <section class="qr-card qr-scan-card">
          <h3>4. Scan</h3>
          <canvas id="qr-inline-canvas" width="280" height="280"></canvas>
          <p class="qr-muted">Generated locally in the dashboard. Scan to paste the selected payload into an approved admin shell.</p>
        </section>
      </div>`;
  }

  function bindEvents() {
    on('qr-template-select', 'change', refreshHelpAndPayload);
    on('qr-prefixes', 'input', refreshHelpAndPayload);
    on('qr-custom-text', 'input', refreshHelpAndPayload);
    on('qr-targets', 'input', function () { selectedTargets = parseTargets(valueOf('qr-targets')); refreshHelpAndPayload(); });
    on('qr-choose-dir', 'click', chooseTargetDirectory);
    on('qr-clear-targets', 'click', clearTargets);
    on('qr-target-file', 'change', loadSelectedTargetFile);
    on('qr-copy-payload', 'click', copyPayload);
    on('qr-download-payload', 'click', downloadPayload);
    on('qr-show-large', 'click', showLargeQr);
  }

  function on(id, event, handler) {
    const el = document.getElementById(id);
    if (el) el.addEventListener(event, handler);
  }

  function valueOf(id) {
    const el = document.getElementById(id);
    return el ? el.value : '';
  }

  async function chooseTargetDirectory() {
    if (!('showDirectoryPicker' in window)) {
      say('Directory picking requires Chrome or Edge 86+. Paste targets directly instead.', 'warning');
      return;
    }

    try {
      directoryHandle = await window.showDirectoryPicker({ mode: 'read' });
    } catch (err) {
      if (err.name !== 'AbortError') say('Could not open target directory: ' + err.message, 'error');
      return;
    }

    targetFiles = [];
    for await (const entry of directoryHandle.values()) {
      if (entry.kind !== 'file') continue;
      if (!/\.(txt|csv)$/i.test(entry.name)) continue;
      targetFiles.push({ name: entry.name, handle: entry });
    }
    targetFiles.sort((a, b) => a.name.localeCompare(b.name));
    renderTargetFilePicker();

    if (targetFiles.length) say(`Loaded target directory ${directoryHandle.name} (${targetFiles.length} file(s)).`, 'success');
    else say(`Loaded ${directoryHandle.name}, but no .txt or .csv target files were found.`, 'warning');
  }

  function renderTargetFilePicker() {
    const select = document.getElementById('qr-target-file');
    if (!select) return;
    select.disabled = targetFiles.length === 0;
    if (!targetFiles.length) {
      select.innerHTML = '<option>No .txt or .csv files found</option>';
      return;
    }
    select.innerHTML = '<option value="">Select a target file...</option>' +
      targetFiles.map((f, idx) => `<option value="${idx}">${esc(f.name)}</option>`).join('');
  }

  async function loadSelectedTargetFile() {
    const idx = Number(valueOf('qr-target-file'));
    if (!Number.isInteger(idx) || idx < 0 || idx >= targetFiles.length) return;

    try {
      const file = await targetFiles[idx].handle.getFile();
      const text = await file.text();
      selectedTargets = parseTargets(text);
      const box = document.getElementById('qr-targets');
      if (box) box.value = selectedTargets.join('\n');
      refreshHelpAndPayload();
      say(`Loaded ${selectedTargets.length} target(s) from ${targetFiles[idx].name}.`, selectedTargets.length ? 'success' : 'warning');
    } catch (err) {
      say('Could not read target file: ' + err.message, 'error');
    }
  }

  function parseTargets(text) {
    const rows = String(text || '')
      .replace(/^\uFEFF/, '')
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(line => line && !line.startsWith('#'));

    const targets = [];
    for (const row of rows) {
      let value = row.includes(',') ? row.split(',')[0].trim() : row;
      value = value.replace(/^["']|["']$/g, '').trim();
      if (/^(host|hostname|computer|computername|target|ip|ipaddress)$/i.test(value)) continue;
      const safe = value.replace(/[^a-zA-Z0-9.\-:_]/g, '');
      if (safe) targets.push(safe);
    }
    return Array.from(new Set(targets));
  }

  function clearTargets() {
    selectedTargets = [];
    const box = document.getElementById('qr-targets');
    if (box) box.value = '';
    refreshHelpAndPayload();
  }

  function selectedTemplate() {
    const id = valueOf('qr-template-select') || TEMPLATES[0].id;
    return TEMPLATES.find(t => t.id === id) || TEMPLATES[0];
  }

  function refreshHelpAndPayload() {
    const template = selectedTemplate();
    const help = document.getElementById('qr-template-help');
    const count = document.getElementById('qr-target-count');
    if (count) count.textContent = selectedTargets.length + ' target' + (selectedTargets.length === 1 ? '' : 's') + ' loaded';

    if (help) {
      help.innerHTML = '<strong>' + esc(template.category) + '</strong> - ' + esc(template.help) +
        (template.platform === 'powershell-legacy'
          ? '<div class="qr-legacy">PowerShell legacy typed payload. Use only where interactive PowerShell is approved.</div>'
          : '');
    }
    updatePayloadPreview();
  }

  async function updatePayloadPreview() {
    const warn = document.getElementById('qr-warn');
    const preview = document.getElementById('qr-payload-preview');
    const canvas = document.getElementById('qr-inline-canvas');
    const template = selectedTemplate();

    let payload = buildPayload(template);
    if (!payload && template.needsTargets) {
      setWarn('This use case needs targets. Choose the target directory, select a file, or paste targets manually.');
      if (preview) preview.value = '';
      clearCanvas(canvas);
      lastPayload = '';
      return;
    }
    if (!payload) {
      setWarn('No payload yet.');
      if (preview) preview.value = '';
      clearCanvas(canvas);
      lastPayload = '';
      return;
    }

    if (payload.length > QR_MAX_PAYLOAD) {
      payload = payload.slice(0, QR_MAX_PAYLOAD);
      setWarn(`Payload truncated to ${QR_MAX_PAYLOAD} characters so scanners do not choke. Use fewer targets or download the TXT payload.`);
    } else {
      setWarn('');
    }

    lastPayload = payload;
    if (preview) preview.value = payload;
    await renderQr(canvas, payload, 280);

    function setWarn(text) { if (warn) warn.textContent = text; }
  }

  function buildPayload(template) {
    if (template.needsTargets && selectedTargets.length === 0) return '';
    return template.build({
      bashTargetBlock: selectedTargets.map(t => `printf '%s\\n' '${shellSingle(t)}' >> /tmp/sas-qr/targets.txt`).join('\n'),
      psTargetBlock: `@'\n${selectedTargets.join('\n')}\n'@ | Set-Content "$env:USERPROFILE\\Desktop\\SAS_QR_Targets.txt"`,
      psFilter: buildPsFilter(),
      customText: valueOf('qr-custom-text')
    });
  }

  function buildPsFilter() {
    const raw = valueOf('qr-prefixes') || 'CYB*,*CYBER*,WNH*,WMH*';
    const prefixes = raw.split(',')
      .map(p => p.trim())
      .filter(Boolean)
      .map(p => p.replace(/[^a-zA-Z0-9*?_ -]/g, '').replace(/\?/g, '*').replace(/\s+/g, ''))
      .filter(Boolean);
    return (prefixes.length ? prefixes : ['CYB*', '*CYBER*', 'WNH*', 'WMH*'])
      .map(p => `Name -like '${p}'`).join(' -or ');
  }

  function shellSingle(text) {
    return String(text).replace(/'/g, `'\\''`);
  }

  async function ensureQrLibrary() {
    if (window.QRCode && typeof window.QRCode.toCanvas === 'function') return true;
    if (qrLibraryLoadStarted) return false;
    qrLibraryLoadStarted = true;

    try {
      await loadScript(QR_LOCAL_LIB);
    } catch (_) {
      try { await loadScript(QR_CDN_LIB); }
      catch (err) { console.warn('QR library unavailable:', err); return false; }
    }
    updatePayloadPreview();
    return !!(window.QRCode && typeof window.QRCode.toCanvas === 'function');
  }

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = src;
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  async function renderQr(canvas, payload, size) {
    if (!canvas) return;
    if (!(window.QRCode && typeof window.QRCode.toCanvas === 'function')) {
      await ensureQrLibrary();
    }
    if (window.QRCode && typeof window.QRCode.toCanvas === 'function') {
      try {
        await window.QRCode.toCanvas(canvas, payload, { width: size, margin: 1, errorCorrectionLevel: 'M' });
        return;
      } catch (err) {
        console.warn('QR render failed:', err);
      }
    }
    drawQrUnavailable(canvas);
  }

  function clearCanvas(canvas) {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
  }

  function drawQrUnavailable(canvas) {
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#111827';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#f59e0b';
    ctx.font = '13px Consolas, monospace';
    ctx.fillText('QR library unavailable', 18, 40);
    ctx.fillStyle = '#d1d5db';
    ctx.font = '11px Consolas, monospace';
    wrapText(ctx, 'Add dashboard/js/vendor/qrcode.min.js for offline QR rendering, or allow the CDN fallback.', 18, 70, canvas.width - 36, 16);
  }

  function wrapText(ctx, text, x, y, maxWidth, lineHeight) {
    const words = text.split(/\s+/);
    let line = '';
    for (const word of words) {
      const next = line ? line + ' ' + word : word;
      if (ctx.measureText(next).width > maxWidth && line) {
        ctx.fillText(line, x, y);
        y += lineHeight;
        line = word;
      } else {
        line = next;
      }
    }
    if (line) ctx.fillText(line, x, y);
  }

  async function copyPayload() {
    if (!lastPayload) await updatePayloadPreview();
    if (!lastPayload) return say('No QR payload to copy yet.', 'warning');
    try {
      await navigator.clipboard.writeText(lastPayload);
      say('QR payload copied.', 'success');
    } catch (_) {
      say('Clipboard blocked. Select the preview text and copy manually.', 'warning');
    }
  }

  async function downloadPayload() {
    if (!lastPayload) await updatePayloadPreview();
    if (!lastPayload) return say('No QR payload to download yet.', 'warning');
    const t = selectedTemplate();
    downloadBlob(new Blob([lastPayload], { type: 'text/plain;charset=utf-8' }), `sas-qr-${t.id}.txt`);
  }

  async function showLargeQr() {
    if (!lastPayload) await updatePayloadPreview();
    if (!lastPayload) return say('No QR payload to show yet.', 'warning');

    const prior = document.getElementById('qr-large-modal');
    if (prior) prior.remove();

    const t = selectedTemplate();
    const modal = document.createElement('div');
    modal.id = 'qr-large-modal';
    modal.className = 'modal-backdrop';
    modal.innerHTML = `
      <div class="modal qr-large-modal">
        <div class="modal-header">
          <div>
            <span class="modal-title">▣ QR Payload - ${esc(t.label)}</span>
            <div class="modal-label">Generated locally. Scan to paste into an approved admin shell.</div>
          </div>
          <button class="modal-close" id="qr-large-close">×</button>
        </div>
        <div class="modal-body qr-large-body">
          <canvas id="qr-large-canvas" width="520" height="520"></canvas>
          <textarea class="qr-preview qr-large-preview" readonly>${esc(lastPayload)}</textarea>
        </div>
        <div class="modal-footer">
          <button class="btn-secondary" id="qr-large-copy">Copy Payload</button>
          <button class="btn-secondary" id="qr-large-download-png">Download PNG</button>
          <button class="btn-primary" id="qr-large-dismiss">Close</button>
        </div>
      </div>`;
    document.body.appendChild(modal);

    const canvas = document.getElementById('qr-large-canvas');
    await renderQr(canvas, lastPayload, 520);

    const close = () => modal.remove();
    on('qr-large-close', 'click', close);
    on('qr-large-dismiss', 'click', close);
    on('qr-large-copy', 'click', copyPayload);
    on('qr-large-download-png', 'click', function () {
      canvas.toBlob(blob => {
        if (!blob) return say('Could not export QR PNG.', 'error');
        downloadBlob(blob, `sas-qr-${t.id}.png`);
      }, 'image/png');
    });
    modal.addEventListener('click', e => { if (e.target === modal) close(); });
  }

  function downloadBlob(blob, name) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    a.click();
    URL.revokeObjectURL(url);
  }

  function say(message, type) {
    if (typeof window.toast === 'function') return window.toast(message, type || 'info');
    const existing = document.getElementById('toast-container');
    if (existing) {
      const t = document.createElement('div');
      t.className = 'toast toast-' + (type || 'info');
      t.textContent = message;
      existing.appendChild(t);
      setTimeout(() => t.remove(), 4000);
    } else {
      console.log('[QR]', message);
    }
  }

  function esc(value) {
    return String(value ?? '').replace(/[&<>'"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[ch]));
  }

  function injectCss() {
    if (document.getElementById('qr-builder-css')) return;
    const style = document.createElement('style');
    style.id = 'qr-builder-css';
    style.textContent = `
      .qr-grid{flex:1;overflow:auto;padding:14px 18px;display:grid;grid-template-columns:minmax(280px,.9fr) minmax(320px,1fr);gap:14px;background:var(--bg)}
      .qr-card{background:var(--bg2);border:1px solid var(--border);border-radius:10px;padding:14px;min-width:0}
      .qr-card h3{font-size:13px;margin-bottom:10px;color:var(--text)}
      .qr-label{display:block;font-size:11px;color:var(--text-dim);margin:10px 0 5px}.qr-full{width:100%}
      .qr-input,.qr-textarea,.qr-preview{width:100%;padding:9px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:6px;color:var(--text);font-family:var(--mono);font-size:11px;outline:none}
      .qr-textarea{min-height:88px;resize:vertical}.qr-targets{min-height:150px}.qr-preview-card{grid-column:1/span 2}.qr-preview{min-height:260px;resize:vertical;white-space:pre}
      .qr-scan-card{display:flex;flex-direction:column;align-items:center}#qr-inline-canvas,#qr-large-canvas{background:#fff;border:1px solid var(--border);border-radius:8px;padding:8px;max-width:100%}
      .qr-dir-note{padding:8px 10px;border:1px solid rgba(79,142,247,.35);background:rgba(79,142,247,.08);border-radius:6px;font-size:11px;color:var(--text-dim)}
      .qr-muted{color:var(--text-muted);font-size:11px;margin-top:8px}.qr-row{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}.qr-help{margin-top:8px;font-size:11px;color:var(--text-dim)}.qr-legacy{margin-top:6px;color:var(--warning)}
      .qr-warn{min-height:18px;color:var(--warning);font-size:11px;margin-bottom:6px}.qr-target-count{margin-top:6px;color:var(--text-muted);font-size:11px;font-family:var(--mono)}
      .qr-large-modal{width:960px;max-width:98vw}.qr-large-body{display:grid;grid-template-columns:540px minmax(260px,1fr);gap:14px;align-items:start}.qr-large-preview{min-height:520px}
      @media(max-width:900px){.qr-grid{grid-template-columns:1fr}.qr-preview-card{grid-column:auto}.qr-large-body{grid-template-columns:1fr}}
    `;
    document.head.appendChild(style);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
