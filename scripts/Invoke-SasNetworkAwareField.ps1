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

function Test-SasPrinterShapeForNetworkTransition {
    [CmdletBinding()]
    param([string[]]$Arguments)

    $values = @($Arguments)
    if ($values.Count -gt 2) { return $false }
    $modeSeen = $false
    $offlineSeen = $false
    foreach ($raw in $values) {
        $value = ([string]$raw).Trim().ToLowerInvariant()
        if ($value -in @('file','batch')) {
            if ($modeSeen) { return $false }
            $modeSeen = $true
            continue
        }
        if ($value -eq 'offline') {
            if ($offlineSeen) { return $false }
            $offlineSeen = $true
            continue
        }
        return $false
    }
    return $true
}

function Test-SasAdHostNameForNetworkTransition {
    param([AllowNull()][string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$'
}

function Test-SasAdManagedOuForNetworkTransition {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $forbiddenPattern = '(?i)(?:^|,)OU=(?:Workstations|Shared_Workstations),OU=_Workstations(?:,|$)'
    if ($Value -match $forbiddenPattern) { return $false }
    $managedPattern = '(?i)(?:^|,)OU=(?:Managed|Managed_Shared),OU=_Workstations(?:,|$)'
    return [bool]($Value -match $managedPattern)
}

function Test-SasAdOuShapeForNetworkTransition {
    [CmdletBinding()]
    param([string[]]$Arguments)

    $values = @($Arguments)
    if ($values.Count -lt 3) { return $false }
    if (([string]$values[0]).Trim().ToLowerInvariant() -ne 'ou') { return $false }
    $mode = ([string]$values[1]).Trim().ToLowerInvariant()
    switch ($mode) {
        'probe' {
            if ($values.Count -lt 3 -or $values.Count -gt 27) { return $false }
            foreach ($value in @($values | Select-Object -Skip 2)) {
                if (-not (Test-SasAdHostNameForNetworkTransition -Value ([string]$value))) { return $false }
            }
            return $true
        }
        'plan' {
            if ($values.Count -ne 4) { return $false }
            return (Test-SasAdHostNameForNetworkTransition -Value ([string]$values[2])) -and
                (Test-SasAdManagedOuForNetworkTransition -Value ([string]$values[3]))
        }
        'apply' {
            if ($values.Count -ne 5) { return $false }
            return (Test-SasAdHostNameForNetworkTransition -Value ([string]$values[2])) -and
                (Test-SasAdManagedOuForNetworkTransition -Value ([string]$values[3])) -and
                (-not [string]::IsNullOrWhiteSpace([string]$values[4]))
        }
        default { return $false }
    }
}

function Test-SasCanaryTargetForNetworkTransition {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $candidate = $Value.Trim()
    if ($candidate -match '[/*?\[\]]') { return $false }
    if ($candidate -match '^\d{1,3}(?:\.\d{1,3}){3}\s*-\s*\d') { return $false }
    if ($candidate -match '^\d{1,3}(?:\.\d{1,3}){3}\s*-\s*\d{1,3}(?:\.\d{1,3}){3}$') { return $false }
    if ($candidate -match '\.\.') { return $false }

    $ip = $null
    if ([System.Net.IPAddress]::TryParse($candidate, [ref]$ip)) { return $true }
    if ($candidate -match '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$') { return $true }
    if ($candidate -match '^[A-Za-z0-9]+[-_][A-Za-z0-9_-]+$') { return $true }
    if ($candidate -match '^[A-Za-z]{2,6}[0-9]{2,}[A-Za-z0-9_-]*$') { return $true }
    return $false
}

function Test-SasCybernetShapeForNetworkTransition {
    [CmdletBinding()]
    param([string[]]$Arguments)

    $values = @($Arguments)
    if ($values.Count -lt 2) { return $false }
    $mode = ([string]$values[0]).Trim().ToLowerInvariant()
    if ($mode -eq 'canary') {
        if ($values.Count -gt 6) { return $false }
        foreach ($value in @($values | Select-Object -Skip 1)) {
            if (-not (Test-SasCanaryTargetForNetworkTransition -Value ([string]$value))) { return $false }
        }
        return $true
    }
    return $mode -in @('probe','deploy','core','profiled-core','recover')
}

# Determine whether a command can actually reach a network-sensitive product path before any
# WLAN transition is allowed. Invalid/incomplete shapes still flow to the canonical dispatcher for
# its usage/error result, but they remain CommandSpecific so they cannot cause a disruptive switch.
switch ($normalized) {
    '' { $intent = 'LocalOnly' }
    'platform' { $intent = 'LocalOnly' }
    'clipboard' { $intent = 'LocalOnly' }
    'refresh' {
        if ($actualArgs.Count -eq 0) { $intent = 'InternetSync' }
    }
    'printer' {
        if (Test-SasPrinterShapeForNetworkTransition -Arguments $actualArgs) { $intent = 'ProtectedNorthwell' }
    }
    'network' {
        if ($actualArgs.Count -eq 0) { $intent = 'LocalOnly' }
        elseif ($actualArgs.Count -eq 1) { $intent = 'ProtectedNorthwell' }
    }
    'ad' {
        if (Test-SasAdOuShapeForNetworkTransition -Arguments $actualArgs) { $intent = 'ProtectedNorthwell' }
    }
    'autologon' {
        if ($actualArgs.Count -eq 2 -and ([string]$actualArgs[0]).Trim().ToLowerInvariant() -in @('remote','recover')) {
            $intent = 'ProtectedNorthwell'
        }
    }
    'cybernet' {
        if (Test-SasCybernetShapeForNetworkTransition -Arguments $actualArgs) {
            $intent = 'ProtectedNorthwell'
        }
    }
}

$transition = $null
$childExit = 1
$restoreFailed = $false
$networkMutex = $null
$networkLockTaken = $false
$serializedIntent = $intent -in @('InternetSync','ProtectedNorthwell')

try {
    if ($serializedIntent) {
        $networkMutex = New-Object System.Threading.Mutex($false, 'Global\SysAdminSuite.NetworkIntent.v1')
        try {
            $networkLockTaken = $networkMutex.WaitOne(0)
        }
        catch [System.Threading.AbandonedMutexException] {
            # The previous owner exited without releasing the mutex. Windows grants ownership to
            # this process, so continue from freshly observed network state under the acquired lock.
            $networkLockTaken = $true
            Write-Warning 'Recovered an abandoned SysAdminSuite network-intent lock; current network state will be re-proven before execution.'
        }
        if (-not $networkLockTaken) {
            [void](Write-SasNetworkCanary -Intent $intent -RepoRoot $controllerRoot -TransitionStatus 'BLOCKED_BY_CONCURRENT_NETWORK_TRANSACTION')
            throw 'SAS_NETWORK_TRANSITION_BUSY: another SysAdminSuite network-sensitive command owns the controller network transaction. No network change was made by this invocation.'
        }
    }

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

    if ($networkLockTaken -and $null -ne $networkMutex) {
        try { $networkMutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $networkMutex) { $networkMutex.Dispose() }
}

if ($restoreFailed -and $childExit -eq 0) { $childExit = 1 }
exit $childExit
