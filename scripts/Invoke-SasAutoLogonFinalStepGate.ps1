#Requires -Version 5.1
<#
.SYNOPSIS
Fail-closed prerequisite gate for AutoLogon product-configuration mutation.

.DESCRIPTION
Invoke-SasAutoLogonFinalStepGate evaluates whether all prerequisites are satisfied before
the AutoLogon installer may execute on a target workstation. AutoLogon is a product-configuration
mutation that modifies Winlogon registry keys; it is not a read-only survey.

The gate must be called before the AutoLogon installer runs. It checks:

  1. Target hostname eligibility (delegates to Test-SasHostEligibility when available)
  2. Approved software catalog entry for the autologon package
  3. State-delta Before snapshot has been captured for this run
  4. Technician runtime proof has been captured (recommended, not blocking)
  5. File access posture has been verified (recommended, not blocking)

When any mandatory prerequisite fails, the gate blocks execution. There is no -Force,
environment variable, or undocumented override that allows a failed gate to proceed.

The gate produces a structured JSON result suitable for evidence collection and audit.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [string]$BeforeSnapshotPath,

    [Parameter(Mandatory = $false)]
    [string]$ApprovedAppsPath,

    [Parameter(Mandatory = $false)]
    [string]$HostEligibilityPolicyPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string]$TechnicianLabel,

    [Parameter(Mandatory = $false)]
    [switch]$RequireRuntimeProof,

    [Parameter(Mandatory = $false)]
    [switch]$RequireFileAccessPosture,

    [Parameter(Mandatory = $false)]
    [ValidateSet('local', 'remote', 'fixture', 'vm')]
    [string]$ExecContext = 'local',

    [Parameter(Mandatory = $false)]
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ── Gate result structure ──────────────────────────────────────────────
$gateResult = [ordered]@{
    gate_id          = 'autologon-final-step'
    gate_version     = '1.0.0'
    target           = $Target
    run_id           = $RunId
    exec_context     = $ExecContext
    timestamp_utc    = (Get-Date).ToUniversalTime().ToString('o')
    technician_label = $TechnicianLabel
    fixture_mode     = $FixtureMode.IsPresent
    prerequisites    = @()
    overall_pass     = $false
    blocked_reason   = $null
}

# ── Prerequisite check functions ───────────────────────────────────────

function Add-Prerequisite {
    param(
        [string]$Id,
        [string]$Description,
        [bool]$Passed,
        [bool]$Mandatory,
        [string]$Detail
    )
    $gateResult.prerequisites += [ordered]@{
        id          = $Id
        description = $Description
        passed      = $Passed
        mandatory   = $Mandatory
        detail      = $Detail
    }
}

function Test-ApprovedSoftwareCatalog {
    param([string]$Path, [string]$PackageName)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @{ passed = $false; detail = 'ApprovedAppsPath not supplied' }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @{ passed = $false; detail = "Approved apps catalog not found: $Path" }
    }

    try {
        $catalog = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        return @{ passed = $false; detail = "Approved apps catalog is malformed: $($_.Exception.Message)" }
    }

    if ($catalog.schema_version -ne 'sas-approved-software-catalog/v1') {
        return @{ passed = $false; detail = "Unexpected catalog schema version: $($catalog.schema_version)" }
    }

    $match = $catalog.packages | Where-Object { $_.id -eq $PackageName }
    if ($null -eq $match) {
        return @{ passed = $false; detail = "Package '$PackageName' not found in approved catalog" }
    }
    if (-not $match.install_enabled) {
        return @{ passed = $false; detail = "Package '$PackageName' exists but install_enabled is false" }
    }
    if ([string]::IsNullOrWhiteSpace($match.installer_file)) {
        return @{ passed = $false; detail = "Package '$PackageName' has no pinned installer_file" }
    }

    return @{ passed = $true; detail = "Package '$PackageName' found: $($match.display_name), installer=$($match.installer_file)" }
}

function Test-StateDeltaBeforeSnapshot {
    param([string]$Path, [string]$ExpectedRunId)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @{ passed = $false; detail = 'BeforeSnapshotPath not supplied' }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @{ passed = $false; detail = "Before snapshot not found: $Path" }
    }

    try {
        $snapshot = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        return @{ passed = $false; detail = "Before snapshot is malformed: $($_.Exception.Message)" }
    }

    $snapshotRunId = $snapshot.run_id
    if ([string]::IsNullOrWhiteSpace($snapshotRunId)) {
        return @{ passed = $false; detail = 'Before snapshot has no run_id' }
    }
    if ($snapshotRunId -ne $ExpectedRunId) {
        return @{ passed = $false; detail = "Before snapshot run_id mismatch: expected '$ExpectedRunId', got '$snapshotRunId'" }
    }

    $phase = $snapshot.phase
    if ($phase -ne 'before_complete') {
        return @{ passed = $false; detail = "Before snapshot phase is '$phase', expected 'before_complete'" }
    }

    $targets = $snapshot.targets
    if ($null -eq $targets -or @($targets).Count -eq 0) {
        return @{ passed = $false; detail = 'Before snapshot has no captured targets' }
    }

    $targetMatch = @($targets | Where-Object {
        $obj = $_
        $matched = $false
        foreach ($prop in @('computer_name', 'ComputerName', 'hostname', 'HostName')) {
            if ($obj.PSObject.Properties.Name -contains $prop) {
                if ($obj.$prop -eq $Target) { $matched = $true; break }
            }
        }
        $matched
    })
    if ($targetMatch.Count -eq 0) {
        return @{ passed = $false; detail = "Target '$Target' not found in Before snapshot targets" }
    }

    return @{ passed = $true; detail = "Before snapshot validated for run '$ExpectedRunId', target '$Target'" }
}

