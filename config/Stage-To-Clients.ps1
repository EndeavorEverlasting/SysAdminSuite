# Stage-To-Clients.ps1
# Mirrors the depot to target PCs (uses Clients.txt)
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
  $clientsPath = Join-Path $here 'Clients.txt'
  if (-not (Test-Path $clientsPath)) { throw "Missing Clients.txt at $clientsPath" }
  $pcs = Get-Content $clientsPath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
  if (-not $pcs -or $pcs.Count -eq 0) {
    throw "No valid client names were found in $clientsPath. `$pcs is empty."
  }
  $copyResults = @(Copy-SoftwareToClients -RepoRoot $RepoRoot -ComputerName $pcs -MaxParallel 8)

  $csv = Join-Path $logs ("Stage-To-Clients-Results-{0}.csv" -f $stamp)
  $html = [IO.Path]::ChangeExtension($csv, '.html')
  $copyResults | Sort-Object Computer | Export-Csv -Path $csv -NoType
  $frag = $copyResults | Select-Object Computer,ExitCode,Dest | Sort-Object Computer |
    ConvertTo-Html -Fragment -PreContent '<h2>Stage To Clients Results</h2>'
  ConvertTo-SuiteHtml -Title 'Stage To Clients' -Subtitle "RepoRoot: $RepoRoot" -SummaryChips @("Targets: $($pcs.Count)", "Results: $($copyResults.Count)") -BodyFragment $frag -OutputPath $html
  Write-Host "Wrote stage results CSV: $csv" -ForegroundColor Green
  Write-Host "Wrote stage results HTML: $html" -ForegroundColor Green
}
finally {
  Stop-Transcript | Out-Null
}