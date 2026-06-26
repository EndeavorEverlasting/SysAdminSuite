#Requires -Version 5.1
<#!
.SYNOPSIS
Central SysAdminSuite target-intake dispatcher.

.DESCRIPTION
Lists and validates approved target files for Cybernet survey use cases, then prints or runs
bounded commands that consume the codified target roots:
- targets/local
- logs/targets
- survey/input after normalization

Generated outputs stay under survey/output, logs/nmap, or survey/artifacts.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ListCandidates', 'NetworkPreflight', 'NaabuPlan', 'ADRegisteredPlan', 'SubnetConfirmPlan')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string]$TargetFile,

    [Parameter(Mandatory = $false)]
    [string]$Site = 'cybernet',

    [Parameter(Mandatory = $false)]
    [int[]]$Ports = @(135, 445, 3389, 9100),

    [Parameter(Mandatory = $false)]
    [string]$NaabuProfile = 'keyports_cybernet_json',

    [Parameter(Mandatory = $false)]
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoGuess = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoGuess 'scripts/SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing target-intake module: $modulePath"
}
Import-Module $modulePath -Force

$repoRoot = Get-SasRepoRoot -StartPath $PSScriptRoot
$roots = Get-SasTargetIntakeRoots -RepoRoot $repoRoot

function Write-DispatchHeader {
    param([string]$SelectedMode)
    Write-Host "SysAdminSuite target intake dispatch: $SelectedMode"
    Write-Host "Repo root: $repoRoot"
    Write-Host "Live intake roots: $($roots.SourceRoots -join ', ')"
    Write-Host "Normalized staging: $($roots.StagingRoot)"
    Write-Host "Generated outputs: $($roots.OutputRoots -join ', ')"
}

function Resolve-DispatchTargetFile {
    if ([string]::IsNullOrWhiteSpace($TargetFile)) {
        Write-DispatchHeader -SelectedMode $Mode
        Write-Host ''
        Write-Host 'No -TargetFile was selected. Candidate .txt/.csv files:'
        $candidates = @(Get-SasCandidateTargetFile -RepoRoot $repoRoot)
        if ($candidates.Count -eq 0) {
            Write-Host '- none found under targets/local or logs/targets'
        } else {
            foreach ($candidate in $candidates) { Write-Host "- $($candidate.FullName)" }
        }
        throw 'Select an approved target file before running a target-consuming mode.'
    }

    Assert-SasApprovedInputPath -Path $TargetFile -RepoRoot $repoRoot -Role 'dispatch target file' -AllowStaging
    return (Resolve-Path -LiteralPath $TargetFile).Path
}

function Write-CommandBlock {
    param(
        [string]$Label,
        [string]$Command
    )
    Write-Host ''
    Write-Host $Label
    Write-Host $Command
}

Write-DispatchHeader -SelectedMode $Mode

switch ($Mode) {
    'ListCandidates' {
        Write-Host ''
        Write-Host 'Candidate .txt/.csv target files from source-side intake roots:'
        $candidates = @(Get-SasCandidateTargetFile -RepoRoot $repoRoot)
        if ($candidates.Count -eq 0) {
            Write-Host '- none found'
        } else {
            foreach ($candidate in $candidates) { Write-Host "- $($candidate.FullName)" }
        }
        break
    }

    'NetworkPreflight' {
        $selected = Resolve-DispatchTargetFile
        $cmd = "& `"$repoRoot\survey\sas-network-preflight.ps1`" -TargetFile `"$selected`" -Ports $($Ports -join ',')"
        Write-CommandBlock -Label 'Run in Windows PowerShell:' -Command $cmd
        if ($Execute) { & (Join-Path $repoRoot 'survey/sas-network-preflight.ps1') -TargetFile $selected -Ports $Ports }
        break
    }

    'NaabuPlan' {
        $selected = Resolve-DispatchTargetFile
        $safeSite = ($Site.ToLowerInvariant() -replace '[^a-z0-9_-]', '')
        if (-not $safeSite) { throw 'Site must contain at least one alphanumeric character.' }
        $out = Join-Path $repoRoot "logs/nmap/${safeSite}_naabu.json"
        $cmd = "bash survey/sas-run-naabu-pipeline.sh --site $safeSite --profile $NaabuProfile --list `"$selected`" --out `"$out`" --dry-run"
        Write-CommandBlock -Label 'Advanced toolbox command plan only. Do not paste this into CMD. Run only in an approved developer/toolbox shell:' -Command $cmd
        break
    }

    'ADRegisteredPlan' {
        $selected = Resolve-DispatchTargetFile
        $outDir = Join-Path $repoRoot 'survey/output/ad_registered_population'
        $cmd = "bash survey/sas-export-ad-registered-population.sh --ad-csv `"$selected`" --output-dir `"$outDir`""
        Write-CommandBlock -Label 'Advanced offline AD export normalization plan. Source CSV must remain local/ignored:' -Command $cmd
        break
    }

    'SubnetConfirmPlan' {
        $selected = Resolve-DispatchTargetFile
        $safeSite = ($Site.ToLowerInvariant() -replace '[^a-z0-9_-]', '')
        if (-not $safeSite) { throw 'Site must contain at least one alphanumeric character.' }
        $cmd = "bash survey/sas-cybernet-subnet-survey.sh --site $safeSite --mode confirm-windows --confirm-tool naabu --host-file `"$selected`" --dry-run"
        Write-CommandBlock -Label 'Advanced subnet confirmation plan. Use only against approved target files:' -Command $cmd
        break
    }
}
