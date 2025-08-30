# Copy Map-EL082-All.vbs to Startup on targeted PCs so it runs next logon
# Run from an elevated PowerShell prompt with admin rights on the targets

$File = Join-Path $PSScriptRoot 'Map-EL082-All.vbs'

$Hosts = @(
  'WEL082MST051','WEL082MST052','WEL082MST053','WEL082MST054',
  'WEL082MST055','WEL082MST057','WEL082MST058','WEL082MST061',
  'WEL082MST063','WEL082MST066','WEL082MST067'
)

foreach ($h in $Hosts) {
  $startup = "\\$h\C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
  if (Test-Connection -ComputerName $h -Count 1 -Quiet -ErrorAction SilentlyContinue) {
    Copy-Item -Path $File -Destination $startup -Force -ErrorAction Stop
    Write-Host "OK -> $h"
  } else {
    Write-Warning "OFFLINE -> $h"
  }
}
