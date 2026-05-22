param(
  [Parameter(Mandatory)][string]$CsvPath,
  [string]$HtmlPath = ([IO.Path]::ChangeExtension($CsvPath, '.html'))
)

if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "CSV file not found: $CsvPath"
}

$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) {
  Write-Warning "CSV contains no rows: $CsvPath"
  return
}

$suiteHtmlHelper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
if (-not (Test-Path -LiteralPath $suiteHtmlHelper)) {
  throw "HTML helper not found: $suiteHtmlHelper"
}
. $suiteHtmlHelper

$okCount = @($rows | Where-Object { $_.Status -eq 'OK' }).Count
$partialCount = @($rows | Where-Object { $_.Status -eq 'Partial Identity' }).Count
$failedCount = @($rows | Where-Object { $_.Status -eq 'Query Failed' }).Count
$warningCount = @($rows | Where-Object { $_.IdentityWarning }).Count

$summaryRows = @(
  [pscustomobject]@{ Metric = 'Total hosts'; Count = $rows.Count }
  [pscustomobject]@{ Metric = 'OK'; Count = $okCount }
  [pscustomobject]@{ Metric = 'Partial Identity'; Count = $partialCount }
  [pscustomobject]@{ Metric = 'Query Failed'; Count = $failedCount }
  [pscustomobject]@{ Metric = 'Identity Warnings'; Count = $warningCount }
)

$identityColumns = @('HostName','ReportedComputerName','Serial','SerialSource','MACAddress','MACSource','Status','ErrorCategory','FailureReason','RepairActions','RepairErrors','LastResortIPAddress','IPFallbackSource')
$failureColumns = @('HostName','ReportedComputerName','Serial','SerialSource','MACAddress','MACSource','Status','ErrorCategory','FailureReason','RepairActions','RepairErrors','RpcProbe','SmbProbe','WinRmProbe','IdentityWarning','ErrorMessage')
$detailColumns = @('HostName','ReportedComputerName','Serial','SerialSource','MACAddress','MACSource','Model','Manufacturer','ReportedNameSource','IdentityWarning','RpcProbe','SmbProbe','WinRmProbe','FallbackProbe','Status','ErrorCategory','FailureReason','RepairActions','RepairErrors','LastResortIPAddress','IPFallbackSource','ErrorMessage','ProbeSummary')

$identityRows = @($rows | Sort-Object HostName | Select-Object -Property $identityColumns)
$failureRows = @($rows | Where-Object { $_.Status -ne 'OK' -or $_.IdentityWarning -or -not $_.Serial -or -not $_.MACAddress } | Sort-Object HostName | Select-Object -Property $failureColumns)
$detailRows = @($rows | Sort-Object HostName | Select-Object -Property $detailColumns)

$bodyParts = @()
$bodyParts += $summaryRows | ConvertTo-Html -Fragment -PreContent '<h2>Run Summary</h2>'
$bodyParts += $identityRows | ConvertTo-Html -Fragment -PreContent '<h2>Identity Quick View - Serial and MAC</h2><p>This section is intentionally first. Use Serial and MACAddress here as the primary identity fields.</p>'

if ($failureRows.Count -gt 0) {
  $bodyParts += $failureRows | ConvertTo-Html -Fragment -PreContent '<h2>Failures and Warnings - Serial, MAC, and Reason</h2>'
} else {
  $bodyParts += '<h2>Failures and Warnings - Serial, MAC, and Reason</h2><p>No failed hosts, missing Serial/MAC fields, or identity warnings were detected in this run.</p>'
}

$bodyParts += $detailRows | ConvertTo-Html -Fragment -PreContent '<h2>Full Machine Info Details</h2>'

$body = $bodyParts -join "`n"
$chips = @("OK: $okCount", "Partial: $partialCount", "Failed: $failedCount", "Warnings: $warningCount")

$body | ConvertTo-SuiteHtml -Title 'Machine Info - Hostname First Native Probe' -Subtitle "$($rows.Count) host(s)" -SummaryChips $chips -OutputPath $HtmlPath

Write-Host "[HTML] Refreshed report with Serial and MAC fields: $HtmlPath" -ForegroundColor Green
