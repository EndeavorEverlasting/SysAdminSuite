#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)][AllowEmptyString()][string[]]$CommandArgs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'SasFieldPlatform.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Missing universal field platform module: $modulePath"
}
Import-Module $modulePath -Force

$callerRoot = try { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path } catch { $null }
$controllerRoot = Resolve-SasControllerRoot -CallerRoot $callerRoot
$runtimeRoot = Resolve-SasExecutionRuntimeRoot -ControllerRoot $controllerRoot
$env:SAS_REPO_ROOT = $controllerRoot
$env:SAS_RUNTIME_ROOT = $runtimeRoot
[void](Save-SasControllerRootCache -Root $controllerRoot)

$normalized = if ([string]::IsNullOrWhiteSpace($Command)) { '' } else { $Command.Trim().ToLowerInvariant() }
$actualArgs = @($CommandArgs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

function Write-SasUniversalContext {
    $authority = Get-SasProtectedNetworkAuthority -RepoRoot $controllerRoot
    Write-Host 'SysAdminSuite universal field platform' -ForegroundColor Cyan
    Write-Host "Controller root: $controllerRoot"
    Write-Host "Execution runtime: $runtimeRoot"
    Write-Host "Runtime scope: LOCAL_MACHINE_ONLY"
    Write-Host "Protected authority: $($authority.authority)"
    if (-not [string]::IsNullOrWhiteSpace([string]$authority.interface_alias)) {
        Write-Host "Interface: $($authority.interface_alias)"
    }
    Write-Host ''
    Write-Host 'Supported protected paths: Northwell hardwire, NSLIJHS-WAB, authenticated DomainAuthenticated VPN.' -ForegroundColor Green
    Write-Host 'SysAdminSuite runtime is never copied to a target; only run-scoped payloads/evidence may cross to an authorized target.' -ForegroundColor Green
}

function Assert-SasProtectedForAction {
    param([string]$Purpose)
    $authority = Assert-SasProtectedNetworkAuthority -RepoRoot $controllerRoot
    Write-Host "Protected network authority: $($authority.authority) [$($authority.interface_alias)]" -ForegroundColor Green
    $gate = Join-Path $runtimeRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
    if (-not (Test-Path -LiteralPath $gate -PathType Leaf)) { $gate = Join-Path $controllerRoot 'scripts\Confirm-SasNorthwellNetwork.ps1' }
    & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $gate -Purpose $Purpose -NonInteractive
    if ($LASTEXITCODE -ne 0) { throw "Canonical protected-network gate rejected the current path for: $Purpose" }
    return $authority
}

function Invoke-SasLegacyDispatcher {
    $dispatcher = Join-Path $controllerRoot 'scripts\SasPortableLauncher.ps1'
    if (-not (Test-Path -LiteralPath $dispatcher -PathType Leaf)) { throw "Missing existing SysAdminSuite dispatcher: $dispatcher" }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $dispatcher $Command @actualArgs
    exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq 'platform') {
    Write-SasUniversalContext
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        Write-Host 'Run the existing sas commands normally; the universal front door resolves controller/runtime/network context first.'
        Write-Host 'Printer quick mapping is also available as: sas printer' -ForegroundColor Green
        Write-Host 'Clipboard recovery is available as: sas clipboard' -ForegroundColor Green
    }
    exit 0
}

