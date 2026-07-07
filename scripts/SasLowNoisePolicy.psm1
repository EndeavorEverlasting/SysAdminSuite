#Requires -Version 5.1
<#
.SYNOPSIS
Shared SysAdminSuite low-noise survey and pragmatic retry policy.

.DESCRIPTION
scripts/SasLowNoisePolicy.psm1 centralizes the retry/noise doctrine used by Cybernet survey planners and probe handoffs.

The policy is deliberately plain: shell choice is not a network-noise control; packet count is controlled by
scope, ports, rate, retries, freshness, evidence reuse, and staging only justified host/IP targets.
#>

Set-StrictMode -Version 2.0

function Get-SasDefaultCybernetTcpPorts {
    [CmdletBinding()]
    param()

    return @(80, 443, 135, 445, 3389, 5985, 5986)
}

function Get-SasWebReachabilityPorts {
    [CmdletBinding()]
    param()

    return @(80, 443)
}

function Get-SasAdminSurfacePorts {
    [CmdletBinding()]
    param()

    return @(135, 445, 3389, 5985, 5986)
}

function Get-SasPortFallbackPolicy {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        DefaultProfile = 'keyports_cybernet_json'
        DefaultCybernetTcpPorts = @(Get-SasDefaultCybernetTcpPorts)
        RawPipelineProfile = 'keyports_cybernet_pipe'
        WebReachabilityFallbackProfile = 'web_reachability_only_json'
        HostDiscoveryFallbackProfile = 'host_discovery_web_syn_txt'
        UdpFallbackProfile = 'udp_dns_snmp_json'
        AllPortsProfile = 'allports_low_noise_json'
        WebReachabilityPorts = @(Get-SasWebReachabilityPorts)
        AdminSurfacePorts = @(Get-SasAdminSurfacePorts)
        BlockedDefaultPortsGuidance = 'If the default Cybernet ports are blocked or filtered, do not broaden automatically. Use the named fallback profile that answers the survey question, and require explicit gates for subnet discovery, UDP, or all-ports scans.'
        AllPortsGuidance = 'All TCP ports are denied by default. Use allports_low_noise_json only for a small approved target set with explicit all-port approval.'
        FallbackDecisionNames = @(
            'default_ok',
            'web_only_fallback',
            'approved_subnet_host_discovery_required',
            'udp_justification_required',
            'all_ports_denied_without_explicit_gate',
            'review_required'
        )
    }
}

function Get-SasPortFallbackDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$TargetCount,

        [Parameter(Mandatory = $true)]
        [int]$OpenDefaultPortTargetCount,

        [Parameter(Mandatory = $true)]
        [int]$WebOnlyReachableCount,

        [Parameter(Mandatory = $true)]
        [int]$AdminSurfaceReachableCount,

        [Parameter(Mandatory = $true)]
        [int]$SilentOnDefaultProfileCount,

        [Parameter(Mandatory = $false)]
        [switch]$ApprovedSubnetScope,

        [Parameter(Mandatory = $false)]
        [switch]$UdpJustified,

        [Parameter(Mandatory = $false)]
        [switch]$AllowFullPorts
    )

    $policy = Get-SasPortFallbackPolicy
    $fallbackProfile = ''
    $fallbackRequiresApproval = $false
    $decision = 'review_required'
    $allPortsAllowed = [bool]$AllowFullPorts

    if ($TargetCount -le 0) {
        $decision = 'review_required'
    } elseif ($SilentOnDefaultProfileCount -eq 0 -and $OpenDefaultPortTargetCount -gt 0) {
        $decision = 'default_ok'
    } elseif ($SilentOnDefaultProfileCount -gt 0 -and $ApprovedSubnetScope) {
        $decision = 'approved_subnet_host_discovery_required'
        $fallbackProfile = $policy.HostDiscoveryFallbackProfile
        $fallbackRequiresApproval = $true
    } elseif ($SilentOnDefaultProfileCount -gt 0) {
        $decision = 'web_only_fallback'
        $fallbackProfile = $policy.WebReachabilityFallbackProfile
    }

    if ($UdpJustified) {
        $fallbackProfile = $policy.UdpFallbackProfile
        $fallbackRequiresApproval = $true
        if ($decision -eq 'review_required') { $decision = 'udp_justification_required' }
    }

    if (-not $AllowFullPorts -and $decision -eq 'review_required' -and $SilentOnDefaultProfileCount -gt 0) {
        $decision = 'all_ports_denied_without_explicit_gate'
        $fallbackRequiresApproval = $true
    }

    return [pscustomobject]@{
        default_profile = $policy.DefaultProfile
        ports_requested = $policy.DefaultCybernetTcpPorts
        open_default_port_target_count = $OpenDefaultPortTargetCount
        web_only_reachable_count = $WebOnlyReachableCount
        admin_surface_reachable_count = $AdminSurfaceReachableCount
        default_ports_blocked_or_filtered_count = $SilentOnDefaultProfileCount
        fallback_profile_recommended = $fallbackProfile
        fallback_requires_approval = $fallbackRequiresApproval
        all_ports_allowed = $allPortsAllowed
        decision = $decision
        guidance = $policy.BlockedDefaultPortsGuidance
    }
}

