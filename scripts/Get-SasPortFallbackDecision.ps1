<#
.SYNOPSIS
Entrypoint for the pure port-fallback decision service.
.DESCRIPTION
Accepts sanitized structured input or consumes a network preflight summary.
Emits port_fallback_decision.json. No DNS, no network, no mutation.
.PARAMETER SummaryJson
Path to a network_preflight summary JSON.
.PARAMETER FixtureMode
Operate on sanitized parameters only. No target contact is possible.
.PARAMETER TargetCount
.PARAMETER TestedTargetCount
.PARAMETER UntestedTargetCount
.PARAMETER OpenDefaultPortTargetCount
.PARAMETER WebOnlyReachableCount
.PARAMETER AdminSurfaceReachableCount
.PARAMETER SilentOnDefaultProfileCount
.PARAMETER SourceProfileId
.PARAMETER ProfileSource
.PARAMETER EffectivePorts
.PARAMETER UdpJustified
.PARAMETER AllowFullPorts
.PARAMETER ApprovedSubnetScope
.PARAMETER OutputPath
.PARAMETER NoNetwork
#>

[CmdletBinding(DefaultParameterSetName = 'FromSummary')]
param(
    [Parameter(Mandatory = $false, ParameterSetName = 'FromSummary')]
    [string]$SummaryJson,

    [Parameter(Mandatory = $false, ParameterSetName = 'FromParameters')]
    [switch]$FixtureMode,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [int]$TargetCount,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [int]$TestedTargetCount,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [int]$UntestedTargetCount,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [int]$OpenDefaultPortTargetCount,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [int]$WebOnlyReachableCount,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [int]$AdminSurfaceReachableCount,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [int]$SilentOnDefaultProfileCount,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [string]$SourceProfileId,

    [Parameter(Mandatory = $true, ParameterSetName = 'FromParameters')]
    [ValidateSet('canonical_default', 'explicit_named_profile', 'explicit_subset_override')]
    [string]$ProfileSource,

    [Parameter(Mandatory = $false, ParameterSetName = 'FromParameters')]
    [int[]]$EffectivePorts,

    [Parameter(ParameterSetName = 'FromParameters')]
    [switch]$UdpJustified,

    [Parameter(ParameterSetName = 'FromParameters')]
    [switch]$AllowFullPorts,

    [Parameter(ParameterSetName = 'FromParameters')]
    [switch]$ApprovedSubnetScope,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(ParameterSetName = 'FromParameters')]
    [switch]$NoNetwork
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'SasPortFallbackDecision.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing port-fallback decision module: $modulePath"
}
Import-Module $modulePath -Force

function Write-Decision {
    param($Decision, [string]$Path)
    $json = $Decision | ConvertTo-Json -Depth 4
    if ($Path) {
        $parent = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
    }
    Write-Output $json
}

if ($PSCmdlet.ParameterSetName -eq 'FromParameters') {
    $params = @{
        TargetCount                    = $TargetCount
        TestedTargetCount              = $TestedTargetCount
        UntestedTargetCount            = $UntestedTargetCount
        OpenDefaultPortTargetCount     = $OpenDefaultPortTargetCount
        WebOnlyReachableCount          = $WebOnlyReachableCount
        AdminSurfaceReachableCount     = $AdminSurfaceReachableCount
        SilentOnDefaultProfileCount    = $SilentOnDefaultProfileCount
        SourceProfileId                = $SourceProfileId
        ProfileSource                  = $ProfileSource
    }
    if ($PSBoundParameters.ContainsKey('EffectivePorts')) { $params.EffectivePorts = $EffectivePorts }
    if ($UdpJustified) { $params.UdpJustified = $true }
    if ($AllowFullPorts) { $params.AllowFullPorts = $true }
    if ($ApprovedSubnetScope) { $params.ApprovedSubnetScope = $true }
    if ($NoNetwork) { $params.NoNetwork = $true }

    $decision = New-SasPortFallbackDecision @params
    Write-Decision -Decision $decision -Path $OutputPath
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq 'FromSummary') {
    if (-not $SummaryJson) {
        throw "-SummaryJson is required when not in FixtureMode."
    }
    if (-not (Test-Path -LiteralPath $SummaryJson -PathType Leaf)) {
        throw "Summary JSON not found: $SummaryJson"
    }

    $summary = Get-Content -LiteralPath $SummaryJson -Raw -ErrorAction Stop | ConvertFrom-Json

    $targetCount      = [int]$summary.target_count
    $testedCount      = [int]($summary.open_default_port_target_count + $summary.default_ports_blocked_or_filtered_count)
    $untestedCount    = [int]$summary.untested_target_count
    $openDefault      = [int]$summary.open_default_port_target_count
    $webOnly          = [int]$summary.web_only_reachable_count
    $adminSurface     = [int]$summary.admin_surface_reachable_count
    $silent           = [int]$summary.default_ports_blocked_or_filtered_count

    $sourceProfileId  = if ($summary.source_profile_id) { $summary.source_profile_id } else { 'network_preflight' }
    $profileSource    = if ($summary.ports_source) { $summary.ports_source } else { 'explicit_named_profile' }
    $effPorts         = if ($summary.ports) { @($summary.ports) } else { @() }

    $params = @{
        TargetCount                    = $targetCount
        TestedTargetCount              = $testedCount
        UntestedTargetCount            = $untestedCount
        OpenDefaultPortTargetCount     = $openDefault
        WebOnlyReachableCount          = $webOnly
        AdminSurfaceReachableCount     = $adminSurface
        SilentOnDefaultProfileCount    = $silent
        SourceProfileId                = $sourceProfileId
        ProfileSource                  = $profileSource
        NoNetwork                      = $true
    }
    if ($effPorts.Count -gt 0) { $params.EffectivePorts = $effPorts }

    $decision = New-SasPortFallbackDecision @params
    $outPath = if ($OutputPath) { $OutputPath } else { Join-Path (Split-Path -Parent $SummaryJson) 'port_fallback_decision.json' }
    Write-Decision -Decision $decision -Path $outPath
    exit 0
}

exit 1
