# Map-FromCsv-PerUser.ps1 — per-user, CSV-driven
param([string]$CsvPath = ".\per_user_printers.csv")

$rows = Import-Csv -Path $CsvPath
New-Item -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'LegacyDefaultPrinterMode' -Type DWord -Value 1

$default = ($rows | Where-Object { $_.Default -match '^(y|yes|true|1)$' }).Queue
foreach ($r in $rows) {
  Start-Process rundll32.exe -ArgumentList 'printui.dll,PrintUIEntry','/in','/n',"$($r.Queue)" -NoNewWindow -Wait
}
if ($default) {
  Start-Process rundll32.exe -ArgumentList 'printui.dll,PrintUIEntry','/y','/n',"$default" -NoNewWindow -Wait
}
Write-Host "Mapped per-user printers from CSV. Default: $default"
