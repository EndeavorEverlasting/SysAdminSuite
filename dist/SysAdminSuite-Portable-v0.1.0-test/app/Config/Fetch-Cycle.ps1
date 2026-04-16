# Fetch-Cycle.ps1
# Rebuild -> test -> fetch -> hash -> fill types
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

Preflight-Repo   -RepoRoot $RepoRoot
Rebuild-FetchMap -RepoRoot $RepoRoot
$r = Test-FetchMap -RepoRoot $RepoRoot -HeadOnly
$r.Results | Sort-Object Status | Format-Table Name,Status,FinalUrl,Error -Auto
$testCsv = Join-Path $logs ("Fetch-Cycle-TestLinks-{0}.csv" -f $stamp)
$testHtml = [IO.Path]::ChangeExtension($testCsv, '.html')
$rows = @($r.Results | Sort-Object Status,Name)
$rows | Export-Csv -Path $testCsv -NoTypeInformation -Encoding UTF8
$frag = $rows | Select-Object Name,Status,FinalUrl,Error | ConvertTo-Html -Fragment -PreContent '<h2>Fetch Cycle Link Validation</h2>'
ConvertTo-SuiteHtml -Title 'Fetch Cycle - Link Validation' -Subtitle "RepoRoot: $RepoRoot" -SummaryChips @("Total: $($r.Total)", "Bad: $($r.Bad)") -BodyFragment $frag -OutputPath $testHtml
Write-Host "Wrote link validation CSV: $testCsv" -ForegroundColor Green
Write-Host "Wrote link validation HTML: $testHtml" -ForegroundColor Green
Invoke-Fetch      -RepoRoot $RepoRoot -MaxParallel 4
New-RepoChecksums -RepoRoot $RepoRoot
Fill-PackagesTypes -RepoRoot $RepoRoot
Stop-Transcript | Out-Null