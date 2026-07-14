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

function Get-SasCanonicalLowNoiseDocument {
    [CmdletBinding()]
    param()

    $path = if ($env:SAS_LOW_NOISE_POLICY_PATH) {
        $env:SAS_LOW_NOISE_POLICY_PATH
    } else {
        Join-Path $PSScriptRoot '..\Config\low-noise-policy.json'
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Canonical low-noise policy is missing: $path"
    }
    try {
        $document = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
    } catch {
        throw "Canonical low-noise policy is invalid: $path; $($_.Exception.Message)"
    }
    if ($document.schema_version -ne 'sas-low-noise-policy/v1' -or -not $document.profiles) {
        throw "Canonical low-noise policy has unsupported schema or no profiles: $path"
    }
    return $document
}

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
        [int]$UntestedCount = 0,

        [Parameter(Mandatory = $false)]
        [switch]$ApprovedSubnetScope,

        [Parameter(Mandatory = $false)]
        [switch]$UdpJustified,

        [Parameter(Mandatory = $false)]
        [switch]$AllowFullPorts,

        [Parameter(Mandatory = $false)]
        [int[]]$EffectivePorts
    )

    $policy = Get-SasPortFallbackPolicy
    $fallbackProfile = ''
    $fallbackRequiresApproval = $false
    $decision = 'review_required'
    $allPortsAllowed = [bool]$AllowFullPorts

    if ($TargetCount -le 0 -or $UntestedCount -eq $TargetCount) {
        $decision = 'review_required'
    } elseif ($SilentOnDefaultProfileCount -eq 0 -and $OpenDefaultPortTargetCount -gt 0) {
        $decision = 'default_ok'
    } elseif ($SilentOnDefaultProfileCount -gt 0) {
        if ($UdpJustified) {
            $decision = 'udp_justification_required'
            $fallbackProfile = $policy.UdpFallbackProfile
            $fallbackRequiresApproval = $true
        } elseif (-not $AllowFullPorts) {
            $decision = 'all_ports_denied_without_explicit_gate'
            $fallbackRequiresApproval = $true
        } elseif ($ApprovedSubnetScope) {
            $decision = 'approved_subnet_host_discovery_required'
            $fallbackProfile = $policy.HostDiscoveryFallbackProfile
            $fallbackRequiresApproval = $true
        } else {
            $decision = 'web_only_fallback'
            $fallbackProfile = $policy.WebReachabilityFallbackProfile
        }
    }

    $emittedDefaultProfile = $policy.DefaultProfile
    $emittedPortsRequested = $policy.DefaultCybernetTcpPorts
    if ($PSBoundParameters.ContainsKey('EffectivePorts') -and $null -ne $EffectivePorts -and $EffectivePorts.Count -gt 0) {
        $canonical = @($policy.DefaultCybernetTcpPorts | Sort-Object)
        $effective = @($EffectivePorts | Sort-Object)
        $isNarrowed = $effective.Count -ne $canonical.Count
        if (-not $isNarrowed) {
            for ($i = 0; $i -lt $canonical.Count; $i++) {
                if ($canonical[$i] -ne $effective[$i]) { $isNarrowed = $true; break }
            }
        }
        if ($isNarrowed) {
            $emittedDefaultProfile = ''
            $emittedPortsRequested = @()
        }
    }

    return [pscustomobject]@{
        default_profile = $emittedDefaultProfile
        ports_requested = $emittedPortsRequested
        open_default_port_target_count = $OpenDefaultPortTargetCount
        web_only_reachable_count = $WebOnlyReachableCount
        admin_surface_reachable_count = $AdminSurfaceReachableCount
        default_ports_blocked_or_filtered_count = $SilentOnDefaultProfileCount
        untested_target_count = $UntestedCount
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

    $document = Get-SasCanonicalLowNoiseDocument
    $guidance = $document.guidance
    $portPolicy = Get-SasPortFallbackPolicy

    return [pscustomobject]@{
        PolicyVersion = $document.policy_version
        SchemaVersion = $document.schema_version
        Profiles = @($document.profiles | ForEach-Object { $_.PSObject.Copy() })
        LowNoisePrinciple = $guidance.low_noise_principle
        NetworkVisibilityNote = $guidance.network_visibility_note
        ProbeAgainGuidance = $guidance.probe_again_guidance
        FreshEvidenceGuidance = $guidance.fresh_evidence_guidance
        MysterySerialGuidance = $guidance.mystery_serial_guidance
        FrontDoorGuidance = $guidance.front_door_guidance
        PacketProfileGuidance = $guidance.packet_profile_guidance
        ProbeSelectionQuestions = @($guidance.probe_selection_questions)

        # Fallback fields required by Add-SasLowNoisePolicyToObject and matrix reports
        DefaultProfile = $portPolicy.DefaultProfile
        DefaultCybernetTcpPorts = $portPolicy.DefaultCybernetTcpPorts
        WebReachabilityFallbackProfile = $portPolicy.WebReachabilityFallbackProfile
        HostDiscoveryFallbackProfile = $portPolicy.HostDiscoveryFallbackProfile
        UdpFallbackProfile = $portPolicy.UdpFallbackProfile
        AllPortsProfile = $portPolicy.AllPortsProfile
        WebReachabilityPorts = $portPolicy.WebReachabilityPorts
        AdminSurfacePorts = $portPolicy.AdminSurfacePorts
        BlockedDefaultPortsGuidance = $portPolicy.BlockedDefaultPortsGuidance
        AllPortsGuidance = $portPolicy.AllPortsGuidance
        FallbackDecisionNames = $portPolicy.FallbackDecisionNames
    }
}

