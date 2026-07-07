#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-SasRepoRoot {
    [CmdletBinding()]
    param([string]$StartPath)

    $cursor = if ($StartPath) { [System.IO.Path]::GetFullPath($StartPath) } else { (Get-Location).Path }
    if (Test-Path -LiteralPath $cursor -PathType Leaf) {
        $cursor = Split-Path -Parent $cursor
    }

    while ($cursor) {
        if ((Test-Path -LiteralPath (Join-Path $cursor 'targets/README.md')) -and
            (Test-Path -LiteralPath (Join-Path $cursor 'survey'))) {
            return $cursor
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }

    throw 'Unable to resolve SysAdminSuite repo root.'
}

function ConvertTo-SasRunContextFullPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Test-SasRunContextPathUnderRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = ConvertTo-SasRunContextFullPath -Path $Path
    $fullRoot = ConvertTo-SasRunContextFullPath -Path $Root
    if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if (-not $fullRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fullRoot = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    }

    return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-SasRunIdPrefix {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkflowId)

    Assert-SasWorkflowId -WorkflowId $WorkflowId

    $sanitized = $WorkflowId.ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
    $sanitized = $sanitized -replace '-+', '-'

    while ($sanitized.Length -gt 0 -and ($sanitized.StartsWith('-') -or $sanitized.StartsWith('_'))) {
        $sanitized = $sanitized.Substring(1)
    }
    while ($sanitized.Length -gt 0 -and ($sanitized.EndsWith('-') -or $sanitized.EndsWith('_'))) {
        $sanitized = $sanitized.Substring(0, $sanitized.Length - 1)
    }

    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        $sanitized = 'run'
    }
    if ($sanitized -notmatch '^[a-zA-Z]') {
        $sanitized = "run-$sanitized"
    }
    if ($sanitized.Length -gt 32) {
        $sanitized = $sanitized.Substring(0, 32)
    }

    return $sanitized
}

function New-SasRunId {
    [CmdletBinding()]
    param(
        [datetime]$Timestamp = (Get-Date),
        [string]$Prefix = 'run'
    )

    if ($Prefix -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,31}$') {
        throw "Run ID prefix is invalid: $Prefix"
    }

    return ('{0}-{1}-{2}' -f $Prefix.ToLowerInvariant(), $Timestamp.ToUniversalTime().ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8)))
}

function Test-SasWorkflowId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkflowId)

    return ($WorkflowId -match '^[a-zA-Z0-9][a-zA-Z0-9_.-]{1,127}$' -and
        $WorkflowId -notmatch '\.\.' -and
        $WorkflowId -notmatch '[\\/:*?"<>|]')
}

function Assert-SasWorkflowId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkflowId)

    if (-not (Test-SasWorkflowId -WorkflowId $WorkflowId)) {
        throw "Invalid SysAdminSuite workflow id: $WorkflowId"
    }
}

function Resolve-SasOutputRoot {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        [switch]$Survey,
        [string]$OutputRoot
    )

    if ($OutputRoot) { return ConvertTo-SasRunContextFullPath -Path $OutputRoot }
    if (-not $RepoRoot) { $RepoRoot = Get-SasRepoRoot }

    if ($Survey) {
        return Join-Path $RepoRoot 'survey/output/runs'
    }

    return Join-Path $RepoRoot 'runs'
}

function Assert-SasLocalOutputRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [string]$RepoRoot,
        [switch]$AllowNonstandard
    )

    if (-not $RepoRoot) { $RepoRoot = Get-SasRepoRoot }

    $approvedRoots = @(
        (Join-Path $RepoRoot 'runs'),
        (Join-Path $RepoRoot 'survey/output/runs'),
        (Join-Path $RepoRoot 'survey/output'),
        (Join-Path $RepoRoot 'survey/artifacts'),
        (Join-Path $RepoRoot 'logs')
    )

    foreach ($root in $approvedRoots) {
        if (Test-SasRunContextPathUnderRoot -Path $OutputRoot -Root $root) { return }
    }

    if ($AllowNonstandard) {
        Write-Warning "NONSTANDARD RUN OUTPUT OVERRIDE: output root is outside codified local roots: $OutputRoot"
        return
    }

    throw "Run output root is outside approved local output roots. Use runs/, survey/output/runs/, survey/output/, survey/artifacts/, or logs/. Refusing: $OutputRoot"
}

function New-SasArtifactRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkflowId,
        [Parameter(Mandatory = $true)][string]$RunId,
        [string]$CreatedBy = 'SasRunContext'
    )

    Assert-SasWorkflowId -WorkflowId $WorkflowId

    return [pscustomobject]@{
        schema_version = 'sas-artifact-registry/v1'
        workflow_id = $WorkflowId
        run_id = $RunId
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        created_by = $CreatedBy
        artifacts = @()
    }
}

function Save-SasJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 12
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SasRunSummaryPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RunRoot)

    return Join-Path $RunRoot 'summary.json'
}

