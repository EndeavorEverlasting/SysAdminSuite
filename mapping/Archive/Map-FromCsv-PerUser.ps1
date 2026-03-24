# Map-FromCsv-PerUser.ps1 — per-user, CSV-driven
param([string]$CsvPath = ".\per_user_printers.csv")

# BUG-FIX: Validate CSV exists and is readable before Import-Csv
if (-not (Test-Path -LiteralPath $CsvPath)) {
  Write-Error "CSV not found: $CsvPath"
  exit 1
}
try {
  $rows = Import-Csv -Path $CsvPath -ErrorAction Stop
} catch {
  Write-Error "Failed to read CSV '$CsvPath': $($_.Exception.Message)"
  exit 1
}

# BUG-FIX: Validate required columns exist
$requiredCols = @('Queue','Default')
$actualCols   = if ($rows) { $rows[0].PSObject.Properties.Name } else { @() }
foreach ($col in $requiredCols) {
  if ($col -notin $actualCols) {
    Write-Error "CSV '$CsvPath' is missing required column: $col"
    exit 1
  }
}

New-Item -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'LegacyDefaultPrinterMode' -Type DWord -Value 1

# BUG-FIX: Use Select-Object -First 1 -ExpandProperty to ensure $default is always a scalar
$default = $rows | Where-Object { $_.Default -match '^(y|yes|true|1)$' } | Select-Object -First 1 -ExpandProperty Queue

$failures = @()
foreach ($r in $rows) {
  try {
    $proc = Start-Process rundll32.exe -ArgumentList 'printui.dll,PrintUIEntry','/in','/n',"$($r.Queue)" -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($proc.ExitCode -ne 0) { throw "Exit code $($proc.ExitCode)" }
  } catch {
    Write-Warning "Failed to add printer '$($r.Queue)': $($_.Exception.Message)"
    $failures += $r.Queue
  }
}

if ($default) {
  try {
    $proc = Start-Process rundll32.exe -ArgumentList 'printui.dll,PrintUIEntry','/y','/n',"$default" -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($proc.ExitCode -ne 0) { throw "Exit code $($proc.ExitCode)" }
  } catch {
    Write-Warning "Failed to set default printer '$default': $($_.Exception.Message)"
  }
}

if ($failures.Count -gt 0) {
  Write-Warning "The following printers failed to map: $($failures -join ', ')"
}
Write-Host "Mapped per-user printers from CSV. Default: $default"
