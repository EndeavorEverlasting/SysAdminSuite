<# Runbook-Inventory.ps1
   Inventory installed software on source/target -> Repo\inventory\<HOST>\*.csv|html + software_superset.csv
#>

[CmdletBinding()]
param(
  [string]   $RepoHost     = $env:REPO_HOST,
  [string[]] $ComputerName = @('LPW003ASI037','LPW003ASI173')
)
if ([string]::IsNullOrWhiteSpace($RepoHost)) { $RepoHost = 'LPW003ASI037' }

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

# 0) Tools + repo
. .\GoLiveTools.ps1 -RepoHost $RepoHost
Preflight-Repo -RepoRoot $RepoRoot | Out-Null
"Using RepoRoot: $RepoRoot"
$suiteHtml = Join-Path $here '..\tools\ConvertTo-SuiteHtml.ps1'
if (-not (Test-Path -LiteralPath $suiteHtml)) { throw "Missing ConvertTo-SuiteHtml.ps1 at $suiteHtml" }
. $suiteHtml

# 1) Hygiene
Get-ChildItem *.ps1 | Unblock-File | Out-Null
New-Item -ItemType Directory -Force .\Logs | Out-Null
$ts = ".\Logs\INV-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)
Start-Transcript -Path $ts -Append | Out-Null

# 2) Guard: patch into temp script (do not mutate source file)
$inv = Join-Path $here 'Inventory-Software.patched.ps1'
if (-not (Test-Path $inv)) { $inv = Join-Path $here 'Inventory-Software.ps1' }
if (-not (Test-Path $inv)) { throw "Inventory script not found in $here" }
$raw = Get-Content -Raw $inv
$runInv = $inv
if ($raw -match 'Failed to inventory \$cn:') {
  $raw = $raw -replace 'Failed to inventory \$cn:', 'Failed to inventory $($cn):'
  $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.ps1')
  $raw | Set-Content -Encoding UTF8 $tmp
  $runInv = $tmp
  Write-Host "Using temporary patched inventory script: $runInv" -ForegroundColor Yellow
}

# 3) Run inventory
Write-Host "Inventorying: $($ComputerName -join ', ')" -ForegroundColor Cyan
try {
  & $runInv -ComputerName $ComputerName -RepoHost $RepoHost -Verbose
}
finally {
  Stop-Transcript | Out-Null
  if ($runInv -ne $inv -and (Test-Path $runInv)) { Remove-Item -LiteralPath $runInv -Force -ErrorAction SilentlyContinue }
}

# 4) Show outputs
$invRoot = Join-Path $RepoRoot 'inventory'
$paths = @()
foreach ($c in $ComputerName) {
  $paths += Join-Path $invRoot "$c\installed_software_$c.csv"
  $paths += Join-Path $invRoot "$c\installed_software_$c.html"
}
$paths += Join-Path $invRoot 'software_superset.csv'
$paths | ForEach-Object {
  if (Test-Path $_) { Write-Host "[OK] $_" -ForegroundColor Green } else { Write-Warning "Missing: $_" }
}
$summaryRows = foreach ($p in $paths) {
  [pscustomobject]@{
    Path   = $p
    Exists = (Test-Path -LiteralPath $p)
  }
}
$summaryCsv = Join-Path $invRoot ("runbook_inventory_summary_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$summaryHtml = [IO.Path]::ChangeExtension($summaryCsv, '.html')
$summaryRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $summaryCsv
$summaryFrag = $summaryRows | ConvertTo-Html -Fragment -PreContent '<h2>Runbook Inventory Output Check</h2>'
ConvertTo-SuiteHtml -Title 'Runbook Inventory Summary' -Subtitle "Targets: $($ComputerName -join ', ')" -SummaryChips @("Total paths: $($summaryRows.Count)", "Missing: $(($summaryRows | Where-Object { -not $_.Exists }).Count)") -BodyFragment $summaryFrag -OutputPath $summaryHtml
Write-Host "[OK] $summaryCsv" -ForegroundColor Green
Write-Host "[OK] $summaryHtml" -ForegroundColor Green
Write-Host "Transcript: $ts"