# Test-Links.ps1
# HEAD checks every URL in fetch-map.csv
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
if (-not $repoHost -and (Test-Path $hostFile)) {
  $line = Get-Content $hostFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
  if ($line) { $repoHost = $line.Trim() }
}
if ([string]::IsNullOrWhiteSpace($repoHost)) {
  throw "Repo host is empty. Set REPO_HOST or provide a non-empty value in $hostFile."
}
. $tools -RepoHost $repoHost
try {
  $r = Test-FetchMap -RepoRoot $RepoRoot -HeadOnly
  $r.Results | Sort-Object Status | Format-Table Name,Status,FinalUrl,Error -Auto
  $csv = Join-Path $logs "Test-Links-Results-$stamp.csv"
  $html = [IO.Path]::ChangeExtension($csv, '.html')
  $rows = @($r.Results | Sort-Object Status,Name)
  $rows | Export-Csv -Path $csv -NoType
  $frag = $rows | Select-Object Name,Status,FinalUrl,Error | ConvertTo-Html -Fragment -PreContent '<h2>Fetch Map Link Validation</h2>'
  ConvertTo-SuiteHtml -Title 'Test Links' -Subtitle "RepoRoot: $RepoRoot" -SummaryChips @("Total: $($r.Total)", "Bad: $($r.Bad)") -BodyFragment $frag -OutputPath $html
  Write-Host "Wrote CSV: $csv" -ForegroundColor Green
  Write-Host "Wrote HTML: $html" -ForegroundColor Green
}
finally {
  Stop-Transcript | Out-Null
}