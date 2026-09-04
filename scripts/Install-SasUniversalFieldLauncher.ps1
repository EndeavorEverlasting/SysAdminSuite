#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceLauncher = Join-Path $repoRoot 'scripts\Invoke-SasUniversalField.ps1'
$sourceNetworkAwareLauncher = Join-Path $repoRoot 'scripts\Invoke-SasNetworkAwareField.ps1'
$sourcePlatform = Join-Path $repoRoot 'scripts\SasFieldPlatform.psm1'
$sourceNetworkIntent = Join-Path $repoRoot 'scripts\SasNetworkIntent.psm1'
$sourceOperatorSession = Join-Path $repoRoot 'scripts\SasOperatorSession.psm1'
$sourceNetworkGuard = Join-Path $repoRoot 'scripts\SasNetworkGuard.psm1'
$sourceBoundedNative = Join-Path $repoRoot 'scripts\SasBoundedNative.psm1'
$sourcePrinterBootstrap = Join-Path $repoRoot 'Bootstrap-SysAdminSuitePrinter.ps1'
$sourcePrinterTechnicianCmd = Join-Path $repoRoot 'Map-NorthwellPrinter.cmd'
$sourceNetworkBatchProbe = Join-Path $repoRoot 'survey\sas-network-batch-probe.ps1'
$sourceNetworkPreflight = Join-Path $repoRoot 'survey\sas-network-preflight.ps1'
$sourceCybernetCanary = Join-Path $repoRoot 'survey\sas-cybernet-canary.ps1'
foreach ($required in @(
    $sourceLauncher,$sourceNetworkAwareLauncher,$sourcePlatform,$sourceNetworkIntent,
    $sourceOperatorSession,$sourceNetworkGuard,$sourceBoundedNative,$sourcePrinterBootstrap,
    $sourceNetworkBatchProbe,$sourceNetworkPreflight,$sourceCybernetCanary
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required universal field file missing: $required" }
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($required,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw "PowerShell parse failure: $required :: $($errors[0].Message)" }
}
if (-not (Test-Path -LiteralPath $sourcePrinterTechnicianCmd -PathType Leaf)) {
    throw "Required technician printer CMD missing: $sourcePrinterTechnicianCmd"
}
Import-Module $sourcePlatform -Force

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

$canonicalRuntime = 'C:\SASAL'
$canonicalReady = Test-SasControllerSurface -Root $canonicalRuntime
if ($canonicalReady) {
    # The installed network-intent module resolves these dependencies from the controller root.
    # A legacy C:\SASAL that lacks any one of them must be refreshed before we install a shim
    # that would otherwise fail on its first network canary.
    $networkProbeRuntimeFiles = @(
        'survey\sas-network-batch-probe.ps1',
        'survey\sas-network-preflight.ps1',
        'survey\sas-cybernet-canary.ps1',
        'scripts\SasFieldPlatform.psm1',
        'scripts\SasOperatorSession.psm1',
        'scripts\SasNetworkGuard.psm1',
        'scripts\SasBoundedNative.psm1',
        'scripts\SasTargetIntake.psm1',
        'scripts\SasLowNoisePolicy.psm1',
        'scripts\SasPortFallbackDecision.psm1',
        'scripts\Render-SasEnglishReport.ps1'
    )
    foreach ($relative in $networkProbeRuntimeFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $canonicalRuntime $relative) -PathType Leaf)) {
            throw "MACHINE_RUNTIME_REFRESH_REQUIRED: C:\SASAL is a valid legacy controller but does not contain the current network-aware runtime dependency ($relative). Run 'sas refresh' on Guest/Internet before installing the current universal launcher."
        }
    }

    $canonicalCanary = Join-Path $canonicalRuntime 'survey\sas-cybernet-canary.ps1'
    $sourceCanaryHash = (Get-FileHash -LiteralPath $sourceCybernetCanary -Algorithm SHA256).Hash
    $canonicalCanaryHash = (Get-FileHash -LiteralPath $canonicalCanary -Algorithm SHA256).Hash
    if (-not $sourceCanaryHash.Equals($canonicalCanaryHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "MACHINE_RUNTIME_REFRESH_REQUIRED: C:\SASAL contains a stale Cybernet canary. Run 'sas refresh' on Guest/Internet so the installed sas command cannot route to older canary behavior."
    }
}