function Get-SasLowNoiseProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )

    $document = Get-SasCanonicalLowNoiseDocument
    $profile = @($document.profiles | Where-Object { $_.id -eq $Id })
    if ($profile.Count -ne 1) {
        throw "Unknown or duplicated low-noise profile: $Id"
    }
    return $profile[0].PSObject.Copy()
}

function New-SasLowNoiseContextObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [Parameter(Mandatory = $true)][ValidateSet('canonical_default', 'explicit_named_profile', 'explicit_subset_override')][string]$ProfileSource,
        [Parameter(Mandatory = $true)][string]$EvidenceSource,
        [Parameter(Mandatory = $true)][string]$Disposition,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][bool]$NetworkActivityPerformed,
        [Parameter(Mandatory = $true)][bool]$TargetMutationPerformed,
        [Parameter(Mandatory = $true)][string]$NextAction,
        [int[]]$EffectivePorts
    )

    $policy = Get-SasLowNoisePolicy
    $profile = Get-SasLowNoiseProfile -Id $ProfileId
    $ports = if ($PSBoundParameters.ContainsKey('EffectivePorts')) { @($EffectivePorts) } else { @($profile.ports) }
    return [pscustomobject]@{
        applicability = 'applicable'
        policy_schema_version = $policy.SchemaVersion
        policy_version = $policy.PolicyVersion
        profile_id = $profile.id
        profile_source = $ProfileSource
        target_source = $profile.target_source
        effective_constraints = [pscustomobject]@{
            ports = $ports
            rate_cap = $profile.rate_cap
            retries = $profile.retries
            host_discovery_mode = $profile.host_discovery_mode
            exclude_cdn = $profile.exclude_cdn
            silent_output = $profile.silent_output
            machine_output = $profile.machine_output
        }
        evidence_source = $EvidenceSource
        disposition = $Disposition
        reason = $Reason
        network_activity_performed = $NetworkActivityPerformed
        target_mutation_performed = $TargetMutationPerformed
        next_action = $NextAction
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

Export-ModuleMember -Function Get-SasLowNoisePolicy, Get-SasLowNoiseProfile, New-SasLowNoiseContextObject, Add-SasLowNoisePolicyToObject, New-SasLowNoiseSummaryObject, Get-SasLowNoiseOperatorLines, Get-SasDefaultCybernetTcpPorts, Get-SasWebReachabilityPorts, Get-SasAdminSurfacePorts, Get-SasPortFallbackPolicy, Get-SasPortFallbackDecision
