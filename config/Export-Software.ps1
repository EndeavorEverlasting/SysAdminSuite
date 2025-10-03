# Export-Inventory.ps1
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot 'exports'
New-Item -ItemType Directory -Force -Path $root | Out-Null

$regPaths = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$items = foreach ($path in $regPaths) {
  Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
    if ($p.DisplayName) {
      [PSCustomObject]@{
        DisplayName     = $p.DisplayName
        DisplayVersion  = $p.DisplayVersion
        Publisher       = $p.Publisher
        InstallLocation = $p.InstallLocation
        UninstallString = $p.UninstallString
        QuietUninstall  = $p.QuietUninstallString
        ProductCode     = $p.PSObject.Properties['ProductID']?.Value -as [string]
        RegistryPath    = $_.PsPath
      }
    }
  }
}

$inv = Join-Path $root 'installed_software.csv'
$items | Sort-Object DisplayName | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $inv
Write-Host "Exported: $inv" -ForegroundColor Green
