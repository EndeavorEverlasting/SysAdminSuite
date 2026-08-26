#Requires -Version 5.1
<#
.SYNOPSIS
Run the full Cybernet software deployment from the canonical sealed C:\SASAL runtime.

.DESCRIPTION
This protected-network admission layer is intentionally local before deployment. It requires the exact
C:\SASAL runtime, resolves the Guest-created manifest authority, runs the complete tracked-file seal audit,
then opens every tracked runtime file read-only with FileShare.Read and re-hashes it while that write/delete
exclusion is held. Those handles remain open for the entire canonical Cybernet deployment, preventing a
tracked runtime file from changing between verification and target mutation.

The manifest/seal/lock phases perform no Git network activity and no target contact. The existing Cybernet
software orchestrator remains the sole owner of target readiness, package deployment, AutoLogon ordering,
and restart completion evidence.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$RuntimeRoot = 'C:\SASAL',

    [string]$ExpectedCommit
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasJsonPropertyValue {
    param([AllowNull()]$Object,[Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-SasSha256FromStream {
    param([Parameter(Mandatory = $true)][IO.FileStream]$Stream)
    $sha = $null
    try {
        $Stream.Position = 0
        $sha = [Security.Cryptography.SHA256]::Create()
        $hash = $sha.ComputeHash($Stream)
        $Stream.Position = 0
        return ([BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
    }
}

function Close-SasRuntimeLocks {
    param([AllowNull()][object[]]$Locks)
    foreach ($item in @($Locks)) {
        if ($null -eq $item) { continue }
        try {
            if ($null -ne $item.stream) { $item.stream.Dispose() }
        }
        catch { }
    }
}

function Invoke-SasChildPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$PowerShellExe,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [AllowNull()][string[]]$Arguments
    )
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $PowerShellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments | Out-Host
        return [int]$global:LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Lock-SasTrackedRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$CanonicalRuntime,
        [Parameter(Mandatory = $true)]$Manifest
    )

    $algorithm = [string](Get-SasJsonPropertyValue -Object $Manifest -Name 'tracked_file_hash_algorithm')
    if ($algorithm -ne 'SHA256') { throw "CYBERNET_SEALED_RUNTIME_HASH_ALGORITHM_INVALID: $algorithm" }

    $entries = @((Get-SasJsonPropertyValue -Object $Manifest -Name 'tracked_file_hashes'))
    $countValue = Get-SasJsonPropertyValue -Object $Manifest -Name 'tracked_file_count'
    $declaredCount = 0
    if (-not [int]::TryParse(([string]$countValue).Trim(),[ref]$declaredCount) -or
        $declaredCount -lt 1 -or $entries.Count -ne $declaredCount) {
        throw "CYBERNET_SEALED_RUNTIME_COUNT_INVALID: declared=$countValue actual=$($entries.Count)"
    }

    $runtimePrefix = $CanonicalRuntime.TrimEnd('\') + '\'
    $locks = @()
    try {
        foreach ($entry in $entries) {
            $relative = [string](Get-SasJsonPropertyValue -Object $entry -Name 'path')
            $expectedHash = ([string](Get-SasJsonPropertyValue -Object $entry -Name 'sha256')).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) {
                throw "CYBERNET_SEALED_RUNTIME_TRACKED_PATH_INVALID: $relative"
            }
            if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
                throw "CYBERNET_SEALED_RUNTIME_EXPECTED_HASH_INVALID: $relative"
            }

            $relativeWindows = $relative.Replace('/','\')
            $fullPath = [IO.Path]::GetFullPath((Join-Path $CanonicalRuntime $relativeWindows))
            if (-not $fullPath.StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) {
                throw "CYBERNET_SEALED_RUNTIME_TRACKED_PATH_ESCAPE: $relative"
            }
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw "CYBERNET_SEALED_RUNTIME_TRACKED_FILE_MISSING: $relative"
            }

            # FileShare.Read permits later readers (PowerShell loading scripts/configs) but denies writers
            # and delete/replace operations for the life of this handle.
            $stream = [IO.File]::Open(
                $fullPath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::Read
            )
            $actualHash = Get-SasSha256FromStream -Stream $stream
            if ($actualHash -ne $expectedHash) {
                $stream.Dispose()
                throw "CYBERNET_SEALED_RUNTIME_RECHECK_MISMATCH: $relative"
            }
            $locks += [pscustomobject]@{ path=$relative; stream=$stream }
        }
        return @($locks)
    }
    catch {
        Close-SasRuntimeLocks -Locks $locks
        throw
    }
}

$canonicalRuntime = [IO.Path]::GetFullPath('C:\SASAL').TrimEnd('\')
try { $runtimeFull = [IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\') }
catch { throw "CYBERNET_SEALED_RUNTIME_AUTHORITY_INVALID: $($_.Exception.Message)" }
if (-not $runtimeFull.Equals($canonicalRuntime,[StringComparison]::OrdinalIgnoreCase)) {
    throw "CYBERNET_SEALED_RUNTIME_AUTHORITY_INVALID: required=$canonicalRuntime actual=$runtimeFull"
}

$target = $ComputerName.Trim().TrimEnd('.')
if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw "CYBERNET_SEALED_TARGET_INVALID: $target"
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and
    $ExpectedCommit.Trim() -notmatch '^(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{64})$') {
    throw "CYBERNET_SEALED_EXPECTED_COMMIT_INVALID: $ExpectedCommit"
}

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$manifestResolver = Join-Path $runtimeFull 'scripts\Resolve-SasAutoLogonManifestAuthority.ps1'
$auditScript = Join-Path $runtimeFull 'scripts\Test-SasAutoLogonRuntimeSeal.ps1'
$engineScript = Join-Path $runtimeFull 'scripts\Invoke-SasCybernetSoftwareDeployment.ps1'
$runtimeManifest = Join-Path $runtimeFull '.git\sas-autologon-short-runtime.json'
foreach ($required in @($psExe,$manifestResolver,$auditScript,$engineScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "CYBERNET_SEALED_RUNTIME_DEPENDENCY_MISSING: $required"
    }
}

$resolverArgs = @('-RuntimeRoot',$runtimeFull,'-RequireManifest')
if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit)) {
    $resolverArgs += @('-ExpectedCommit',$ExpectedCommit.Trim())
}
Write-Host 'CYBERNET SEALED ADMISSION: resolving manifest authority (no target contact).' -ForegroundColor Cyan
$resolverExit = Invoke-SasChildPowerShell -PowerShellExe $psExe -ScriptPath $manifestResolver -Arguments $resolverArgs
if ($resolverExit -ne 0) {
    throw "CYBERNET_SEALED_MANIFEST_AUTHORITY_FAILED: exit=$resolverExit"
}

$auditArgs = @('-RuntimeRoot',$runtimeFull)
if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit)) {
    $auditArgs += @('-ExpectedCommit',$ExpectedCommit.Trim())
}
Write-Host 'CYBERNET SEALED ADMISSION: auditing complete tracked runtime (no target contact).' -ForegroundColor Cyan
$auditExit = Invoke-SasChildPowerShell -PowerShellExe $psExe -ScriptPath $auditScript -Arguments $auditArgs
if ($auditExit -ne 0) {
    throw "CYBERNET_SEALED_RUNTIME_AUDIT_FAILED: exit=$auditExit"
}