switch ($normalized) {
    'refresh' {
        if ($actualArgs.Count -ne 0) { Write-Host 'Usage: sas refresh' -ForegroundColor Red; exit 2 }
        $refresh = Join-Path $controllerRoot 'scripts\Refresh-SasOperatorCommand.ps1'
        if (-not (Test-Path -LiteralPath $refresh -PathType Leaf)) { throw "Missing canonical refresh workflow: $refresh" }

        # The existing refresh owns Guest/Internet Git synchronization and seals the next local
        # C:\SASAL runtime. It currently installs the compatibility dispatcher as part of that flow.
        # After it succeeds, reinstall the universal machine-neutral front door from the newly sealed
        # runtime so refresh converges to this platform rather than silently regressing it.
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $refresh -RepositoryRoot $controllerRoot
        $refreshExit = $LASTEXITCODE
        if ($refreshExit -ne 0) { exit $refreshExit }

        $sealedInstaller = 'C:\SASAL\scripts\Install-SasUniversalFieldLauncher.ps1'
        if (-not (Test-Path -LiteralPath $sealedInstaller -PathType Leaf)) {
            throw "Refreshed machine-local runtime is missing the universal installer: $sealedInstaller"
        }
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $sealedInstaller
        $installExit = $LASTEXITCODE
        if ($installExit -ne 0) { exit $installExit }

        Write-Host 'UNIVERSAL_FIELD_PLATFORM_REFRESH_CONVERGED' -ForegroundColor Green
        exit 0
    }

    'network' {
        if ($actualArgs.Count -gt 1) { Write-Host 'Usage: sas network [HOST]' -ForegroundColor Red; exit 2 }
        if ($actualArgs.Count -eq 1) {
            [void](Assert-SasProtectedForAction -Purpose "Network readiness probe for $($actualArgs[0])")
            # Preserve the existing one-target readiness contract. The universal layer owns local
            # protected-path admission; the established dispatcher continues to own the target probe.
            Invoke-SasLegacyDispatcher
        }
        Write-SasUniversalContext
        $gate = Join-Path $runtimeRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
        if (-not (Test-Path -LiteralPath $gate -PathType Leaf)) { $gate = Join-Path $controllerRoot 'scripts\Confirm-SasNorthwellNetwork.ps1' }
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $gate -Purpose 'manual SysAdminSuite operator check' -NonInteractive
        exit $LASTEXITCODE
    }

    'printer' {
        if ($actualArgs.Count -ne 0) { Write-Host 'Usage: sas printer' -ForegroundColor Red; exit 2 }
        [void](Assert-SasProtectedForAction -Purpose 'Northwell system-wide printer mapping')
        $printerLauncher = Join-Path $controllerRoot 'Map-NorthwellPrinter-SystemWide.cmd'
        if (-not (Test-Path -LiteralPath $printerLauncher -PathType Leaf)) {
            throw "Canonical printer mapping launcher is missing: $printerLauncher"
        }
        & $printerLauncher
        exit $LASTEXITCODE
    }

    'clipboard' {
        if ($actualArgs.Count -gt 1 -or ($actualArgs.Count -eq 1 -and ([string]$actualArgs[0]).Trim().ToLowerInvariant() -ne 'reset')) {
            Write-Host 'Usage: sas clipboard [reset]' -ForegroundColor Red
            exit 2
        }
        $clipboardReset = Join-Path $runtimeRoot 'scripts\Reset-SasClipboard.ps1'
        if (-not (Test-Path -LiteralPath $clipboardReset -PathType Leaf)) {
            $clipboardReset = Join-Path $controllerRoot 'scripts\Reset-SasClipboard.ps1'
        }
        if (-not (Test-Path -LiteralPath $clipboardReset -PathType Leaf)) {
            throw "Canonical clipboard reset script is missing: $clipboardReset"
        }
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $clipboardReset
        exit $LASTEXITCODE
    }

    'autologon' {
        if ($actualArgs.Count -eq 2) {
            $mode = ([string]$actualArgs[0]).Trim().ToLowerInvariant()
            $target = ([string]$actualArgs[1]).Trim()
            if ($mode -in @('remote','recover')) {
                [void](Assert-SasProtectedForAction -Purpose "AutoLogon $mode for $target")
                $launcher = Join-Path $runtimeRoot 'Run-AutoLogonOnsite.cmd'
                if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
                    throw "Canonical local AutoLogon launcher is missing from runtime: $launcher"
                }
                $action = if ($mode -eq 'remote') { 'Remote' } else { 'Recover' }
                & $launcher $action $target
                exit $LASTEXITCODE
            }
        }
        Invoke-SasLegacyDispatcher
    }

    'cybernet' {
        if ($actualArgs.Count -gt 0) {
            $mode = ([string]$actualArgs[0]).Trim().ToLowerInvariant()
            if ($mode -in @('probe','deploy','core','profiled-core','recover')) {
                $targetLabel = if ($actualArgs.Count -gt 1) { [string]$actualArgs[1] } else { '<target>' }
                [void](Assert-SasProtectedForAction -Purpose "Cybernet $mode for $targetLabel")
            }
        }
        Invoke-SasLegacyDispatcher
    }

    default {
        Invoke-SasLegacyDispatcher
    }
}
