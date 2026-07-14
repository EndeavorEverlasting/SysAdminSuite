[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SummaryJson,

    [Parameter(Mandatory = $true)]
    [string]$ArtifactRegistry,

    [Parameter(Mandatory = $true)]
    [ValidateSet('serial-preflight', 'network-preflight', 'iteration', 'audit')]
    [string]$Template,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Throw-SasReportError {
    param([string]$Message)
    throw "Render-SasEnglishReport: $Message"
}

function Read-SasJsonFile {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-SasReportError "$Label not found: $Path"
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        Throw-SasReportError "$Label is not valid JSON: $Path"
    }
}

function Assert-SasProperties {
    param(
        [object]$Object,
        [string[]]$Names,
        [string]$Label
    )

    $existing = @($Object.PSObject.Properties.Name)
    $missing = @()
    foreach ($name in $Names) {
        if ($existing -notcontains $name) {
            $missing += $name
        }
    }

    if ($missing.Count -gt 0) {
        Throw-SasReportError "$Label missing required variable(s): $($missing -join ', ')"
    }
}

function Format-SasInlineCode {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return '``'
    }

    return ('`{0}`' -f $Text)
}

function Convert-SasIdentifierToWords {
    param([string]$Name)

    $text = $Name -replace '_', ' '
    $text = $text -creplace '([a-z0-9])([A-Z])', '$1 $2'
    return $text.ToLowerInvariant()
}

function Format-SasObjectSentence {
    param([object]$Value)

    $parts = @()
    foreach ($property in $Value.PSObject.Properties) {
        if ($null -eq $property.Value) { continue }
        $label = Convert-SasIdentifierToWords -Name $property.Name
        $parts += "$label as $($property.Value)"
    }
    if ($parts.Count -eq 0) { return 'This record contains no declared values.' }
    return "This record reports $($parts -join '; ')."
}

function Format-SasValueList {
    param([object]$Value)

    if ($null -eq $Value) {
        return @('- none declared')
    }

    if ($Value -is [System.Array]) {
        $items = @()
        foreach ($item in $Value) {
            if ($null -eq $item) { continue }
            if ($item -is [string]) {
                $items += "- $item"
            }
            else {
                $name = $null
                $path = $null
                $description = $null
                if ($item.PSObject.Properties.Name -contains 'name') { $name = $item.name }
                if ($item.PSObject.Properties.Name -contains 'path') { $path = $item.path }
                if ($item.PSObject.Properties.Name -contains 'description') { $description = $item.description }

                $parts = @()
                if ($name) { $parts += $name }
                if ($path) { $parts += (Format-SasInlineCode -Text $path) }
                if ($description) { $parts += $description }
                if ($parts.Count -eq 0) {
                    $items += "- $(Format-SasObjectSentence -Value $item)"
                }
                else {
                    $items += "- $($parts -join ' - ')"
                }
            }
        }
        if ($items.Count -eq 0) { return @('- none declared') }
        return $items
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @('- none declared') }
        return @("- $Value")
    }

    return @("- $(Format-SasObjectSentence -Value $Value)")
}

function Add-SasSection {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Title,
        [string[]]$Body
    )

    $Lines.Add('')
    $Lines.Add("## $Title")
    foreach ($line in $Body) {
        $Lines.Add($line)
    }
}

$coreRequired = @(
    'workflow_id',
    'run_id',
    'request_summary',
    'source_artifacts',
    'loaded_evidence_artifacts',
    'planner_name',
    'planner_version',
    'network_activity_performed',
    'low_noise_policy_version',
    'started_at',
    'finished_at',
    'operator_handoff_path',
    'summary_json_path',
    'report_markdown_path',
    'next_action'
)

$summary = Read-SasJsonFile -Path $SummaryJson -Label 'SummaryJson'
$registry = Read-SasJsonFile -Path $ArtifactRegistry -Label 'ArtifactRegistry'

Assert-SasProperties -Object $summary -Names $coreRequired -Label 'SummaryJson'
Assert-SasProperties -Object $registry -Names @('workflow_id', 'run_id', 'artifacts') -Label 'ArtifactRegistry'

if ($registry.artifacts -isnot [System.Array]) {
    Throw-SasReportError 'ArtifactRegistry artifacts must be an array'
}