$userProfileRoot = $null
if (-not [string]::IsNullOrWhiteSpace([string]$env:USERPROFILE)) {
    try { $userProfileRoot = ([IO.Path]::GetFullPath($env:USERPROFILE)).TrimEnd('\') + '\' } catch { $userProfileRoot = $null }
}
$normalizedRepo = ([IO.Path]::GetFullPath($repoRoot)).TrimEnd('\') + '\'
$repoIsUserScoped = (-not [string]::IsNullOrWhiteSpace($userProfileRoot) -and
    $normalizedRepo.StartsWith($userProfileRoot,[StringComparison]::OrdinalIgnoreCase))

$machineRoot = if ($env:ProgramData) { Join-Path $env:ProgramData 'SysAdminSuite' } else { 'C:\ProgramData\SysAdminSuite' }
$machineBin = Join-Path $machineRoot 'bin'
$userBin = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin' } else { $null }
$machineInstall = Test-SasDirectoryWritable -Path $machineBin

# A user-profile checkout may bootstrap installation, but it cannot become shared execution authority.
# If the canonical machine runtime is absent, require either a machine-neutral source root or its
# preparation before claiming that the universal command is installed for arbitrary technicians.
if (-not $canonicalReady -and $repoIsUserScoped) {
    throw 'MACHINE_NEUTRAL_RUNTIME_REQUIRED: C:\SASAL is not prepared and the source checkout is under the current user profile. Prepare the canonical local runtime (normally via sas refresh on Guest/Internet) or install from a machine-neutral local checkout.'
}

$installRoot = if ($machineInstall) {
    $machineBin
}
elseif ($userBin -and $canonicalReady -and (Test-SasDirectoryWritable -Path $userBin)) {
    $userBin
}
else {
    throw 'No safe universal launcher installation is available. A current-user shim requires an existing canonical machine-local C:\SASAL runtime.'
}
$installScope = if ($machineInstall) { 'MACHINE' } else { 'CURRENT_USER_SHIM_WITH_MACHINE_RUNTIME' }

$launcherDestination = Join-Path $installRoot 'Invoke-SasUniversalField.ps1'
$networkAwareLauncherDestination = Join-Path $installRoot 'Invoke-SasNetworkAwareField.ps1'
$platformDestination = Join-Path $installRoot 'SasFieldPlatform.psm1'
$networkIntentDestination = Join-Path $installRoot 'SasNetworkIntent.psm1'
$printerBootstrapDestination = Join-Path $installRoot 'Bootstrap-SysAdminSuitePrinter.ps1'
$printerTechnicianCmdDestination = Join-Path $installRoot 'Map-NorthwellPrinter.cmd'
$cmdDestination = Join-Path $installRoot 'sas.cmd'
Copy-Item -LiteralPath $sourceLauncher -Destination $launcherDestination -Force
Copy-Item -LiteralPath $sourceNetworkAwareLauncher -Destination $networkAwareLauncherDestination -Force
Copy-Item -LiteralPath $sourcePlatform -Destination $platformDestination -Force
Copy-Item -LiteralPath $sourceNetworkIntent -Destination $networkIntentDestination -Force
Copy-Item -LiteralPath $sourcePrinterBootstrap -Destination $printerBootstrapDestination -Force
Copy-Item -LiteralPath $sourcePrinterTechnicianCmd -Destination $printerTechnicianCmdDestination -Force

# Machine cache is optional and never points at a user-profile checkout. The trusted installed
# launcher still resolves C:\SASAL first, and cache write failures cannot break command execution.
$cacheRoot = if ($canonicalReady) { $canonicalRuntime } elseif (-not $repoIsUserScoped) { $repoRoot } else { $null }
if (-not [string]::IsNullOrWhiteSpace([string]$cacheRoot) -and (Test-SasDirectoryWritable -Path $machineRoot)) {
    try { Set-Content -LiteralPath (Join-Path $machineRoot 'repo-root.txt') -Value $cacheRoot -Encoding ASCII -ErrorAction Stop }
    catch { Write-Warning "Machine controller cache could not be updated; continuing without it: $($_.Exception.Message)" }
}

# The CMD shim executes only the installer-owned network-aware PowerShell copy beside itself. That
# wrapper prints the network canary before delegating to the existing universal dispatcher and may
# perform only bounded saved-WLAN transitions that it can prove and restore. VPN lifecycle remains
# fail-closed until a repository-proven client adapter exists.
$cmd = @'
@echo off
setlocal EnableExtensions
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-SasNetworkAwareField.ps1" %*
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
Write-Host "Network-aware launcher: $networkAwareLauncherDestination"
Write-Host "Network intent module: $networkIntentDestination"
Write-Host "Printer technician CMD: $printerTechnicianCmdDestination"
Write-Host "Printer bootstrap: $printerBootstrapDestination"
Write-Host 'Execution resolution: trusted installed shim -> network canary/intent -> validated universal field dispatcher.'
Write-Host 'Protected network authority: hardwire OR NSLIJHS-WAB OR authenticated DomainAuthenticated VPN.'
Write-Host 'Automatic switching: saved WLAN profiles only, with exact-state proof and restoration; VPN lifecycle is not guessed.'
Write-Host 'Controller runtime distribution: LOCAL MACHINE ONLY; SysAdminSuite is not copied to target machines.' -ForegroundColor Green
