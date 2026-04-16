<#  Run-Mapping.WCC.Lite.ps1
    Purpose
      Fast printer mapping when ADMIN$ is blocked. Uses CIM/DCOM to read Win32_Printer
      from target hosts (no file copy, no Task Scheduler), then renders an exec HTML.

    Output
      .\logs\recon-YYYYMMDD-HHmmss\CentralResults.csv
      .\logs\Mapping.WCC.LITE.<label>.YYYYMMDD-HHmmss.html
      (optional) .\logs\Mapping.WCC.LITE.<label>.Pack.YYYYMMDD-HHmmss.zip

    Usage
      cd C:\Dev\SysAdminSuite\mapping
      .\Run-Mapping.WCC.Lite.ps1 -Hosts WLS111WCC009,WLS111WCC010,WLS111WCC011 -Label SMOKE -Package

      # or
      .\Run-Mapping.WCC.Lite.ps1 -HostsPath .\csv\hosts_smoke.txt -Label SMOKE -Package
#>

[CmdletBinding()]
param(
  [string[]]$Hosts,
  [string]  $HostsPath,
  [int]     $ThrottleLimit    = 8,
  [int]     $OperationTimeout = 20,   # seconds per RPC call
  [switch]  $Package,
  [string]  $Label = "SMOKE"
)

$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $PSCommandPath
$csvDir  = Join-Path $here 'csv'
$logsDir = Join-Path $here 'logs'
New-Item -ItemType Directory -Force -Path $csvDir,$logsDir | Out-Null

# --- Load hosts (inline or file) ------------------------------------------------
if ($Hosts -and -not $HostsPath) {
  $HostsPath = Join-Path $csvDir 'hosts_runtime.txt'
  $Hosts | Set-Content -Encoding UTF8 $HostsPath
}
if (-not $HostsPath) { throw "Provide -Hosts or -HostsPath." }
$HostsPath = (Resolve-Path $HostsPath).Path
$HostList  = Get-Content $HostsPath | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
if ($HostList.Count -eq 0) { throw "Hosts file is empty: $HostsPath" }
Write-Host "→ Hosts loaded: $($HostList.Count) from $HostsPath"

# --- Recon (CIM/DCOM) -----------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$recon = Join-Path $logsDir "recon-$stamp"
New-Item -ItemType Directory -Force -Path $recon | Out-Null

# DCOM to avoid WinRM requirements
$opt  = New-CimSessionOption -Protocol Dcom
$rows = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

$scriptBlock = {
  param($h,$OperationTimeoutSec)
  try {
    $sess = New-CimSession -ComputerName $h -SessionOption (New-CimSessionOption -Protocol Dcom)
    try {
      $printers = Get-CimInstance -CimSession $sess -ClassName Win32_Printer -OperationTimeoutSec $OperationTimeoutSec
      foreach($p in $printers){
        # Share/Name normalization (queue path when available)
        $queue = if ($p.Shared -and $p.ShareName) {
          "\\$($p.ServerName)\$($p.ShareName)"
        } else { [string]$p.Name }

        [pscustomobject]@{
          Host        = $h
          PrinterName = $queue
          DriverName  = [string]$p.DriverName
          PortName    = [string]$p.PortName
          IsDefault   = [bool]$p.Default
          Status      = if ($p.WorkOffline) { 'Offline' } else { 'OK' }
        }
      }
    }
    finally { if ($sess) { $sess | Remove-CimSession } }
  }
  catch {
    # One row to show failure on this host
    [pscustomobject]@{
      Host        = $h
      PrinterName = '(query failed)'
      DriverName  = ''
      PortName    = ''
      IsDefault   = $false
      Status      = $_.Exception.Message
    }
  }
}

$HostList | ForEach-Object -Parallel {
  using $scriptBlock
  $scriptBlock.Invoke($_, $using:OperationTimeout)
} -ThrottleLimit $ThrottleLimit | ForEach-Object { $rows.Add($_) }

# Persist raw per-host (optional, helps auditing)
$perHost = $rows.ToArray() | Group-Object Host
foreach($g in $perHost){
  $out = Join-Path $recon ("{0}_Results.csv" -f $g.Name)
  $g.Group | Export-Csv $out -NoTypeInformation -Encoding UTF8
}

