# Optional quick checks
Test-NetConnection WPV522PED001 -Port 135
Get-Service -ComputerName WPV522PED001 Schedule

# Execute (uses your current domain token)
.\Deploy-AllPrinters.ps1 -CsvPath '.\printer_mapping_csv - Sheet1.csv'

# If your current token isn't local admin on the targets:
.\Deploy-AllPrinters.ps1 -CsvPath '.\printer_mapping_csv - Sheet1.csv' -AltUser 'YOURDOMAIN\YourAdmin' -AltPass 'Secret'
