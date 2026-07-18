#Requires -Version 7.0
[CmdletBinding()]
param([string]$FeedbackRoot)

Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FeedbackRoot)) {
    $FeedbackRoot = Join-Path $repoRoot 'survey/output/agent_feedback'
}
$summaryPath = Join-Path $FeedbackRoot 'feedback_summary.json'
$eventsPath = Join-Path $FeedbackRoot 'feedback_events.jsonl'

if (-not (Test-Path -LiteralPath $summaryPath)) {
    Write-Output 'No feedback summary found. No votes have been cast yet.'
    return
}

$summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
$events = if (Test-Path -LiteralPath $eventsPath) {
    @(Get-Content -LiteralPath $eventsPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
} else { @() }

Write-Output "=== Agent Feedback Summary ==="
Write-Output "Total votes: $($summary.total_events)"
Write-Output "Generated: $($summary.generated_utc)"
Write-Output ""

if ($summary.agents.PSObject.Properties.Count -eq 0) {
    Write-Output "No agent feedback recorded."
    return
}

foreach ($agentProp in $summary.agents.PSObject.Properties) {
    $agent = $agentProp.Value
    $flag = if ($agent.flagged) { ' [FLAGGED]' } else { '' }
    Write-Output "Agent: $($agentProp.Name)$flag"
    Write-Output "  Total: $($agent.total) | Up: $($agent.thumbs_up) | Down: $($agent.thumbs_down) | Neutral: $($agent.neutral)"

    if ($agent.models.PSObject.Properties.Count -gt 0) {
        foreach ($modelProp in $agent.models.PSObject.Properties) {
            $m = $modelProp.Value
            $mflag = if ($m.flagged) { ' [FLAGGED - ORCHESTRATOR WILL AVOID]' } else { '' }
            Write-Output "  Model: $($m.model_id) @ $($m.provider_id)$mflag"
            Write-Output "    Total: $($m.total) | Up: $($m.thumbs_up) | Down: $($m.thumbs_down) | Neutral: $($m.neutral)"
        }
    }

    $downVotes = @($events | Where-Object { $_.agent_id -eq $agentProp.Name -and $_.vote -eq 'thumbs_down' })
    if ($downVotes.Count -gt 0) {
        Write-Output "  Recent thumbs-down:"
        foreach ($dv in $downVotes[-3..-1]) {
            Write-Output "    [$($dv.timestamp_utc)] $($dv.model_id) @ $($dv.provider_id): $($dv.reason)"
        }
    }
    Write-Output ""
}

Write-Output "=== End ==="
