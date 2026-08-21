#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command,
    [Parameter(ValueFromRemainingArguments=$true)][AllowEmptyString()][string[]]$CommandArgs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$platformPath = Join-Path $PSScriptRoot 'SasFieldPlatform.psm1'
$intentPath = Join-Path $PSScriptRoot 'SasNetworkIntent.psm1'
$universalPath = Join-Path $PSScriptRoot 'Invoke-SasUniversalField.ps1'
foreach ($required in @($platformPath,$intentPath,$universalPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing network-aware field dependency: $required"
    }
}
Import-Module $platformPath -Force
Import-Module $intentPath -Force

$callerRoot = try { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path } catch { $null }
$controllerRoot = Resolve-SasControllerRoot -CallerRoot $callerRoot
$runtimeRoot = Resolve-SasExecutionRuntimeRoot -ControllerRoot $controllerRoot
$env:SAS_REPO_ROOT = $controllerRoot
$env:SAS_RUNTIME_ROOT = $runtimeRoot

$normalized = if ([string]::IsNullOrWhiteSpace($Command)) { '' } else { $Command.Trim().ToLowerInvariant() }
$actualArgs = @($CommandArgs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$intent = 'CommandSpecific'

switch ($normalized) {
    '' { $intent = 'LocalOnly' }
    'platform' { $intent = 'LocalOnly' }
    'clipboard' { $intent = 'LocalOnly' }
    'refresh' { $intent = 'InternetSync' }
    'printer' { $intent = 'ProtectedNorthwell' }
    'network' {
        if ($actualArgs.Count -eq 0) { $intent = 'LocalOnly' }
        else { $intent = 'ProtectedNorthwell' }
    }
    'autologon' {
        if ($actualArgs.Count -gt 0 -and ([string]$actualArgs[0]).Trim().ToLowerInvariant() -in @('remote','recover')) {
            $intent = 'ProtectedNorthwell'
        }
    }
    'cybernet' {
        if ($actualArgs.Count -gt 0 -and ([string]$actualArgs[0]).Trim().ToLowerInvariant() -in @('probe','deploy','core','profiled-core','recover')) {
            $intent = 'ProtectedNorthwell'
        }
    }
}

$transition = $null
$childExit = 1
$restoreFailed = $false
try {
    $transition = Enter-SasNetworkIntent -Intent $intent -RepoRoot $controllerRoot -AllowAutomaticWlanTransition
    $childArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$universalPath)
    if (-not [string]::IsNullOrWhiteSpace($Command)) { $childArgs += $Command }
    if ($actualArgs.Count -gt 0) { $childArgs += $actualArgs }
    & powershell.exe @childArgs
    $childExit = [int]$global:LASTEXITCODE
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    $childExit = 1
}
finally {
    if ($null -ne $transition) {
        try {
            Restore-SasNetworkIntent -Transition $transition -RepoRoot $controllerRoot
        }
        catch {
            $restoreFailed = $true
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host 'NETWORK RESTORE REQUIRES OPERATOR ATTENTION. The command result is not promoted to success until the requested return posture is restored.' -ForegroundColor Red
        }
    }
}

if ($restoreFailed -and $childExit -eq 0) { $childExit = 1 }
exit $childExit
