#Requires -Version 5.1
<#
.SYNOPSIS
Pure port-fallback decision service. No DNS, no network, no mutation.
.DESCRIPTION
Consumes structured counts and canonical profile metadata to produce one mutually
exclusive port-fallback decision conforming to schemas/harness/port-fallback-decision.schema.json.
#>

Set-StrictMode -Version 2.0

$script:NaabuProfilesPath  = Join-Path $PSScriptRoot '..\survey\naabu_profiles.json'
$script:LowNoisePolicyPath = Join-Path $PSScriptRoot '..\Config\low-noise-policy.json'
$script:RegisteredProfileIds = $null

function Get-RegisteredNaabuProfileIds {
    if ($null -ne $script:RegisteredProfileIds) { return $script:RegisteredProfileIds }
    $raw = Get-Content -LiteralPath $script:NaabuProfilesPath -Raw -ErrorAction Stop | ConvertFrom-Json
    $script:RegisteredProfileIds = @{}
    $raw.profiles.PSObject.Properties | ForEach-Object { $script:RegisteredProfileIds[$_.Name] = $true }
    $script:RegisteredProfileIds
}

function Get-NaabuProfileMetadata {
    param([string]$ProfileId)
    $raw = Get-Content -LiteralPath $script:NaabuProfilesPath -Raw -ErrorAction Stop | ConvertFrom-Json
    $profile = $raw.profiles.PSObject.Properties | Where-Object { $_.Name -eq $ProfileId } | Select-Object -First 1
    if (-not $profile) { return $null }
    return $profile.Value
}

function Get-CanonicDefaultPorts {
    $meta = Get-NaabuProfileMetadata -ProfileId 'keyports_cybernet_json'
    if (-not $meta) { return @() }
    return ($meta.ports -split ',' | ForEach-Object { [int]$_.Trim() } | Where-Object { $_ -gt 0 })
}

function Test-IsCanonicalDefaultPortSet {
    param([int[]]$Ports)
    if (-not $Ports -or $Ports.Count -eq 0) { return $false }
    $default = @(Get-CanonicDefaultPorts)
    if ($Ports.Count -ne $default.Count) { return $false }
    $sorted = @($Ports | Sort-Object)
    $sortedDefault = @($default | Sort-Object)
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        if ($sorted[$i] -ne $sortedDefault[$i]) { return $false }
    }
    return $true
}