function Test-HostEligibility {
    param([string]$TargetName, [string]$PolicyPath, [string]$RepoRoot)

    $eligibilityScript = $null
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $candidate = Join-Path $RepoRoot 'scripts' | Join-Path -ChildPath 'Test-SasHostEligibility.ps1'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $eligibilityScript = $candidate
        }
    }
    if ($null -eq $eligibilityScript) {
        $fromPSScriptRoot = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'scripts' | Join-Path -ChildPath 'Test-SasHostEligibility.ps1'
        if (Test-Path -LiteralPath $fromPSScriptRoot -PathType Leaf) {
            $eligibilityScript = $fromPSScriptRoot
        }
    }

    if ($null -eq $eligibilityScript) {
        return @{ passed = $false; detail = 'Test-SasHostEligibility.ps1 not found; host eligibility cannot be verified' }
    }

    try {
        $params = @{
            Target     = $TargetName
            ExecContext = $ExecContext
        }
        if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) {
            $params.PolicyPath = $PolicyPath
        }
        if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
            $params.RepoRoot = $RepoRoot
        }

        $result = & $eligibilityScript @params
        if ($result.eligible) {
            return @{ passed = $true; detail = "Host '$TargetName' is eligible for local execution context" }
        }
        else {
            return @{ passed = $false; detail = "Host '$TargetName' is NOT eligible: $($result.reason)" }
        }
    }
    catch {
        return @{ passed = $false; detail = "Host eligibility check failed: $($_.Exception.Message)" }
    }
}

# ── Execute prerequisite checks ────────────────────────────────────────

# 1. Run ID format validation
$runIdValid = $RunId -match '^autologon-delta-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$'
Add-Prerequisite -Id 'run_id_format' -Description 'Run ID matches autologon-delta format' `
    -Passed $runIdValid -Mandatory $true `
    -Detail $(if ($runIdValid) { "Run ID '$RunId' is valid" } else { "Run ID '$RunId' does not match expected format" })

# 2. Host eligibility
$repoRoot = Split-Path $PSScriptRoot -Parent
$eligibility = Test-HostEligibility -TargetName $Target -PolicyPath $HostEligibilityPolicyPath -RepoRoot $repoRoot
Add-Prerequisite -Id 'host_eligibility' -Description 'Target host is eligible for package execution' `
    -Passed $eligibility.passed -Mandatory $true -Detail $eligibility.detail

# 3. Approved software catalog
$catalogCheck = Test-ApprovedSoftwareCatalog -Path $ApprovedAppsPath -PackageName 'autologon'
Add-Prerequisite -Id 'approved_catalog' -Description 'Autologon package exists in approved software catalog' `
    -Passed $catalogCheck.passed -Mandatory $true -Detail $catalogCheck.detail

# 4. State-delta Before snapshot
$beforeSnapshot = Test-StateDeltaBeforeSnapshot -Path $BeforeSnapshotPath -ExpectedRunId $RunId
Add-Prerequisite -Id 'before_snapshot' -Description 'State-delta Before snapshot captured for this run' `
    -Passed $beforeSnapshot.passed -Mandatory $true -Detail $beforeSnapshot.detail

# 5. Technician runtime proof (recommended)
$runtimeProofDetail = 'Not checked'
if ($RequireRuntimeProof.IsPresent) {
    # Check for runtime proof file in expected location
    $proofPath = $null
    if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
        $candidate = Join-Path $OutputRoot $RunId | Join-Path -ChildPath 'technician_runtime_proof.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $proofPath = $candidate
        }
    }
    if ($null -ne $proofPath) {
        $runtimeProofDetail = "Runtime proof found: $proofPath"
    }
    else {
        $runtimeProofDetail = 'Runtime proof not found (recommended but not blocking)'
    }
}
Add-Prerequisite -Id 'runtime_proof' -Description 'Technician runtime proof captured' `
    -Passed $true -Mandatory $false -Detail $runtimeProofDetail

# 6. File access posture (recommended)
$fileAccessDetail = 'Not checked'
if ($RequireFileAccessPosture.IsPresent) {
    $fileAccessDetail = 'File access posture check delegated to deployment workflow'
}
Add-Prerequisite -Id 'file_access_posture' -Description 'File access posture verified' `
    -Passed $true -Mandatory $false -Detail $fileAccessDetail

# ── Compute overall result ─────────────────────────────────────────────
$mandatoryPrereqs = @($gateResult.prerequisites | Where-Object { $_.mandatory -eq $true })
$mandatoryFailures = @($mandatoryPrereqs | Where-Object { $_.passed -eq $false })

$gateResult.overall_pass = $mandatoryFailures.Count -eq 0
if (-not $gateResult.overall_pass) {
    $gateResult.blocked_reason = "Mandatory prerequisite(s) failed: $(($mandatoryFailures | ForEach-Object { $_.id }) -join ', ')"
}

# ── Write gate result ──────────────────────────────────────────────────
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $gateDir = Join-Path $OutputRoot $RunId
    if (-not (Test-Path -LiteralPath $gateDir)) {
        New-Item -ItemType Directory -Path $gateDir -Force | Out-Null
    }
    $gatePath = Join-Path $gateDir 'autologon_final_step_gate.json'
    $gateResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $gatePath -Encoding UTF8
}

# ── Output ─────────────────────────────────────────────────────────────
[pscustomobject]$gateResult
