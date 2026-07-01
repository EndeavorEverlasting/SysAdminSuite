#Requires -Version 5.1
<#
.SYNOPSIS
Shared SysAdminSuite low-noise survey and pragmatic retry policy.

.DESCRIPTION
This module centralizes the retry/noise doctrine used by Cybernet survey planners and probe handoffs.

The policy is deliberately plain: shell choice is not a network-noise control; packet count is controlled by
scope, ports, rate, retries, freshness, evidence reuse, and staging only justified host/IP targets.
#>

Set-StrictMode -Version 2.0

function Get-SasLowNoisePolicy {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        PolicyVersion = '1.0'
        LowNoisePrinciple = 'The network sees packets, not the shell. Reduce packets by using local evidence before probes.'
        NetworkVisibilityNote = 'CMD versus PowerShell does not materially change network visibility when the same packets, targets, ports, rate, and retries are used.'
        ProbeAgainGuidance = 'Five probes are unnecessary when a device was already recently reachable or identity-confirmed. If retrying is justified, prefer a different time of day or different day of week over immediate repeated probes.'
        FreshEvidenceGuidance = 'Fresh identity or reachability evidence should reduce re-probing. Stale, missing, conflicting, or operator-forced evidence can justify staging a target.'
        MysterySerialGuidance = 'A serial with no approved host/IP bridge remains a mystery serial for review; do not ping the serial string.'
        FrontDoorGuidance = 'CDN/WAF/load-balanced/front-door targets should not be treated as serial proof. Review or use bounded profiles rather than broad probing.'
        PacketProfileGuidance = 'Prefer smaller scope, fewer ports, lower rate, fewer retries, smarter evidence reuse, and avoiding broad scans.'
        ProbeSelectionQuestions = @(
            'Should this target be probed at all?',
            'Which exact host/IP should be probed?',
            'Which exact ports answer the survey question?',
            'At what rate?',
            'How many retries?',
            'Is this already fresh in local evidence?',
            'Is this a CDN/WAF/load-balanced/front-door target?',
            'Is this a mystery serial that needs review, not packets?'
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

Export-ModuleMember -Function Get-SasLowNoisePolicy, Add-SasLowNoisePolicyToObject, New-SasLowNoiseSummaryObject, Get-SasLowNoiseOperatorLines
