[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ApprovedCommit,
    [string]$ReleaseRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\Bluetooth\Releases')
)
$ErrorActionPreference='Stop'

# The installer travels INSIDE the coordinator-prepared bundle. It does not
# fetch Git, change a running release, require an SDK, or touch the radio.
$bundleRoot=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'SasBluetoothRuntime.psm1') -Force
$stage=$null
try {
    $null=Test-SasBluetoothBundle $bundleRoot
    $manifest=Get-Content -LiteralPath (Join-Path $bundleRoot 'bluetooth-bundle.json') -Raw | ConvertFrom-Json
    if($manifest.SourceCommit -cne $ApprovedCommit.ToLowerInvariant()) {
        throw 'SOURCE_COMMIT_NOT_APPROVED: verify the exact release against refreshed provider truth.'
    }
    $root=[IO.Path]::GetFullPath($ReleaseRoot)
    $source=[IO.Path]::GetFullPath($bundleRoot)
    if($root.TrimEnd('\') -eq $source.TrimEnd('\') -or
       $root.StartsWith($source.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'RELEASE_ROOT_MUST_BE_OUTSIDE_SOURCE_BUNDLE'
    }
    if(-not (Test-Path -LiteralPath $root)){New-Item -ItemType Directory -Path $root -Force | Out-Null}
    $target=Join-Path $root ('release-'+$ApprovedCommit.ToLowerInvariant())
    if(Test-Path -LiteralPath $target){throw 'RELEASE_ALREADY_EXISTS: do not overwrite last-known-good.'}
    $stage=Join-Path $root ('.pending-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
    foreach($item in (Get-ChildItem -LiteralPath $source -Force -ErrorAction Stop)) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $stage $item.Name) -Recurse -Force -ErrorAction Stop
    }
    $null=Test-SasBluetoothBundle $stage
    if(Test-Path -LiteralPath $target){throw 'RELEASE_TARGET_RACE: refusing overwrite.'}
    Move-Item -LiteralPath $stage -Destination $target -ErrorAction Stop
    $stage=$null
    [ordered]@{
        Status='VERIFIED_SIDE_BY_SIDE_RELEASE'
        SourceCommit=$ApprovedCommit.ToLowerInvariant()
        Entrypoint=(Join-Path $target 'SasBluetooth.cmd')
        DiagnosticEntrypoint=(Join-Path $target 'Recover-BluetoothPeripheral.cmd')
        AutoActivated=$false
        ExistingReleasesPreserved=$true
        HostBluetoothChanged=$false
        ReleaseFolder=$target
    } | ConvertTo-Json -Depth 3
} catch {
    Write-Error ('RELEASE_NOT_INSTALLED: '+$_.Exception.Message)
    exit 1
} finally {
    if($stage -and (Test-Path -LiteralPath $stage)) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