$networkText = 'planner did not perform network activity.'
if ([bool]$summary.network_activity_performed) {
    $networkText = 'network activity occurred.'
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# SysAdminSuite $Template Report")

Add-SasSection -Lines $lines -Title 'Run identity' -Body @(
    "- Workflow: $($summary.workflow_id)",
    "- Run ID: $($summary.run_id)",
    "- Planner: $($summary.planner_name) $($summary.planner_version)",
    "- Started: $($summary.started_at)",
    "- Finished: $($summary.finished_at)"
)

Add-SasSection -Lines $lines -Title 'Request summary' -Body @($summary.request_summary)
Add-SasSection -Lines $lines -Title 'Source artifacts' -Body (Format-SasValueList -Value $summary.source_artifacts)
Add-SasSection -Lines $lines -Title 'Local evidence used' -Body (Format-SasValueList -Value $summary.loaded_evidence_artifacts)

$actionBody = if ($summary.PSObject.Properties.Name -contains 'action_decision') {
    @(
        "- Decision: $($summary.action_decision)",
        "- Next action: $($summary.next_action)"
    )
}
else {
    @(
        '- Decision: not separately declared; see next action.',
        "- Next action: $($summary.next_action)"
    )
}
Add-SasSection -Lines $lines -Title 'Action decision' -Body $actionBody

Add-SasSection -Lines $lines -Title 'Network activity status' -Body @(
    "- This run reports: $networkText"
)

$lowNoiseBody = @("- Policy version: $($summary.low_noise_policy_version)")
if ($summary.PSObject.Properties.Name -contains 'low_noise_profile') {
    $lowNoiseBody += "- Effective profile: $($summary.low_noise_profile)"
}
if ($summary.PSObject.Properties.Name -contains 'ports_source') {
    $lowNoiseBody += "- Constraint source: $($summary.ports_source)"
}
if ($summary.PSObject.Properties.Name -contains 'target_mutation_performed') {
    $mutationText = if ([bool]$summary.target_mutation_performed) { 'target mutation occurred.' } else { 'no target mutation occurred.' }
    $lowNoiseBody += "- Target posture: $mutationText"
}
if (($summary.PSObject.Properties.Name -contains 'low_noise_context') -and
    ($summary.low_noise_context.PSObject.Properties.Name -contains 'profile_id')) {
    $context = $summary.low_noise_context
    $constraints = $context.effective_constraints
    $lowNoiseBody += @(
        "- SysAdminSuite applied profile $($context.profile_id) from $($context.profile_source).",
        "- The approved target source was $($context.target_source), and the evidence source was $($context.evidence_source).",
        "- Effective constraints limited ports to $(@($constraints.ports) -join ','), rate to $($constraints.rate_cap), retries to $($constraints.retries), and host discovery to $($constraints.host_discovery_mode).",
        "- The run disposition was $($context.disposition) because $($context.reason)",
        "- Network activity performed: $($context.network_activity_performed); target mutation performed: $($context.target_mutation_performed).",
        "- Policy-directed next action: $($context.next_action)"
    )
}
elseif ($summary.PSObject.Properties.Name -contains 'low_noise_context') {
    $lowNoiseBody += Format-SasValueList -Value $summary.low_noise_context
}
else {
    $lowNoiseBody += '- Fresh evidence should reduce repeat work; retries should be justified by changed timing, changed evidence, or operator review.'
}
Add-SasSection -Lines $lines -Title 'Low-noise context' -Body $lowNoiseBody

$results = @()
foreach ($name in @(
    'serials_total',
    'serials_with_probe_ready_bridge',
    'serials_mystery_no_bridge',
    'review_required_count',
    'probe_targets_staged',
    'probe_target_file',
    'ports_requested',
    'target_count',
    'network_preflight_csv',
    'newly_reachable_count',
    'still_silent_count',
    'stale_or_conflicting_count',
    'persistent_silent_time_diverse_count',
    'plateau_detected'
)) {
    if ($summary.PSObject.Properties.Name -contains $name) {
        $label = Convert-SasIdentifierToWords -Name $name
        $results += "- The $label value is $($summary.$name)."
    }
}
if ($results.Count -eq 0) { $results += '- No result counters declared.' }
Add-SasSection -Lines $lines -Title 'Results summary' -Body $results

$reviewBody = @('- Review-required rows are preserved for operator review; this report does not convert uncertainty into proof.')
if ($summary.PSObject.Properties.Name -contains 'review_required_rows') {
    $reviewBody += Format-SasValueList -Value $summary.review_required_rows
}
elseif ($summary.PSObject.Properties.Name -contains 'review_required_count') {
    $reviewBody += "- Review-required count: $($summary.review_required_count)"
}
Add-SasSection -Lines $lines -Title 'Review-required rows' -Body $reviewBody

Add-SasSection -Lines $lines -Title 'Next action' -Body @($summary.next_action)

$artifactLines = @()
foreach ($artifact in $registry.artifacts) {
    Assert-SasProperties -Object $artifact -Names @('role', 'path', 'tracked', 'contains_live_data', 'generated', 'description') -Label 'ArtifactRegistry artifact'
    $artifactPath = Format-SasInlineCode -Text $artifact.path
    $trackedText = if ([bool]$artifact.tracked) { 'tracked' } else { 'not tracked' }
    $liveText = if ([bool]$artifact.contains_live_data) { 'contains live data' } else { 'contains synthetic or non-live data' }
    $generatedText = if ([bool]$artifact.generated) { 'was generated by the run' } else { 'was supplied as an input' }
    $artifactLines += "- The $($artifact.role) artifact at $artifactPath is $trackedText, $liveText, and $generatedText. $($artifact.description)"
}
Add-SasSection -Lines $lines -Title 'Artifact list' -Body $artifactLines

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
Write-Host "Rendered SysAdminSuite English report: $OutputPath"
