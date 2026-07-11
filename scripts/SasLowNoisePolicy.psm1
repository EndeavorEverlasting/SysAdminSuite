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

function Get-SasLowNoisePolicy {
    [CmdletBinding()]
    param()

    $document = Get-SasCanonicalLowNoiseDocument
    $guidance = $document.guidance
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
        '',
        'Pre-probe questions:'
    ) + ($policy.ProbeSelectionQuestions | ForEach-Object { "- $_" })
}

Export-ModuleMember -Function Get-SasLowNoisePolicy, Get-SasLowNoiseProfile, New-SasLowNoiseContextObject, Add-SasLowNoisePolicyToObject, New-SasLowNoiseSummaryObject, Get-SasLowNoiseOperatorLines
