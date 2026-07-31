#Requires -Version 5.1
<#
.SYNOPSIS
Return the operator workstation from protected Northwell Wi-Fi to its previously recorded guest/internet Wi-Fi profile.

.DESCRIPTION
Reads the machine-local SysAdminSuite operator session, requires an exact previously recorded
GUEST_INTERNET Wi-Fi label, proves that label is a saved Windows WLAN profile, requests that saved
profile through bounded local netsh, verifies the exact transition locally, and updates the operator
session. It performs no target contact or target mutation and never reads or stores Wi-Fi secrets.
#>
[CmdletBinding()]
param(
    [ValidateRange(10,120)][int]$TransitionTimeoutSeconds = 45,
    [ValidateRange(3,30)][int]$NativeTimeoutSeconds = 10
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot=(Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$sessionModule=Join-Path -Path $PSScriptRoot -ChildPath 'SasOperatorSession.psm1'
$networkModule=Join-Path -Path $PSScriptRoot -ChildPath 'SasNetworkGuard.psm1'
$boundedModule=Join-Path -Path $PSScriptRoot -ChildPath 'SasBoundedNative.psm1'
foreach ($required in @($sessionModule,$networkModule,$boundedModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing network-return dependency: $required"
    }
}
Import-Module $sessionModule -Force
Import-Module $networkModule -Force
Import-Module $boundedModule -Force

$session=Read-SasOperatorSession
$previousClassification=[string](Get-SasObjectPropertyValue -Object $session -Name 'last_network_classification' -Default 'UNKNOWN')
$previousLabel=[string](Get-SasObjectPropertyValue -Object $session -Name 'last_network_label' -Default $null)
$current=Get-SasOperatorNetworkClassification -RepoRoot $repoRoot

if ($previousClassification -ne 'GUEST_INTERNET') {
    throw "No previously recorded guest/internet network is available. Recorded previous classification: $previousClassification"
}
if ([string]::IsNullOrWhiteSpace($previousLabel) -or $previousLabel -eq 'unknown') {
    throw 'The previous guest/internet Wi-Fi label was not recorded. Nothing was changed.'
}
if (Test-SasNorthwellWifiSsid -Ssid $previousLabel) {
    throw 'The recorded previous Wi-Fi label is an approved protected Northwell profile; refusing to use it as the leave-protected destination.'
}

Write-Host "`n=== RETURN TO PREVIOUS NETWORK ===" -ForegroundColor Cyan
Write-Host "Current:  $($current.classification) [$($current.label)]"
Write-Host "Previous: $previousClassification [$previousLabel]"
Write-Host 'Target contact: NO' -ForegroundColor Green
Write-Host 'Target mutation: NO' -ForegroundColor Green

if ([string]$current.label -eq $previousLabel) {
    [void](Set-SasOperatorSessionValues -Values @{
        current_network_classification='GUEST_INTERNET'
        current_network_label=$previousLabel
    })
    Write-Host 'Already connected to the previously recorded guest/internet network.' -ForegroundColor Green
    Write-Host 'SAS_OPERATOR_RETURNED_TO_PREVIOUS_NETWORK' -ForegroundColor Green
    exit 0
}

$netsh=Join-Path -Path $env:WINDIR -ChildPath 'System32\netsh.exe'
$profiles=Invoke-SasBoundedNative -FilePath $netsh -Arguments @('wlan','show','profiles') -TimeoutSeconds $NativeTimeoutSeconds
if ($profiles.timed_out) { throw "Timed out listing saved WLAN profiles after $NativeTimeoutSeconds seconds." }
if ($profiles.exit_code -ne 0) { throw "Could not list saved WLAN profiles. Exit=$($profiles.exit_code) $($profiles.error)" }

$savedProfiles=New-Object 'System.Collections.Generic.List[string]'
foreach ($line in (([string]$profiles.output) -split "`r?`n")) {
    if ($line -notmatch '^\s*(?:All User Profile|User Profile)\s*:\s*(.+?)\s*$') { continue }
    $name=$Matches[1].Trim()
    if ($name -and -not $savedProfiles.Contains($name)) { [void]$savedProfiles.Add($name) }
}
if (-not $savedProfiles.Contains($previousLabel)) {
    throw "The previously recorded guest/internet network is not a saved Windows WLAN profile: $previousLabel"
}

Write-Host "Connecting to saved previous profile: $previousLabel" -ForegroundColor Cyan
$connect=Invoke-SasBoundedNative -FilePath $netsh -Arguments @('wlan','connect',("name={0}" -f $previousLabel)) -TimeoutSeconds $NativeTimeoutSeconds
if ($connect.timed_out) { throw "Timed out asking Windows to connect to $previousLabel." }
if ($connect.exit_code -ne 0) { throw "Windows rejected the saved-profile connection request. Exit=$($connect.exit_code) $($connect.error)" }

$deadline=(Get-Date).AddSeconds($TransitionTimeoutSeconds)
$observed=$null
while ((Get-Date) -lt $deadline) {
    $observed=Get-SasCurrentWifiSsid
    if (-not [string]::IsNullOrWhiteSpace($observed) -and $observed.Equals($previousLabel,[StringComparison]::OrdinalIgnoreCase)) { break }
    Start-Sleep -Seconds 2
}
if ([string]::IsNullOrWhiteSpace($observed) -or -not $observed.Equals($previousLabel,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Windows accepted the saved-profile request, but the exact previous network was not observed within $TransitionTimeoutSeconds seconds. Last observed label: $observed"
}

[void](Set-SasOperatorSessionValues -Values @{
    current_network_classification='GUEST_INTERNET'
    current_network_label=$previousLabel
})

Write-Host "Connected: $previousLabel" -ForegroundColor Green
Write-Host 'SAS_OPERATOR_RETURNED_TO_PREVIOUS_NETWORK' -ForegroundColor Green
Write-Host 'No target was contacted or mutated.' -ForegroundColor Green
exit 0
