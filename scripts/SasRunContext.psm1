Set-StrictMode -Version Latest

function New-SasRunId {
    [CmdletBinding()]
    param(
        [datetime]$Timestamp = (Get-Date)
    )

    return $Timestamp.ToString('yyyyMMdd-HHmmss')
}

function Get-SasRepoRoot {
    [CmdletBinding()]
    param()

    $current = Get-Location
    try {
        $gitRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
            return $gitRoot.Trim()
        }
    }
    catch {
        # Fall back below when git is unavailable.
    }

    return $current.Path
}

function New-SasRunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [string]$RunId = (New-SasRunId),

        [string]$RepoRoot = (Get-SasRepoRoot),

        [bool]$NetworkActivityPlanned = $false,

        [bool]$NetworkActivityPerformed = $false,

        [string]$LowNoisePolicyVersion = 'sas-low-noise-policy/v1'
    )

    $outputRoot = Join-Path -Path $RepoRoot -ChildPath (Join-Path -Path 'survey/output/runs' -ChildPath (Join-Path -Path $WorkflowId -ChildPath $RunId))
    $registryPath = Join-Path -Path $outputRoot -ChildPath 'artifact_registry.json'

    return [pscustomobject]@{
        workflow_id = $WorkflowId
        run_id = $RunId
        started_at = (Get-Date).ToString('o')
        repo_root = $RepoRoot
        output_root = $outputRoot
        network_activity_planned = $NetworkActivityPlanned
        network_activity_performed = $NetworkActivityPerformed
        low_noise_policy_version = $LowNoisePolicyVersion
        artifact_registry_path = $registryPath
        artifacts = @()
    }
}

function Add-SasRunArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [bool]$Tracked,

        [Parameter(Mandatory = $true)]
        [bool]$ContainsLiveData,

        [Parameter(Mandatory = $true)]
        [bool]$Generated,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [string]$Sha256
    )

    $artifact = [ordered]@{
        role = $Role
        path = $Path
        tracked = $Tracked
        contains_live_data = $ContainsLiveData
        generated = $Generated
        description = $Description
        created_at = (Get-Date).ToString('o')
    }

    if (-not [string]::IsNullOrWhiteSpace($Sha256)) {
        $artifact.sha256 = $Sha256
    }

    $existing = @($Context.artifacts)
    $Context.artifacts = @($existing + [pscustomobject]$artifact)
    return $Context
}

function Write-SasArtifactRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [string]$Path = $Context.artifact_registry_path
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $registry = [ordered]@{
        workflow_id = $Context.workflow_id
        run_id = $Context.run_id
        started_at = $Context.started_at
        repo_root = $Context.repo_root
        output_root = $Context.output_root
        network_activity_planned = $Context.network_activity_planned
        network_activity_performed = $Context.network_activity_performed
        low_noise_policy_version = $Context.low_noise_policy_version
        artifact_registry_path = $Path
        artifacts = @($Context.artifacts)
    }

    $registry | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Read-SasArtifactRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "SasRunContext: artifact registry not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

Export-ModuleMember -Function New-SasRunId, New-SasRunContext, Add-SasRunArtifact, Write-SasArtifactRegistry, Read-SasArtifactRegistry
