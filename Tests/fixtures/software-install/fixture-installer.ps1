#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:SAS_FIXTURE_INSTALL_ROOT)) {
    Write-Error 'SAS_FIXTURE_INSTALL_ROOT is required for the fixture installer.'
    exit 41
}

$targetRoot = [IO.Path]::GetFullPath($env:SAS_FIXTURE_INSTALL_ROOT)
$packageRoot = Join-Path $targetRoot 'InstalledPackages\SysAdminSuiteFixturePackage'
$logRoot = Join-Path $targetRoot 'InstallerLogs'
$manifestPath = Join-Path $packageRoot 'manifest.json'
$logPath = Join-Path $logRoot 'sysadminsuite-fixture-package.log'

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

$manifest = [ordered]@{
    schema_version = 'sas-fixture-installed-package/v1'
    package_name = 'SysAdminSuite Fixture Package'
    version = '1.0.0'
    installed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    installer = 'fixture-installer.ps1'
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
    '{0} installed {1} version {2}' -f
        (Get-Date).ToUniversalTime().ToString('o'),
        $manifest.package_name,
        $manifest.version
)

exit 0