# Roll-up
$central = Join-Path $recon 'CentralResults.csv'
$rows.ToArray() | Export-Csv $central -NoTypeInformation -Encoding UTF8
Write-Host "→ Central roll-up: $central"

# --- Renderer (embedded; no external dependency) --------------------------------
function Render-WCCHtml {
  param(
    [Parameter(Mandatory)] [string]$CentralCsv,
    [Parameter(Mandatory)] [string]$OutHtml,
    [string]$TitleSuffix = "LITE"
  )
  $data = Import-Csv $CentralCsv
  if (-not $data -or $data.Count -eq 0) { throw "CentralResults.csv has 0 rows: $CentralCsv" }

  # Regex rules
  $reHost    = '^(?<Prefix>W)LS(?<Site>\d{3})WCC(?<Room>\d{3})$'             # WLS111WCC145
  $rePrinter = '^\\\\(?<Server>[^\\]+)\\LS(?<Site>\d{3})-WCC(?<WCC>\d{2,3})' # \\server\LS111-WCC61
  function Normalize-WCC([string]$w){ if(-not $w){return $null}; '{0:d3}' -f ([int]$w) }

  $enriched = foreach($r in $data){
    $host = [string]$r.Host
    $p    = [string]$r.PrinterName
    if (-not $host -and -not $p) { continue }

    $hm=[regex]::Match($host,$reHost,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $pm=[regex]::Match($p,$rePrinter,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $hSite= if($hm.Success){$hm.Groups['Site'].Value}else{$null}
    $hRoom= if($hm.Success){$hm.Groups['Room'].Value}else{$null}
    $srv  = if($pm.Success){$pm.Groups['Server'].Value}else{$null}
    $pSite= if($pm.Success){$pm.Groups['Site'].Value}else{$null}
    $pWCC = if($pm.Success){ Normalize-WCC $pm.Groups['WCC'].Value }else{$null}

    $siteOK = ($hSite -and $pSite -and $hSite -eq $pSite)
    $roomOK = ($hRoom -and $pWCC  -and $hRoom -eq $pWCC)
    $health = if($siteOK -and $roomOK){'OK'}
              elseif($siteOK){'SiteOK/RoomMismatch'}
              elseif($roomOK){'RoomOK/SiteMismatch'}
              else{'Mismatch'}

    [pscustomobject]@{
      Workstation=$host; HostSite=$hSite; HostRoomWCC=$hRoom
      Printer=$p; Server=$srv; PrnSite=$pSite; PrnWCC=$pWCC
      Driver=$r.DriverName; Port=$r.PortName
      Default = if("$($r.IsDefault)" -match '^(True|Yes|1)$'){'✓'}else{''}
      Status  = $r.Status; Health=$health
    }
  }

  $totalPrinters = $enriched.Count
  $totalHosts    = ($enriched.Workstation | Sort-Object -Unique).Count
  $ok   = ($enriched | Where-Object Health -eq 'OK').Count
  $warn = ($enriched | Where-Object { $_.Health -in 'SiteOK/RoomMismatch','RoomOK/SiteMismatch'}).Count
  $bad  = ($enriched | Where-Object Health -eq 'Mismatch').Count

  $css = @"
:root{--ok:#0a7c2f;--warn:#b58900;--bad:#c0392b}
body{font-family:Segoe UI,Arial,sans-serif;margin:18px}
h1{margin:0 0 12px 0}
.kpis{display:flex;gap:12px;margin:8px 0 16px 0}
.kpi{padding:10px 12px;border:1px solid #e6e6eb;border-radius:10px;background:#f6f6f8}
.kpi b{font-size:18px}
.filter{margin:6px 0 12px 0}
input[type=search]{width:360px;padding:8px;border:1px solid #c9c9cf;border-radius:8px}
.group{margin:18px 0 28px;border:1px solid #e5e7eb;border-radius:10px;overflow:hidden}
.group h3{margin:0;padding:10px 12px;background:#0f172a;color:#fff;font-size:14px}
table{width:100%;border-collapse:collapse}
th,td{border:1px solid #e5e7eb;padding:6px 8px;font-size:12px}
th{background:#111;color:#fff;position:sticky;top:0}
tbody tr:nth-child(even){background:#f9fafb}
.badge{padding:2px 8px;border-radius:999px;color:#fff;font-weight:700}
.ok{background:var(--ok)} .warn{background:var(--warn)} .bad{background:var(--bad)}
.small{color:#475569} .footer{margin-top:18px;color:#475569;font-size:12px}
"@

  $js = @"
function f(){const q=document.getElementById('q').value.toLowerCase();
document.querySelectorAll('tbody tr').forEach(tr=>{
  const t=tr.textContent.toLowerCase(); tr.style.display = t.indexOf(q)===-1?'none':'';});
}
"@

  $head = "<meta charset='utf-8'><title>WCC Mapping ($TitleSuffix)</title><style>$css</style><script>$js</script>"
  $pre  = @"
<h1>Workstation ↔ Printers (WCC) — $TitleSuffix</h1>
<div class='kpis'>
  <div class='kpi'><div class='small'>Workstations</div><b>$totalHosts</b></div>
  <div class='kpi'><div class='small'>Printers</div><b>$totalPrinters</b></div>
  <div class='kpi'><div class='small'>OK</div><span class='badge ok'>$ok</span></div>
  <div class='kpi'><div class='small'>Warnings</div><span class='badge warn'>$warn</span></div>
  <div class='kpi'><div class='small'>Mismatches</div><span class='badge bad'>$bad</span></div>
</div>
<div class='filter'><input id='q' type='search' placeholder='Filter…' oninput='f()'></div>
<div class='small'>Source: $([System.Web.HttpUtility]::HtmlEncode($CentralCsv)) — Generated: $(Get-Date)</div>
"@

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("<html><head>$head</head><body>$pre")
  $groups = $enriched | Sort-Object Workstation,Printer | Group-Object Workstation
  foreach($g in $groups){
    $ws   = $g.Name
    $meta = $g.Group | Select-Object -First 1
    [void]$sb.Append("<div class='group'><h3>$ws • Site $($meta.HostSite) • Room/WCC $($meta.HostRoomWCC)</h3>
    <table><thead><tr><th>Printer</th><th>Server</th><th>PrnSite</th><th>PrnWCC</th>
    <th>Driver</th><th>Port</th><th>Default</th><th>Status</th><th>Check</th></tr></thead><tbody>")
    foreach($r in $g.Group){
      $badge = switch($r.Health){
        'OK' {'<span class="badge ok">OK</span>'}
        'SiteOK/RoomMismatch' {'<span class="badge warn">SiteOK / RoomMismatch</span>'}
        'RoomOK/SiteMismatch' {'<span class="badge warn">RoomOK / SiteMismatch</span>'}
        default {'<span class="badge bad">Mismatch</span>'}
      }
      [void]$sb.Append("<tr><td>$($r.Printer)</td><td>$($r.Server)</td><td>$($r.PrnSite)</td>
        <td>$($r.PrnWCC)</td><td>$($r.Driver)</td><td>$($r.Port)</td>
        <td style='text-align:center'>$($r.Default)</td><td>$($r.Status)</td><td>$badge</td></tr>")
    }
    [void]$sb.Append("</tbody></table></div>")
  }
  [void]$sb.Append("<div class='footer'>Rules: <code>WLS###WCC###</code> (PC), <code>\\server\LS###-WCC###</code> (queue).</div></body></html>")
  $sb.ToString() | Out-File -Encoding UTF8 $OutHtml
}

$outHtml = Join-Path $logsDir ("Mapping.WCC.LITE.{0}.{1}.html" -f $Label,(Get-Date).ToString('yyyyMMdd-HHmmss'))
Render-WCCHtml -CentralCsv $central -OutHtml $outHtml -TitleSuffix "LITE/$Label"
Write-Host "→ HTML report: $outHtml"

if ($Package) {
  $zip = Join-Path $logsDir ("Mapping.WCC.LITE.{0}.Pack.{1}.zip" -f $Label,(Get-Date).ToString('yyyyMMdd-HHmmss'))
  Compress-Archive -Path $outHtml,$central -DestinationPath $zip -Force
  Write-Host "→ Attach: $(Split-Path $outHtml -Leaf)  +  $(Split-Path $zip -Leaf)"
}