function Get-SasLowNoisePolicy {
    [CmdletBinding()]
    param()

    $portPolicy = Get-SasPortFallbackPolicy

    return [pscustomobject]@{
        PolicyVersion = '1.1'
        LowNoisePrinciple = 'The network sees packets, not the shell. Reduce packets by using local evidence before probes.'
        NetworkVisibilityNote = 'CMD versus PowerShell does not materially change network visibility when the same packets, targets, ports, rate, and retries are used.'
        ProbeAgainGuidance = 'Five probes are unnecessary when a device was already recently reachable or identity-confirmed. If retrying is justified, prefer a different time of day or different day of week over immediate repeated probes.'
        FreshEvidenceGuidance = 'Fresh identity or reachability evidence should reduce re-probing. Stale, missing, conflicting, or operator-forced evidence can justify staging a target.'
        MysterySerialGuidance = 'A serial with no approved host/IP bridge remains a mystery serial for review; do not ping the serial string.'
        FrontDoorGuidance = 'CDN/WAF/load-balanced/front-door targets should not be treated as serial proof. Review or use bounded profiles rather than broad probing.'
        PacketProfileGuidance = 'Prefer smaller scope, fewer ports, lower rate, fewer retries, smarter evidence reuse, and avoiding broad scans.'
        DefaultProfile = $portPolicy.DefaultProfile
        DefaultCybernetTcpPorts = $portPolicy.DefaultCybernetTcpPorts
        WebReachabilityFallbackProfile = $portPolicy.WebReachabilityFallbackProfile
        HostDiscoveryFallbackProfile = $portPolicy.HostDiscoveryFallbackProfile
        UdpFallbackProfile = $portPolicy.UdpFallbackProfile
        AllPortsProfile = $portPolicy.AllPortsProfile
        BlockedDefaultPortsGuidance = $portPolicy.BlockedDefaultPortsGuidance
        AllPortsGuidance = $portPolicy.AllPortsGuidance
        FallbackDecisionNames = $portPolicy.FallbackDecisionNames
        ProbeSelectionQuestions = @(
            'Should this target be probed at all?',
            'Which exact host/IP should be probed?',
            'Which exact ports answer the survey question?',
            'At what rate?',
            'How many retries?',
            'Is this already fresh in local evidence?',
            'Is this a CDN/WAF/load-balanced/front-door target?',
            'Is this a mystery serial that needs review, not packets?',
            'If default ports are blocked, which named fallback profile is justified?'
        )
    }
}

function Add-SasLowNoisePolicyToObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    $policy = Get-SasLowNoisePolicy

    $InputObject | Add-Member -NotePropertyName low_noise_policy_version -NotePropertyValue $policy.PolicyVersion -Force
    $InputObject | Add-Member -NotePropertyName low_noise_principle -NotePropertyValue $policy.LowNoisePrinciple -Force
    $InputObject | Add-Member -NotePropertyName network_visibility_note -NotePropertyValue $policy.NetworkVisibilityNote -Force
    $InputObject | Add-Member -NotePropertyName probe_selection_questions -NotePropertyValue $policy.ProbeSelectionQuestions -Force
    $InputObject | Add-Member -NotePropertyName probe_again_guidance -NotePropertyValue $policy.ProbeAgainGuidance -Force
    $InputObject | Add-Member -NotePropertyName fresh_evidence_guidance -NotePropertyValue $policy.FreshEvidenceGuidance -Force
    $InputObject | Add-Member -NotePropertyName mystery_serial_guidance -NotePropertyValue $policy.MysterySerialGuidance -Force
    $InputObject | Add-Member -NotePropertyName front_door_guidance -NotePropertyValue $policy.FrontDoorGuidance -Force
    $InputObject | Add-Member -NotePropertyName packet_profile_guidance -NotePropertyValue $policy.PacketProfileGuidance -Force
    $InputObject | Add-Member -NotePropertyName default_profile -NotePropertyValue $policy.DefaultProfile -Force
    $InputObject | Add-Member -NotePropertyName default_cybernet_tcp_ports -NotePropertyValue $policy.DefaultCybernetTcpPorts -Force
    $InputObject | Add-Member -NotePropertyName blocked_default_ports_guidance -NotePropertyValue $policy.BlockedDefaultPortsGuidance -Force
    $InputObject | Add-Member -NotePropertyName all_ports_guidance -NotePropertyValue $policy.AllPortsGuidance -Force

    return $InputObject
}

function New-SasLowNoiseSummaryObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Properties = @{}
    )

    $obj = [pscustomobject]$Properties
    return Add-SasLowNoisePolicyToObject -InputObject $obj
}

function Get-SasLowNoiseOperatorLines {
    [CmdletBinding()]
    param()

    $policy = Get-SasLowNoisePolicy

    return @(
        'Low-noise context:',
        "- $($policy.LowNoisePrinciple)",
        "- $($policy.NetworkVisibilityNote)",
        "- $($policy.FreshEvidenceGuidance)",
        "- $($policy.ProbeAgainGuidance)",
        "- $($policy.MysterySerialGuidance)",
        "- $($policy.FrontDoorGuidance)",
        "- Default Cybernet TCP profile: $($policy.DefaultProfile) on ports $($policy.DefaultCybernetTcpPorts -join ',')",
        "- $($policy.BlockedDefaultPortsGuidance)",
        '',
        'Pre-probe questions:'
    ) + ($policy.ProbeSelectionQuestions | ForEach-Object { "- $_" })
}

Export-ModuleMember -Function Get-SasLowNoisePolicy, Add-SasLowNoisePolicyToObject, New-SasLowNoiseSummaryObject, Get-SasLowNoiseOperatorLines, Get-SasDefaultCybernetTcpPorts, Get-SasWebReachabilityPorts, Get-SasAdminSurfacePorts, Get-SasPortFallbackPolicy, Get-SasPortFallbackDecision