function New-SasRunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkflowId,
        [string]$RunId,
        [string]$RepoRoot,
        [string]$OutputRoot,
        [switch]$Survey,
        [string]$RequestSummary = 'No request summary provided.',
        [string]$SourceArtifact = '',
        [string]$CreatedBy = 'SasRunContext',
        [switch]$AllowNonstandardOutputRoot
    )

    Assert-SasWorkflowId -WorkflowId $WorkflowId
    if (-not $RepoRoot) { $RepoRoot = Get-SasRepoRoot }
    if (-not $RunId) { $RunId = New-SasRunId -Prefix (ConvertTo-SasRunIdPrefix -WorkflowId $WorkflowId) }

    $resolvedOutputRoot = Resolve-SasOutputRoot -RepoRoot $RepoRoot -Survey:$Survey -OutputRoot $OutputRoot
    Assert-SasLocalOutputRoot -OutputRoot $resolvedOutputRoot -RepoRoot $RepoRoot -AllowNonstandard:$AllowNonstandardOutputRoot

    $workflowRoot = Join-Path $resolvedOutputRoot $WorkflowId
    $runRoot = Join-Path $workflowRoot $RunId
    if (Test-Path -LiteralPath (Join-Path $runRoot 'context.json') -PathType Leaf) {
        throw "Run context already exists: $runRoot"
    }

    $directories = @(
        $runRoot,
        (Join-Path $runRoot 'actions'),
        (Join-Path $runRoot 'artifacts'),
        (Join-Path $runRoot 'evidence'),
        (Join-Path $runRoot 'reports'),
        (Join-Path $runRoot 'review')
    )

    foreach ($directory in $directories) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $context = [pscustomobject]@{
        schema_version = 'sas-run-context/v1'
        workflow_id = $WorkflowId
        run_id = $RunId
        workflow_root = $workflowRoot
        run_root = $runRoot
        output_root = $resolvedOutputRoot
        request_summary = $RequestSummary
        source_artifact = $SourceArtifact
        network_activity = 'No network activity performed.'
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        created_by = $CreatedBy
        directories = [pscustomobject]@{
            actions = Join-Path $runRoot 'actions'
            artifacts = Join-Path $runRoot 'artifacts'
            evidence = Join-Path $runRoot 'evidence'
            reports = Join-Path $runRoot 'reports'
            review = Join-Path $runRoot 'review'
        }
        artifact_registry_path = Join-Path $runRoot 'artifact_registry.json'
        summary_path = Get-SasRunSummaryPath -RunRoot $runRoot
        operator_handoff_path = Join-Path $runRoot 'operator_handoff.txt'
    }

    $request = [pscustomobject]@{
        schema_version = 'sas-run-request/v1'
        workflow_id = $WorkflowId
        run_id = $RunId
        request_summary = $RequestSummary
        source_artifact = $SourceArtifact
        network_activity = 'No network activity performed.'
        created_at = $context.created_at
    }

    $plan = [pscustomobject]@{
        schema_version = 'sas-run-plan/v1'
        workflow_id = $WorkflowId
        run_id = $RunId
        action = 'initialize-run-context'
        network_activity = 'No network activity performed.'
        next_action = 'Register source and output artifacts before rendering reports.'
    }

    $summary = [pscustomobject]@{
        schema_version = 'sas-run-summary/v1'
        workflow_id = $WorkflowId
        run_id = $RunId
        network_activity = 'No network activity performed.'
        artifact_count = 0
        review_required = $false
    }

    $registry = New-SasArtifactRegistry -WorkflowId $WorkflowId -RunId $RunId -CreatedBy $CreatedBy

    Save-SasJsonFile -InputObject $request -Path (Join-Path $runRoot 'request.json')
    Save-SasJsonFile -InputObject $context -Path (Join-Path $runRoot 'context.json')
    Save-SasJsonFile -InputObject $plan -Path (Join-Path $runRoot 'plan.json')
    Save-SasJsonFile -InputObject $summary -Path $context.summary_path
    Save-SasJsonFile -InputObject $registry -Path $context.artifact_registry_path
    Set-Content -LiteralPath (Join-Path $runRoot 'plan.md') -Encoding UTF8 -Value @(
        "# $WorkflowId plan",
        '',
        'Network activity: No network activity performed.',
        '',
        'Next action: Register source and output artifacts before rendering reports.'
    )
    Set-Content -LiteralPath $context.operator_handoff_path -Encoding UTF8 -Value 'No network activity performed. Register source and output artifacts before rendering reports.'

    return $context
}

function Register-SasArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Path,
        [bool]$Tracked = $false,
        [bool]$LiveData = $false,
        [Parameter(Mandatory = $true)][string]$Description,
        [string]$SourceArtifact = '',
        [string]$NetworkActivity = 'No network activity performed.',
        [string]$CreatedBy = 'SasRunContext'
    )

    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
        throw "Artifact registry not found: $RegistryPath"
    }

    $registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
    if ($registry.schema_version -ne 'sas-artifact-registry/v1') {
        throw "Unsupported artifact registry schema: $($registry.schema_version)"
    }

    $entry = [pscustomobject]@{
        role = $Role
        path = $Path
        tracked = $Tracked
        live_data = $LiveData
        description = $Description
        source_artifact = $SourceArtifact
        network_activity = $NetworkActivity
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        created_by = $CreatedBy
    }

    $artifacts = @($registry.artifacts)
    $artifacts += $entry
    $registry.artifacts = $artifacts
    Save-SasJsonFile -InputObject $registry -Path $RegistryPath

    return $entry
}

Export-ModuleMember -Function New-SasRunId, Test-SasWorkflowId, Resolve-SasOutputRoot, Assert-SasLocalOutputRoot, New-SasArtifactRegistry, Register-SasArtifact, Get-SasRunSummaryPath, New-SasRunContext
