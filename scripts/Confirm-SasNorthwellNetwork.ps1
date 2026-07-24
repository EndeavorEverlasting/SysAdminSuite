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
#>
[CmdletBinding()]
param(
    [string]$Purpose = 'target operation',
    [string]$Ssid,
    [string]$NetworkTextPath,
    [switch]$NonInteractive,
    [switch]$NoOpenWifiSettings
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
$localNetworkSwitchAttempted = $false

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

function Get-SasOperatorNetworkPosture {
    $effectiveSsid = if ($callerSuppliedSsid) { [string]$Ssid } else { Get-SasCurrentWifiSsid }
    $networkText = if ($callerNetworkTextPath) {
        Get-Content -LiteralPath $callerNetworkTextPath -Raw -ErrorAction Stop
    }
    else {
        Get-SasLocalNetworkText
    }

    $wifiApproved = Test-SasNorthwellWifiSsid -Ssid $effectiveSsid
    $wiredApproved = $false
    if (-not $wifiApproved) {
        $wiredApproved = Test-SasNorthwellWiredEvidence -NetworkText $networkText
    }

    $approved = ($wifiApproved -or $wiredApproved)
    $classification = if ($approved) {
        'OK_NETWORK_POSTURE'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($effectiveSsid) -and $effectiveSsid -ne 'unknown') {
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
        wifi_ssid = $effectiveSsid
        wifi_approved = $wifiApproved
        wired_approved = $wiredApproved
        local_network_switch_attempted = $localNetworkSwitchAttempted
        network_activity_performed = $localNetworkSwitchAttempted
        target_contact_performed = $false
        target_mutation_performed = $false
    }
}

function Write-SasOperatorNetworkEvidence {
    param([Parameter(Mandatory = $true)]$Posture)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $path = Join-Path $outputRoot "operator_network_posture_$stamp.json"
    $Posture | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
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
    Write-Host "Wi-Fi SSID: $($posture.wifi_ssid)"
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
        Write-Host '[S] Switch to a saved approved Northwell Wi-Fi profile (explicit confirmation required)'
    }
    Write-Host '[R] I switched networks manually - recheck now'
    if (-not $NoOpenWifiSettings) {
        Write-Host '[W] Open Windows Wi-Fi settings, then recheck'
    }
    Write-Host '[C] Cancel this target operation'

    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
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
            $localNetworkSwitchAttempted = $true
            & netsh wlan connect name="$profile"
            $switchExit = $LASTEXITCODE
            if ($switchExit -ne 0) {
                Write-Host "Windows could not switch using the saved approved profile. netsh exit code: $switchExit" -ForegroundColor Yellow
                continue
            }
            Start-Sleep -Seconds 3
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
