<#
Deploy-EL082-Startup.ps1
- Purges any old printer-map scripts from All Users Startup on each computer
- Copies EL082-MapAll-SetDefault.vbs fresh
Run elevated on your admin box.
#>

param(
  [string[]] $ComputerName = @(
    'WEL082MST051','WEL082MST052','WEL082MST053','WEL082MST054',
    'WEL082MST055','WEL082MST056','WEL082MST057','WEL082MST058',
    'WEL082MST061','WEL082MST063','WEL082MST066','WEL082MST067'
  ),
  [string] $LocalVbs = "$PSScriptRoot\EL082-MapAll-SetDefault.vbs"
)

if (!(Test-Path -LiteralPath $LocalVbs)) {
  throw "Put EL082-MapAll-SetDefault.vbs in the same folder as this script."
}

$oldNames = @(
  'Map-082-Defaults.vbs',
  'Map-EL082-All.vbs',
  'EL082-MapAll-SetDefault.vbs'  # remove stale copy before copying new
)

foreach ($c in $ComputerName) {
  try {
    $startup = "\\$c\C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    if (!(Test-Path $startup)) { Write-Warning "$c : Startup path not reachable"; continue }

    foreach ($n in $oldNames) {
      $p = Join-Path $startup $n
      if (Test-Path $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }

    Copy-Item -LiteralPath $LocalVbs -Destination (Join-Path $startup 'EL082-MapAll-SetDefault.vbs') -Force
    Set-Content -Path (Join-Path $startup 'EL082-PrinterMap.version.txt') -Value ("deployed {0} by {1}" -f (Get-Date), $env:USERNAME)

    if (Test-Path (Join-Path $startup 'EL082-MapAll-SetDefault.vbs')) {
      Write-Host "$c : DEPLOYED"
    } else {
      Write-Warning "$c : COPY FAILED"
    }
  } catch {
    Write-Warning "$c : $_"
  }
}

Write-Host "`nNext: have users sign out/in (or reboot) to run the Startup script."
