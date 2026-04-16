<# New-MappingReport.WCC.v2.ps1
   Read CentralResults.csv → normalize headers → enforce WCC naming rules →
   exec-ready HTML (KPIs, filter box, per-workstation groups, badges).
#>

[CmdletBinding()]
param(
  [string]$SearchRoot = ".\logs",  # repo default
  [string]$CentralPath,
  [string]$OutPath = ".\logs\Mapping.WCC.SMOKE.v2.$((Get-Date).ToString('yyyyMMdd-HHmmss')).html",
  [switch]$OpenWhenDone
)

$ErrorActionPreference = 'Stop'

# 1) Locate CentralResults.csv
if (-not $CentralPath) {
  $central = Get-ChildItem -Path $SearchRoot -Recurse -Filter CentralResults.csv |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $central) { throw "No CentralResults.csv found under $SearchRoot" }
  $CentralPath = $central.FullName
}
if (-not (Test-Path $CentralPath)) { throw "CentralResults.csv not found: $CentralPath" }

# 2) Import + normalize columns (tolerates worker variants)
$raw = Import-Csv $CentralPath
if (-not $raw -or $raw.Count -eq 0) { throw "CentralResults.csv has 0 rows: $CentralPath" }

function Get-ColValue($row, [string[]]$candidates) {
  foreach ($c in $candidates) { $v = $row.$c; if ($null -ne $v -and "$v") { return $v } }
  return $null
}

$reHost    = '^(?<Prefix>W)LS(?<Site>\d{3})WCC(?<Room>\d{3})$'              # WLS111WCC145
$rePrinter = '^\\\\(?<Server>[^\\]+)\\LS(?<Site>\d{3})-WCC(?<WCC>\d{2,3})'  # \\server\LS111-WCC61

function Normalize-WCC([string]$w){ if(-not $w){return $null}; ('{0:d3}' -f [int]$w) }

