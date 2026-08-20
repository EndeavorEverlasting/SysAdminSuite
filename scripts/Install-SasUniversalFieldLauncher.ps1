#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceLauncher = Join-Path $repoRoot 'scripts\Invoke-SasUniversalField.ps1'
$sourcePlatform = Join-Path $repoRoot 'scripts\SasFieldPlatform.psm1'
foreach ($required in @($sourceLauncher,$sourcePlatform)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required universal field file missing: $required" }
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($required,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw "PowerShell parse failure: $required :: $($errors[0].Message)" }
}

function Test-SasDirectoryWritable {
    param([Parameter(Mandatory=$true)][string]$Path)
    try {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        $probe = Join-Path $Path ('.write-probe-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe,'ok')
        Remove-Item -LiteralPath $probe -Force
        return $true
    }
    catch { return $false }
}

$machineRoot = if ($env:ProgramData) { Join-Path $env:ProgramData 'SysAdminSuite' } else { 'C:\ProgramData\SysAdminSuite' }
$machineBin = Join-Path $machineRoot 'bin'
$userBin = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin' } else { $null }
$machineInstall = Test-SasDirectoryWritable -Path $machineBin
$installRoot = if ($machineInstall) { $machineBin } elseif ($userBin -and (Test-SasDirectoryWritable -Path $userBin)) { $userBin } else { throw 'No writable local install directory is available.' }
$installScope = if ($machineInstall) { 'MACHINE' } else { 'CURRENT_USER_FALLBACK' }

$launcherDestination = Join-Path $installRoot 'Invoke-SasUniversalField.ps1'
$platformDestination = Join-Path $installRoot 'SasFieldPlatform.psm1'
$cmdDestination = Join-Path $installRoot 'sas.cmd'
Copy-Item -LiteralPath $sourceLauncher -Destination $launcherDestination -Force
Copy-Item -LiteralPath $sourcePlatform -Destination $platformDestination -Force

# Machine state is a convenience cache only. Execution never depends on a username-specific repo path.
if (Test-SasDirectoryWritable -Path $machineRoot) {
    Set-Content -LiteralPath (Join-Path $machineRoot 'repo-root.txt') -Value $repoRoot -Encoding ASCII
}

$cmd = @'
@echo off
setlocal EnableExtensions
set "SAS_UNIVERSAL="
if defined SAS_RUNTIME_ROOT if exist "%SAS_RUNTIME_ROOT%\scripts\Invoke-SasUniversalField.ps1" set "SAS_UNIVERSAL=%SAS_RUNTIME_ROOT%\scripts\Invoke-SasUniversalField.ps1"
if not defined SAS_UNIVERSAL if exist "C:\SASAL\scripts\Invoke-SasUniversalField.ps1" set "SAS_UNIVERSAL=C:\SASAL\scripts\Invoke-SasUniversalField.ps1"
if not defined SAS_UNIVERSAL set "SAS_UNIVERSAL=%~dp0Invoke-SasUniversalField.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_UNIVERSAL%" %*
set "SAS_EXIT=%ERRORLEVEL%"
endlocal & exit /b %SAS_EXIT%
'@
Set-Content -LiteralPath $cmdDestination -Value $cmd -Encoding ASCII

$pathScope = if ($machineInstall) { 'Machine' } else { 'User' }
$currentPath = [Environment]::GetEnvironmentVariable('Path',$pathScope)
$segments = @($currentPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ })
if (@($segments | Where-Object { $_.Equals($installRoot.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
    $newPath = if ([string]::IsNullOrWhiteSpace($currentPath)) { $installRoot } else { $currentPath.TrimEnd(';') + ';' + $installRoot }
    try { [Environment]::SetEnvironmentVariable('Path',$newPath,$pathScope) }
    catch {
        if ($pathScope -eq 'Machine') {
            $pathScope = 'User'
            $currentPath = [Environment]::GetEnvironmentVariable('Path','User')
            $newPath = if ([string]::IsNullOrWhiteSpace($currentPath)) { $installRoot } else { $currentPath.TrimEnd(';') + ';' + $installRoot }
            [Environment]::SetEnvironmentVariable('Path',$newPath,'User')
        }
        else { throw }
    }
}
if (-not (($env:Path -split ';') -contains $installRoot)) { $env:Path = $env:Path.TrimEnd(';') + ';' + $installRoot }

Write-Host 'SysAdminSuite universal field command installed.' -ForegroundColor Green
Write-Host "Install scope: $installScope"
Write-Host "Launcher: $cmdDestination"
Write-Host 'Execution resolution: SAS_RUNTIME_ROOT -> C:\SASAL -> local repo/controller surface.'
Write-Host 'Protected network authority: hardwire OR NSLIJHS-WAB OR authenticated DomainAuthenticated VPN.'
Write-Host 'Controller runtime distribution: LOCAL MACHINE ONLY; SysAdminSuite is not copied to target machines.' -ForegroundColor Green
