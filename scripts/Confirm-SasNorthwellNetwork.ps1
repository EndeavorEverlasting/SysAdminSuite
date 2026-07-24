#Requires -Version 5.1
<#
.SYNOPSIS
Fail-closed local network posture gate for on-site target operations.

.DESCRIPTION
Reads local Wi-Fi and network configuration evidence through SasNetworkGuard.
It never creates Wi-Fi profiles, stores credentials, probes a target, or mutates a target.
When the current posture is not approved, an interactive operator may explicitly confirm a switch
to an already-saved approved Wi-Fi profile, open Windows Wi-Fi settings and recheck, or cancel
before the target operation starts.

A successful saved-profile switch is not accepted from the netsh exit code alone. The gate waits
for the Wi-Fi connection to leave the prior network label, finish Windows "Identifying..." state,
and reach usable connectivity. That verified transition is trusted only for the lifetime of this
process when Windows withholds the actual SSID.
#>
[CmdletBinding()]
param(
    [string]$Purpose = 'target operation',
    [string]$Ssid,
    [string]$NetworkTextPath,
    [switch]$NonInteractive,
    [switch]$NoOpenWifiSettings,
    [ValidateRange(5,120)][int]$SwitchVerificationTimeoutSeconds = 45
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$guardModule = Join-Path $repoRoot 'scripts\SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $guardModule -PathType Leaf)) {
    throw "Missing shared network guard module: $guardModule"
}
Import-Module $guardModule -Force

$outputRoot = Join-Path $repoRoot 'survey\output\network_posture'
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$callerSuppliedSsid = $PSBoundParameters.ContainsKey('Ssid')
$callerNetworkTextPath = if ($NetworkTextPath) {
    (Resolve-Path -LiteralPath $NetworkTextPath -ErrorAction Stop).Path
}
else {
    $null
}
$script:localNetworkSwitchAttempted = $false
$script:confirmedApprovedProfile = $null
$script:switchVerification = $null

function Get-SasApprovedSavedWifiProfiles {
    try {
        $text = (& netsh wlan show profiles 2>$null | Out-String)
        $profiles = New-Object System.Collections.Generic.List[string]
        foreach ($line in ($text -split "`r?`n")) {
            if ($line -notmatch '^\s*(?:All User Profile|User Profile)\s*:\s*(.+?)\s*$') { continue }
            $name = $Matches[1].Trim()
            if ((Test-SasNorthwellWifiSsid -Ssid $name) -and -not $profiles.Contains($name)) {
                [void]$profiles.Add($name)
            }
        }
        return @($profiles)
    }
    catch {
        return @()
    }
}

function Get-SasActiveWifiConnectionProfile {
    try {
        $profiles = @(Get-NetConnectionProfile -ErrorAction Stop)
        $wifiProfiles = @($profiles | Where-Object {
            ([string]$_.InterfaceAlias) -match '(?i)(wi-?fi|wireless|wlan)'
        })
        if ($wifiProfiles.Count -eq 0) { return $null }

        $preferred = @($wifiProfiles | Where-Object {
            ([string]$_.IPv4Connectivity) -in @('Subnet','LocalNetwork','Internet') -or
            ([string]$_.IPv6Connectivity) -in @('Subnet','LocalNetwork','Internet')
        })
        $profile = if ($preferred.Count -gt 0) { $preferred[0] } else { $wifiProfiles[0] }

        return [pscustomobject][ordered]@{
            name = [string]$profile.Name
            interface_alias = [string]$profile.InterfaceAlias
            ipv4_connectivity = [string]$profile.IPv4Connectivity
            ipv6_connectivity = [string]$profile.IPv6Connectivity
        }
    }
    catch {
        return $null
    }
}

function Test-SasUsableWifiConnectivity {
    param([AllowNull()]$Profile)
    if ($null -eq $Profile) { return $false }
    $usable = @('Subnet','LocalNetwork','Internet')
    return (([string]$Profile.ipv4_connectivity) -in $usable) -or (([string]$Profile.ipv6_connectivity) -in $usable)
}