if (-not (Test-Path -LiteralPath $runtimeManifest -PathType Leaf)) {
    throw "CYBERNET_SEALED_RUNTIME_MANIFEST_MISSING_AFTER_RESOLUTION: $runtimeManifest"
}
$manifest = Get-Content -LiteralPath $runtimeManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$preparedCommit = ([string](Get-SasJsonPropertyValue -Object $manifest -Name 'prepared_commit')).Trim()
if ([string]::IsNullOrWhiteSpace($preparedCommit)) {
    throw 'CYBERNET_SEALED_RUNTIME_PREPARED_COMMIT_MISSING'
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and
    -not $preparedCommit.Equals($ExpectedCommit.Trim(),[StringComparison]::OrdinalIgnoreCase)) {
    throw "CYBERNET_SEALED_RUNTIME_PREPARED_COMMIT_MISMATCH: expected=$($ExpectedCommit.Trim()) prepared=$preparedCommit"
}

$locks = @()
$deploymentExit = 1
try {
    Write-Host 'CYBERNET SEALED ADMISSION: acquiring write/delete exclusion and re-hashing every tracked file.' -ForegroundColor Cyan
    $locks = @(Lock-SasTrackedRuntime -CanonicalRuntime $runtimeFull -Manifest $manifest)
    Write-Host "CYBERNET_SEALED_RUNTIME_LOCKED: $($locks.Count) tracked files verified and write-protected for this process." -ForegroundColor Green
    Write-Host 'Protected Git network activity: NONE' -ForegroundColor Green
    Write-Host "Prepared commit: $preparedCommit" -ForegroundColor Green

    # The engine is invoked with PassThru so its normal trailing `exit 0` path is not taken; this parent
    # process therefore retains every tracked-file lock until the complete deployment call returns.
    $deployment = & $engineScript -ComputerName $target -AllowTargetMutation -ConfirmDeployment -PassThru
    if ($null -eq $deployment -or [string]$deployment.status -ne 'CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED') {
        $observed = if ($null -eq $deployment) { '<no result>' } else { [string]$deployment.status }
        throw "CYBERNET_SEALED_DEPLOYMENT_NOT_COMPLETE: $observed"
    }
    $deploymentExit = 0
}
catch {
    Write-Error $_
    $deploymentExit = 1
}
finally {
    Close-SasRuntimeLocks -Locks $locks
    if ($locks.Count -gt 0) {
        Write-Host 'CYBERNET_SEALED_RUNTIME_UNLOCKED: deployment process ended; tracked-file locks released.' -ForegroundColor DarkGray
    }
}

exit $deploymentExit
