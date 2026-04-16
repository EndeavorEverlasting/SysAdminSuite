# .\mapping\New-MappingReport.WCC.ps1
param(
  [string]$SearchRoot = ".\mapping\logs",
  [string]$OutPath = ".\mapping\logs\Mapping.SMOKE.WCC.$((Get-Date).ToString('yyyyMMdd-HHmmss')).html"
)

# 1) Pull freshest rollup
$csv = Get-ChildItem -Path $SearchRoot -Recurse -Filter CentralResults.csv |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $csv) { throw "No CentralResults.csv under $SearchRoot" }
$data = Import-Csv $csv.FullName

# 2) Parsers locked to your conventions
$reHost    = '^(?<Prefix>W)LS(?<Site>\d{3})WCC(?<Room>\d{3})$'           # e.g. WLS111WCC145
$rePrinter = '^\\\\(?<Server>[^\\]+)\\LS(?<Site>\d{3})-WCC(?<WCC>\d{2,3})$' # e.g. \\swbpnshps01v\LS111-WCC61

function Normalize-WCC([string]$w){ if(-not $w){return $null}; ('{0:d3}' -f [int]$w) }

# 3) Derive fields + health
$enriched = foreach($row in $data){
  $host = [string]$row.Host
  $p    = [string]$row.PrinterName

  $hm = [regex]::Match($host,$reHost,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $pm = [regex]::Match($p,$rePrinter,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

  $hSite = if($hm.Success){ $hm.Groups['Site'].Value } else { $null }
  $hRoom = if($hm.Success){ $hm.Groups['Room'].Value } else { $null }

  $prnServer = if($pm.Success){ $pm.Groups['Server'].Value } else { $null }
  $pSiteRaw  = if($pm.Success){ $pm.Groups['Site'].Value } else { $null }
  $pWCCRaw   = if($pm.Success){ $pm.Groups['WCC'].Value } else { $null }

  $pSite = $pSiteRaw
  $pWCC  = Normalize-WCC $pWCCRaw

  # Rules:
  #  R1: Site must match (111 == 111)
  #  R2: WCC should usually match host room (e.g., 145 ↔ 145); tolerate nulls.
  $r1 = ($hSite -and $pSite -and ($hSite -eq $pSite))
  $r2 = ($hRoom -and $pWCC  -and ($hRoom -eq $pWCC))

  $health =
    if($r1 -and $r2){ 'OK' }
    elseif($r1 -and -not $r2){ 'SiteOK/RoomMismatch' }
    elseif(-not $r1 -and $r2){ 'RoomOK/SiteMismatch' }
    else{ 'Mismatch' }

  [pscustomobject]@{
    Workstation    = $host
    HostSite       = $hSite
    HostRoomWCC    = $hRoom
    Printer        = $p
    Server         = $prnServer
    PrnSite        = $pSite
    PrnWCC         = $pWCC
    Driver         = $row.DriverName
    Port           = $row.PortName
    Default        = if("$($row.IsDefault)" -match '^(True|Yes|1)$'){ '✓' } else { '' }
    Status         = $row.Status
    Health         = $health
  }
}

# 4) HTML (grouped by workstation; mismatches pop)
$css = @"
:root{--ok:#0a7c2f;--warn:#b58900;--bad:#c0392b;--ink:#111}
body{font-family:'Segoe UI',Arial,sans-serif;margin:16px}
h2{margin:8px 0 16px 0}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:6px 8px;font-size:12px}
th{background:var(--ink);color:#eee;position:sticky;top:0}
tr:nth-child(even){background:#f6f6f6}
.badge{padding:2px 6px;border-radius:10px;color:#fff;font-weight:600}
.ok{background:var(--ok)}
.warn{background:var(--warn)}
.bad{background:var(--bad)}
code{background:#f5f5f5;padding:1px 4px;border-radius:6px}
"@

function Get-Badge([string]$h){
  switch ($h){
    'OK'                   { "<span class='badge ok'>OK</span>" }
    'SiteOK/RoomMismatch'  { "<span class='badge warn'>SiteOK / RoomMismatch</span>" }
    'RoomOK/SiteMismatch'  { "<span class='badge warn'>RoomOK / SiteMismatch</span>" }
    default                { "<span class='badge bad'>Mismatch</span>" }
  }
}

$rows =
  $enriched |
  Sort-Object Workstation, Printer |
  Select-Object Workstation,HostSite,HostRoomWCC,Printer,Server,PrnSite,PrnWCC,Driver,Port,Default,Status,@{n='Check';e={ Get-Badge $_.Health }}

$head = "<meta charset='utf-8'><title>WCC Mapping</title><style>$css</style>"
$pre  = "<h2>Workstation ↔ Printers (WCC) — Source: $([System.Web.HttpUtility]::HtmlEncode($csv.FullName)) — Generated: $(Get-Date)</h2>
<p>Naming rules enforced: <code>WLS###WCC###</code> for PCs; <code>\\\\server\\LS###-WCC###[…]</code> for printers. Case-insensitive server names normalized.</p>"

$rows | ConvertTo-Html -Head $head -PreContent $pre -Property Workstation,HostSite,HostRoomWCC,Printer,Server,PrnSite,PrnWCC,Driver,Port,Default,Status,Check |
  Out-File -Encoding UTF8 $OutPath

Write-Host "HTML ready: $OutPath"