function Test-SasStableNetworkLabel {
    param([AllowNull()][string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { return $false }
    return $Label.Trim() -notmatch '^(?i:unknown|identifying(?:\.\.\.)?|unidentified network)$'
}

function Wait-SasApprovedSavedProfileTransition {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedProfile,
        [AllowNull()][string]$PreviousNetworkLabel,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    if (-not (Test-SasNorthwellWifiSsid -Ssid $ExpectedProfile)) {
        throw "Saved profile is not approved by the Northwell Wi-Fi policy: $ExpectedProfile"
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastProfile = $null
    $lastObservedLabel = $null
    while ((Get-Date) -lt $deadline) {
        $observedLabel = Get-SasCurrentWifiSsid
        $lastObservedLabel = $observedLabel
        if (Test-SasNorthwellWifiSsid -Ssid $observedLabel) {
            return [pscustomobject][ordered]@{
                verified = $true
                evidence_source = 'direct_approved_network_label'
                approved_profile = $ExpectedProfile
                previous_network_label = $PreviousNetworkLabel
                observed_network_label = $observedLabel
                active_profile = Get-SasActiveWifiConnectionProfile
            }
        }

        $active = Get-SasActiveWifiConnectionProfile
        $lastProfile = $active
        if ($null -ne $active -and (Test-SasStableNetworkLabel -Label $active.name) -and (Test-SasUsableWifiConnectivity -Profile $active)) {
            $baselineUsable = Test-SasStableNetworkLabel -Label $PreviousNetworkLabel
            $changedFromBaseline = $baselineUsable -and -not ([string]$active.name).Equals([string]$PreviousNetworkLabel, [StringComparison]::OrdinalIgnoreCase)
            if ($changedFromBaseline) {
                return [pscustomobject][ordered]@{
                    verified = $true
                    evidence_source = 'confirmed_saved_profile_network_transition'
                    approved_profile = $ExpectedProfile
                    previous_network_label = $PreviousNetworkLabel
                    observed_network_label = [string]$active.name
                    active_profile = $active
                }
            }
        }

        Start-Sleep -Seconds 2
    }

    return [pscustomobject][ordered]@{
        verified = $false
        evidence_source = 'saved_profile_switch_not_verified'
        approved_profile = $ExpectedProfile
        previous_network_label = $PreviousNetworkLabel
        observed_network_label = $lastObservedLabel
        active_profile = $lastProfile
    }
}

function Get-SasOperatorNetworkPosture {
    $observedNetworkLabel = if ($callerSuppliedSsid) { [string]$Ssid } else { Get-SasCurrentWifiSsid }
    $networkText = if ($callerNetworkTextPath) {
        Get-Content -LiteralPath $callerNetworkTextPath -Raw -ErrorAction Stop
    }
    else {
        Get-SasLocalNetworkText
    }

    $directWifiApproved = Test-SasNorthwellWifiSsid -Ssid $observedNetworkLabel
    $confirmedSwitchApproved = $false
    if (-not $directWifiApproved -and -not [string]::IsNullOrWhiteSpace([string]$script:confirmedApprovedProfile) -and $null -ne $script:switchVerification) {
        $confirmedSwitchApproved = [bool]$script:switchVerification.verified -and (Test-SasNorthwellWifiSsid -Ssid $script:confirmedApprovedProfile)
    }

    $wifiApproved = ($directWifiApproved -or $confirmedSwitchApproved)
    $effectiveApprovedProfile = if ($directWifiApproved) { $observedNetworkLabel } elseif ($confirmedSwitchApproved) { [string]$script:confirmedApprovedProfile } else { $null }
    $wifiEvidenceSource = if ($directWifiApproved) { 'direct_network_label' } elseif ($confirmedSwitchApproved) { [string]$script:switchVerification.evidence_source } else { 'none' }

    $wiredApproved = $false
    if (-not $wifiApproved) {
        $wiredApproved = Test-SasNorthwellWiredEvidence -NetworkText $networkText
    }

    $approved = ($wifiApproved -or $wiredApproved)
    $classification = if ($approved) {
        'OK_NETWORK_POSTURE'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($observedNetworkLabel) -and $observedNetworkLabel -ne 'unknown') {
        'ENVIRONMENT_BLOCKED_GUEST_NETWORK'
    }
    else {
        'ENVIRONMENT_BLOCKED_NETWORK_INCONCLUSIVE'
    }

    [pscustomobject][ordered]@{
        schema_version = 'sas-operator-network-posture/v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        purpose = $Purpose
        classification = $classification
        allowed_for_target_operation = $approved
        observed_wifi_network_label = $observedNetworkLabel
        approved_wifi_profile = $effectiveApprovedProfile
        wifi_evidence_source = $wifiEvidenceSource
        wifi_approved = $wifiApproved
        wired_approved = $wiredApproved
        local_network_switch_attempted = $script:localNetworkSwitchAttempted
        switch_verification = $script:switchVerification
        network_activity_performed = $script:localNetworkSwitchAttempted
        target_contact_performed = $false
        target_mutation_performed = $false
    }
}

function Write-SasOperatorNetworkEvidence {
    param([Parameter(Mandatory = $true)]$Posture)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $path = Join-Path $outputRoot "operator_network_posture_$stamp.json"
    $Posture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Select-SasApprovedWifiProfile {
    param([string[]]$Profiles)
    if ($Profiles.Count -eq 0) { return $null }
    if ($Profiles.Count -eq 1) { return $Profiles[0] }

    Write-Host 'Saved approved Wi-Fi profiles:' -ForegroundColor Cyan
    for ($index = 0; $index -lt $Profiles.Count; $index++) {
        Write-Host ('  [{0}] {1}' -f ($index + 1), $Profiles[$index])
    }
    $selection = 0
    if (-not [int]::TryParse((Read-Host 'Choose the approved profile number'), [ref]$selection)) { return $null }
    if ($selection -lt 1 -or $selection -gt $Profiles.Count) { return $null }
    return $Profiles[$selection - 1]
}

while ($true) {
    $posture = Get-SasOperatorNetworkPosture
    $evidencePath = Write-SasOperatorNetworkEvidence -Posture $posture

    Write-Host ''
    $color = if ($posture.allowed_for_target_operation) { 'Green' } else { 'Yellow' }
    Write-Host "Network gate: $($posture.classification)" -ForegroundColor $color
    Write-Host "Purpose: $Purpose"
    Write-Host "Windows Wi-Fi/network label: $($posture.observed_wifi_network_label)"
    if (-not [string]::IsNullOrWhiteSpace([string]$posture.approved_wifi_profile)) {
        Write-Host "Approved Wi-Fi profile: $($posture.approved_wifi_profile)"
        Write-Host "Wi-Fi evidence: $($posture.wifi_evidence_source)"
    }
    Write-Host "Evidence: $evidencePath"

    if ([bool]$posture.allowed_for_target_operation) {
        Write-Host 'Approved Northwell network posture detected. Target operation may continue.' -ForegroundColor Green
        exit 0
    }

    if ($NonInteractive) {
        Write-Host 'Target operation blocked because approved Northwell network posture was not detected.' -ForegroundColor Yellow
        exit 20
    }

    $approvedProfiles = @(Get-SasApprovedSavedWifiProfiles)
    Write-Host ''
    Write-Host 'No target contact or mutation has occurred.' -ForegroundColor Yellow
    if ($approvedProfiles.Count -gt 0) {
        Write-Host '[1/S] Switch to a saved approved Northwell Wi-Fi profile (explicit confirmation required)'
    }
    Write-Host '[2/R] I switched networks manually - recheck now'
    if (-not $NoOpenWifiSettings) {
        Write-Host '[3/W] Open Windows Wi-Fi settings, then recheck'
    }
    Write-Host '[Q/C] Cancel this target operation'

    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $choice = 'S' }
        '2' { $choice = 'R' }
        '3' { $choice = 'W' }
        'Q' { $choice = 'C' }
    }

    switch ($choice) {
        'S' {
            if ($approvedProfiles.Count -eq 0) {
                Write-Host 'No saved approved Northwell Wi-Fi profile is available for automatic switching.' -ForegroundColor Yellow
                continue
            }
            $profile = Select-SasApprovedWifiProfile -Profiles $approvedProfiles
            if ([string]::IsNullOrWhiteSpace($profile)) {
                Write-Host 'No valid approved profile was selected. Nothing changed.' -ForegroundColor Yellow
                continue
            }
            $ack = (Read-Host "Type SWITCH to connect using the saved profile '$profile'").Trim().ToUpperInvariant()
            if ($ack -ne 'SWITCH') {
                Write-Host 'Network switch canceled. Nothing changed.' -ForegroundColor Yellow
                continue
            }

            $previousNetworkLabel = [string]$posture.observed_wifi_network_label
            $script:localNetworkSwitchAttempted = $true
            $script:confirmedApprovedProfile = $null
            $script:switchVerification = $null

            & netsh wlan connect name="$profile"
            $switchExit = $LASTEXITCODE
            if ($switchExit -ne 0) {
                Write-Host "Windows could not start the saved-profile switch. netsh exit code: $switchExit" -ForegroundColor Yellow
                continue
            }

            Write-Host "Windows accepted the switch request. Waiting up to $SwitchVerificationTimeoutSeconds seconds for enterprise Wi-Fi authentication to stabilize..." -ForegroundColor Cyan
            $verification = Wait-SasApprovedSavedProfileTransition -ExpectedProfile $profile -PreviousNetworkLabel $previousNetworkLabel -TimeoutSeconds $SwitchVerificationTimeoutSeconds
            $script:switchVerification = $verification
            if ([bool]$verification.verified) {
                $script:confirmedApprovedProfile = $profile
                Write-Host "Approved saved-profile transition verified: $profile" -ForegroundColor Green
                Write-Host "Observed Windows network label: $($verification.observed_network_label)"
                continue
            }

            Write-Host 'Windows accepted the connection request, but the approved network transition could not be verified.' -ForegroundColor Yellow
            Write-Host "Last observed network label: $($verification.observed_network_label)"
            Write-Host 'No target contact or mutation will be allowed. Recheck, open Wi-Fi settings, or cancel.' -ForegroundColor Yellow
            continue
        }
        'R' { continue }
        'W' {
            if ($NoOpenWifiSettings) { continue }
            try { Start-Process 'ms-settings:network-wifi' | Out-Null }
            catch { Write-Warning "Could not open Windows Wi-Fi settings: $($_.Exception.Message)" }
            [void](Read-Host 'Switch to the approved Northwell network, then press Enter to recheck')
            continue
        }
        'C' {
            Write-Host 'Operation canceled before target contact or mutation.' -ForegroundColor Yellow
            exit 1223
        }
        default {
            Write-Host 'Invalid selection. Nothing has run against a target.' -ForegroundColor Yellow
        }
    }
}
