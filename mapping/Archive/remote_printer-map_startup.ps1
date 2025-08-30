# Open an elevated PowerShell and run:
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# .\remote_printer-map_startup.ps1


$Hosts = "WEL082MST051","WEL082MST052","WEL082MST053","WEL082MST054","WEL082MST063"
$File  = ".\Map-EL082-All.vbs"
foreach ($h in $Hosts) {
  $startup = "\\$h\C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
  Copy-Item $File $startup -Force
}
