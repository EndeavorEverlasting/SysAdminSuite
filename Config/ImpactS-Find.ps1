# ImpactS-Find.ps1
# --- bootstrap ---
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$logs   = Join-Path $here 'Logs'; New-Item -ItemType Directory -Force -Path $logs | Out-Null
$stamp  = (Get-Date -Format 'yyyyMMdd_HHmmss')
$log    = Join-Path $logs ("{0}-{1}.log" -f ($MyInvocation.MyCommand.Name -replace '\.ps1$',''), $stamp)
Start-Transcript -Path $log -Append | Out-Null
$suiteHtml = Join-Path $here '..\tools\ConvertTo-SuiteHtml.ps1'
if (-not (Test-Path -LiteralPath $suiteHtml)) { throw "Missing ConvertTo-SuiteHtml.ps1 at $suiteHtml" }
. $suiteHtml
$tools = Join-Path $here 'GoLiveTools.ps1'
if (-not (Test-Path $tools)) { throw "Missing GoLiveTools.ps1 at $tools" }
$repoHost = $env:REPO_HOST
$hostFile = Join-Path $here 'RepoHost.txt'
if (-not $repoHost -and (Test-Path $hostFile)) { $repoHost = (Get-Content $hostFile | Select-Object -First 1).Trim() }
. $tools -RepoHost $repoHost

$clientsPath = Join-Path $here 'Clients.txt'
if (-not (Test-Path $clientsPath)) { throw "Missing Clients.txt at $clientsPath" }
$pcs = Get-Content $clientsPath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }

try {
  $impact = Get-ImpactS -ComputerName $pcs
  $csv = Join-Path $logs ("ImpactS-Inventory-{0}.csv" -f $stamp)
  $html = [IO.Path]::ChangeExtension($csv, '.html')

  # Flatten for CSV/HTML
  $rows = foreach($r in $impact){
    foreach($a in $r.ARP){
      [pscustomobject]@{ Computer=$r.ComputerName; Type='ARP'; Name=$a.DisplayName; Version=$a.Version; Path=$a.RegPath }
    }
    foreach($s in $r.Shortcuts){
      [pscustomobject]@{ Computer=$r.ComputerName; Type='Shortcut'; Name=(Split-Path $s.Shortcut -Leaf); Version=''; Path=$s.Target }
    }
  }

  $rows = @($rows | Sort-Object Computer,Type,Name)
  $rows | Export-Csv -Path $csv -NoType
  $frag = $rows | ConvertTo-Html -Fragment -PreContent '<h2>ImpactS Inventory</h2>'
  $chips = @(
    "Rows: $($rows.Count)"
    "Computers: $(($rows | Select-Object -ExpandProperty Computer -Unique).Count)"
  )
  ConvertTo-SuiteHtml -Title 'ImpactS Find' -Subtitle "$($pcs.Count) target(s)" -SummaryChips $chips -BodyFragment $frag -OutputPath $html

  Write-Host "Wrote ImpactS inventory CSV: $csv" -ForegroundColor Green
  Write-Host "Wrote ImpactS inventory HTML: $html" -ForegroundColor Green
}
finally {
  Stop-Transcript | Out-Null
}