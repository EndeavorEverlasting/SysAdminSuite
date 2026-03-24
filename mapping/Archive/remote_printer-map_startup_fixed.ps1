# Copy Map-EL082-All.vbs to Startup on targeted PCs so it runs next logon
# Run from an elevated PowerShell prompt with admin rights on the targets

$File = Join-Path $PSScriptRoot 'Map-EL082-All.vbs'

# BUG-FIX: Validate $PSScriptRoot and source file exist before any copy attempts
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  Write-Error "PSScriptRoot is empty — run this as a saved .ps1 file, not interactively."
  exit 1
}
if (-not (Test-Path -LiteralPath $File)) {
  Write-Error "Source file not found: $File (Map-EL082-All.vbs must be in the same directory)"
  exit 1
}

$Hosts = @(
  'WEL082MST051','WEL082MST052','WEL082MST053','WEL082MST054',
  'WEL082MST055','WEL082MST057','WEL082MST058','WEL082MST061',
  'WEL082MST063','WEL082MST066','WEL082MST067'
)

foreach ($h in $Hosts) {
  $startup = "\\$h\C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
  if (Test-Connection -ComputerName $h -Count 1 -Quiet -ErrorAction SilentlyContinue) {
    # BUG-FIX: Wrap Copy-Item in try/catch so a single failure doesn't abort remaining hosts
    try {
      Copy-Item -Path $File -Destination $startup -Force -ErrorAction Stop
      Write-Host "OK -> $h"
    } catch {
      Write-Error "FAILED -> $h ($startup): $($_.Exception.Message)"
    }
  } else {
    Write-Warning "OFFLINE -> $h"
  }
}
