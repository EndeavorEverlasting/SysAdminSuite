#Requires -Version 5.1
<#
.SYNOPSIS
Classifies local workstation network posture before Cybernet target preflight.

.DESCRIPTION
Reads only local Wi-Fi and network-configuration evidence through SasNetworkGuard.
It never probes a target, scans a subnet, launches an app, or changes local or remote state.
The JSON result is local evidence and belongs in an ignored output directory.
#>
[CmdletBinding()]
param(
    [string]$Ssid,
    [string]$NetworkTextPath,
    [string]$GuardConfigPath,
    [string]$OutputPath,
    [switch]$NoExitCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$guardModule = Join-Path $repoRoot 'scripts/SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $guardModule -PathType Leaf)) {
    throw "Missing shared network guard module: $guardModule"
}

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutputPath = Join-Path $repoRoot "survey/output/network_posture/network_posture_$stamp.json"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}

$originalGuardConfig = $env:SAS_NETWORK_GUARD_CONFIG
$originalRepoRoot = $env:SAS_REPO_ROOT
try {
    $env:SAS_REPO_ROOT = $repoRoot
    if ($GuardConfigPath) {
        $env:SAS_NETWORK_GUARD_CONFIG = (Resolve-Path -LiteralPath $GuardConfigPath -ErrorAction Stop).Path
    }

    Import-Module $guardModule -Force
    $effectiveSsid = if ($PSBoundParameters.ContainsKey('Ssid')) { $Ssid } else { Get-SasCurrentWifiSsid }
    $networkText = if ($NetworkTextPath) {
        Get-Content -LiteralPath $NetworkTextPath -Raw -ErrorAction Stop
    }
    else {
        Get-SasLocalNetworkText
    }
    $config = Get-SasNetworkGuardConfig
    $wiredGuardConfigured = $false
    if ($null -ne $config) {
        $wiredGuardConfigured = @(
            $config.allowedDnsSuffixes +
            $config.allowedWindowsDomains +
            $config.allowedLocalIpCidrs +
            $config.allowedGatewayCidrs +
            $config.allowedDnsServerCidrs
        ).Count -gt 0
    }
    $wifiApproved = Test-SasNorthwellWifiSsid -Ssid $effectiveSsid
    $wiredApproved = $false
    $classification = 'INCONCLUSIVE'
    $reason = 'no approved Wi-Fi or wired evidence was detected'
    $exitCode = 2

    if ($null -eq $config) {
        $classification = 'ENVIRONMENT_BLOCKED_POLICY'
        $reason = 'the local network-guard configuration is malformed'
        $exitCode = 3
    }
    elseif ($wifiApproved) {
        $classification = 'OK_NETWORK_POSTURE'
        $reason = 'approved Wi-Fi posture detected'
        $exitCode = 0
    }
    else {
        $wiredApproved = Test-SasNorthwellWiredEvidence -NetworkText $networkText
        if ($wiredApproved) {
            $classification = 'OK_NETWORK_POSTURE'
            $reason = 'approved wired evidence detected'
            $exitCode = 0
        }
        elseif (-not [string]::IsNullOrWhiteSpace($effectiveSsid) -and $effectiveSsid -ne 'unknown') {
            $classification = 'ENVIRONMENT_BLOCKED_GUEST_NETWORK'
            $reason = 'connected Wi-Fi is not an approved enterprise SSID'
        }
    }

    $result = [ordered]@{
        schema_version = 'sas-cybernet-network-posture/v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        classification = $classification
        allowed_for_target_preflight = ($exitCode -eq 0)
        reason = $reason
        wifi_ssid = $effectiveSsid
        wifi_approved = $wifiApproved
        wired_approved = $wiredApproved
        wired_guard_configured = $wiredGuardConfigured
        network_activity_performed = $false
        target_mutation_performed = $false
        next_action = $(if ($exitCode -eq 0) {
            'Use an approved staged target file for read-only network preflight.'
        } elseif ($classification -eq 'ENVIRONMENT_BLOCKED_POLICY') {
            'Correct the ignored local network-guard allowlist, then rerun this posture check.'
        } else {
            'Move to an approved enterprise Wi-Fi, VPN, or wired segment, then rerun this posture check before target preflight.'
        })
    }

    $parent = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Network posture: $classification"
    Write-Host "Result: $OutputPath"

    if ($NoExitCode) { return [pscustomobject]$result }
    if ($exitCode -ne 0) { exit $exitCode }
}
finally {
    $env:SAS_NETWORK_GUARD_CONFIG = $originalGuardConfig
    $env:SAS_REPO_ROOT = $originalRepoRoot
}
