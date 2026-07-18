#Requires -Version 7.0
<#
.SYNOPSIS
Shows the currently active agent, its backend resolution, model, provider, tier, and free-token status.
AgentSwitchboard wrappers (opencode, agy, goose, gnhf) often default to predefined models without
surfacing the active choice. This script makes the active routing visible so the operator always
knows which agent and model are in use and what the fallback chain looks like.
#>
[CmdletBinding()]
param(
    [string]$AgentId,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\workstation'),
    [string]$FeedbackRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$catalogPath = Join-Path $repoRoot 'Config/ai-provider-catalog.json'
$routingPath = Join-Path $repoRoot 'harness/api/developer-workstation-agent-routing.json'

if ([string]::IsNullOrWhiteSpace($FeedbackRoot)) {
    $FeedbackRoot = Join-Path $repoRoot 'survey/output/agent_feedback'
}

$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$feedbackSummaryPath = Join-Path $FeedbackRoot 'feedback_summary.json'
$feedback = if (Test-Path -LiteralPath $feedbackSummaryPath) {
    Get-Content -Raw -LiteralPath $feedbackSummaryPath | ConvertFrom-Json
} else { $null }

$wsStatePath = Join-Path $StateRoot 'windows-tmux-workspace-state.json'
$wsState = if (Test-Path -LiteralPath $wsStatePath) { Get-Content -Raw -LiteralPath $wsStatePath | ConvertFrom-Json } else { $null }

$gnhfFleetRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"
$gnhfCapabilityPath = Join-Path $gnhfFleetRoot 'gnhf-runtime-capability.json'
$gnhfStatePath = Join-Path $gnhfFleetRoot 'state.json'
$gnhfCapability = if (Test-Path -LiteralPath $gnhfCapabilityPath) { Get-Content -Raw -LiteralPath $gnhfCapabilityPath | ConvertFrom-Json } else { $null }
$gnhfState = if (Test-Path -LiteralPath $gnhfStatePath) { Get-Content -Raw -LiteralPath $gnhfStatePath | ConvertFrom-Json } else { $null }

function Get-AgentInfoFromTmux {
    param([string]$Name)
    $result = & wsl.exe -d ($wsState.distro) -- sh -c "export PATH=`$HOME/.local/agent-switchboard/bin:`$PATH; $Name --agent-switchboard-probe 2>&1; echo 'EXIT_CODE='`$?"
    $lines = @($result | ForEach-Object { $_.ToString() })
    $exitLine = $lines | Where-Object { $_ -match '^EXIT_CODE=(\d+)$' }
    $exitCode = if ($exitLine) { [int]$exitLine -replace 'EXIT_CODE=', '' } else { -1 }
    $versionLines = $lines | Where-Object { $_ -notmatch '^EXIT_CODE=' }
    return [pscustomobject]@{ agent = $Name; available = ($exitCode -eq 0); exit_code = $exitCode; version_info = ($versionLines -join '; ').Trim() }
}

function Get-GnhfRoutingInfo {
    $result = [pscustomobject]@{ available = $false; version = $null; backend = $null; active_model = $null; active_agent = $null; ready = $false }
    if (-not $gnhfCapability -or -not $gnhfCapability.ready) { return $result }
    $result.available = $true
    $result.version = $gnhfCapability.distribution.installedVersion
    $result.ready = $gnhfCapability.ready
    $result.backend = "agent-switchboard-fleet (GnhfFleet)"
    $lm = $gnhfCapability.launchers
    $result.launcher_path = $lm.providerPs1
    $result.model_authority = $gnhfCapability.modelSelection.authority
    $result.model_mechanisms = ($gnhfCapability.modelSelection.mechanisms -join ', ')
    $result.has_cli_model_flag = $gnhfCapability.modelSelection.gnhfCliModelFlag
    if ($gnhfState -and $gnhfState.lastActiveModel) {
        $result.active_model = $gnhfState.lastActiveModel
    }
    if ($gnhfState -and $gnhfState.lastActiveAgent) {
        $result.active_agent = $gnhfState.lastActiveAgent
    }
    return $result
}

Write-Output "=== Agent Status ===" -ForegroundColor Cyan

$agentsToCheck = if ($AgentId) { @($AgentId) } else { @('opencode', 'agy', 'goose') }
$anyAvailable = $false

foreach ($agent in $agentsToCheck) {
    $info = Get-AgentInfoFromTmux -Name $agent
    $availableMark = if ($info.available) { 'AVAILABLE' } else { 'NOT FOUND' }
    $color = if ($info.available) { 'Green' } else { 'DarkYellow' }

    Write-Host "Agent: $agent [$availableMark]" -ForegroundColor $color
    if (-not $info.available) {
        Write-Host "  Backend: none (agent wrapper not installed)"
        Write-Host "  Status: skipped in routing"
        continue
    }
    $anyAvailable = $true

    $agentFeedback = if ($feedback -and $feedback.agents.PSObject.Properties.Name -contains $agent) { $feedback.agents.$agent } else { $null }
    $flagged = if ($agentFeedback -and $agentFeedback.flagged) { ' [FLAGGED - ORCHESTRATOR AVOIDING]' } else { '' }
    $backend = "managed-wrapper (AgentSwitchboard)"
    Write-Host "  Backend: $backend$flagged"

    $candidateModels = @()
    foreach ($provider in $catalog.providers) {
        foreach ($m in $provider.models) {
            $modelKey = "$($m.id)@$($provider.id)"
            $modelFeedback = if ($agentFeedback -and $agentFeedback.models.PSObject.Properties.Name -contains $modelKey) { $agentFeedback.models.$modelKey } else { $null }
            $flagged2 = if ($modelFeedback -and $modelFeedback.flagged) { ' [FLAGGED]' } else { '' }
            $tierLabel = switch ($provider.tier) {
                'free_local' { 'FREE LOCAL' }
                'free_cloud_free_tokens' { 'FREE CLOUD (free tokens)' }
                'free_cloud_trial' { 'FREE CLOUD (trial tokens)' }
                'paid' { 'PAID' }
            }
            $candidateModels += [pscustomobject]@{
                model = $m.id
                provider = $provider.display_name
                tier = $provider.tier
                tier_label = $tierLabel
                free_tokens = $provider.free_tokens_available
                flagged = $modelFeedback.flagged
                flag_text = $flagged2
            }
        }
    }

    $sorted = $candidateModels | Sort-Object @{Expression={$_.tier -eq 'paid'}}, @{Expression={$_.tier -eq 'free_cloud_trial'}}, @{Expression={$_.tier -eq 'free_cloud_free_tokens'}}, @{Expression={$_.tier -eq 'free_local'}}
    $available = $sorted | Where-Object { -not $_.flagged }
    $fallback = $sorted | Where-Object { $_.flagged }

    Write-Host "  Model priority (free tokens first, flagged avoided):"
    $shown = 0
    foreach ($m in $available) {
        if ($shown -ge 3) { break }
        $freeNote = if ($m.free_tokens) { ' (free tokens)' } else { ' (billed)' }
        Write-Host "    [$($m.tier_label)] $($m.model) @ $($m.provider)$freeNote"
        $shown++
    }
    if ($fallback.Count -gt 0) {
        Write-Host "  Flagged/avoided models:"
        foreach ($m in $fallback) {
            Write-Host "    [AVOIDED] $($m.model) @ $($m.provider)"
        }
    }
    Write-Host ""
}

$gnhfInfo = Get-GnhfRoutingInfo
if ($gnhfInfo.available) {
    $gnhfColor = if ($gnhfInfo.ready) { 'Green' } else { 'Yellow' }
    Write-Host "Orchestrator: GNHF (Good Night Have Fun)" -ForegroundColor $gnhfColor
    Write-Host "  Version: $($gnhfInfo.version)"
    Write-Host "  Ready: $($gnhfInfo.ready)"
    Write-Host "  Backend: $($gnhfInfo.backend)"
    Write-Host "  Model authority: $($gnhfInfo.model_authority)"
    Write-Host "  Model selection: $($gnhfInfo.model_mechanisms)"
    if ($gnhfInfo.active_model) {
        Write-Host "  Last active model: $($gnhfInfo.active_model)"
    } else {
        Write-Host "  Last active model: not recorded (GNHF delegates to OpenCode; model is hidden)"
        Write-Host "  [VISIBILITY] Enable model tracking by configuring OPENCODE_CONFIG_CONTENT or use the managed wrapper"
    }
    if ($gnhfInfo.active_agent) { Write-Host "  Last active agent: $($gnhfInfo.active_agent)" }
    Write-Host "  Fleet config: $gnhfFleetRoot"
    Write-Host ""
} else {
    Write-Host "Orchestrator: GNHF [NOT INSTALLED]" -ForegroundColor DarkYellow
    Write-Host "  Enable: npm install -g gnhf"
    Write-Host ""
}

$policy = $catalog.catalog_policy
Write-Host "Catalog Policy:" -ForegroundColor Cyan
Write-Host "  Free tokens before paid: $($policy.free_tokens_before_paid)"
Write-Host "  Free to paid fallback: $($policy.free_to_paid_fallback)"
Write-Host "  Feedback gated routing: $($policy.feedback_gates_orchestrator_routing)"
Write-Host "  Tier order: $($catalog.tier_fallback_order -join ' -> ')"
Write-Host ""

if (-not $anyAvailable) {
    Write-Host "No agents are available. Run the workstation setup to install agent wrappers:" -ForegroundColor Yellow
    Write-Host "  Developer-Workstation.cmd" -ForegroundColor White
}
