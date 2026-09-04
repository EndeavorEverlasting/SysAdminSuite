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

function Resolve-SasInstalledPrinterBootstrap {
    # A machine-wide/user shim owns its sibling printer bootstrap. Source-checkout invocation may
    # fall back to the validated local runtime/controller, but never to the caller's current path.
    foreach ($candidate in @(
        (Join-Path $PSScriptRoot 'Bootstrap-SysAdminSuitePrinter.ps1'),
        (Join-Path $runtimeRoot 'Bootstrap-SysAdminSuitePrinter.ps1'),
        (Join-Path $controllerRoot 'Bootstrap-SysAdminSuitePrinter.ps1')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'Trusted Northwell printer bootstrap is missing. Reinstall the universal sas command from a current machine-local runtime.'
}

function Resolve-SasInstalledAutoLogonBootstrap {
    # Target-mutating AutoLogon Remote must enter the sealed crash-safe bootstrap so every run gets
    # the registered LOCALAPPDATA transcript/result/latest-pointer recovery surface. Prefer the
    # execution runtime; the controller fallback supports source-checkout validation only.
    foreach ($candidate in @(
        (Join-Path $runtimeRoot 'Bootstrap-SysAdminSuiteAutoLogon.cmd'),
        (Join-Path $controllerRoot 'Bootstrap-SysAdminSuiteAutoLogon.cmd')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'Trusted crash-safe AutoLogon bootstrap is missing. Refresh/reseal the machine-local runtime before Remote deployment.'
}

if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq 'platform') {
    Write-SasUniversalContext
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        Write-Host 'Run the existing sas commands normally; the universal front door resolves controller/runtime/network context first.'
        Write-Host 'Printer quick mapping: sas printer' -ForegroundColor Green
        Write-Host 'Printer file/batch mapping: sas printer file' -ForegroundColor Green
        Write-Host 'Printer mapping when GitHub is intentionally unavailable: sas printer offline' -ForegroundColor DarkGray
        Write-Host 'Clipboard recovery is available as: sas clipboard' -ForegroundColor Green
        Write-Host 'Batch network probing is available as: sas network probe HOST01 HOST02 ...' -ForegroundColor Green
        Write-Host 'Cybernet model+serial canary is available as: sas cybernet canary HOST01 HOST02 ...' -ForegroundColor Green
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
        if ($actualArgs.Count -gt 0 -and ([string]$actualArgs[0]).Trim().ToLowerInvariant() -eq 'probe') {
            $targets = @($actualArgs | Select-Object -Skip 1)
            if ($targets.Count -eq 0) {
                Write-Host 'Usage: sas network probe HOST01 [HOST02 ...]' -ForegroundColor Red
                exit 2
            }
            [void](Assert-SasProtectedForAction -Purpose "Batch network probe for $($targets.Count) explicit targets")
            $batchProbe = Join-Path $controllerRoot 'survey\sas-network-batch-probe.ps1'
            if (-not (Test-Path -LiteralPath $batchProbe -PathType Leaf)) {
                throw "Batch network probe runtime is not present in the active controller: $controllerRoot. Run 'sas refresh' on Guest/Internet to install the current sealed runtime."
            }
            & $batchProbe -Target $targets
            exit 0
        }
        if ($actualArgs.Count -gt 1) { Write-Host 'Usage: sas network [HOST]  OR  sas network probe HOST01 [HOST02 ...]' -ForegroundColor Red; exit 2 }
        if ($actualArgs.Count -eq 1) {
            [void](Assert-SasProtectedForAction -Purpose "Network readiness probe for $($actualArgs[0])")
            Invoke-SasLegacyDispatcher
        }
        Write-SasUniversalContext
        $gate = Join-Path $runtimeRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
        if (-not (Test-Path -LiteralPath $gate -PathType Leaf)) { $gate = Join-Path $controllerRoot 'scripts\Confirm-SasNorthwellNetwork.ps1' }
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $gate -Purpose 'manual SysAdminSuite operator check' -NonInteractive
        exit $LASTEXITCODE
    }

    'printer' {
        if ($actualArgs.Count -gt 2) { Write-Host 'Usage: sas printer [file] [offline]' -ForegroundColor Red; exit 2 }
        $printerMode = 'Quick'
        $printerOffline = $false
        foreach ($rawArg in $actualArgs) {
            $printerArg = ([string]$rawArg).Trim().ToLowerInvariant()
            switch ($printerArg) {
                { $_ -in @('file','batch') } {
                    if ($printerMode -eq 'File') { Write-Host 'Usage: sas printer [file] [offline]' -ForegroundColor Red; exit 2 }
                    $printerMode = 'File'
                    continue
                }
                'offline' {
                    if ($printerOffline) { Write-Host 'Usage: sas printer [file] [offline]' -ForegroundColor Red; exit 2 }
                    $printerOffline = $true
                    continue
                }
                default { Write-Host 'Usage: sas printer [file] [offline]' -ForegroundColor Red; exit 2 }
            }
        }
        [void](Assert-SasProtectedForAction -Purpose "Northwell printer mapping ($printerMode)")
        $printerBootstrap = Resolve-SasInstalledPrinterBootstrap
        if ($printerOffline) {
            Write-Host "Printer entrypoint: explicit local-only bootstrap ($printerMode); current origin is NOT claimed." -ForegroundColor Yellow
            & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $printerBootstrap -RequiredCommit '66d38dd45881692303f77267e29e4fa44b4a9351' -Mode $printerMode -UseLocalRuntimeOnly
        }
        else {
            Write-Host "Printer entrypoint: current-origin bootstrap ($printerMode); no repository path is required." -ForegroundColor Green
            & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $printerBootstrap -RequiredCommit '66d38dd45881692303f77267e29e4fa44b4a9351' -Mode $printerMode
        }
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
                if ($mode -eq 'remote') {
                    $bootstrap = Resolve-SasInstalledAutoLogonBootstrap
                    Write-Host 'AutoLogon entrypoint: sealed crash-safe bootstrap; durable field evidence REQUIRED.' -ForegroundColor Green
                    & $bootstrap $target
                    exit $LASTEXITCODE
                }

                # Recovery stays recovery-only. Do not send Recover through the deployment bootstrap.
                $recoveryLauncher = Join-Path $runtimeRoot 'Run-AutoLogonOnsite.cmd'
                if (-not (Test-Path -LiteralPath $recoveryLauncher -PathType Leaf)) {
                    throw "Canonical local AutoLogon recovery launcher is missing from runtime: $recoveryLauncher"
                }
                & $recoveryLauncher Recover $target
                exit $LASTEXITCODE
            }
        }
        Invoke-SasLegacyDispatcher
    }

    'cybernet' {
        if ($actualArgs.Count -gt 0) {
            $mode = ([string]$actualArgs[0]).Trim().ToLowerInvariant()
            if ($mode -eq 'canary') {
                $targets = @($actualArgs | Select-Object -Skip 1)
                if ($targets.Count -eq 0) {
                    Write-Host 'Usage: sas cybernet canary HOST01 [HOST02 ...]' -ForegroundColor Red
                    exit 2
                }
                [void](Assert-SasProtectedForAction -Purpose "Cybernet low-noise canary for $($targets.Count) explicit targets")
                $canary = Join-Path $controllerRoot 'survey\sas-cybernet-canary.ps1'
                if (-not (Test-Path -LiteralPath $canary -PathType Leaf)) {
                    throw "Cybernet canary runtime is not present in the active controller: $controllerRoot. Run 'sas refresh' on Guest/Internet to install the current sealed runtime."
                }
                & $canary -Target $targets
                exit 0
            }
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
