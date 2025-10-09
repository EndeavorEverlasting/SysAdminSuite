# Run-Preflight.ps1
# Checks depot structure and warns on missing files
# [see bootstrap above]
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
  Preflight-Repo -RepoRoot $RepoRoot
  $rows = @(
    [pscustomobject]@{ Item='RepoRoot'; Path=$RepoRoot; Exists=(Test-Path -LiteralPath $RepoRoot) }
    [pscustomobject]@{ Item='installers'; Path=(Join-Path $RepoRoot 'installers'); Exists=(Test-Path -LiteralPath (Join-Path $RepoRoot 'installers')) }
    [pscustomobject]@{ Item='checksums'; Path=(Join-Path $RepoRoot 'checksums'); Exists=(Test-Path -LiteralPath (Join-Path $RepoRoot 'checksums')) }
    [pscustomobject]@{ Item='sources.csv'; Path=(Join-Path $RepoRoot 'sources.csv'); Exists=(Test-Path -LiteralPath (Join-Path $RepoRoot 'sources.csv')) }
    [pscustomobject]@{ Item='fetch-map.csv'; Path=(Join-Path $RepoRoot 'fetch-map.csv'); Exists=(Test-Path -LiteralPath (Join-Path $RepoRoot 'fetch-map.csv')) }
    [pscustomobject]@{ Item='packages.csv'; Path=(Join-Path $RepoRoot 'packages.csv'); Exists=(Test-Path -LiteralPath (Join-Path $RepoRoot 'packages.csv')) }
  )
  $csv = Join-Path $logs ("Run-Preflight-Results-{0}.csv" -f $stamp)
  $html = [IO.Path]::ChangeExtension($csv, '.html')
  $rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
  $frag = $rows | ConvertTo-Html -Fragment -PreContent '<h2>Repo Preflight Status</h2>'
  ConvertTo-SuiteHtml -Title 'Run Preflight' -Subtitle "RepoRoot: $RepoRoot" -SummaryChips @("Total checks: $($rows.Count)", "Missing: $(($rows | Where-Object { -not $_.Exists }).Count)") -BodyFragment $frag -OutputPath $html
  Write-Host "Wrote preflight CSV: $csv" -ForegroundColor Green
  Write-Host "Wrote preflight HTML: $html" -ForegroundColor Green
  Write-Host "Preflight complete. Logs: $log" -ForegroundColor Green
}
finally {
  Stop-Transcript | Out-Null
}