$rows = foreach ($r in $raw) {
  $host        = Get-ColValue $r @('Host','ComputerName','Workstation','Machine','PC','Device')
  $printerName = Get-ColValue $r @('PrinterName','QueueName','Target','Printer','SharePath')
  $driverName  = Get-ColValue $r @('DriverName','Driver')
  $portName    = Get-ColValue $r @('PortName','Port')
  $isDefault   = Get-ColValue $r @('IsDefault','Default','IsDefaultPrinter')
  $status      = Get-ColValue $r @('Status','Result','State'); if (-not $status) { $status = 'OK' }
  if (-not $host -and -not $printerName) { continue }

  $hm = [regex]::Match([string]$host,$reHost,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $pm = [regex]::Match([string]$printerName,$rePrinter,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

  $hSite = if($hm.Success){ $hm.Groups['Site'].Value } else { $null }
  $hRoom = if($hm.Success){ $hm.Groups['Room'].Value } else { $null }

  $prnServer = if($pm.Success){ $pm.Groups['Server'].Value } else { $null }
  $pSiteRaw  = if($pm.Success){ $pm.Groups['Site'].Value } else { $null }
  $pWCCRaw   = if($pm.Success){ $pm.Groups['WCC'].Value } else { $null }
  $pSite     = $pSiteRaw
  $pWCC      = Normalize-WCC $pWCCRaw

  $siteOK = ($hSite -and $pSite -and ($hSite -eq $pSite))
  $roomOK = ($hRoom -and $pWCC  -and ($hRoom -eq $pWCC))
  $health = if($siteOK -and $roomOK){'OK'}
            elseif($siteOK){'SiteOK/RoomMismatch'}
            elseif($roomOK){'RoomOK/SiteMismatch'}
            else{'Mismatch'}

  [pscustomobject]@{
    Workstation = $host
    HostSite    = $hSite
    HostRoomWCC = $hRoom
    Printer     = $printerName
    Server      = $prnServer
    PrnSite     = $pSite
    PrnWCC      = $pWCC
    Driver      = $driverName
    Port        = $portName
    Default     = if("$isDefault" -match '^(True|Yes|1)$'){ '✓' } else { '' }
    Status      = $status
    Health      = $health
  }
}

if (-not $rows -or $rows.Count -eq 0) {
  throw "After normalization, 0 usable rows remained. Check column names in $CentralPath."
}

# 3) KPIs
$totalPrinters = $rows.Count
$totalHosts    = ($rows.Workstation | Sort-Object -Unique).Count
$ok            = ($rows | ? Health -eq 'OK').Count
$warn          = ($rows | ? { $_.Health -in 'SiteOK/RoomMismatch','RoomOK/SiteMismatch' }).Count
$bad           = ($rows | ? Health -eq 'Mismatch').Count

# 4) HTML (clean, grouped, filter box)
$css = @"
:root{--ok:#0a7c2f;--warn:#b58900;--bad:#c0392b;--ink:#0f172a}
body{font-family:Segoe UI,Arial,sans-serif;margin:18px;color:#0b0b0b}
h1{margin:0 0 12px 0;font-size:22px}
.kpis{display:flex;gap:12px;margin:8px 0 16px 0}
.kpi{padding:10px 12px;border-radius:10px;background:#f6f6f8;border:1px solid #e6e6eb}
.kpi b{font-size:18px}
.filter{margin:6px 0 12px 0}
input[type=search]{width:360px;padding:8px 10px;border:1px solid #c9c9cf;border-radius:8px}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #e5e7eb;padding:6px 8px;font-size:12px}
th{background:#111;color:#fff;position:sticky;top:0}
tbody tr:nth-child(even){background:#f9fafb}
.badge{padding:2px 8px;border-radius:999px;color:#fff;font-weight:600;display:inline-block}
.ok{background:var(--ok)} .warn{background:var(--warn)} .bad{background:var(--bad)}
.group{margin:18px 0 28px;border:1px solid #e5e7eb;border-radius:10px;overflow:hidden}
.group h3{margin:0;padding:10px 12px;background:#0f172a;color:#fff;font-size:14px}
.small{color:#475569}
.footer{margin-top:18px;color:#475569;font-size:12px}
code{background:#eef2ff;padding:1px 6px;border-radius:6px}
"@

$js = @"
function f(){const q=document.getElementById('q').value.toLowerCase();
  document.querySelectorAll('tbody tr').forEach(tr=>{
    const t=tr.textContent.toLowerCase();
    tr.style.display = t.indexOf(q)===-1 ? 'none' : '';
  });
}
"@

$head = "<meta charset='utf-8'><title>WCC Mapping</title><style>$css</style><script>$js</script>"
$pre  = @"
<h1>Workstation ↔ Printers (WCC)</h1>
<div class='kpis'>
  <div class='kpi'><div class='small'>Workstations</div><b>$totalHosts</b></div>
  <div class='kpi'><div class='small'>Printers</div><b>$totalPrinters</b></div>
  <div class='kpi'><div class='small'>OK</div><span class='badge ok'>$ok</span></div>
  <div class='kpi'><div class='small'>Warnings</div><span class='badge warn'>$warn</span></div>
  <div class='kpi'><div class='small'>Mismatches</div><span class='badge bad'>$bad</span></div>
</div>
<div class='filter'>
  <input id='q' type='search' placeholder='Filter by workstation, queue, server, room…' oninput='f()'>
</div>
<div class='small'>Source: $([System.Web.HttpUtility]::HtmlEncode($CentralPath)) — Generated: $(Get-Date)</div>
"@

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("<html><head>$head</head><body>$pre")

$groups = $rows | Sort-Object Workstation, Printer | Group-Object Workstation
foreach($g in $groups){
  $ws = $g.Name
  $first = $g.Group | Select-Object -First 1
  $hdr = "$ws  •  Site $($first.HostSite)  •  Room/WCC $($first.HostRoomWCC)"
  [void]$sb.Append("<div class='group'><h3>$hdr</h3><table><thead><tr>
    <th>Printer</th><th>Server</th><th>PrnSite</th><th>PrnWCC</th><th>Driver</th>
    <th>Port</th><th>Default</th><th>Status</th><th>Check</th></tr></thead><tbody>")
  foreach($r in $g.Group){
    $badge = switch ($r.Health) {
      'OK'                   { "<span class='badge ok'>OK</span>" }
      'SiteOK/RoomMismatch'  { "<span class='badge warn'>SiteOK / RoomMismatch</span>" }
      'RoomOK/SiteMismatch'  { "<span class='badge warn'>RoomOK / SiteMismatch</span>" }
      default                { "<span class='badge bad'>Mismatch</span>" }
    }
    $rowHtml = "<tr><td>$($r.Printer)</td><td>$($r.Server)</td><td>$($r.PrnSite)</td>
                <td>$($r.PrnWCC)</td><td>$($r.Driver)</td><td>$($r.Port)</td>
                <td style='text-align:center'>$($r.Default)</td><td>$($r.Status)</td><td>$badge</td></tr>"
    [void]$sb.Append($rowHtml)
  }
  [void]$sb.Append("</tbody></table></div>")
}
[void]$sb.Append("<div class='footer'>Rules: <code>WLS###WCC###</code> (PC), <code>\\server\LS###-WCC###</code> (queue). Case-insensitive servers.</div></body></html>")

$null = New-Item -ItemType Directory -Path (Split-Path $OutPath) -Force
$sb.ToString() | Out-File -Encoding UTF8 $OutPath
Write-Host "HTML report: $OutPath"
if ($OpenWhenDone) { Start-Process $OutPath | Out-Null }
