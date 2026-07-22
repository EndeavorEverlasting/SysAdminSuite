#Requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasCybernetRepositoryRoot {
    [CmdletBinding()]
    param()

    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function Import-SasCybernetTargetIntake {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $modulePath = Join-Path $RepoRoot 'scripts\SasTargetIntake.psm1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "Missing canonical target-intake module: $modulePath"
    }
    Import-Module -Name $modulePath -Force
}

function Resolve-SasCybernetTargets {
    [CmdletBinding()]
    param(
        [string[]]$ComputerName = @(),
        [string]$TargetsCsv,
        [ValidateRange(1, 25)]
        [int]$MaxTargets = 25,
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$Role
    )

    Import-SasCybernetTargetIntake -RepoRoot $RepoRoot
    $items = @()
    foreach ($target in @($ComputerName)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$target)) {
            $items += ([string]$target).Trim()
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($TargetsCsv)) {
        Assert-SasApprovedInputPath -Path $TargetsCsv -RepoRoot $RepoRoot -Role $Role -AllowStaging
        foreach ($row in @(Import-Csv -LiteralPath $TargetsCsv)) {
            foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
                if ($row.PSObject.Properties.Name -contains $column) {
                    $candidate = [string]$row.$column
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $items += $candidate.Trim()
                        break
                    }
                }
            }
        }
    }

    $seen = @{}
    $resolved = @()
    foreach ($target in $items) {
        if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$') {
            throw "Invalid Cybernet target name: $target"
        }
        $key = $target.ToUpperInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $resolved += $target
        }
    }

    if ($resolved.Count -eq 0) {
        throw 'No explicit Cybernet targets were supplied. Use -ComputerName or -TargetsCsv.'
    }
    if ($resolved.Count -gt $MaxTargets) {
        throw "Target count $($resolved.Count) exceeds MaxTargets $MaxTargets. Split the batch."
    }

    return @($resolved)
}

function New-SasCybernetRunRoot {
    [CmdletBinding()]
    param(
        [string]$OutputRoot,
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        [Parameter(Mandatory = $true)]
        [string]$Role
    )

    Import-SasCybernetTargetIntake -RepoRoot $RepoRoot
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Join-Path $RepoRoot 'survey\output\cybernet_hardware'
    }
    Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $RepoRoot -Role $Role

    $runId = '{0}-{1}-{2}' -f $Prefix, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runRoot = Join-Path $OutputRoot $runId
    New-Item -ItemType Directory -Path $runRoot -Force -WhatIf:$false | Out-Null

    return [pscustomobject]@{
        run_id = $runId
        output_root = $OutputRoot
        run_root = $runRoot
    }
}

function Write-SasCybernetHardwareJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -WhatIf:$false | Out-Null
    }
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}

function Get-SasCybernetComClassification {
    [CmdletBinding()]
    param([string[]]$Ports)

    $normalized = @($Ports | Where-Object { $_ -match '^COM\d+$' } | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object -Unique)
    $ready = @('COM1', 'COM2', 'COM3', 'COM4')
    $repairable = @('COM3', 'COM4', 'COM5', 'COM6')
    $joined = $normalized -join ','

    if ($joined -eq ($ready -join ',')) { return 'COM_PORTS_READY' }
    if ($joined -eq ($repairable -join ',')) { return 'COM_AUTOFIX_ELIGIBLE_LOCAL_ONLY' }
    return 'COM_PORT_REVIEW_REQUIRED'
}

Export-ModuleMember -Function `
    Get-SasCybernetRepositoryRoot, `
    Resolve-SasCybernetTargets, `
    New-SasCybernetRunRoot, `
    Write-SasCybernetHardwareJson, `
    Get-SasCybernetComClassification