function New-SasPortFallbackDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$TargetCount,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$TestedTargetCount,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$UntestedTargetCount,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$OpenDefaultPortTargetCount,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$WebOnlyReachableCount,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$AdminSurfaceReachableCount,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$SilentOnDefaultProfileCount,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SourceProfileId,
        [Parameter(Mandatory = $true)][ValidateSet('canonical_default', 'explicit_named_profile', 'explicit_subset_override')][string]$ProfileSource,
        [Parameter(Mandatory = $false)][int[]]$EffectivePorts,
        [Parameter(Mandatory = $false)][switch]$UdpJustified,
        [Parameter(Mandatory = $false)][switch]$AllowFullPorts,
        [Parameter(Mandatory = $false)][switch]$ApprovedSubnetScope,
        [Parameter(Mandatory = $false)][switch]$NoNetwork
    )

    if ($TargetCount -ne ($TestedTargetCount + $UntestedTargetCount)) {
        throw "target_count ($TargetCount) must equal tested ($TestedTargetCount) + untested ($UntestedTargetCount)"
    }
    if ($TestedTargetCount -ne ($OpenDefaultPortTargetCount + $SilentOnDefaultProfileCount)) {
        throw "tested_target_count ($TestedTargetCount) must equal open_default ($OpenDefaultPortTargetCount) + silent ($SilentOnDefaultProfileCount)"
    }
    if ($SilentOnDefaultProfileCount -gt 0 -and $UntestedTargetCount -gt 0) {
        throw "targets with unknown status (untested) must not be counted as silent-on-default-profile (filtered)"
    }

    $registeredIds = Get-RegisteredNaabuProfileIds
    $ports = if ($PSBoundParameters.ContainsKey('EffectivePorts')) { @($EffectivePorts) } else { @() }
    $networkActivity = -not $NoNetwork

    $defaultProfileId = ''
    $portsRequested = @()
    if (Test-IsCanonicalDefaultPortSet -Ports $ports) {
        $defaultProfileId = 'keyports_cybernet_json'
        $portsRequested = $ports
    }

    $decision = ''
    $recommended = ''
    $approvalRequired = $false
    $gate = ''
    $reason = ''
    $nextAction = ''
    $proofLevel = if ($NoNetwork) { 'fixture_e2e' } else { 'static_pester' }

    if ($TestedTargetCount -eq 0 -and $UntestedTargetCount -gt 0) {
        $decision = 'review_required'
        $recommended = ''
        $approvalRequired = $false
        $gate = ''
        $reason = "All $UntestedTargetCount target(s) are untested. Review is required before any profile expansion."
        $nextAction = 'Review untested targets before authorizing a bounded network preflight.'
    }
    elseif ($UdpJustified) {
        $meta = Get-NaabuProfileMetadata -ProfileId 'udp_dns_snmp_json'
        $decision = 'udp_justification_required'
        $recommended = if ($meta) { 'udp_dns_snmp_json' } else { '' }
        $approvalRequired = $true
        $gate = 'udp_justification'
        $reason = "UDP justification recorded for $TestedTargetCount tested target(s). UDP profile requires separate authorization."
        $nextAction = 'Obtain explicit UDP-profile authorization before running udp_dns_snmp_json.'
    }
    elseif ($SilentOnDefaultProfileCount -gt 0 -and $OpenDefaultPortTargetCount -eq 0 -and -not $AllowFullPorts) {
        $decision = 'all_ports_denied_without_explicit_gate'
        $recommended = ''
        $approvalRequired = $true
        $gate = 'explicit_all_ports_gate'
        $reason = "All $TestedTargetCount tested target(s) were silent on the default profile. Full-port scan requires explicit authorization."
        $nextAction = 'Do not broaden to all ports. Obtain explicit all-ports gate authorization from a lead or operator.'
    }
    elseif ($SilentOnDefaultProfileCount -gt 0 -and $ApprovedSubnetScope -and $AllowFullPorts) {
        $meta = Get-NaabuProfileMetadata -ProfileId 'host_discovery_web_syn_txt'
        $decision = 'approved_subnet_host_discovery_required'
        $recommended = if ($meta) { 'host_discovery_web_syn_txt' } else { '' }
        $approvalRequired = $true
        $gate = 'approved_subnet_scope'
        $reason = "$SilentOnDefaultProfileCount target(s) silent on default profile. Approved subnet scope and full-port authorization recorded."
        $nextAction = 'Proceed with host_discovery_web_syn_txt only after confirming approved subnet scope.'
    }
    elseif ($WebOnlyReachableCount -gt 0 -and $AdminSurfaceReachableCount -eq 0 -and $OpenDefaultPortTargetCount -gt 0) {
        $meta = Get-NaabuProfileMetadata -ProfileId 'web_reachability_only_json'
        $decision = 'web_only_fallback'
        $recommended = if ($meta) { 'web_reachability_only_json' } else { '' }
        $approvalRequired = $false
        $gate = ''
        $reason = "$WebOnlyReachableCount target(s) answered only on web ports 80/443. Admin surface ports silent on $SilentOnDefaultProfileCount target(s)."
        $nextAction = 'Narrow to web-reachability profile for confirmed web-only targets.'
    }
    elseif ($OpenDefaultPortTargetCount -gt 0 -and $SilentOnDefaultProfileCount -eq 0) {
        $decision = 'default_ok'
        $recommended = ''
        $approvalRequired = $false
        $gate = ''
        $reason = "All $TestedTargetCount tested target(s) answered on at least one default port."
        $nextAction = 'Proceed with the canonical Cybernet reachability baseline.'
    }
    elseif ($SilentOnDefaultProfileCount -gt 0 -and -not $AllowFullPorts) {
        $decision = 'all_ports_denied_without_explicit_gate'
        $recommended = ''
        $approvalRequired = $true
        $gate = 'explicit_all_ports_gate'
        $reason = "$SilentOnDefaultProfileCount tested target(s) were silent on the default profile. Full-port expansion requires explicit approval."
        $nextAction = 'Do not broaden to all ports. Obtain explicit all-ports gate authorization from a lead or operator.'
    }
    elseif ($SilentOnDefaultProfileCount -gt 0 -and $AllowFullPorts -and -not $ApprovedSubnetScope) {
        $decision = 'approved_subnet_host_discovery_required'
        $recommended = 'host_discovery_web_syn_txt'
        $approvalRequired = $true
        $gate = 'approved_subnet_scope'
        $reason = "$SilentOnDefaultProfileCount target(s) silent. Full ports allowed but approved subnet scope required for host discovery."
        $nextAction = 'Obtain approved subnet scope authorization before running host_discovery_web_syn_txt.'
    }
    else {
        $decision = 'review_required'
        $recommended = ''
        $approvalRequired = $false
        $gate = ''
        $reason = "Uncertain classification for $TestedTargetCount tested, $UntestedTargetCount untested target(s)."
        $nextAction = 'Review the results manually before deciding next profile.'
    }

    if ($recommended -and -not ($registeredIds.ContainsKey($recommended) -or $registeredIds.Contains($recommended))) {
        Write-Warning "Recommended profile '$recommended' is not registered in survey/naabu_profiles.json"
        $recommended = ''
    }

    if ($ProfileSource -eq 'canonical_default' -and -not (Test-IsCanonicalDefaultPortSet -Ports $ports)) {
        $defaultProfileId = ''
        $portsRequested = @()
    }

    return [pscustomobject]@{
        schema_version                    = 'sas-port-fallback-decision/v1'
        source_profile_id                 = $SourceProfileId
        profile_source                    = $ProfileSource
        effective_ports                   = [array]$ports
        target_count                      = $TargetCount
        tested_target_count               = $TestedTargetCount
        untested_target_count             = $UntestedTargetCount
        open_default_port_target_count    = $OpenDefaultPortTargetCount
        web_only_reachable_count          = $WebOnlyReachableCount
        admin_surface_reachable_count     = $AdminSurfaceReachableCount
        silent_on_default_profile_count   = $SilentOnDefaultProfileCount
        decision                          = $decision
        recommended_profile_id            = $recommended
        approval_required                 = $approvalRequired
        required_gate                     = $gate
        network_activity_performed        = $networkActivity
        target_mutation_performed         = $false
        reason                            = $reason
        next_action                       = $nextAction
        proof_level                       = $proofLevel
    }
}

Export-ModuleMember -Function New-SasPortFallbackDecision
