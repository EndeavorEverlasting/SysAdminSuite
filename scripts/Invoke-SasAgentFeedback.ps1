#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$AgentId,
    [Parameter(Mandatory)][string]$ModelId,
    [Parameter(Mandatory)][string]$ProviderId,
    [Parameter(Mandatory)][ValidateSet('thumbs_up','thumbs_down','neutral')][string]$Vote,
    [Parameter(Mandatory)][string]$WorkContext,
    [string]$ContributionSummary,
    [string]$Reason,
    [string]$SessionId,
    [string]$Voter,
    [string]$FeedbackRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Vote -eq 'thumbs_down' -and [string]::IsNullOrWhiteSpace($Reason)) {
    throw 'Thumbs-down vote requires a Reason. Provide the reason the contribution had to be undone or modified.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FeedbackRoot)) {
    $FeedbackRoot = Join-Path $repoRoot 'survey/output/agent_feedback'
}
New-Item -ItemType Directory -Path $FeedbackRoot -Force -WhatIf:$false | Out-Null
$eventsPath = Join-Path $FeedbackRoot 'feedback_events.jsonl'
$summaryPath = Join-Path $FeedbackRoot 'feedback_summary.json'
$schemaPath = Join-Path $repoRoot 'schemas/harness/agent-feedback-event.schema.json'

$event = [ordered]@{
    schema_version = 'sas-agent-feedback-event/v1'
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    agent_id = $AgentId
    model_id = $ModelId
    provider_id = $ProviderId
    vote = $Vote
    work_context = $WorkContext
    contribution_summary = $ContributionSummary
    reason = $Reason
    session_id = $SessionId
    voter = $Voter
}

$json = $event | ConvertTo-Json -Depth 6
if (-not ($json | Test-Json -SchemaFile $schemaPath)) {
    throw 'Feedback event did not validate against agent-feedback-event schema'
}

$json | Add-Content -LiteralPath $eventsPath -Encoding UTF8 -WhatIf:$false

$events = @(Get-Content -LiteralPath $eventsPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
$summary = [ordered]@{
    schema_version = 'sas-agent-feedback-summary/v1'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    total_events = $events.Count
    agents = [ordered]@{}
    providers = [ordered]@{}
}

foreach ($evt in $events) {
    if (-not $summary.agents.Contains($evt.agent_id)) {
        $summary.agents[$evt.agent_id] = [ordered]@{
            total = 0; thumbs_up = 0; thumbs_down = 0; neutral = 0; flagged = $false
            models = [ordered]@{}
        }
    }
    $agentEntry = $summary.agents[$evt.agent_id]
    $agentEntry.total++
    $agentEntry.$($evt.vote)++

    $modelKey = "$($evt.model_id)@$($evt.provider_id)"
    if (-not $agentEntry.models.Contains($modelKey)) {
        $agentEntry.models[$modelKey] = [ordered]@{ model_id = $evt.model_id; provider_id = $evt.provider_id; total = 0; thumbs_up = 0; thumbs_down = 0; neutral = 0; flagged = $false }
    }
    $modelEntry = $agentEntry.models[$modelKey]
    $modelEntry.total++
    $modelEntry.$($evt.vote)++

    if ($modelEntry.thumbs_down -ge 2 -or ($modelEntry.total -ge 5 -and $modelEntry.thumbs_down -ge 3)) {
        $modelEntry.flagged = $true
    }
}

foreach ($agentId in $summary.agents.Keys) {
    $agentEntry = $summary.agents[$agentId]
    $anyFlagged = @($agentEntry.models.Values | Where-Object { $_.flagged }).Count -gt 0
    if ($anyFlagged) { $agentEntry.flagged = $true }
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8 -WhatIf:$false

Write-Output $event
Write-Output "Feedback written to $eventsPath"
Write-Output "Summary written to $summaryPath"
